import { equals, toJsonString } from '@bufbuild/protobuf';
import {
  stateMutationResponseSchema,
  stateMutationSchema,
} from '@karuyomi/contracts';
import {
  BusinessStateErrorCode as ErrorCode,
  MangaStateResponseSchema,
  StateMutationResponseSchema,
  StateMutationSchema,
} from '@karuyomi/protocol';
import type { requestJson } from '../src/business-request.js';
import type { readMangaState } from '../src/state-store.js';
import { sha256, shouldObserveAck } from './acceptance-ack.ts';
import {
  xkcdChapterKey,
  xkcdLastPageCompletion,
  xkcdMangaKey,
} from './acceptance-xkcd.ts';

export interface ProgressD1ErrorAttempt {
  sequence: number;
  http_status: number;
  error_code: string | null;
  mutation_id: string;
  expected_revision: number;
  account_revision: number;
  manga_revision: number;
  body_sha256: string;
  response_sha256: string;
  receipt_sha256: string | null;
}

export async function prepareProgressD1Error(db: D1Database): Promise<void> {
  await db.batch([
    db.prepare(`CREATE TABLE acceptance_progress_d1_attempts (
      sequence INTEGER PRIMARY KEY,
      http_status INTEGER NOT NULL UNIQUE CHECK (http_status IN (503, 200)),
      error_code TEXT,
      mutation_id TEXT NOT NULL,
      expected_revision INTEGER NOT NULL,
      account_revision INTEGER NOT NULL,
      manga_revision INTEGER NOT NULL,
      body_sha256 TEXT NOT NULL,
      response_sha256 TEXT NOT NULL,
      receipt_sha256 TEXT
    )`),
    db.prepare(`CREATE TABLE acceptance_progress_d1_target (
      slot INTEGER PRIMARY KEY CHECK (slot = 1),
      subject TEXT NOT NULL,
      mutation_id TEXT NOT NULL
    )`),
    // This is the final statement of the real batch: the earlier receipt
    // INSERT, account and manga revisions, and progress UPSERT must roll back.
    db.prepare(`CREATE TRIGGER acceptance_progress_d1_abort
      BEFORE UPDATE OF response_json ON state_mutations
      WHEN NEW.kind = 'manga' AND EXISTS (
        SELECT 1 FROM acceptance_progress_d1_target
        WHERE subject = NEW.subject AND mutation_id = NEW.mutation_id
      )
      BEGIN SELECT RAISE(ABORT, 'acceptance progress D1 error'); END`),
  ]);
}

export async function progressD1ErrorAttempts(db: D1Database) {
  const { results } = await db
    .prepare('SELECT * FROM acceptance_progress_d1_attempts ORDER BY sequence')
    .all<ProgressD1ErrorAttempt>();
  return results.map((attempt) => ({
    ...attempt,
    manga_key: xkcdMangaKey,
    chapter_key: xkcdChapterKey,
  }));
}

export function shouldObserveProgressD1Error(
  request: Request,
  origin: string,
  subject: string,
): boolean {
  return (
    request.headers.get('X-App-Subject') === subject &&
    shouldObserveAck('progress-ack-loss', request, origin)
  );
}

function receiptFor(db: D1Database, subject: string, mutationId: string) {
  return db
    .prepare(
      `SELECT kind, request_hash, response_json FROM state_mutations
      WHERE subject = ? AND mutation_id = ?`,
    )
    .bind(subject, mutationId)
    .first<{ kind: string; request_hash: string; response_json: string }>();
}

async function targetCommand(request: Request, readJson: typeof requestJson) {
  try {
    const mutation = stateMutationSchema.parse(await readJson(request.clone()));
    const completion = xkcdLastPageCompletion(mutation);
    if (completion)
      return {
        mutation,
        completion,
        bodySha256: await sha256(await request.arrayBuffer()),
      };
  } catch {
    // Leave malformed requests to the formal route and its error contract.
  } finally {
    void request.body?.cancel().catch(() => {});
  }
}

