import { create, fromJsonString, toJsonString } from '@bufbuild/protobuf';
import {
  BusinessStateErrorCode as ErrorCode,
  ChapterProgressStateSchema,
  LibraryPageResponseSchema,
  MangaStateResponseSchema,
  MangaStateSchema,
  ReadingAnchorSchema,
  StateMutationResponseSchema,
  StateMutationSchema,
  type ChapterProgressState,
  type ChapterSnapshot,
  type LibraryMetadata,
  type MangaState,
  type ReadingAnchor,
  type StateMutation,
  type StateMutationResponse,
} from '@karuyomi/protocol';
import { businessSchemaVersion, LIBRARY_PAGE_SIZE } from '@karuyomi/contracts';

const MAX_REVISION = 0xffff_ffff;
type SnapshotRow = {
  account_revision: number;
  manga_json: string | null;
  progress_json: string | null;
};
type MutationRow = { request_hash: string; response_json: string };

export class StateError extends Error {
  constructor(
    readonly code: ErrorCode,
    message: string,
    readonly status: 400 | 409 | 413 | 503 = 400,
  ) {
    super(message);
  }
}

export async function hashText(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    new TextEncoder().encode(text),
  );
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, '0'),
  ).join('');
}

async function validateMetadataKey(
  mangaKey: string,
  metadata: LibraryMetadata,
) {
  if (
    !metadata.manga ||
    mangaKey !==
      (await hashText(
        JSON.stringify([
          metadata.packageName,
          metadata.sourceId,
          metadata.manga.url,
        ]),
      ))
  )
    throw new StateError(
      ErrorCode.INVALID_INPUT,
      'Metadata does not match manga identity',
    );
}

export async function readMangaState(
  db: D1Database,
  subject: string,
  mangaKey: string,
  chapterKey = '',
) {
  // A single statement observes account, manga and chapter in one D1 snapshot.
  const row = await db
    .prepare(
      `SELECT
    COALESCE((SELECT revision FROM account_state WHERE subject = ?1), 0) account_revision,
    (SELECT state_json FROM manga_state WHERE subject = ?1 AND manga_key = ?2) manga_json,
    (SELECT state_json FROM chapter_progress WHERE subject = ?1 AND manga_key = ?2 AND chapter_key = ?3) progress_json`,
    )
    .bind(subject, mangaKey, chapterKey)
    .first<SnapshotRow>();
  if (!row)
    throw new StateError(ErrorCode.UNAVAILABLE, 'State is unavailable', 503);
  return create(MangaStateResponseSchema, {
    schemaVersion: businessSchemaVersion,
    accountRevision: row.account_revision,
    manga: row.manga_json
      ? fromJsonString(MangaStateSchema, row.manga_json)
      : create(MangaStateSchema, { mangaKey }),
    ...(row.progress_json
      ? {
          progress: fromJsonString(
            ChapterProgressStateSchema,
            row.progress_json,
          ),
        }
      : {}),
  });
}

export async function readLibrary(
  db: D1Database,
  subject: string,
  afterKey: string,
  revision?: number,
) {
  const row = await db
    .prepare(
      `SELECT
    COALESCE((SELECT revision FROM account_state WHERE subject = ?1), 0) account_revision,
    (SELECT json_group_array(json(state_json)) FROM (
      SELECT state_json FROM manga_state WHERE subject = ?1 AND favorite = 1 AND manga_key > ?2
      ORDER BY manga_key LIMIT ?3
    )) entries_json`,
    )
    .bind(subject, afterKey, LIBRARY_PAGE_SIZE + 1)
    .first<{ account_revision: number; entries_json: string }>();
  if (!row)
    throw new StateError(ErrorCode.UNAVAILABLE, 'Library is unavailable', 503);
  const response = fromJsonString(
    LibraryPageResponseSchema,
    JSON.stringify({
      schemaVersion: businessSchemaVersion,
      accountRevision: row.account_revision,
      entries: JSON.parse(row.entries_json),
    }),
  );
  if (revision !== undefined && revision !== response.accountRevision) {
    response.entries = [];
    response.error = {
      $typeName: 'karuyomi.v1.BusinessStateError',
      code: ErrorCode.REVISION_CONFLICT,
      message: 'Library changed; restart pagination',
      retryable: false,
    };
    return response;
  }
  if (response.entries.length > LIBRARY_PAGE_SIZE) {
    response.entries.length = LIBRARY_PAGE_SIZE;
    response.nextKey = response.entries.at(-1)?.mangaKey ?? '';
  }
  return response;
}

