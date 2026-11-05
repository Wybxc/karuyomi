// Test-only entry point. Production src/index.ts never imports this module.
// Every probe request still verifies a real RS256 JWT against a test public key.
import { createLocalJWKSet, type JSONWebKeySet } from 'jose';
import { createAccessVerifier } from '../src/access.js';
import { createApp } from '../src/app.js';
import type { Bindings } from '../src/env.js';

export { RuntimeSession } from '../src/runtime-session.js';

export default {
  async fetch(
    request: Request,
    env: Bindings & { PROBE_ACCESS_JWKS: string },
    context: ExecutionContext,
  ) {
    const verifier = createAccessVerifier(
      createLocalJWKSet(JSON.parse(env.PROBE_ACCESS_JWKS) as JSONWebKeySet),
    );
    const response = await createApp(verifier).fetch(request, env, context);
    // Formal probes assert that real Static Assets delivery bypasses this entry.
    const marked = new Response(response.body, response);
    marked.headers.set('X-Karuyomi-Probe-Worker', '1');
    return marked;
  },
};
