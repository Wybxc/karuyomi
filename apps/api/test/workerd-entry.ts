// Test-only entry point. Production src/index.ts never imports this module.
// Every probe request still verifies a real RS256 JWT against a test public key.
import { createLocalJWKSet, type JSONWebKeySet } from 'jose';
import { createAccessVerifier } from '../src/access.js';
import { createApp, type Bindings } from '../src/app.js';

export default {
  fetch(
    request: Request,
    env: Bindings & { PROBE_ACCESS_JWKS: string },
    context: ExecutionContext,
  ) {
    const verifier = createAccessVerifier(
      createLocalJWKSet(JSON.parse(env.PROBE_ACCESS_JWKS) as JSONWebKeySet),
    );
    return createApp(verifier).fetch(request, env, context);
  },
};
