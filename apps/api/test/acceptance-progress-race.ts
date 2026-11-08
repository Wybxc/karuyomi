import { create, equals, toJsonString } from '@bufbuild/protobuf';
import {
  stateMutationResponseSchema,
  stateMutationSchema,
} from '@karuyomi/contracts';
import {
  BusinessStateErrorCode,
  ChapterSnapshotSchema,
  MangaStateResponseSchema,
  StateMutationResponseSchema,
  StateMutationSchema,
  type ReadingAnchor,
} from '@karuyomi/protocol';
import type { requestJson } from '../src/business-request.js';
import type { readMangaState } from '../src/state-store.js';
import { sha256 } from './acceptance-ack.ts';
import { xkcdChapterKey, xkcdMangaKey } from './acceptance-xkcd.ts';

const waitBudgetMs = 15_000;
const batchBudgetMs = 5_000;
const pollIntervalMs = 25;

interface Arrival {
  sequence: number;
  mutation_id: string;
  intent: 'complete' | 'reset';
  body_sha256: string;
  snapshot_sha256: string;
  expected_revision: number;
  before_account_revision: number;
  before_epoch: number;
  arrived_at_ms: number;
}

interface RaceAttempt extends Arrival {
  expired: number;
  release_at_ms: number | null;
  dispatch_at_ms: number | null;
  batch_ready_at_ms: number | null;
  response_at_ms: number | null;
  http_status: number | null;
  error_code: BusinessStateErrorCode | null;
  account_revision: number | null;
  manga_revision: number | null;
  epoch: number | null;
  completed: number | null;
  current_page_key: string | null;
  furthest_page_key: string | null;
  state_sha256: string | null;
  ack_sha256: string | null;
  receipt_sha256: string | null;
}

interface AdmittedAttempt {
  arrival: Arrival;
  requestHash: string;
  releaseAtMs: number;
  manifestVersion: string;
  firstPage: string;
  lastPage: string;
  reversedOrder: boolean;
}

export async function prepareProgressRace(db: D1Database): Promise<void> {
  await db
    .prepare(
      `CREATE TABLE acceptance_progress_race (
    sequence INTEGER PRIMARY KEY CHECK (sequence IN (1, 2)),
    mutation_id TEXT NOT NULL UNIQUE,
    intent TEXT NOT NULL UNIQUE CHECK (intent IN ('complete', 'reset')),
    body_sha256 TEXT NOT NULL,
    snapshot_sha256 TEXT NOT NULL,
    expected_revision INTEGER NOT NULL,
    before_account_revision INTEGER NOT NULL,
    before_epoch INTEGER NOT NULL,
    arrived_at_ms INTEGER NOT NULL,
    expired INTEGER NOT NULL DEFAULT 0 CHECK (expired IN (0, 1)),
    release_at_ms INTEGER,
    dispatch_at_ms INTEGER,
    batch_ready_at_ms INTEGER,
    response_at_ms INTEGER,
    http_status INTEGER,
    error_code INTEGER,
    account_revision INTEGER,
    manga_revision INTEGER,
    epoch INTEGER,
    completed INTEGER,
    current_page_key TEXT,
    furthest_page_key TEXT,
    state_sha256 TEXT,
    ack_sha256 TEXT,
    receipt_sha256 TEXT
  )`,
    )
    .run();
}

export async function progressRaceAttempts(db: D1Database) {
  const { results } = await db
    .prepare('SELECT * FROM acceptance_progress_race ORDER BY sequence')
    .all<RaceAttempt>();
  return results.map((row) => ({
    ...row,
    manga_key: xkcdMangaKey,
    chapter_key: xkcdChapterKey,
  }));
}

function gateFailure(reason: string): Response {
  return Response.json(
    { acceptanceFixtureError: reason },
    {
      status: 503,
      headers: { 'Cache-Control': 'no-store' },
    },
  );
}

