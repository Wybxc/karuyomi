import { create, toJsonString } from '@bufbuild/protobuf';
import {
  businessSchemaVersion,
  settingsMutationResponseSchema,
  settingsResponseSchema,
  mangaStateResponseSchema,
  stateMutationResponseSchema,
} from '@karuyomi/contracts';
import {
  BusinessStateErrorCode,
  ReaderMode,
  SettingsMutationSchema,
  StateMutationSchema,
} from '@karuyomi/protocol';
import { applyD1Migrations, createExecutionContext } from 'cloudflare:test';
import { env } from 'cloudflare:workers';
import { exportJWK, exportPKCS8, generateKeyPair } from 'jose';
import { afterEach, beforeAll, beforeEach, expect, test } from 'vitest';
import acceptance from './acceptance-entry.ts';
import {
  prepareEditorUi,
  setEditorUiMode,
  editorUiAttempts,
} from './acceptance-editor-ui.ts';

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
  subject = 'editor-ui-' + crypto.randomUUID();
  await prepareEditorUi(env.DB);
});
afterEach(async () => {
  await env.DB.exec(
    'DROP TABLE IF EXISTS acceptance_editor_ui_attempts; DROP TABLE IF EXISTS acceptance_editor_ui_control',
  );
});

function request(
  path: string,
  body?: string | FormData,
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
        ...(typeof body === 'string'
          ? { 'Content-Type': 'application/json' }
          : {}),
      },
      ...(body === undefined ? {} : { body }),
      ...(signal === undefined ? {} : { signal }),
    }),
    {
      ...env,
      ...credentials,
      APP_ORIGIN: origin,
      ACCEPTANCE_SUBJECT: subject,
      ...(fixture ? { ACCEPTANCE_EDITOR_UI: '1' as const } : {}),
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

const coverPath = '/api/state/manga/' + mangaKey;
const image = Uint8Array.from(
  Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1sAAAAASUVORK5CYII=',
    'base64',
  ),
);

async function coverSnapshot() {
  const reply = await request(coverPath, undefined, false);
  expect(reply.status).toBe(200);
  return mangaStateResponseSchema.parse(await reply.json());
}

function clearCommand(expectedRevision = 1) {
  return toJsonString(
    StateMutationSchema,
    create(StateMutationSchema, {
      schemaVersion: businessSchemaVersion,
      mutationId: crypto.randomUUID(),
      mangaKey,
      expectedRevision,
      operation: { case: 'setCustomCover', value: {} },
    }),
  );
}

async function seedCover() {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', image));
  const cover = {
    assetId: crypto.randomUUID(),
    contentType: 'image/png',
    byteLength: image.byteLength,
    sha256: Array.from(digest, (value) =>
      value.toString(16).padStart(2, '0'),
    ).join(''),
  };
  const form = new FormData();
  form.set(
    'mutation',
    toJsonString(
      StateMutationSchema,
      create(StateMutationSchema, {
        schemaVersion: businessSchemaVersion,
        mutationId: crypto.randomUUID(),
        mangaKey,
        operation: { case: 'setCustomCover', value: { cover } },
      }),
    ),
  );
  form.set('image', new File([image], 'cover.png', { type: 'image/png' }));
  const saved = await request('/api/covers/' + mangaKey, form, false);
  expect(saved.status).toBe(200);
  expect(
    stateMutationResponseSchema.parse(await saved.json()).manga?.customCover,
  ).toMatchObject(cover);
  return cover;
}

async function entered() {
  for (let attempt = 0; attempt < 30; attempt++) {
    const audit = await editorUiAttempts(env.DB);
    if (audit.length > 0) return audit;
    await new Promise<void>((resolve) => setTimeout(resolve, 50));
  }
  throw new Error('Editor UI request did not enter the fixture');
}

