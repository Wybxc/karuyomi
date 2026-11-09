import { beforeAll, expect, test } from 'vitest';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';
import { bootstrapSchema, BootstrapStage } from '@karuyomi/contracts';
import { createAccessVerifier } from '../src/access.js';
import { createApp } from '../src/app.js';
import type { Bindings } from '../src/env.js';

const config = {
  ACCESS_TEAM_DOMAIN: 'example.cloudflareaccess.com',
  ACCESS_AUD: 'test-audience',
  APP_ORIGIN: 'https://read.example.com',
};
const env = {
  ...config,
  ASSETS: {
    fetch: async () => new Response('<html>public shell</html>'),
  },
} as unknown as Bindings;

let keys: Awaited<ReturnType<typeof generateKeyPair>>;
let app: ReturnType<typeof createApp>;

beforeAll(async () => {
  keys = await generateKeyPair('RS256');
  const jwk = await exportJWK(keys.publicKey);
  jwk.kid = 'test-key';
  app = createApp(createAccessVerifier(createLocalJWKSet({ keys: [jwk] })));
});

async function token(
  options: {
    subject?: string;
    audience?: string;
    issuer?: string;
    expired?: boolean;
    email?: string;
  } = {},
) {
  return new SignJWT({ email: options.email ?? 'owner@example.com' })
    .setProtectedHeader({ alg: 'RS256', kid: 'test-key' })
    .setSubject(options.subject ?? 'owner-subject')
    .setIssuer(options.issuer ?? `https://${config.ACCESS_TEAM_DOMAIN}`)
    .setAudience(options.audience ?? config.ACCESS_AUD)
    .setIssuedAt()
    .setExpirationTime(options.expired ? '0s' : '5m')
    .sign(keys.privateKey);
}

test.each(['/', '/library', '/reader/example', '/runtime/host.html'])(
  'public shell is accessible without Access: %s',
  async (path) => {
    const response = await app.request(
      `https://read.example.com${path}`,
      {},
      env,
    );
    expect(response.status).toBe(200);
    expect(await response.text()).toContain('public shell');
  },
);

test.each(['/api', '/api/', '/api/bootstrap', '/api/unknown'])(
  'all API paths reject missing JWT and never use SPA fallback: %s',
  async (path) => {
    const response = await app.request(
      `https://read.example.com${path}`,
      {},
      env,
    );
    expect(response.status).toBe(401);
    expect(response.headers.get('cache-control')).toBe('private, no-store');
    expect(await response.json()).toEqual({ error: 'access_required' });
  },
);

test.each(['/%61pi/bootstrap', '/api%2Fbootstrap'])(
  'encoded API alias fails closed: %s',
  async (path) => {
    const response = await app.request(
      `https://read.example.com${path}`,
      {},
      env,
    );
    expect(response.status).toBe(400);
  },
);

test('unconfigured Access is unavailable, with no development bypass', async () => {
  const response = await app.request(
    'https://read.example.com/api/bootstrap',
    {},
    {
      ...env,
      ACCESS_AUD: '',
    },
  );
  expect(response.status).toBe(503);
});

test.each([
  { audience: 'wrong-audience' },
  { issuer: 'https://wrong.cloudflareaccess.com' },
  { expired: true },
])('rejects invalid Access claims: %j', async (options) => {
  const response = await app.request(
    'https://read.example.com/api/bootstrap',
    {
      headers: { 'Cf-Access-Jwt-Assertion': await token(options) },
    },
    env,
  );
  expect(response.status).toBe(401);
});

test('rejects forged tokens and identity headers', async () => {
  const response = await app.request(
    'https://read.example.com/api/bootstrap',
    {
      headers: {
        'Cf-Access-Jwt-Assertion': 'forged.token.signature',
        'Cf-Access-Authenticated-User-Email': 'owner@example.com',
      },
    },
    env,
  );
  expect(response.status).toBe(401);
});