async function waitForPair(
  db: D1Database,
  stage: 'arrived_at_ms' | 'batch_ready_at_ms',
  budgetMs: number,
): Promise<number | undefined> {
  while (true) {
    const gate = await db
      .prepare(
        `SELECT COUNT(${stage}) AS ready, MAX(expired) AS expired,
        MIN(${stage}) AS first_ready, MAX(${stage}) AS last_ready
        FROM acceptance_progress_race`,
      )
      .first<{
        ready: number;
        expired: number | null;
        first_ready: number | null;
        last_ready: number | null;
      }>();
    if (!gate || gate.expired || gate.first_ready === null) return;
    if (gate.ready === 2 && gate.last_ready !== null) return gate.last_ready;
    const remaining = gate.first_ready + budgetMs - Date.now();
    if (remaining <= 0) {
      // Expiry and the peer's arrival are serialized by D1.
      await db
        .prepare(
          `UPDATE acceptance_progress_race SET expired = 1
          WHERE (SELECT COUNT(${stage}) FROM acceptance_progress_race) = 1`,
        )
        .run();
    } else {
      await scheduler.wait(Math.min(pollIntervalMs, remaining));
    }
  }
}

function atPage(
  anchor: ReadingAnchor | undefined,
  manifest: string,
  pageKey: string,
  index: number,
): boolean {
  return (
    anchor?.chapterKey === xkcdChapterKey &&
    anchor.manifestVersion === manifest &&
    anchor.pageKey === pageKey &&
    anchor.pageIndexHint === index
  );
}

export async function holdProgressRace(
  request: Request,
  db: D1Database,
  origin: string,
  subject: string,
  readers: {
    requestJson: typeof requestJson;
    readMangaState: typeof readMangaState;
  },
  budgetMs = waitBudgetMs,
): Promise<AdmittedAttempt | Response | undefined> {
  const url = new URL(request.url);
  if (
    request.method !== 'POST' ||
    url.origin !== origin ||
    url.hostname !== '127.0.0.1' ||
    url.pathname !== '/api/state/mutations' ||
    url.search !== '' ||
    request.headers.get('Origin') !== origin ||
    request.headers.get('X-App-Subject') !== subject ||
    request.headers.get('X-App-Request') !== '1'
  )
    return;

  let mutation;
  try {
    mutation = stateMutationSchema.parse(
      await readers.requestJson(request.clone()),
    );
  } catch {
    return;
  }
  const { operation, expectedRevision, mutationId } = mutation;
  if (
    mutation.mangaKey !== xkcdMangaKey ||
    (operation.case !== 'saveProgress' && operation.case !== 'resetProgress')
  )
    return;
  const { snapshot, reversedOrder } = operation.value;
  const [firstPage, lastPage] = snapshot?.pageKeys ?? [];
  if (
    snapshot?.chapterKey !== xkcdChapterKey ||
    snapshot.pageKeys.length !== 2 ||
    !firstPage ||
    !lastPage
  )
    return;
  const manifestVersion = snapshot.manifestVersion;
  const completion =
    operation.case === 'saveProgress' ? operation.value.progress : undefined;
  if (
    operation.case === 'saveProgress' &&
    (!completion?.completed ||
      !atPage(completion.current, manifestVersion, lastPage, 1) ||
      !atPage(completion.furthest, manifestVersion, lastPage, 1))
  )
    return; // Automatic page observations do not consume a slot.

  const first = await db
    .prepare(
      `SELECT expected_revision, expired
    FROM acceptance_progress_race WHERE sequence = 1`,
    )
    .first<{
      expected_revision: number;
      expired: number;
    }>();
  // A later intent with the current revision can use the normal Worker.
  if (first && expectedRevision !== first.expected_revision) return;
  if (first?.expired) return gateFailure('Progress race slot expired');

  const baseline = await readers.readMangaState(
    db,
    subject,
    xkcdMangaKey,
    xkcdChapterKey,
  );
  if (
    baseline.manga?.revision !== expectedRevision ||
    baseline.manga.resume?.chapterKey !== xkcdChapterKey ||
    baseline.manga.resume.reversedOrder !== reversedOrder ||
    !baseline.progress ||
    baseline.progress.completed ||
    !atPage(baseline.progress.current, manifestVersion, lastPage, 1) ||
    !atPage(baseline.progress.furthest, manifestVersion, lastPage, 1) ||
    (completion && completion.epoch !== baseline.progress.epoch)
  )
    return gateFailure(
      'Progress race requires the same confirmed, unfinished last page',
    );

  const [bodyHash, snapshotHash, requestHash] = await Promise.all([
    request.clone().arrayBuffer().then(sha256),
    sha256(toJsonString(ChapterSnapshotSchema, snapshot)),
    sha256('manga\n' + toJsonString(StateMutationSchema, mutation)),
  ]);
  const intent = completion ? 'complete' : 'reset';
  const arrival = await db
    .prepare(
      `INSERT INTO acceptance_progress_race (
      mutation_id, intent, body_sha256, snapshot_sha256, expected_revision,
      before_account_revision, before_epoch, arrived_at_ms
    )
    SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8
    WHERE (SELECT COUNT(*) FROM acceptance_progress_race) < 2
      AND NOT EXISTS (SELECT 1 FROM acceptance_progress_race WHERE
        expired = 1 OR expected_revision <> ?5 OR before_account_revision <> ?6
        OR before_epoch <> ?7 OR snapshot_sha256 <> ?4 OR arrived_at_ms + ?9 <= ?8)
      AND EXISTS (SELECT 1 FROM account_state WHERE subject = ?10 AND revision = ?6)
      AND EXISTS (SELECT 1 FROM manga_state WHERE subject = ?10 AND manga_key = ?11 AND revision = ?5)
    ON CONFLICT DO NOTHING RETURNING *`,
    )
    .bind(
      mutationId,
      intent,
      bodyHash,
      snapshotHash,
      expectedRevision,
      baseline.accountRevision,
      baseline.progress.epoch,
      Date.now(),
      budgetMs,
      subject,
      xkcdMangaKey,
    )
    .first<Arrival>();
  if (!arrival)
    return gateFailure('Progress race slot is closed, duplicated or stale');
  console.log('ACCEPTANCE_PROGRESS_RACE_ARRIVAL=' + JSON.stringify(arrival));

  const releaseAtMs = await waitForPair(db, 'arrived_at_ms', budgetMs);
  if (releaseAtMs === undefined)
    return gateFailure('Progress race timed out before release');
  return {
    arrival,
    requestHash,
    manifestVersion,
    firstPage,
    lastPage,
    reversedOrder,
    releaseAtMs,
  };
}

