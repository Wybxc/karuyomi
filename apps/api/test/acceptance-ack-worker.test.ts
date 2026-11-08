import { create, toJsonString } from '@bufbuild/protobuf';
import { applyD1Migrations, createExecutionContext } from 'cloudflare:test';
import { env } from 'cloudflare:workers';
import {
  businessSchemaVersion,
  mangaStateResponseSchema,
  settingsMutationResponseSchema,
} from '@karuyomi/contracts';
import {
  AppTheme,
  ReaderBackground,
  ReaderFit,
  ReaderInputPreset,
  ReaderMode,
  ReaderPageLayout,
  SettingsMutationSchema,
  StateMutationSchema,
} from '@karuyomi/protocol';
import { exportJWK, exportPKCS8, generateKeyPair } from 'jose';
import { createHash } from 'node:crypto';
import { afterEach, beforeAll, expect, test } from 'vitest';
import acceptance from './acceptance-entry.ts';
import {
  ackAttempts,
  prepareAckLoss,
  type AckLossFixture,
} from './acceptance-ack.ts';

const origin = 'http://127.0.0.1:44123';
const subject = 'acceptance-owner';
const statePath = '/api/state/mutations';
const settingsPath = '/api/settings/mutations';
// Exact stable English xkcd SINGLE /3319/ identities from the reader.
const mangaKey =
  '62c3d5a079471dde67f80c71005112fde078e4fa3111e6faedc9757350392a6f';
const targetChapter =
  '3ebd1a075e8cc6fad4cae9daa7595caac80545bdf9499496417bb3d3b6b1142c';
const secondPage = 'manifest:1';

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

function request(
  fixture: AckLossFixture | undefined,
  path: string,
  body?: string,
  identity = subject,
) {
  return acceptance.fetch(
    new Request(origin + path, {
      method: body === undefined ? 'GET' : 'POST',
      headers: {
        Origin: origin,
        'X-App-Request': '1',
        'X-App-Subject': identity,
        'Content-Type': 'application/json',
      },
      ...(body === undefined ? {} : { body }),
    }),
    {
      ...env,
      ...credentials,
      APP_ORIGIN: origin,
      ACCEPTANCE_SUBJECT: identity,
      ...(fixture ? { ACCEPTANCE_ACK_LOSS: fixture } : {}),
    },
    createExecutionContext(),
  );
}

function save(
  revision: number,
  completed: boolean,
  chapterKey = targetChapter,
) {
  const anchor = {
    chapterKey,
    pageKey: secondPage,
    pageIndexHint: 1,
    manifestVersion: 'manifest',
  };
  return toJsonString(
    StateMutationSchema,
    create(StateMutationSchema, {
      schemaVersion: businessSchemaVersion,
      mutationId: crypto.randomUUID(),
      mangaKey,
      expectedRevision: revision,
      operation: {
        case: 'saveProgress',
        value: {
          snapshot: {
            chapterKey,
            manifestVersion: 'manifest',
            pageKeys: ['manifest:0', secondPage],
          },
          progress: {
            chapterKey,
            current: anchor,
            furthest: anchor,
            completed,
          },
        },
      },
    }),
  );
}

async function targetState() {
  const response = await request(
    undefined,
    `/api/state/manga/${mangaKey}?chapterKey=${targetChapter}`,
  );
  expect(response.status).toBe(200);
  return mangaStateResponseSchema.parse(await response.json());
}

afterEach(async () => {
  await env.DB.exec('DROP TABLE IF EXISTS acceptance_ack_attempts');
});

test('the opt-in progress fault drops the completed target ACK after D1 commits and releases the exact replay', async () => {
  const fixture = 'progress-ack-loss';
  await prepareAckLoss(env.DB);

  // Automatic last-page observations and completion of another chapter must
  // not consume the fault. Neither should a target write rejected by CAS.
  const initial = await request(fixture, statePath, save(0, false));
  expect(initial.status).toBe(200);
  await expect(initial.json()).resolves.toMatchObject({
    manga: { revision: 1 },
  });
  const otherChapter = await request(
    fixture,
    statePath,
    save(1, true, 'other-chapter'),
  );
  expect(otherChapter.status).toBe(200);
  await expect(otherChapter.json()).resolves.toMatchObject({
    manga: { revision: 2 },
  });
  const conflict = await request(fixture, statePath, save(0, true));
  expect(conflict.status).toBe(409);
  await expect(conflict.json()).resolves.toHaveProperty('error');
  expect(await ackAttempts(env.DB, fixture)).toEqual([]);

  const body = save(2, true);
  const dropped = await request(fixture, statePath, body);
  expect(dropped.status).toBe(200);
  await expect(dropped.text()).rejects.toThrow();
  const committed = await targetState();
  expect(committed).toMatchObject({
    accountRevision: 3,
    manga: { revision: 3 },
    progress: {
      chapterKey: targetChapter,
      current: { pageKey: secondPage },
      epoch: 0,
      completed: true,
    },
  });

  const replay = await request(fixture, statePath, body);
  expect(replay.status).toBe(200);
  await expect(replay.json()).resolves.toMatchObject({
    accountRevision: 3,
    manga: { revision: 3 },
    progress: { completed: true },
  });
  expect(await targetState()).toEqual(committed);

  const [drop, retry] = await ackAttempts(env.DB, fixture);
  expect(drop).toMatchObject({
    sequence: 1,
    drop_ack: 1,
    expected_revision: 2,
    account_revision: 3,
    manga_revision: 3,
    manga_key: mangaKey,
    chapter_key: targetChapter,
    body_sha256: createHash('sha256').update(body).digest('hex'),
  });
  expect(retry).toEqual({ ...drop, sequence: 2, drop_ack: 0 });
  expect(await ackAttempts(env.DB, fixture)).toHaveLength(2);
});

test('default acceptance does not intercept and the existing settings fixture preserves its exact replay audit', async () => {
  const unchanged = await request(
    undefined,
    statePath,
    save(0, true),
    'default-acceptance-owner',
  );
  expect(unchanged.status).toBe(200);
  await expect(unchanged.json()).resolves.toMatchObject({
    progress: { completed: true },
  });
  expect(
    await env.DB.prepare(
      "SELECT name FROM sqlite_master WHERE name = 'acceptance_ack_attempts'",
    ).first(),
  ).toBeNull();

  const fixture = 'settings-ack-loss';
  await prepareAckLoss(env.DB);
  const body = toJsonString(
    SettingsMutationSchema,
    create(SettingsMutationSchema, {
      schemaVersion: businessSchemaVersion,
      mutationId: crypto.randomUUID(),
      operation: {
        case: 'setGlobal',
        value: {
          theme: AppTheme.DARK,
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
    }),
  );
  const dropped = await request(
    fixture,
    settingsPath,
    body,
    'settings-acceptance-owner',
  );
  expect(dropped.status).toBe(200);
  await expect(dropped.text()).rejects.toThrow();

  const replay = await request(
    fixture,
    settingsPath,
    body,
    'settings-acceptance-owner',
  );
  expect(replay.status).toBe(200);
  const saved = settingsMutationResponseSchema.parse(await replay.json());
  expect(saved.global?.revision).toBe(1);
  const attempts = await ackAttempts(env.DB, fixture);
  expect(attempts).toHaveLength(2);
  const [drop, retry] = attempts;
  expect(drop).toMatchObject({ expected_revision: 0, global_revision: 1 });
  expect(retry).toEqual({ ...drop, sequence: 2, drop_ack: 0 });
});
