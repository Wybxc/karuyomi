import { create, toJsonString } from '@bufbuild/protobuf';
import {
  businessSchemaVersion,
  mangaStateResponseSchema,
  stateMutationResponseSchema,
} from '@karuyomi/contracts';
import {
  BusinessStateErrorCode,
  StateMutationSchema,
} from '@karuyomi/protocol';
import { applyD1Migrations, createExecutionContext } from 'cloudflare:test';
import { env } from 'cloudflare:workers';
import { exportJWK, exportPKCS8, generateKeyPair } from 'jose';
import { createHash } from 'node:crypto';
import { afterEach, beforeAll, expect, test } from 'vitest';
import { requestJson } from '../src/business-request.js';
import { readMangaState } from '../src/state-store.js';
import acceptance from './acceptance-entry.ts';
import {
  holdProgressRace,
  prepareProgressRace,
  progressRaceAttempts,
  progressRaceDatabase,
} from './acceptance-progress-race.ts';
import { xkcdChapterKey, xkcdMangaKey } from './acceptance-xkcd.ts';

const origin = 'http://127.0.0.1:44125';
const mutationPath = '/api/state/mutations';
const manifestVersion = 'manifest';
const pageKeys = ['manifest:0', 'manifest:1'];
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
  await env.DB.exec('DROP TABLE IF EXISTS acceptance_progress_race');
});

function command(
  intent: 'observe' | 'complete' | 'reset',
  expectedRevision: number,
  { chapterKey = xkcdChapterKey, epoch = 0 } = {},
) {
  const snapshot = { chapterKey, manifestVersion, pageKeys };
  const anchor = {
    chapterKey,
    manifestVersion,
    pageKey: pageKeys[1]!,
    pageIndexHint: 1,
  };
  const mutation = create(StateMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    mangaKey: xkcdMangaKey,
    expectedRevision,
    operation:
      intent === 'reset'
        ? {
            case: 'resetProgress',
            value: { snapshot },
          }
        : {
            case: 'saveProgress',
            value: {
              snapshot,
              progress: {
                chapterKey,
                current: anchor,
                furthest: anchor,
                epoch,
                completed: intent === 'complete',
              },
            },
          },
  });
  const body = toJsonString(StateMutationSchema, mutation);
  return {
    body,
    intent,
    id: mutation.mutationId,
    hash: createHash('sha256').update(body).digest('hex'),
  };
}

function post(subject: string, body: string, clientOrigin = origin): Request {
  return new Request(origin + mutationPath, {
    method: 'POST',
    headers: {
      Origin: clientOrigin,
      'X-App-Request': '1',
      'X-App-Subject': subject,
      'Content-Type': 'application/json',
    },
    body,
  });
}

function fetchAcceptance(subject: string, request: Request, enabled = true) {
  return acceptance.fetch(
    request,
    {
      ...env,
      ...credentials,
      APP_ORIGIN: origin,
      ACCEPTANCE_SUBJECT: subject,
      ...(enabled ? { ACCEPTANCE_PROGRESS_CAS_RACE: '1' } : {}),
    },
    createExecutionContext(),
  );
}

async function readChapter(subject: string) {
  const response = await fetchAcceptance(
    subject,
    new Request(
      origin + `/api/state/manga/${xkcdMangaKey}?chapterKey=${xkcdChapterKey}`,
      { headers: { 'X-App-Subject': subject } },
    ),
  );
  expect(response.status).toBe(200);
  return mangaStateResponseSchema.parse(await response.json());
}