export function progressRaceDatabase(
  db: D1Database,
  attempt: AdmittedAttempt,
  budgetMs = batchBudgetMs,
): D1Database {
  // Only an admitted acceptance request gets this wrapper. Let the real
  // Worker finish authorization, reading, and preflight before synchronizing
  // the original D1 batches. A timed release alone cannot guarantee both
  // requests reach the atomic CAS.
  return new Proxy(db, {
    get(database, property) {
      if (property === 'batch')
        return async <T>(statements: D1PreparedStatement[]) => {
          const arrived = await database
            .prepare(
              `UPDATE acceptance_progress_race SET batch_ready_at_ms = ?2
              WHERE sequence = ?1 AND batch_ready_at_ms IS NULL AND expired = 0
              AND NOT EXISTS (SELECT 1 FROM acceptance_progress_race
                WHERE batch_ready_at_ms + ?3 <= ?2)
              RETURNING sequence`,
            )
            .bind(attempt.arrival.sequence, Date.now(), budgetMs)
            .first();
          if (
            !arrived ||
            (await waitForPair(database, 'batch_ready_at_ms', budgetMs)) ===
              undefined
          )
            throw new Error(
              'Progress race timed out before the atomic D1 batch',
            );
          return database.batch<T>(statements);
        };
      const value: unknown = Reflect.get(database, property, database);
      return typeof value === 'function' ? value.bind(database) : value;
    },
  });
}

