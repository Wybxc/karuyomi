import { create, toJsonString } from '@bufbuild/protobuf';
import {
  businessSchemaVersion,
  settingsMutationResponseSchema,
  settingsResponseSchema,
} from '@karuyomi/contracts';
import {
  BusinessStateErrorCode,
  ReaderMode,
  SettingsMutationSchema,
} from '@karuyomi/protocol';
import { applyD1Migrations, createExecutionContext } from 'cloudflare:test';
import { env } from 'cloudflare:workers';
import { exportJWK, exportPKCS8, generateKeyPair } from 'jose';
import { afterEach, beforeAll, beforeEach, expect, test } from 'vitest';
import acceptance from './acceptance-entry.ts';
import {
  prepareSettingsUi,
  setSettingsUiMode,
  settingsUiAttempts,
} from './acceptance-settings-ui.ts';

const origin = 'http://127.0.0.1:44127';
const mangaKey = 'a'.repeat(64);
const mangaPath = '/api/settings/manga/' + mangaKey;
let subject: string;
let credentials: { PROBE_ACCESS_JWKS: string; ACCEPTANCE_PRIVATE_KEY: string };

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

beforeEach(async () => {
  subject = 'settings-ui-' + crypto.randomUUID();
  await prepareSettingsUi(env.DB);
});
afterEach(async () => {
  await env.DB.exec(
    'DROP TABLE IF EXISTS acceptance_settings_ui_attempts; DROP TABLE IF EXISTS acceptance_settings_ui_control',
  );
});

function request(
  path: string,
  body?: string,
  fixture = true,
  requestOrigin = origin,
  signal?: AbortSignal,
) {
  return acceptance.fetch(
    new Request(requestOrigin + path, {
      method: body === undefined ? 'GET' : 'POST',
      headers: {
        Origin: origin,
        'X-App-Request': '1',
        'X-App-Subject': subject,
        'Content-Type': 'application/json',
      },
      ...(body === undefined ? {} : { body }),
      ...(signal === undefined ? {} : { signal }),
    }),
    {
      ...env,
      ...credentials,
      APP_ORIGIN: origin,
      ACCEPTANCE_SUBJECT: subject,
      ...(fixture ? { ACCEPTANCE_SETTINGS_UI: '1' as const } : {}),
    },
    createExecutionContext(),
  );
}

function command(expectedRevision = 0) {
  return toJsonString(
    SettingsMutationSchema,
    create(SettingsMutationSchema, {
      schemaVersion: businessSchemaVersion,
      mutationId: crypto.randomUUID(),
      expectedRevision,
      operation: {
        case: 'setManga',
        value: { mangaKey, overrides: { mode: ReaderMode.RIGHT_TO_LEFT } },
      },
    }),
  );
}

async function snapshot() {
  const reply = await request(mangaPath, undefined, false);
  expect(reply.status).toBe(200);
  return settingsResponseSchema.parse(await reply.json());
}

async function entered() {
  for (let attempt = 0; attempt < 30; attempt++) {
    const audit = await settingsUiAttempts(env.DB);
    if (audit.length > 0) return audit;
    await new Promise<void>((resolve) => setTimeout(resolve, 50));
  }
  throw new Error('Settings UI request did not enter the fixture');
}

test('fixture stays opt-in, loopback-only, scoped and absent from other APIs', async () => {
  await setSettingsUiMode(env.DB, 'fail-read', 'manga');
  expect((await request(mangaPath, undefined, false)).status).toBe(200);
  expect((await request('/api/settings')).status).toBe(200);
  expect((await request('/api/library')).status).toBe(200);
  await request(mangaPath, undefined, true, 'https://read.example.com');
  const audit = await settingsUiAttempts(env.DB);
  expect(audit).toHaveLength(1);
  expect(audit[0]).toMatchObject({
    path: '/api/settings',
    mode: 'pass',
    worker_status: 200,
    client_status: 200,
  });
  await expect(setSettingsUiMode(env.DB, 'unknown', 'manga')).rejects.toThrow(
    'Expected',
  );
  await expect(setSettingsUiMode(env.DB, 'pass', 'other')).rejects.toThrow(
    'Expected',
  );
});