test.each(['complete', 'reset'] as const)(
  'the real progress CAS adjudicates simultaneous complete/reset (%s arrives first)',
  async (firstIntent) => {
    const subject = `progress-race-${firstIntent}`;
    await prepareProgressRace(env.DB);

    // A completion in another chapter and ordinary target observation are never gated.
    for (const body of [
      command('complete', 0, { chapterKey: 'other-chapter' }).body,
      command('observe', 1).body,
    ]) {
      const response = await fetchAcceptance(subject, post(subject, body));
      expect(response.status).toBe(200);
      await response.body?.cancel();
    }
    expect(await progressRaceAttempts(env.DB)).toEqual([]);
    const before = await readChapter(subject);
    expect(before).toMatchObject({
      accountRevision: 2,
      manga: { revision: 2 },
      progress: {
        current: { pageKey: pageKeys[1] },
        furthest: { pageKey: pageKeys[1] },
        completed: false,
        epoch: 0,
      },
    });

    const intents = [
      command(firstIntent, 2),
      command(firstIntent === 'complete' ? 'reset' : 'complete', 2),
    ];
    const [first, second] = intents;
    const wrongOrigin = await fetchAcceptance(
      subject,
      post(subject, first!.body, 'https://not-the-app.test'),
    );
    expect(wrongOrigin.status).toBe(403);
    expect(await progressRaceAttempts(env.DB)).toEqual([]);

    const firstResponse = fetchAcceptance(subject, post(subject, first!.body));
    await expect
      .poll(() => progressRaceAttempts(env.DB))
      .toMatchObject([
        {
          sequence: 1,
          mutation_id: first!.id,
          http_status: null,
          dispatch_at_ms: null,
        },
      ]);
    expect(await readChapter(subject)).toEqual(before);
    const duplicate = await fetchAcceptance(
      subject,
      post(subject, command(firstIntent, 2).body),
    );
    expect(duplicate.status).toBe(503);
    expect(await progressRaceAttempts(env.DB)).toHaveLength(1);

    const responses = await Promise.all([
      firstResponse,
      fetchAcceptance(subject, post(subject, second!.body)),
    ]);
    expect(responses.map((response) => response.status).sort()).toEqual([
      200, 409,
    ]);
    const responsesWithState = await Promise.all(
      responses.map(async (response) => {
        const raw = await response.text();
        return {
          status: response.status,
          body: stateMutationResponseSchema.parse(JSON.parse(raw)),
          hash: createHash('sha256').update(raw).digest('hex'),
        };
      }),
    );
    const winner = responsesWithState.find(({ status }) => status === 200)!;
    const loser = responsesWithState.find(({ status }) => status === 409)!;
    expect(winner.body.error).toBeUndefined();
    expect(loser.body.error).toMatchObject({
      code: BusinessStateErrorCode.REVISION_CONFLICT,
      retryable: false,
    });
    expect(loser.body.progress).toEqual(winner.body.progress);
    expect(loser.body.manga).toEqual(winner.body.manga);
    const completeWon =
      intents.find(({ id }) => id === winner.body.mutationId)?.intent ===
      'complete';
    expect(winner.body.progress).toMatchObject({
      epoch: completeWon ? 0 : 1,
      completed: completeWon,
      current: { pageKey: pageKeys[completeWon ? 1 : 0] },
    });
    if (completeWon)
      expect(winner.body.progress?.furthest?.pageKey).toBe(pageKeys[1]);
    else expect(winner.body.progress?.furthest).toBeUndefined();

    const audit = await progressRaceAttempts(env.DB);
    expect(audit).toHaveLength(2);
    const laterArrival = Math.max(
      ...audit.map((attempt) => attempt.arrived_at_ms),
    );
    for (const [index, input] of intents.entries()) {
      const attempt = audit[index]!;
      const won = winner.body.mutationId === input.id;
      expect(attempt).toMatchObject({
        mutation_id: input.id,
        intent: input.intent,
        body_sha256: input.hash,
        expected_revision: 2,
        before_account_revision: 2,
        before_epoch: 0,
        expired: 0,
        http_status: won ? 200 : 409,
        error_code: won ? null : BusinessStateErrorCode.REVISION_CONFLICT,
        account_revision: 3,
        manga_revision: 3,
        epoch: completeWon ? 0 : 1,
        completed: Number(completeWon),
        current_page_key: pageKeys[completeWon ? 1 : 0],
        furthest_page_key: completeWon ? pageKeys[1] : null,
        ack_sha256: (won ? winner : loser).hash,
        receipt_sha256: won ? expect.stringMatching(/^[a-f0-9]{64}$/) : null,
      });
      expect(attempt.release_at_ms).toBe(laterArrival);
      expect(attempt.dispatch_at_ms).toBeGreaterThanOrEqual(
        attempt.release_at_ms!,
      );
      expect(attempt.batch_ready_at_ms).toBeGreaterThanOrEqual(
        attempt.dispatch_at_ms!,
      );
      expect(attempt.response_at_ms).toBeGreaterThanOrEqual(
        Math.max(...audit.map((attempt) => attempt.batch_ready_at_ms!)),
      );
    }
    expect(audit[0]!.release_at_ms).toBe(audit[1]!.release_at_ms);
    expect(audit[0]!.snapshot_sha256).toBe(audit[1]!.snapshot_sha256);
    expect(audit[0]!.state_sha256).toBe(audit[1]!.state_sha256);
    const overlap =
      Math.min(...audit.map((attempt) => attempt.response_at_ms!)) -
      Math.max(...audit.map((attempt) => attempt.dispatch_at_ms!));
    expect(overlap).toBeGreaterThan(0);

    const after = await readChapter(subject);
    expect(after.accountRevision).toBe(3);
    expect(after.manga).toEqual(winner.body.manga);
    expect(after.progress).toEqual(winner.body.progress);
    const { results: receipts } = await env.DB.prepare(
      `SELECT mutation_id FROM state_mutations
    WHERE subject = ?1 AND mutation_id IN (?2, ?3)`,
    )
      .bind(subject, first!.id, second!.id)
      .all();
    expect(receipts).toEqual([{ mutation_id: winner.body.mutationId }]);

    // Reopening then making a new intent against the winner's revision is not gated.
    const next = command(completeWon ? 'reset' : 'complete', 3, {
      epoch: completeWon ? 0 : 1,
    });
    const followup = await fetchAcceptance(subject, post(subject, next.body));
    expect(followup.status).toBe(200);
    expect(
      stateMutationResponseSchema.parse(await followup.json()),
    ).toMatchObject({
      mutationId: next.id,
      accountRevision: 4,
      manga: { revision: 4 },
    });
    expect(await progressRaceAttempts(env.DB)).toEqual(audit);
  },
);

