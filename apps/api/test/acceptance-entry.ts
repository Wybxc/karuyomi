// Test-only Access edge for the official local acceptance harness.
import { importPKCS8, SignJWT } from 'jose';
import { requestJson } from '../src/business-request.js';
import type { Bindings } from '../src/env.js';
import verifiedWorker from './workerd-entry.ts';
import {
  observeAck,
  shouldObserveAck,
  type AckLossFixture,
} from './acceptance-ack.ts';
import {
  waitForSettingsRaceRelease,
  holdSettingsRace,
  observeSettingsRace,
} from './acceptance-settings-race.ts';

export { RuntimeSession } from '../src/runtime-session.js';

export interface AcceptanceBindings extends Bindings {
  PROBE_ACCESS_JWKS: string;
  ACCEPTANCE_PRIVATE_KEY: string;
  ACCEPTANCE_ACK_LOSS?: AckLossFixture;
  ACCEPTANCE_SETTINGS_CAS_RACE?: '1';
}

export default {
  async fetch(
    request: Request,
    env: AcceptanceBindings,
    context: ExecutionContext,
  ) {
    const url = new URL(request.url);
    if (url.pathname === '/api' || url.pathname.startsWith('/api/')) {
      const fixture = env.ACCEPTANCE_ACK_LOSS;
      const original =
        fixture && shouldObserveAck(fixture, request, env.APP_ORIGIN)
          ? request.clone()
          : undefined;
      const contender =
        env.ACCEPTANCE_SETTINGS_CAS_RACE === '1'
          ? await holdSettingsRace(
              request,
              env.DB,
              env.APP_ORIGIN,
              env.ACCESS_SUBJECT,
              requestJson,
            )
          : undefined;
      if (contender instanceof Response) return contender;
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
      if (contender) await waitForSettingsRaceRelease(contender);
      const dispatchAtMs = contender ? Date.now() : 0;
      const response = await verifiedWorker.fetch(forwarded, env, context);
      if (contender) {
        await observeSettingsRace(
          env.DB,
          env.ACCESS_SUBJECT,
          contender,
          response,
          dispatchAtMs,
          Date.now(),
        );
      }
      return fixture && original
        ? observeAck(fixture, original, response, env.DB, env.ACCESS_SUBJECT)
        : response;
    }
    return verifiedWorker.fetch(request, env, context);
  },
};