test('fixture stays opt-in, loopback-only, scoped and absent from other APIs', async () => {
  await setEditorUiMode(env.DB, 'fail-read', 'manga');
  expect((await request(mangaPath, undefined, false)).status).toBe(200);
  expect((await request('/api/settings')).status).toBe(200);
  expect((await request('/api/library')).status).toBe(200);
  await request(mangaPath, undefined, true, 'https://read.example.com');
  const audit = await editorUiAttempts(env.DB);
  expect(audit).toHaveLength(1);
  expect(audit[0]).toMatchObject({
    path: '/api/settings',
    mode: 'pass',
    worker_status: 200,
    client_status: 200,
  });
  await expect(setEditorUiMode(env.DB, 'unknown', 'manga')).rejects.toThrow(
    'Expected',
  );
  await expect(setEditorUiMode(env.DB, 'pass', 'other')).rejects.toThrow(
    'Expected',
  );
});

test.each([
  ['manga', mangaPath],
  ['cover', coverPath],
])(
  'reading %s remains pending until an explicit stdin-controlled generation change',
  async (scope, path) => {
    await setEditorUiMode(env.DB, 'hold-read', scope);
    let delivered = false;
    const pending = request(path).then((reply) => {
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
      await setEditorUiMode(env.DB, 'pass', scope);
    }
    expect((await pending).status).toBe(200);
    expect((await editorUiAttempts(env.DB))[0]).toMatchObject({
      worker_status: 200,
      client_status: 200,
    });
  },
);

test.each([
  ['manga', mangaPath],
  ['cover', coverPath],
])(
  'an aborted %s reader leaves the gate without dispatching a late request',
  async (scope, path) => {
    await setEditorUiMode(env.DB, 'hold-read', scope);
    const controller = new AbortController();
    const pending = request(path, undefined, true, origin, controller.signal);
    const rejected = expect(pending).rejects.toThrow();
    await entered();
    controller.abort();
    await rejected;
    expect((await editorUiAttempts(env.DB))[0]).toMatchObject({
      worker_status: null,
      client_status: null,
    });
  },
);

test('confirmation gate holds delivery after the real D1 transaction commits', async () => {
  await setEditorUiMode(env.DB, 'hold-confirm', 'manga');
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
    await setEditorUiMode(env.DB, 'pass', 'manga');
  }
  const ack = settingsMutationResponseSchema.parse(
    await (await pending).json(),
  );
  expect(ack.manga?.revision).toBe(1);
  expect((await editorUiAttempts(env.DB))[0]?.body).toBe(body);
});

test('lost committed ACK retries exact body once, while stale fresh commands still conflict', async () => {
  await setEditorUiMode(env.DB, 'lose-confirm', 'manga');
  const body = command();
  expect((await request('/api/settings/mutations', body)).status).toBe(502);
  expect((await snapshot()).manga?.revision).toBe(1);
  await setEditorUiMode(env.DB, 'pass', 'manga');
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
  const audit = await editorUiAttempts(env.DB);
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
  await setEditorUiMode(env.DB, 'fail-read', 'manga');
  expect((await request(mangaPath)).status).toBe(503);
  await setEditorUiMode(env.DB, 'reject-save', 'manga');
  const rejected = await request('/api/settings/mutations', command());
  expect(rejected.status).toBe(400);
  expect(
    settingsMutationResponseSchema.parse(await rejected.json()).error,
  ).toMatchObject({
    code: BusinessStateErrorCode.INVALID_INPUT,
    retryable: false,
  });
  expect((await snapshot()).manga?.revision).toBe(0);
  await setEditorUiMode(env.DB, 'login-required', 'manga');
  const login = await request(mangaPath);
  expect(login.status).toBe(401);
  expect(login.headers.get('content-type')).toBe('text/html');
  await setEditorUiMode(env.DB, 'pass', 'manga');
  expect((await snapshot()).manga?.revision).toBe(0);
  expect(
    (await editorUiAttempts(env.DB)).every((row) => row.worker_status === null),
  ).toBe(true);
});

