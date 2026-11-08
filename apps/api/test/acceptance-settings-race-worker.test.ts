import { create, toJsonString } from '@bufbuild/protobuf';
import {
  businessSchemaVersion,
  settingsMutationResponseSchema,
  settingsResponseSchema,
} from '@karuyomi/contracts';
import {
  AppTheme,
  BusinessStateErrorCode,
  ReaderBackground,
  ReaderFit,
  ReaderInputPreset,
  ReaderMode,
  ReaderPageLayout,
  SettingsMutationSchema,
} from '@karuyomi/protocol';
import { applyD1Migrations, createExecutionContext } from 'cloudflare:test';
import { env } from 'cloudflare:workers';
import { exportJWK, exportPKCS8, generateKeyPair } from 'jose';
import { createHash } from 'node:crypto';
import { afterEach, beforeAll, expect, test } from 'vitest';
import { requestJson } from '../src/business-request.js';
import acceptance from './acceptance-entry.ts';
import {
  holdSettingsRace,
  prepareSettingsRace,
  settingsRaceAttempts,
} from './acceptance-settings-race.ts';

const origin = 'http://127.0.0.1:44124';
const mutationPath = '/api/settings/mutations';
let credentials: {
  PROBE_ACCESS_JWKS: string;
  ACCEPTANCE_PRIVATE_KEY: string;
};

beforeAll(async () => {
  const keys = await generateKeyPair('RS256', { extractable: true });
  const jwk = await exportJWK(keys.publicKey);
  jwk.kid = 'acceptance';
  credentials = {
    PROBE_ACCESS_JWKS: JSON.stringify({ keys: [jwk] }),
    ACCEPTANCE_PRIVATE_KEY: await exportPKCS8(keys.privateKey),
  };
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
}, 30_000);

afterEach(async () => {
  await env.DB.exec('DROP TABLE IF EXISTS acceptance_settings_race');
});

function command(theme: AppTheme, expectedRevision = 0) {
  const mutation = create(SettingsMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    expectedRevision,
    operation: {
      case: 'setGlobal',
      value: {
        theme,
        reader: {
          mode: ReaderMode.LEFT_TO_RIGHT,
          pageLayout: ReaderPageLayout.AUTO,
          background: ReaderBackground.BLACK,
          fit: ReaderFit.CONTAIN,
          tapZones: ReaderInputPreset.STANDARD,
          keyboard: ReaderInputPreset.STANDARD,
        },
      },
    },
  });
  const body = toJsonString(SettingsMutationSchema, mutation);
  return {
    mutationId: mutation.mutationId,
    theme,
    body,
    hash: createHash('sha256').update(body).digest('hex'),
  };
}

function post(subject: string, body: string): Request {
  return new Request(origin + mutationPath, {
    method: 'POST',
    headers: {
      Origin: origin,
      'X-App-Request': '1',
      'X-App-Subject': subject,
      'Content-Type': 'application/json',
    },
    body,
  });
}

function fetchAcceptance(subject: string, request: Request) {
  return acceptance.fetch(
    request,
    {
      ...env,
      ...credentials,
      APP_ORIGIN: origin,
      ACCEPTANCE_SUBJECT: subject,
      ACCEPTANCE_SETTINGS_CAS_RACE: '1',
    },
    createExecutionContext(),
  );
}

async function readSettings(subject: string) {
  const response = await fetchAcceptance(
    subject,
    new Request(origin + '/api/settings', {
      headers: { 'X-App-Subject': subject },
    }),
  );
  expect(response.status).toBe(200);
  return settingsResponseSchema.parse(await response.json());
}