/** Observe the real response without changing it or replacing the D1 binding. */
export async function withProgressD1Error(
  request: Request,
  db: D1Database,
  subject: string,
  readers: {
    requestJson: typeof requestJson;
    readMangaState: typeof readMangaState;
  },
  dispatch: () => Promise<Response>,
): Promise<Response> {
  const command = await targetCommand(request, readers.requestJson);
  if (!command) return dispatch();
  const { mutation, completion, bodySha256 } = command,
    { mutationId, expectedRevision } = mutation;
  const prior = await db
    .prepare(
      'SELECT * FROM acceptance_progress_d1_attempts WHERE http_status = 503',
    )
    .first<ProgressD1ErrorAttempt>();
  if (prior) {
    const response = await dispatch();
    if (
      response.status !== 200 ||
      prior.mutation_id !== mutationId ||
      prior.expected_revision !== expectedRevision ||
      prior.body_sha256 !== bodySha256
    )
      return response;
    const text = await response.clone().text();
    const ack = stateMutationResponseSchema.parse(JSON.parse(text));
    const receipt = await receiptFor(db, subject, mutationId);
    if (
      ack.error ||
      ack.mutationId !== mutationId ||
      ack.accountRevision !== prior.account_revision + 1 ||
      ack.manga?.revision !== expectedRevision + 1 ||
      ack.manga.mangaKey !== xkcdMangaKey ||
      ack.progress?.chapterKey !== xkcdChapterKey ||
      !ack.progress.completed ||
      ack.progress.epoch !== completion.progress.epoch ||
      ack.progress.current?.pageKey !== completion.current.pageKey ||
      ack.progress.current.manifestVersion !==
        completion.snapshot.manifestVersion ||
      receipt?.kind !== 'manga' ||
      receipt.request_hash !==
        (await sha256(
          'manga\n' + toJsonString(StateMutationSchema, mutation),
        )) ||
      !equals(
        StateMutationResponseSchema,
        ack,
        stateMutationResponseSchema.parse(JSON.parse(receipt.response_json)),
      )
    )
      throw new Error(
        'Progress D1 error retry has no matching committed receipt',
      );
    await db
      .prepare(
        `INSERT OR IGNORE INTO acceptance_progress_d1_attempts
        (http_status, mutation_id, expected_revision, account_revision,
        manga_revision, body_sha256, response_sha256, receipt_sha256)
        VALUES (200, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .bind(
        mutationId,
        expectedRevision,
        ack.accountRevision,
        ack.manga.revision,
        bodySha256,
        await sha256(text),
        await sha256(receipt.response_json),
      )
      .run();
    return response;
  }

  const before = await readers.readMangaState(
    db,
    subject,
    xkcdMangaKey,
    xkcdChapterKey,
  );
  if (
    before.manga?.revision !== expectedRevision ||
    before.progress?.completed !== false ||
    before.progress.current?.pageKey !== completion.current.pageKey ||
    before.progress.current.manifestVersion !==
      completion.snapshot.manifestVersion
  )
    return dispatch();
  const armed = await db
    .prepare(
      `INSERT OR IGNORE INTO acceptance_progress_d1_target (slot, subject, mutation_id)
      SELECT 1, ?, ? WHERE NOT EXISTS (
        SELECT 1 FROM acceptance_progress_d1_attempts WHERE http_status = 503
      ) RETURNING slot`,
    )
    .bind(subject, mutationId)
    .first<number>('slot');
  if (armed !== 1) return dispatch();

  try {
    const response = await dispatch();
    if (response.status === 200)
      throw new Error('Armed progress D1 trigger did not reject the write');
    if (response.status !== 503) return response;
    const text = await response.clone().text();
    const rejected = stateMutationResponseSchema.parse(JSON.parse(text));
    const after = await readers.readMangaState(
      db,
      subject,
      xkcdMangaKey,
      xkcdChapterKey,
    );
    if (
      rejected.mutationId !== mutationId ||
      rejected.error?.code !== ErrorCode.UNAVAILABLE ||
      !rejected.error.retryable ||
      rejected.manga ||
      rejected.progress ||
      !equals(MangaStateResponseSchema, before, after) ||
      (await receiptFor(db, subject, mutationId)) !== null
    )
      throw new Error('Progress D1 error did not roll back state and receipt');

    await db.batch([
      db
        .prepare(
          `INSERT INTO acceptance_progress_d1_attempts
        (http_status, error_code, mutation_id, expected_revision, account_revision,
        manga_revision, body_sha256, response_sha256)
        VALUES (503, 'UNAVAILABLE', ?, ?, ?, ?, ?, ?)`,
        )
        .bind(
          mutationId,
          expectedRevision,
          after.accountRevision,
          before.manga.revision,
          bodySha256,
          await sha256(text),
        ),
      db.prepare('DROP TRIGGER acceptance_progress_d1_abort'),
    ]);
    return response;
  } finally {
    await db
      .prepare(
        'DELETE FROM acceptance_progress_d1_target WHERE slot = 1 AND subject = ? AND mutation_id = ?',
      )
      .bind(subject, mutationId)
      .run();
  }
}