test('cover confirmation waits after the real clear commits and never retains image bytes in the audit', async () => {
  await seedCover();
  await setEditorUiMode(env.DB, 'hold-confirm', 'cover');
  const body = clearCommand();
  let delivered = false;
  const pending = request('/api/state/mutations', body).then((reply) => {
    delivered = true;
    return reply;
  });
  try {
    await entered();
    for (
      let attempt = 0;
      attempt < 30 && (await coverSnapshot()).manga?.revision !== 2;
      attempt++
    ) {
      await new Promise<void>((resolve) => setTimeout(resolve, 50));
    }
    const committed = await coverSnapshot();
    expect(committed.accountRevision).toBe(2);
    expect(committed.manga?.customCover).toBeUndefined();
    expect(delivered).toBe(false);
  } finally {
    await setEditorUiMode(env.DB, 'pass', 'cover');
  }
  const ack = stateMutationResponseSchema.parse(await (await pending).json());
  expect(ack.manga?.revision).toBe(2);
  expect(await editorUiAttempts(env.DB)).toEqual([
    expect.objectContaining({
      method: 'POST',
      path: '/api/state/mutations',
      body,
      worker_status: 200,
      client_status: 200,
    }),
  ]);
});

test('lost cover clear ACK retries the identical command without another revision and rejects a fresh stale command', async () => {
  await seedCover();
  await setEditorUiMode(env.DB, 'lose-confirm', 'cover');
  const body = clearCommand();
  expect((await request('/api/state/mutations', body)).status).toBe(502);
  const committed = await coverSnapshot();
  expect(committed.manga?.revision).toBe(2);
  expect(committed.manga?.customCover).toBeUndefined();
  await setEditorUiMode(env.DB, 'pass', 'cover');
  const retry = await request('/api/state/mutations', body);
  expect(retry.status).toBe(200);
  expect(
    stateMutationResponseSchema.parse(await retry.json()).manga?.revision,
  ).toBe(2);
  const stale = await request('/api/state/mutations', clearCommand());
  expect(stale.status).toBe(409);
  expect(
    stateMutationResponseSchema.parse(await stale.json()).error?.code,
  ).toBe(BusinessStateErrorCode.REVISION_CONFLICT);
  expect(await coverSnapshot()).toEqual(committed);
  expect((await editorUiAttempts(env.DB)).slice(0, 2)).toEqual([
    expect.objectContaining({ body, worker_status: 200, client_status: 502 }),
    expect.objectContaining({ body, worker_status: 200, client_status: 200 }),
  ]);
});

test('cover read/rejection/login faults keep the confirmed cover and other scopes stay real', async () => {
  const cover = await seedCover();
  const before = await coverSnapshot();
  await setEditorUiMode(env.DB, 'fail-read', 'cover');
  expect((await request(coverPath)).status).toBe(503);
  expect((await request('/api/settings')).status).toBe(200);
  expect((await request(mangaPath)).status).toBe(200);
  await setEditorUiMode(env.DB, 'reject-save', 'cover');
  const rejected = await request('/api/state/mutations', clearCommand());
  expect(rejected.status).toBe(400);
  expect(
    stateMutationResponseSchema.parse(await rejected.json()).error,
  ).toMatchObject({
    code: BusinessStateErrorCode.INVALID_INPUT,
    retryable: false,
  });
  expect(await coverSnapshot()).toEqual(before);
  await setEditorUiMode(env.DB, 'login-required', 'cover');
  const login = await request(coverPath);
  expect(login.status).toBe(401);
  expect(login.headers.get('content-type')).toBe('text/html');
  expect((await request('/api/covers/' + cover.assetId)).status).toBe(401);
  expect(await coverSnapshot()).toEqual(before);
});

test('cover byte failure preserves the record and retries the same private resource', async () => {
  const cover = await seedCover();
  const before = await coverSnapshot();
  const path = '/api/covers/' + cover.assetId;
  await setEditorUiMode(env.DB, 'fail-image', 'cover');
  expect((await request(path)).status).toBe(503);
  expect((await request(coverPath)).status).toBe(200);
  expect(await coverSnapshot()).toEqual(before);
  await setEditorUiMode(env.DB, 'pass', 'cover');
  const retry = await request(path);
  expect(retry.status).toBe(200);
  expect(new Uint8Array(await retry.arrayBuffer())).toEqual(image);
  expect(await coverSnapshot()).toEqual(before);
  expect(
    (await editorUiAttempts(env.DB)).every((row) => row.body === null),
  ).toBe(true);
});