test('both real settings mutations arrive before release, then only one CAS writes', async () => {
  const subject = 'settings-race-owner';
  await prepareSettingsRace(env.DB);
  const dark = command(AppTheme.DARK);
  const light = command(AppTheme.LIGHT);
  const first = fetchAcceptance(subject, post(subject, dark.body));
  await expect
    .poll(() => settingsRaceAttempts(env.DB))
    .toMatchObject([
      { sequence: 1, mutation_id: dark.mutationId, http_status: null },
    ]);
  expect(await readSettings(subject)).toMatchObject({
    accountRevision: 0,
    global: { revision: 0, values: { theme: AppTheme.SYSTEM } },
  });
  const duplicate = await fetchAcceptance(subject, post(subject, dark.body));
  expect(duplicate.status).toBe(503);
  expect(await settingsRaceAttempts(env.DB)).toHaveLength(1);

  const responses = await Promise.all([
    first,
    fetchAcceptance(subject, post(subject, light.body)),
  ]);
  expect(responses.map((response) => response.status).sort()).toEqual([
    200, 409,
  ]);
  const outcome = await Promise.all(
    responses.map(async (response) => ({
      status: response.status,
      body: settingsMutationResponseSchema.parse(await response.json()),
    })),
  );
  const winner = outcome.find(({ status }) => status === 200);
  const loser = outcome.find(({ status }) => status === 409);
  expect(winner?.body.error).toBeUndefined();
  expect(loser?.body.error).toMatchObject({
    code: BusinessStateErrorCode.REVISION_CONFLICT,
    retryable: false,
  });

  const audit = await settingsRaceAttempts(env.DB);
  expect(audit).toHaveLength(2);
  const laterArrival = Math.max(
    ...audit.map((attempt) => attempt.arrived_at_ms),
  );
  for (const [index, input] of [dark, light].entries()) {
    const attempt = audit[index]!;
    const won = winner?.body.mutationId === input.mutationId;
    expect(attempt).toMatchObject({
      mutation_id: input.mutationId,
      expected_revision: 0,
      theme: input.theme,
      body_sha256: input.hash,
      http_status: won ? 200 : 409,
      global_revision: 1,
      account_revision: 1,
      error_code: won ? null : BusinessStateErrorCode.REVISION_CONFLICT,
      receipt_sha256: won ? expect.stringMatching(/^[a-f0-9]{64}$/) : null,
    });
    expect(attempt.dispatch_at_ms).toBeGreaterThanOrEqual(laterArrival);
    expect(attempt.response_at_ms).toBeGreaterThanOrEqual(
      attempt.dispatch_at_ms!,
    );
  }

  const current = await readSettings(subject);
  expect(current.accountRevision).toBe(1);
  expect(current.global).toEqual(winner?.body.global);

  // A new intent after the loser reads the confirmed revision is not gated.
  const losingTheme =
    loser?.body.mutationId === dark.mutationId ? AppTheme.DARK : AppTheme.LIGHT;
  const next = command(losingTheme, 1);
  const secondWrite = await fetchAcceptance(subject, post(subject, next.body));
  expect(secondWrite.status).toBe(200);
  await expect(secondWrite.json()).resolves.toMatchObject({
    mutationId: next.mutationId,
    accountRevision: 2,
    global: { revision: 2 },
  });
  expect(await settingsRaceAttempts(env.DB)).toEqual(audit);
});

test('a single arrival expires without a business write and cannot be released by a late contender', async () => {
  const subject = 'settings-race-timeout-owner';
  await prepareSettingsRace(env.DB);
  const dark = command(AppTheme.DARK);
  const timedOut = await holdSettingsRace(
    post(subject, dark.body),
    env.DB,
    origin,
    subject,
    requestJson,
    25,
  );
  expect(timedOut).toBeInstanceOf(Response);
  if (!(timedOut instanceof Response))
    throw new Error('Expected fixture timeout');
  expect(timedOut.status).toBe(503);
  expect(await settingsRaceAttempts(env.DB)).toMatchObject([
    {
      mutation_id: dark.mutationId,
      expired: 1,
      dispatch_at_ms: null,
      http_status: null,
    },
  ]);
  const late = await fetchAcceptance(
    subject,
    post(subject, command(AppTheme.LIGHT).body),
  );
  expect(late.status).toBe(503);
  expect(await settingsRaceAttempts(env.DB)).toHaveLength(1);
  expect(await readSettings(subject)).toMatchObject({
    accountRevision: 0,
    global: { revision: 0, values: { theme: AppTheme.SYSTEM } },
  });
});
