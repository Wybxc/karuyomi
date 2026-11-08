import { expect, test, vi } from 'vitest';
import { createApp } from '../src/app.js';
import type { Bindings } from '../src/env.js';

function fixture() {
  const assets = vi.fn(async () => new Response('static asset'));
  const database = vi.fn(() => {
    throw new Error('static distribution must not read D1');
  });
  const verify = vi.fn(async () => ({
    subject: 'owner',
    email: 'owner@example.com',
    expiresAt: 4_000_000_000,
  }));
  const env = {
    ACCESS_TEAM_DOMAIN: 'example.cloudflareaccess.com',
    ACCESS_AUD: 'app',
    APP_ORIGIN: 'https://read.example.com',
    ASSETS: { fetch: assets },
    DB: { prepare: database },
  } as unknown as Bindings;
  return { app: createApp(verify), env, assets, database, verify };
}

test.each([
  '/extensions/index.json',
  '/extensions/builds/current/manifest.json',
  `/extensions/artifacts/${'a'.repeat(64)}.gz`,
  `/runtime/materials/${'b'.repeat(64)}`,
])(
  'static distribution bypasses private bindings and Access: %s',
  async (pathname) => {
    const f = fixture();
    const response = await f.app.request(
      `https://read.example.com${pathname}`,
      {},
      { ...f.env, ACCESS_TEAM_DOMAIN: '' },
    );
    expect(response.status).toBe(200);
    expect(await response.text()).toBe('static asset');
    expect(f.assets).toHaveBeenCalledOnce();
    expect(f.database).not.toHaveBeenCalled();
    expect(f.verify).not.toHaveBeenCalled();
  },
);

test.each([
  '/api/extensions/builds',
  '/api/extensions/builds/current/manifest',
  `/api/extensions/artifacts/${'a'.repeat(64)}`,
])(
  'removed distribution API remains authenticated 404, never SPA fallback: %s',
  async (pathname) => {
    const f = fixture();
    expect(
      (await f.app.request(`https://read.example.com${pathname}`, {}, f.env))
        .status,
    ).toBe(401);
    const response = await f.app.request(
      `https://read.example.com${pathname}`,
      { headers: { 'Cf-Access-Jwt-Assertion': 'test-verifier-token' } },
      f.env,
    );
    expect(response.status).toBe(404);
    expect(response.headers.get('Cache-Control')).toBe('private, no-store');
    expect(await response.json()).toEqual({ error: 'not_found' });
    expect(f.assets).not.toHaveBeenCalled();
    expect(f.database).not.toHaveBeenCalled();
  },
);
