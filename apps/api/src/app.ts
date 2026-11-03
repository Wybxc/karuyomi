import { Hono } from 'hono';
import { protocolVersion, type Bootstrap } from '@karuyomi/contracts';
import {
  accessIssuer,
  createAccessVerifier,
  type AccessConfig,
  type AccessIdentity,
  type VerifyAccess,
} from './access.js';

export type Bindings = AccessConfig & {
  ASSETS: Fetcher;
  DB: D1Database;
  ARTIFACTS: R2Bucket;
  RUNTIME_SESSIONS: DurableObjectNamespace;
};

type AppEnv = {
  Bindings: Bindings;
  Variables: { identity: AccessIdentity };
};

export function createApp(verifyAccess: VerifyAccess = createAccessVerifier()) {
  const app = new Hono<AppEnv>();

  // Global dispatch prevents encoded API paths or unknown API routes from
  // reaching the SPA fallback. Assets never read private bindings.
  app.use('*', async (c, next) => {
    const rawPath = new URL(c.req.url).pathname;
    let path: string;
    try {
      path = decodeURIComponent(rawPath).replaceAll('\\', '/');
    } catch {
      return c.json({ error: 'invalid_path' }, 400);
    }
    const api = path === '/api' || path.startsWith('/api/');
    if (!api) {
      if (path.startsWith('/cdn-cgi/')) return c.notFound();
      return c.env.ASSETS.fetch(c.req.raw);
    }
    c.header('Cache-Control', 'no-store');
    if (path !== rawPath)
      return c.json({ error: 'noncanonical_api_path' }, 400);
    try {
      accessIssuer(c.env);
    } catch {
      return c.json({ error: 'access_not_configured' }, 503);
    }
    const token = c.req.header('Cf-Access-Jwt-Assertion');
    if (!token) return c.json({ error: 'access_required' }, 401);
    try {
      c.set('identity', await verifyAccess(token, c.env));
    } catch {
      return c.json({ error: 'access_denied' }, 403);
    }
    await next();
  });

  app.get('/api/auth/login', (c) => c.redirect('/auth/complete', 303));
  app.get('/api/bootstrap', (c) => {
    const identity = c.get('identity');
    const body: Bootstrap = {
      protocolVersion,
      identity: { subject: identity.subject },
      expiresAt: identity.expiresAt,
      stage: 'scaffold',
    };
    return c.json(body);
  });
  app.notFound((c) => c.json({ error: 'not_found' }, 404));
  app.onError((_error, c) => c.json({ error: 'internal_error' }, 500));
  return app;
}