test('an unpaired target times out without dispatch, and default acceptance is unchanged', async () => {
  const subject = 'progress-race-timeout';
  // With no test fixture, even an otherwise eligible last-page completion is a normal request.
  const first = await fetchAcceptance(
    subject,
    post(subject, command('observe', 0).body),
    false,
  );
  expect(first.status).toBe(200);
  await first.body?.cancel();
  const defaultSubject = 'progress-race-default';
  const defaultWrite = await fetchAcceptance(
    defaultSubject,
    post(defaultSubject, command('complete', 0).body),
    false,
  );
  expect(defaultWrite.status).toBe(200);
  await defaultWrite.body?.cancel();
  expect(
    await env.DB.prepare(
      "SELECT name FROM sqlite_master WHERE name = 'acceptance_progress_race'",
    ).first(),
  ).toBeNull();

  const before = await readChapter(subject);
  await prepareProgressRace(env.DB);
  const withoutBaseline = await fetchAcceptance(
    'empty-progress-race',
    post('empty-progress-race', command('reset', 0).body),
  );
  expect(withoutBaseline.status).toBe(503);
  expect(await progressRaceAttempts(env.DB)).toEqual([]);

  const complete = command('complete', 1);
  const timedOut = await holdProgressRace(
    post(subject, complete.body),
    env.DB,
    origin,
    subject,
    { requestJson, readMangaState },
    25,
  );
  expect(timedOut).toBeInstanceOf(Response);
  if (!(timedOut instanceof Response))
    throw new Error('Expected progress race timeout response');
  expect(timedOut.status).toBe(503);
  await timedOut.body?.cancel();
  const late = await fetchAcceptance(
    subject,
    post(subject, command('reset', 1).body),
  );
  expect(late.status).toBe(503);
  await late.body?.cancel();
  expect(await progressRaceAttempts(env.DB)).toMatchObject([
    {
      mutation_id: complete.id,
      expired: 1,
      dispatch_at_ms: null,
      http_status: null,
    },
  ]);
  expect(await readChapter(subject)).toEqual(before);
});

test('two admitted requests do not write if one never reaches its D1 batch', async () => {
  const subject = 'progress-race-batch-timeout';
  await prepareProgressRace(env.DB);
  const seed = await fetchAcceptance(
    subject,
    post(subject, command('observe', 0).body),
  );
  expect(seed.status).toBe(200);
  await seed.body?.cancel();
  const before = await readChapter(subject);
  const contenders = await Promise.all(
    (['complete', 'reset'] as const).map((intent) =>
      holdProgressRace(
        post(subject, command(intent, 1).body),
        env.DB,
        origin,
        subject,
        { requestJson, readMangaState },
      ),
    ),
  );
  expect(
    contenders.every((entry) => entry && !(entry instanceof Response)),
  ).toBe(true);
  const first = contenders[0];
  if (!first || first instanceof Response)
    throw new Error('Missing admitted progress race attempt');
  const blocked = progressRaceDatabase(env.DB, first, 25);
  await expect(
    blocked.batch([
      blocked
        .prepare(
          'UPDATE account_state SET revision = revision + 1 WHERE subject = ?',
        )
        .bind(subject),
    ]),
  ).rejects.toThrow('Progress race timed out before the atomic D1 batch');
  const audit = await progressRaceAttempts(env.DB);
  expect(audit).toHaveLength(2);
  expect(
    audit.every((row) => row.expired === 1 && row.http_status === null),
  ).toBe(true);
  expect(audit.filter((row) => row.batch_ready_at_ms !== null)).toHaveLength(1);
  expect(await readChapter(subject)).toEqual(before);
});