test.each([
  { subject: 'owner-subject', email: 'owner@example.com' },
  { subject: 'another-person', email: 'other@example.com' },
])(
  'an identity authorized by Access gets its own typed bootstrap: %j',
  async (claims) => {
    const response = await app.request(
      'https://read.example.com/api/bootstrap',
      {
        headers: { 'Cf-Access-Jwt-Assertion': await token(claims) },
      },
      env,
    );
    expect(response.status).toBe(200);
    const body = bootstrapSchema.parse(await response.json());
    expect(body.identity.subject).toBe(claims.subject);
    expect(body.stage).toBe(BootstrapStage.P0);
  },
);

test('unknown authenticated API returns JSON 404', async () => {
  const response = await app.request(
    'https://read.example.com/api/unknown',
    {
      headers: { 'Cf-Access-Jwt-Assertion': await token() },
    },
    env,
  );
  expect(response.status).toBe(404);
  expect(await response.json()).toEqual({ error: 'not_found' });
});

test.each(['/', '/auth/complete', '/browse', '/settings'])(
  'login permits only a public application continuation: %s',
  async (returnTo) => {
    const response = await app.request(
      `https://read.example.com/api/auth/login?returnTo=${encodeURIComponent(returnTo)}`,
      { headers: { 'Cf-Access-Jwt-Assertion': await token() } },
      env,
    );
    expect(response.status).toBe(303);
    expect(response.headers.get('location')).toBe(returnTo);
    expect(response.headers.get('cache-control')).toBe('private, no-store');
  },
);

test('popup login preserves one valid attempt on the fixed first-party callback', async () => {
  const attempt = crypto.randomUUID();
  const response = await app.request(
    `https://read.example.com/api/auth/login?returnTo=/auth/complete&attempt=${attempt}`,
    { headers: { 'Cf-Access-Jwt-Assertion': await token() } },
    env,
  );
  expect(response.status).toBe(303);
  expect(response.headers.get('location')).toBe(
    `/auth/complete?attempt=${attempt}`,
  );
});

test.each([
  { returnTo: '/auth/complete', attempt: '' },
  { returnTo: '/auth/complete', attempt: 'foreign-attempt' },
  { returnTo: '/', attempt: '3f2504e0-4f89-41d3-9a0c-0305e82c3301' },
])(
  'popup login rejects invalid attempts or callbacks: %j',
  async ({ returnTo, attempt }) => {
    const query = new URLSearchParams({ returnTo, attempt });
    const response = await app.request(
      `https://read.example.com/api/auth/login?${query}`,
      {
        headers: { 'Cf-Access-Jwt-Assertion': await token() },
      },
      env,
    );
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({
      error: 'invalid_authentication_attempt',
    });
  },
);

test.each([
  'https://attacker.example',
  '//attacker.example',
  '/api/bootstrap',
  '/runtime/host.html',
  '/cdn-cgi/access/login',
  '/browse?redirect=https://attacker.example',
])('login rejects arbitrary continuations: %s', async (returnTo) => {
  const response = await app.request(
    `https://read.example.com/api/auth/login?returnTo=${encodeURIComponent(returnTo)}`,
    {
      headers: { 'Cf-Access-Jwt-Assertion': await token() },
    },
    env,
  );
  expect(response.status).toBe(400);
  expect(response.headers.get('location')).toBeNull();
});

test.each([
  'https://alternate.example',
  'http://read.example.com',
  'https://read.example.com:8443',
])(
  'API rejects an unexpected request origin before checking identity: %s',
  async (origin) => {
    const response = await app.request(
      `${origin}/api/bootstrap`,
      { headers: { 'Cf-Access-Jwt-Assertion': await token() } },
      env,
    );
    expect(response.status).toBe(403);
    expect(response.headers.get('cache-control')).toBe('private, no-store');
    expect(await response.json()).toEqual({ error: 'invalid_host' });
  },
);

test.each([
  {},
  { Origin: 'https://other.example', 'X-App-Request': '1' },
  { Origin: config.APP_ORIGIN },
])(
  'mutating APIs require the exact application Origin and request marker: %j',
  async (headers) => {
    const response = await app.request(
      'https://read.example.com/api/bridge/http',
      {
        method: 'POST',
        headers: { 'Cf-Access-Jwt-Assertion': await token(), ...headers },
      },
      env,
    );
    expect(response.status).toBe(403);
    expect(await response.json()).toEqual({ error: 'invalid_origin' });
  },
);
