import { categoryCatalogResponseSchema } from '@karuyomi/contracts';
import { exportJWK, generateKeyPair, SignJWT } from 'jose';
import { fileURLToPath, URL } from 'node:url';
import { afterAll, beforeAll, expect, test } from 'vitest';
import { createTestHarness } from 'wrangler';
import type { Bindings } from '../src/env.js';

const origin = 'https://read.example.com';
const keys = await generateKeyPair('RS256');
const publicKey = await exportJWK(keys.publicKey);
publicKey.kid = 'vite-harness';
const server = createTestHarness({
  workers: [
    {
      configPath: fileURLToPath(
        new URL('./fixture/dist/karuyomi/wrangler.json', import.meta.url),
      ),
      vars: {
        PROBE_ACCESS_JWKS: JSON.stringify({ keys: [publicKey] }),
        ACCESS_TEAM_DOMAIN: 'example.cloudflareaccess.com',
        ACCESS_AUD: 'vite-harness',
        ACCESS_SUBJECT: 'vite-owner',
        OWNER_EMAIL: 'owner@example.com',
        APP_ORIGIN: origin,
      },
    },
  ],
});
const worker = server.getWorker<Bindings>();
beforeAll(async () => {
  await server.listen();
  await worker.applyD1Migrations('DB');
});
afterAll(() => server.close());

test('declared Vite assets bypass the Worker and retain their headers', async () => {
  const shell = await server.fetch(`${origin}/`);
  expect(shell.status).toBe(200);
  expect(await shell.text()).toContain('Karuyomi static fixture');
  expect(shell.headers.has('X-Karuyomi-Probe-Worker')).toBe(false);
  const asset = await server.fetch(`${origin}/hello.txt`);
  expect(await asset.text()).toBe('Vite static bytes\n');
  expect(asset.headers.get('X-Vite-Asset')).toBe('copied');
  expect(asset.headers.has('X-Karuyomi-Probe-Worker')).toBe(false);
  const host = await server.fetch(`${origin}/runtime/host.html`, {
    redirect: 'manual',
  });
  expect(host.status).toBe(307);
  expect(new URL(host.headers.get('location') ?? '', origin).pathname).toBe(
    '/runtime/host',
  );
  expect(host.headers.get('X-Karuyomi-Probe-Worker')).toBe('1');
});

test('generated Worker config applies D1 migrations, binds private R2 and verifies the test JWT', async () => {
  expect((await worker.fetch(`${origin}/api/categories`)).status).toBe(401);
  const token = await new SignJWT({ email: 'owner@example.com' })
    .setProtectedHeader({ alg: 'RS256', kid: 'vite-harness' })
    .setSubject('vite-owner')
    .setIssuer('https://example.cloudflareaccess.com')
    .setAudience('vite-harness')
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(keys.privateKey);
  const response = await worker.fetch(`${origin}/api/categories`, {
    headers: {
      'Cf-Access-Jwt-Assertion': token,
      'X-App-Subject': 'vite-owner',
    },
  });
  expect(response.status).toBe(200);
  const catalog = categoryCatalogResponseSchema.parse(await response.json());
  expect(catalog.categoryCatalog).toMatchObject({
    revision: 0,
    categories: [],
  });
  expect(catalog.error).toBeUndefined();
  const bindings = await worker.getEnv();
  expect(
    await bindings.DB.prepare('SELECT count(*) count FROM cover_assets').first(
      'count',
    ),
  ).toBe(0);
  await bindings.COVERS.put('harness-private-cover', 'private R2 binding');
  expect(
    await (await bindings.COVERS.get('harness-private-cover'))?.text(),
  ).toBe('private R2 binding');
  await bindings.COVERS.delete('harness-private-cover');
});
