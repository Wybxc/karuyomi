import { create, toJsonString } from '@bufbuild/protobuf';
import { applyD1Migrations, createExecutionContext } from 'cloudflare:test';
import { env } from 'cloudflare:workers';
import {
  businessSchemaVersion,
  mangaStateResponseSchema,
  settingsMutationResponseSchema,
  stateMutationResponseSchema,
  stateMutationSchema,
} from '@karuyomi/contracts';
import {
  AppTheme,
  BusinessStateErrorCode as ErrorCode,
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
import {
  prepareProgressD1Error,
  progressD1ErrorAttempts,
} from './acceptance-progress-d1-error.ts';
import {
  xkcdChapterKey as targetChapter,
  xkcdMangaKey as mangaKey,
} from './acceptance-xkcd.ts';

const origin = 'http://127.0.0.1:44123';
const subject = 'acceptance-owner';
const statePath = '/api/state/mutations';
const settingsPath = '/api/settings/mutations';
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
  fixture: AckLossFixture | 'progress-d1-error' | undefined,
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
      ...(fixture === 'progress-d1-error'
        ? { ACCEPTANCE_PROGRESS_D1_ERROR: '1' as const }
        : fixture
          ? { ACCEPTANCE_ACK_LOSS: fixture }
          : {}),
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

function bookmark(revision: number, chapterKey: string, bookmarked: boolean) {
  return toJsonString(
    StateMutationSchema,
    create(StateMutationSchema, {
      schemaVersion: businessSchemaVersion,
      mutationId: crypto.randomUUID(),
      mangaKey,
      expectedRevision: revision,
      operation: { case: 'setBookmark', value: { chapterKey, bookmarked } },
    }),
  );
}

async function targetState(identity = subject) {
  const response = await request(
    undefined,
    `/api/state/manga/${mangaKey}?chapterKey=${targetChapter}`,
    undefined,
    identity,
  );
  expect(response.status).toBe(200);
  return mangaStateResponseSchema.parse(await response.json());
}

afterEach(async () => {
  await env.DB.exec('DROP TABLE IF EXISTS acceptance_ack_attempts');
  await env.DB.batch([
    env.DB.prepare('DROP TRIGGER IF EXISTS acceptance_progress_d1_abort'),
    env.DB.prepare('DROP TABLE IF EXISTS acceptance_progress_d1_target'),
    env.DB.prepare('DROP TABLE IF EXISTS acceptance_progress_d1_attempts'),
  ]);
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

test('the bookmark fault interrupts only the target add after commit and preserves the receipt on replay', async () => {
  const fixture = 'bookmark-ack-loss';
  const owner = 'bookmark-acceptance-owner';
  const mutate = (body: string) => request(fixture, statePath, body, owner);
  await prepareAckLoss(env.DB);

  // Progress, a different chapter, and a target removal must leave the fault unused.
  const progress = await mutate(save(0, false));
  expect(progress.status).toBe(200);
  await expect(progress.json()).resolves.toMatchObject({
    manga: { revision: 1 },
  });
  const unrelated = await mutate(bookmark(1, 'other-chapter', true));
  expect(unrelated.status).toBe(200);
  await expect(unrelated.json()).resolves.toMatchObject({
    manga: { revision: 2 },
  });
  const removal = await mutate(bookmark(2, targetChapter, false));
  expect(removal.status).toBe(200);
  expect(stateMutationResponseSchema.parse(await removal.json())).toMatchObject(
    {
      bookmark: { bookmarked: false },
    },
  );
  const before = await targetState(owner);
  const revision = before.manga!.revision;
  expect(await ackAttempts(env.DB, fixture)).toEqual([]);

  const body = bookmark(revision, targetChapter, true);
  const dropped = await mutate(body);
  expect(dropped.status).toBe(200);
  await expect(dropped.text()).rejects.toThrow();
  const committed = await targetState(owner);
  expect(committed).toMatchObject({
    accountRevision: before.accountRevision + 1,
    manga: { revision: revision + 1 },
    bookmark: { chapterKey: targetChapter, bookmarked: true },
  });
  expect(committed.progress).toEqual(before.progress);

  const replay = await mutate(body);
  expect(replay.status).toBe(200);
  await expect(replay.json()).resolves.toMatchObject({
    manga: { revision: revision + 1 },
    bookmark: { chapterKey: targetChapter, bookmarked: true },
  });
  expect(await targetState(owner)).toEqual(committed);

  const attempts = await ackAttempts(env.DB, fixture);
  expect(attempts).toHaveLength(2);
  const [drop, retry] = attempts;
  expect(drop).toMatchObject({
    sequence: 1,
    drop_ack: 1,
    expected_revision: revision,
    manga_revision: revision + 1,
    body_sha256: createHash('sha256').update(body).digest('hex'),
    mutation_id: stateMutationSchema.parse(JSON.parse(body)).mutationId,
  });
  expect(retry).toEqual({ ...drop, sequence: 2, drop_ack: 0 });
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

test('the opt-in D1 fault rejects the real final receipt update, rolls back and accepts the original request once', async () => {
  const fixture = 'progress-d1-error';
  const owner = 'd1-error-acceptance-owner';
  const mutate = (body: string) => request(fixture, statePath, body, owner);
  const trigger = () =>
    env.DB.prepare(
      "SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'acceptance_progress_d1_abort'",
    ).first<string>('sql');
  const rows = () =>
    env.DB.prepare(
      `SELECT a.revision account_revision, m.revision manga_revision,
      m.state_json manga_json, p.state_json progress_json
      FROM account_state a JOIN manga_state m USING (subject)
      JOIN chapter_progress p USING (subject, manga_key)
      WHERE a.subject = ? AND m.manga_key = ? AND p.chapter_key = ?`,
    )
      .bind(owner, mangaKey, targetChapter)
      .first();
  const digest = (text: string) =>
    createHash('sha256').update(text).digest('hex');

  await prepareProgressD1Error(env.DB);
  expect(await trigger()).toMatch(
    /BEFORE UPDATE OF response_json ON state_mutations/,
  );
  expect((await mutate(save(0, false))).status).toBe(200);
  expect((await mutate(save(1, true, 'other-chapter'))).status).toBe(200);
  expect((await mutate(save(0, true))).status).toBe(409);
  expect(await progressD1ErrorAttempts(env.DB)).toEqual([]);
  expect(await trigger()).not.toBeNull();

  const canonical = await targetState(owner);
  const before = await rows();
  expect(before).toMatchObject({ account_revision: 2, manga_revision: 2 });
  expect(canonical.progress?.completed).toBe(false);
  const body = save(2, true);
  const { mutationId } = stateMutationSchema.parse(JSON.parse(body));
  const receipt = () =>
    env.DB.prepare(
      'SELECT response_json FROM state_mutations WHERE subject = ? AND mutation_id = ?',
    )
      .bind(owner, mutationId)
      .first<string>('response_json');

  const rejected = await mutate(body);
  expect(rejected.status).toBe(503);
  const rejectedText = await rejected.text();
  const error = stateMutationResponseSchema.parse(JSON.parse(rejectedText));
  expect(error).toMatchObject({
    mutationId,
    error: { code: ErrorCode.UNAVAILABLE, retryable: true },
  });
  expect(error.manga).toBeUndefined();
  expect(error.progress).toBeUndefined();
  expect(await receipt()).toBeNull();
  expect(await rows()).toEqual(before);
  expect(await targetState(owner)).toEqual(canonical);
  expect(await trigger()).toBeNull();
  const rejectedAttempt = {
    sequence: 1,
    http_status: 503,
    error_code: 'UNAVAILABLE',
    mutation_id: mutationId,
    expected_revision: 2,
    account_revision: 2,
    manga_revision: 2,
    body_sha256: digest(body),
    response_sha256: digest(rejectedText),
    receipt_sha256: null,
    manga_key: mangaKey,
    chapter_key: targetChapter,
  };
  expect(await progressD1ErrorAttempts(env.DB)).toEqual([rejectedAttempt]);

  const retried = await mutate(body);
  expect(retried.status).toBe(200);
  const ack = await retried.text();
  expect(stateMutationResponseSchema.parse(JSON.parse(ack))).toMatchObject({
    mutationId,
    accountRevision: 3,
    manga: { revision: 3 },
    progress: { completed: true },
  });
  const persisted = await receipt();
  expect(persisted).not.toBeNull();
  if (!persisted) throw new Error('Missing persisted receipt');
  expect(stateMutationResponseSchema.parse(JSON.parse(persisted))).toEqual(
    stateMutationResponseSchema.parse(JSON.parse(ack)),
  );
  const committed = await targetState(owner);
  expect(committed).toMatchObject({
    accountRevision: 3,
    manga: { revision: 3 },
    progress: { completed: true },
  });
  const duplicate = await mutate(body);
  expect(duplicate.status).toBe(200);
  expect(await duplicate.text()).toBe(ack);
  expect(await receipt()).toBe(persisted);
  expect(await targetState(owner)).toEqual(committed);
  expect(await progressD1ErrorAttempts(env.DB)).toEqual([
    rejectedAttempt,
    {
      ...rejectedAttempt,
      sequence: 2,
      http_status: 200,
      error_code: null,
      account_revision: 3,
      manga_revision: 3,
      response_sha256: digest(ack),
      receipt_sha256: digest(persisted),
    },
  ]);
});