export async function observeProgressRace(
  db: D1Database,
  subject: string,
  attempt: AdmittedAttempt,
  response: Response,
  dispatchAtMs: number,
  responseAtMs: number,
): Promise<void> {
  const ackText = await response.clone().text();
  const ack = stateMutationResponseSchema.parse(JSON.parse(ackText));
  const { arrival, manifestVersion, firstPage, lastPage } = attempt;
  const { manga, progress } = ack;
  if (
    ack.mutationId !== arrival.mutation_id ||
    ack.accountRevision !== arrival.before_account_revision + 1 ||
    manga?.mangaKey !== xkcdMangaKey ||
    manga.revision !== arrival.expected_revision + 1 ||
    manga.resume?.chapterKey !== xkcdChapterKey ||
    manga.resume.reversedOrder !== attempt.reversedOrder ||
    progress?.chapterKey !== xkcdChapterKey
  )
    throw new Error('Unexpected progress race response identity or revision');

  const completeWon =
    progress.completed &&
    progress.epoch === arrival.before_epoch &&
    atPage(progress.current, manifestVersion, lastPage, 1) &&
    atPage(progress.furthest, manifestVersion, lastPage, 1);
  const resetWon =
    !progress.completed &&
    progress.epoch === arrival.before_epoch + 1 &&
    atPage(progress.current, manifestVersion, firstPage, 0) &&
    !progress.furthest;
  if (!completeWon && !resetWon)
    throw new Error('Progress race result did not match completion or reset');
  const won = arrival.intent === (completeWon ? 'complete' : 'reset');
  const receipt = await db
    .prepare(
      `SELECT kind, request_hash, attempt_nonce, response_json
    FROM state_mutations WHERE subject = ? AND mutation_id = ?`,
    )
    .bind(subject, arrival.mutation_id)
    .first<{
      kind: string;
      request_hash: string;
      attempt_nonce: string;
      response_json: string;
    }>();
  let receiptHash: string | null = null;
  if (won) {
    if (
      response.status !== 200 ||
      ack.error ||
      receipt?.kind !== 'manga' ||
      receipt.request_hash !== attempt.requestHash ||
      !equals(
        StateMutationResponseSchema,
        ack,
        stateMutationResponseSchema.parse(JSON.parse(receipt.response_json)),
      )
    )
      throw new Error('Winning progress race ACK has no matching D1 receipt');
    receiptHash = await sha256(
      JSON.stringify([
        receipt.kind,
        receipt.request_hash,
        receipt.attempt_nonce,
        receipt.response_json,
      ]),
    );
  } else if (
    response.status !== 409 ||
    ack.error?.code !== BusinessStateErrorCode.REVISION_CONFLICT ||
    ack.error.retryable ||
    receipt !== null
  )
    throw new Error('Expected a losing progress CAS without a D1 receipt');

  const [ackHash, stateHash] = await Promise.all([
    sha256(ackText),
    sha256(
      toJsonString(
        MangaStateResponseSchema,
        create(MangaStateResponseSchema, {
          schemaVersion: ack.schemaVersion,
          accountRevision: ack.accountRevision,
          manga,
          progress,
          categoryCatalog: ack.categoryCatalog,
        }),
      ),
    ),
  ]);
  const outcome = await db
    .prepare(
      `UPDATE acceptance_progress_race SET
    release_at_ms = ?2, dispatch_at_ms = ?3, response_at_ms = ?4, http_status = ?5,
    error_code = ?6, account_revision = ?7, manga_revision = ?8, epoch = ?9,
    completed = ?10, current_page_key = ?11, furthest_page_key = ?12,
    state_sha256 = ?13, ack_sha256 = ?14, receipt_sha256 = ?15
    WHERE sequence = ?1 RETURNING *`,
    )
    .bind(
      arrival.sequence,
      attempt.releaseAtMs,
      dispatchAtMs,
      responseAtMs,
      response.status,
      ack.error?.code ?? null,
      ack.accountRevision,
      manga.revision,
      progress.epoch,
      Number(progress.completed),
      progress.current?.pageKey ?? null,
      progress.furthest?.pageKey ?? null,
      stateHash,
      ackHash,
      receiptHash,
    )
    .first<RaceAttempt>();
  console.log('ACCEPTANCE_PROGRESS_RACE_OUTCOME=' + JSON.stringify(outcome));
}