test('reading remains pending until an explicit stdin-controlled generation change', async () => {
  await setSettingsUiMode(env.DB, 'hold-read', 'manga');
  let delivered = false;
  const pending = request(mangaPath).then((reply) => {
    delivered = true;
    return reply;
  });
  try {
    expect((await entered())[0]).toMatchObject({
      mode: 'hold-read',
      method: 'GET',
      worker_status: null,
      client_status: null,
    });
    expect(delivered).toBe(false);
  } finally {
    await setSettingsUiMode(env.DB, 'pass', 'manga');
  }
  expect((await pending).status).toBe(200);
  expect((await settingsUiAttempts(env.DB))[0]).toMatchObject({
    worker_status: 200,
    client_status: 200,
  });
});

test('an aborted reader leaves the gate without dispatching a late request', async () => {
  await setSettingsUiMode(env.DB, 'hold-read', 'manga');
  const controller = new AbortController();
  const pending = request(
    mangaPath,
    undefined,
    true,
    origin,
    controller.signal,
  );
  const rejected = expect(pending).rejects.toThrow();
  await entered();
  controller.abort();
  await rejected;
  expect((await settingsUiAttempts(env.DB))[0]).toMatchObject({
    worker_status: null,
    client_status: null,
  });
});

test('confirmation gate holds delivery after the real D1 transaction commits', async () => {
  await setSettingsUiMode(env.DB, 'hold-confirm', 'manga');
  const body = command();
  let delivered = false;
  const pending = request('/api/settings/mutations', body).then((reply) => {
    delivered = true;
    return reply;
  });
  try {
    await entered();
    for (
      let attempt = 0;
      attempt < 30 && (await snapshot()).manga?.revision !== 1;
      attempt++
    ) {
      await new Promise<void>((resolve) => setTimeout(resolve, 50));
    }
    expect((await snapshot()).manga?.revision).toBe(1);
    expect(delivered).toBe(false);
  } finally {
    await setSettingsUiMode(env.DB, 'pass', 'manga');
  }
  const ack = settingsMutationResponseSchema.parse(
    await (await pending).json(),
  );
  expect(ack.manga?.revision).toBe(1);
  expect((await settingsUiAttempts(env.DB))[0]?.body).toBe(body);
});

test('lost committed ACK retries exact body once, while stale fresh commands still conflict', async () => {
  await setSettingsUiMode(env.DB, 'lose-confirm', 'manga');
  const body = command();
  expect((await request('/api/settings/mutations', body)).status).toBe(502);
  expect((await snapshot()).manga?.revision).toBe(1);
  await setSettingsUiMode(env.DB, 'pass', 'manga');
  const retry = await request('/api/settings/mutations', body);
  expect(retry.status).toBe(200);
  expect(
    settingsMutationResponseSchema.parse(await retry.json()).manga?.revision,
  ).toBe(1);
  const stale = await request('/api/settings/mutations', command());
  expect(stale.status).toBe(409);
  expect(
    settingsMutationResponseSchema.parse(await stale.json()).error?.code,
  ).toBe(BusinessStateErrorCode.REVISION_CONFLICT);
  expect((await snapshot()).manga?.revision).toBe(1);
  const audit = await settingsUiAttempts(env.DB);
  expect(audit[0]).toMatchObject({
    body,
    worker_status: 200,
    client_status: 502,
  });
  expect(audit[1]).toMatchObject({
    body,
    worker_status: 200,
    client_status: 200,
  });
});

test('read failure, pre-dispatch rejection and login HTML never create a settings write', async () => {
  await setSettingsUiMode(env.DB, 'fail-read', 'manga');
  expect((await request(mangaPath)).status).toBe(503);
  await setSettingsUiMode(env.DB, 'reject-save', 'manga');
  const rejected = await request('/api/settings/mutations', command());
  expect(rejected.status).toBe(400);
  expect(
    settingsMutationResponseSchema.parse(await rejected.json()).error,
  ).toMatchObject({
    code: BusinessStateErrorCode.INVALID_INPUT,
    retryable: false,
  });
  expect((await snapshot()).manga?.revision).toBe(0);
  await setSettingsUiMode(env.DB, 'login-required', 'manga');
  const login = await request(mangaPath);
  expect(login.status).toBe(401);
  expect(login.headers.get('content-type')).toBe('text/html');
  await setSettingsUiMode(env.DB, 'pass', 'manga');
  expect((await snapshot()).manga?.revision).toBe(0);
  expect(
    (await settingsUiAttempts(env.DB)).every(
      (row) => row.worker_status === null,
    ),
  ).toBe(true);
});
