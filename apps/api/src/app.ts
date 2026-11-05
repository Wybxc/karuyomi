import { Hono } from 'hono';
import { createHttpBridge } from './http-bridge.js';
import { createStateRoutes } from './state-routes.js';
import {
  protocolVersion,
  BootstrapStage,
  encodeBootstrap,
  type Bootstrap,
} from '@karuyomi/contracts';
import {
  accessIssuer,
  AccessError,
  createAccessVerifier,
  type VerifyAccess,
} from './access.js';

import type { AppEnv } from './env.js';

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
      if (
        ['GET', 'HEAD'].includes(c.req.method) &&
        ['/', '/auth/complete', '/browse', '/settings'].includes(path)
      ) {
        return c.env.ASSETS.fetch(
          new Request(new URL('/', c.req.url), c.req.raw),
        );
      }
      return c.env.ASSETS.fetch(c.req.raw);
    }
    c.header('Cache-Control', 'private, no-store');
    if (path !== rawPath)
      return c.json({ error: 'noncanonical_api_path' }, 400);
    try {
      accessIssuer(c.env);
    } catch {
      return c.json({ error: 'access_not_configured' }, 503);
    }
    if (new URL(c.req.url).origin !== c.env.APP_ORIGIN) {
      return c.json({ error: 'invalid_host' }, 403);
    }
    const token = c.req.header('Cf-Access-Jwt-Assertion');
    if (!token) return c.json({ error: 'access_required' }, 401);
    try {
      c.set('identity', await verifyAccess(token, c.env));
    } catch (error) {
      if (error instanceof AccessError) {
        if (error.status === 503) c.header('Retry-After', '5');
        return c.json({ error: error.code }, error.status);
      }
      return c.json({ error: 'access_unavailable' }, 503);
    }
    if (
      !['GET', 'HEAD', 'OPTIONS'].includes(c.req.method) &&
      (c.req.header('Origin') !== c.env.APP_ORIGIN ||
        c.req.header('X-App-Request') !== '1')
    ) {
      return c.json({ error: 'invalid_origin' }, 403);
    }
    await next();
  });

  app.get('/api/auth/login', (c) => {
    const returnTo = c.req.query('returnTo') ?? '/auth/complete';
    const attempt = c.req.query('attempt');
    // Keep the login continuation on one of the public application routes.
    // In particular, never redirect back into Access or an arbitrary origin.
    if (
      ![
        '/',
        '/auth/complete',
        '/browse',
        '/settings',
        '/runtime/host.html',
      ].includes(returnTo)
    ) {
      return c.json({ error: 'invalid_return_to' }, 400);
    }
    if (attempt !== undefined) {
      if (
        returnTo !== '/auth/complete' ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
          attempt,
        )
      ) {
        return c.json({ error: 'invalid_authentication_attempt' }, 400);
      }
      return c.redirect(
        `${returnTo}?attempt=${encodeURIComponent(attempt)}`,
        303,
      );
    }
    return c.redirect(returnTo, 303);
  });
  app.get('/api/bootstrap', (c) => {
    const identity = c.get('identity');
    const body: Bootstrap = {
      protocolVersion,
      identity: { subject: identity.subject, email: identity.email },
      expiresAt: identity.expiresAt,
      stage: BootstrapStage.P0,
    };
    return c.json(encodeBootstrap(body));
  });
  app.route('/api/bridge', createHttpBridge());
  app.route('/api', createStateRoutes());
  app.notFound((c) => c.json({ error: 'not_found' }, 404));
  app.onError((_error, c) => c.json({ error: 'internal_error' }, 500));
  return app;
}
