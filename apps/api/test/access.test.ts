import { beforeAll, expect, test } from 'vitest';
import { createLocalJWKSet, exportJWK, generateKeyPair, SignJWT } from 'jose';
import { bootstrapSchema } from '@karuyomi/contracts';
import { createAccessVerifier } from '../src/access.js';
import { createApp } from '../src/app.js';
import type { Bindings } from '../src/env.js';

const config = {
  ACCESS_TEAM_DOMAIN: 'example.cloudflareaccess.com',
  ACCESS_AUD: 'test-audience',
  ACCESS_SUBJECT: 'owner-subject',
  OWNER_EMAIL: 'owner@example.com',
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
  return new SignJWT({ email: options.email ?? config.OWNER_EMAIL })
    .setProtectedHeader({ alg: 'RS256', kid: 'test-key' })
    .setSubject(options.subject ?? config.ACCESS_SUBJECT)
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
  { subject: 'another-person' },
  { email: 'other@example.com' },
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
  expect(response.status).toBe(options.subject || options.email ? 403 : 401);
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

test('verified owner gets typed bootstrap without a token in the body', async () => {
  const response = await app.request(
    'https://read.example.com/api/bootstrap',
    {
      headers: { 'Cf-Access-Jwt-Assertion': await token() },
    },
    env,
  );
  expect(response.status).toBe(200);
  const body = bootstrapSchema.parse(await response.json());
  expect(body.identity.subject).toBe(config.ACCESS_SUBJECT);
  expect(body.stage).toBe('p0');
});

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

test.each([
  '/',
  '/auth/complete',
  '/browse',
  '/settings',
  '/runtime/host.html',
])(
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

test.each([
  'https://attacker.example',
  '//attacker.example',
  '/api/bootstrap',
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