function projectAnchor(
  anchor: ReadingAnchor | undefined,
  snapshot: ChapterSnapshot,
) {
  if (!anchor || anchor.chapterKey !== snapshot.chapterKey) return undefined;
  const index = snapshot.pageKeys.indexOf(anchor.pageKey);
  if (index < 0) return undefined;
  return create(ReadingAnchorSchema, {
    chapterKey: snapshot.chapterKey,
    manifestVersion: snapshot.manifestVersion,
    pageKey: anchor.pageKey,
    pageIndexHint: index,
    normalizedOffset: anchor.normalizedOffset,
  });
}

function farther(
  snapshot: ChapterSnapshot,
  previous: ReadingAnchor | undefined,
  incoming: ReadingAnchor | undefined,
) {
  const before = projectAnchor(previous, snapshot);
  const next = projectAnchor(incoming, snapshot);
  // Preserve a missing historical page as unresolved. Its old index cannot
  // establish ordering in this manifest, nor can a navigation anchor replace it.
  if (previous && !before) return previous;
  if (incoming && !next) return previous ?? incoming;
  if (!before) return next;
  if (!next) return before;
  return next.pageIndexHint > before.pageIndexHint ||
    (next.pageIndexHint === before.pageIndexHint &&
      next.normalizedOffset > before.normalizedOffset)
    ? next
    : before;
}

function nextProgress(
  mutation: StateMutation,
  previous: ChapterProgressState | undefined,
): ChapterProgressState | undefined {
  const operation = mutation.operation;
  if (operation.case === 'resetProgress') {
    const snapshot = operation.value.snapshot;
    if (!snapshot)
      throw new StateError(ErrorCode.INVALID_INPUT, 'Snapshot is required');
    if (previous?.epoch === MAX_REVISION)
      throw new StateError(
        ErrorCode.LIMIT_EXCEEDED,
        'Progress epoch is exhausted',
        409,
      );
    const first = snapshot.pageKeys[0];
    if (!first)
      throw new StateError(ErrorCode.INVALID_INPUT, 'Snapshot is empty');
    const current = create(ReadingAnchorSchema, {
      chapterKey: snapshot.chapterKey,
      pageKey: first,
      manifestVersion: snapshot.manifestVersion,
    });
    return create(ChapterProgressStateSchema, {
      chapterKey: snapshot.chapterKey,
      current,
      epoch: (previous?.epoch ?? 0) + 1,
    });
  }
  if (operation.case !== 'saveProgress') return undefined;
  const { snapshot, progress } = operation.value;
  if (!snapshot || !progress || !progress.current)
    throw new StateError(
      ErrorCode.INVALID_INPUT,
      'Progress snapshot is required',
    );
  if (progress.epoch !== (previous?.epoch ?? 0))
    throw new StateError(ErrorCode.STALE_EPOCH, 'Progress epoch changed', 409);
  const current = projectAnchor(progress.current, snapshot);
  if (!current)
    throw new StateError(
      ErrorCode.INVALID_INPUT,
      'Current page is outside snapshot',
    );
  // Old manifest indices have no ordering meaning. Only page identities which
  // exist in this request's snapshot participate in furthest comparison.
  const furthest = farther(snapshot, previous?.furthest, progress.furthest);
  return create(ChapterProgressStateSchema, {
    chapterKey: snapshot.chapterKey,
    current,
    ...(furthest ? { furthest } : {}),
    epoch: progress.epoch,
    completed:
      (previous?.completed === true &&
        previous.current?.manifestVersion === snapshot.manifestVersion) ||
      (progress.completed &&
        progress.current.manifestVersion === snapshot.manifestVersion),
  });
}

