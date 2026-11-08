// Test-only Access edge for the official local acceptance harness.
import { importPKCS8, SignJWT } from 'jose';
import { requestJson } from '../src/business-request.js';
import type { Bindings } from '../src/env.js';
import { readMangaState } from '../src/state-store.js';
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
import {
  holdProgressRace,
  observeProgressRace,
  progressRaceDatabase,
} from './acceptance-progress-race.ts';

export { RuntimeSession } from '../src/runtime-session.js';

export interface AcceptanceBindings extends Bindings {
  PROBE_ACCESS_JWKS: string;
  ACCEPTANCE_PRIVATE_KEY: string;
  ACCEPTANCE_SUBJECT: string;
  ACCEPTANCE_ACK_LOSS?: AckLossFixture;
  ACCEPTANCE_SETTINGS_CAS_RACE?: '1';
  ACCEPTANCE_PROGRESS_CAS_RACE?: '1';
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
      const settingsContender =
        env.ACCEPTANCE_SETTINGS_CAS_RACE === '1'
          ? await holdSettingsRace(
              request,
              env.DB,
              env.APP_ORIGIN,
              env.ACCEPTANCE_SUBJECT,
              requestJson,
            )
          : undefined;
      if (settingsContender instanceof Response) return settingsContender;
      const progressContender =
        env.ACCEPTANCE_PROGRESS_CAS_RACE === '1'
          ? await holdProgressRace(
              request,
              env.DB,
              env.APP_ORIGIN,
              env.ACCEPTANCE_SUBJECT,
              { requestJson, readMangaState },
            )
          : undefined;
      if (progressContender instanceof Response) return progressContender;
      const forwarded = new Request(request);
      const key = await importPKCS8(env.ACCEPTANCE_PRIVATE_KEY, 'RS256');
      const token = await new SignJWT({ email: 'acceptance@example.com' })
        .setProtectedHeader({ alg: 'RS256', kid: 'acceptance' })
        .setSubject(env.ACCEPTANCE_SUBJECT)
        .setIssuer(`https://${env.ACCESS_TEAM_DOMAIN}`)
        .setAudience(env.ACCESS_AUD)
        .setIssuedAt()
        .setExpirationTime('5m')
        .sign(key);
      forwarded.headers.set('Cf-Access-Jwt-Assertion', token);
      // URL, Origin, subject and write headers remain the real client's responsibility.
      if (settingsContender)
        await waitForSettingsRaceRelease(settingsContender);
      const dispatchAtMs = Date.now();
      const workerEnv = progressContender
        ? { ...env, DB: progressRaceDatabase(env.DB, progressContender) }
        : env;
      const response = await verifiedWorker.fetch(
        forwarded,
        workerEnv,
        context,
      );
      const responseAtMs = Date.now();
      if (settingsContender) {
        await observeSettingsRace(
          env.DB,
          env.ACCEPTANCE_SUBJECT,
          settingsContender,
          response,
          dispatchAtMs,
          responseAtMs,
        );
      }
      if (progressContender) {
        await observeProgressRace(
          env.DB,
          env.ACCEPTANCE_SUBJECT,
          progressContender,
          response,
          dispatchAtMs,
          responseAtMs,
        );
      }
      return fixture && original
        ? observeAck(
            fixture,
            original,
            response,
            env.DB,
            env.ACCEPTANCE_SUBJECT,
          )
        : response;
    }
    return verifiedWorker.fetch(request, env, context);
  },
};
