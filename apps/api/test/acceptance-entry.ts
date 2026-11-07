// Test-only Access edge for the official local acceptance harness.
import { importPKCS8, SignJWT } from 'jose';
import type { Bindings } from '../src/env.js';
import verifiedWorker from './workerd-entry.ts';
import {
  observeSettingsAck,
  shouldObserveSettingsAck,
} from './acceptance-settings-ack.ts';

export { RuntimeSession } from '../src/runtime-session.js';

export interface AcceptanceBindings extends Bindings {
  PROBE_ACCESS_JWKS: string;
  ACCEPTANCE_PRIVATE_KEY: string;
  ACCEPTANCE_SETTINGS_ACK_LOSS?: string;
}

export default {
  async fetch(
    request: Request,
    env: AcceptanceBindings,
    context: ExecutionContext,
  ) {
    const url = new URL(request.url);
    if (url.pathname === '/api' || url.pathname.startsWith('/api/')) {
      const observe =
        env.ACCEPTANCE_SETTINGS_ACK_LOSS === '1' &&
        shouldObserveSettingsAck(request, env.APP_ORIGIN);
      const original = observe ? request.clone() : undefined;
      const forwarded = new Request(request);
      const key = await importPKCS8(env.ACCEPTANCE_PRIVATE_KEY, 'RS256');
      const token = await new SignJWT({ email: env.OWNER_EMAIL })
        .setProtectedHeader({ alg: 'RS256', kid: 'acceptance' })
        .setSubject(env.ACCESS_SUBJECT)
        .setIssuer(`https://${env.ACCESS_TEAM_DOMAIN}`)
        .setAudience(env.ACCESS_AUD)
        .setIssuedAt()
        .setExpirationTime('5m')
        .sign(key);
      forwarded.headers.set('Cf-Access-Jwt-Assertion', token);
      // URL, Origin, subject and write headers remain the real client's responsibility.
      const response = await verifiedWorker.fetch(forwarded, env, context);
      return original
        ? observeSettingsAck(original, response, env.DB, env.ACCESS_SUBJECT)
        : response;
    }
    return verifiedWorker.fetch(request, env, context);
  },
};