function chapterFor(mutation: StateMutation): string {
  const operation = mutation.operation;
  return operation.case === 'saveProgress' || operation.case === 'resetProgress'
    ? (operation.value.snapshot?.chapterKey ?? '')
    : '';
}

function mutationError(
  mutation: StateMutation,
  state: Awaited<ReturnType<typeof readMangaState>>,
  error: StateError,
) {
  return create(StateMutationResponseSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: mutation.mutationId,
    accountRevision: state.accountRevision,
    ...(state.manga ? { manga: state.manga } : {}),
    ...(state.progress ? { progress: state.progress } : {}),
    error: {
      code: error.code,
      message: error.message,
      retryable: error.status === 503,
    },
  });
}

export async function applyMutation(
  db: D1Database,
  subject: string,
  mutation: StateMutation,
): Promise<{
  status: 200 | 400 | 409 | 413 | 503;
  response: StateMutationResponse;
}> {
  const requestHash = await hashText(
    toJsonString(StateMutationSchema, mutation),
  );
  const findMutation = () =>
    db
      .prepare(
        'SELECT request_hash, response_json FROM state_mutations WHERE subject = ? AND mutation_id = ?',
      )
      .bind(subject, mutation.mutationId)
      .first<MutationRow>();
  const existing = await findMutation();
  if (existing?.request_hash === requestHash)
    return {
      status: 200,
      response: fromJsonString(
        StateMutationResponseSchema,
        existing.response_json,
      ),
    };
  const state = await readMangaState(
    db,
    subject,
    mutation.mangaKey,
    chapterFor(mutation),
  );
  const fail = (error: StateError) => ({
    status: error.status,
    response: mutationError(mutation, state, error),
  });
  if (existing)
    return fail(
      new StateError(
        ErrorCode.IDEMPOTENCY_CONFLICT,
        'Mutation ID was used for different content',
        409,
      ),
    );
  const oldManga = state.manga;
  if (!oldManga)
    throw new StateError(
      ErrorCode.UNAVAILABLE,
      'Manga state is unavailable',
      503,
    );
  if (oldManga.revision !== mutation.expectedRevision)
    return fail(
      new StateError(
        ErrorCode.REVISION_CONFLICT,
        'Manga revision changed',
        409,
      ),
    );
  if (
    oldManga.revision === MAX_REVISION ||
    state.accountRevision === MAX_REVISION
  )
    return fail(
      new StateError(
        ErrorCode.LIMIT_EXCEEDED,
        'State revision is exhausted',
        409,
      ),
    );
  let manga: MangaState = create(MangaStateSchema, oldManga);
  let progress: ChapterProgressState | undefined;
  try {
    const operation = mutation.operation;
    if (operation.case === 'setFavorite') {
      if (operation.value.metadata) {
        await validateMetadataKey(mutation.mangaKey, operation.value.metadata);
        manga.metadata = operation.value.metadata;
      }
      if (operation.value.favorite && !manga.metadata)
        throw new StateError(
          ErrorCode.INVALID_INPUT,
          'Favorites require metadata',
        );
      if (operation.value.favorite && !manga.favorite)
        manga.addedAtSeconds = Math.floor(Date.now() / 1000);
      manga.favorite = operation.value.favorite;
    } else if (operation.case === 'updateMetadata') {
      await validateMetadataKey(mutation.mangaKey, operation.value);
      manga.metadata = operation.value;
    } else {
      progress = nextProgress(mutation, state.progress);
      if (progress)
        manga.resume = {
          $typeName: 'karuyomi.v1.MangaResume',
          chapterKey: progress.chapterKey,
          reversedOrder: operation.value?.reversedOrder ?? false,
        };
    }
    manga.revision += 1;
  } catch (error) {
    if (error instanceof StateError) return fail(error);
    throw error;
  }
  const response = create(StateMutationResponseSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: mutation.mutationId,
    manga,
    ...(progress ? { progress } : {}),
  });
  const nonce = crypto.randomUUID();
  const winner =
    'EXISTS (SELECT 1 FROM state_mutations WHERE subject = ?1 AND mutation_id = ?2 AND attempt_nonce = ?3)';
  const statements = [
    db
      .prepare(
        'INSERT OR IGNORE INTO account_state(subject, revision) VALUES (?, 0)',
      )
      .bind(subject),
    db
      .prepare(
        `INSERT OR IGNORE INTO state_mutations(subject, mutation_id, request_hash, attempt_nonce, response_json)
      SELECT ?1, ?2, ?3, ?4, ?5 WHERE COALESCE((SELECT revision FROM manga_state WHERE subject = ?1 AND manga_key = ?6), 0) = ?7
      AND (SELECT revision FROM account_state WHERE subject = ?1) < ?8`,
      )
      .bind(
        subject,
        mutation.mutationId,
        requestHash,
        nonce,
        toJsonString(StateMutationResponseSchema, response),
        mutation.mangaKey,
        mutation.expectedRevision,
        MAX_REVISION,
      ),
    db
      .prepare(
        `UPDATE account_state SET revision = revision + 1 WHERE subject = ?1 AND ${winner}`,
      )
      .bind(subject, mutation.mutationId, nonce),
    db
      .prepare(
        `INSERT INTO manga_state(subject, manga_key, revision, favorite, state_json)
      SELECT ?1, ?4, ?5, ?6, ?7 WHERE ${winner}
      ON CONFLICT(subject, manga_key) DO UPDATE SET revision = excluded.revision, favorite = excluded.favorite, state_json = excluded.state_json`,
      )
      .bind(
        subject,
        mutation.mutationId,
        nonce,
        mutation.mangaKey,
        manga.revision,
        manga.favorite ? 1 : 0,
        toJsonString(MangaStateSchema, manga),
      ),
  ];
  if (progress)
    statements.push(
      db
        .prepare(
          `INSERT INTO chapter_progress(subject, manga_key, chapter_key, state_json)
    SELECT ?1, ?4, ?5, ?6 WHERE ${winner}
    ON CONFLICT(subject, manga_key, chapter_key) DO UPDATE SET state_json = excluded.state_json`,
        )
        .bind(
          subject,
          mutation.mutationId,
          nonce,
          mutation.mangaKey,
          progress.chapterKey,
          toJsonString(ChapterProgressStateSchema, progress),
        ),
    );
  statements.push(
    db
      .prepare(
        `UPDATE state_mutations SET response_json = json_set(response_json, '$.accountRevision',
    (SELECT revision FROM account_state WHERE subject = ?1)) WHERE subject = ?1 AND mutation_id = ?2 AND attempt_nonce = ?3`,
      )
      .bind(subject, mutation.mutationId, nonce),
  );
  // D1 batches are transactional. The nonce gates every effect so a duplicate
  // request or concurrent loser cannot increment revisions or apply stale data.
  await db.batch(statements);
  const committed = await findMutation();
  if (committed?.request_hash === requestHash)
    return {
      status: 200,
      response: fromJsonString(
        StateMutationResponseSchema,
        committed.response_json,
      ),
    };
  const canonical = await readMangaState(
    db,
    subject,
    mutation.mangaKey,
    chapterFor(mutation),
  );
  return {
    status: 409,
    response: mutationError(
      mutation,
      canonical,
      new StateError(
        committed
          ? ErrorCode.IDEMPOTENCY_CONFLICT
          : ErrorCode.REVISION_CONFLICT,
        committed
          ? 'Mutation ID was used for different content'
          : 'Manga revision changed',
        409,
      ),
    ),
  };
}
