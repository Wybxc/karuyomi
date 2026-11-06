import {
  clone,
  create,
  fromJsonString,
  toJsonString,
} from '@bufbuild/protobuf';
import {
  BusinessStateErrorCode as ErrorCode,
  BookmarkPageResponseSchema,
  ChapterBookmarkSchema,
  CategoryCatalogSchema,
  CategoryCatalogResponseSchema,
  CategoryMutationSchema,
  CategoryMutationResponseSchema,
  ChapterProgressStateSchema,
  CustomCoverSchema,
  ChapterProgressPageResponseSchema,
  LibraryPageResponseSchema,
  MangaStateResponseSchema,
  MangaStateSchema,
  ReadingAnchorSchema,
  MigrationResultSchema,
  StateMutationResponseSchema,
  StateMutationSchema,
  type ChapterProgressState,
  type ChapterBookmark,
  type CategoryMutation,
  type CategoryMutationResponse,
  type ChapterSnapshot,
  type LibraryMetadata,
  type MangaState,
  type ReadingAnchor,
  type StateMutation,
  type StateMutationResponse,
} from '@karuyomi/protocol';
import {
  businessSchemaVersion,
  LIBRARY_PAGE_SIZE,
  BOOKMARK_PAGE_SIZE,
  CHAPTER_PROGRESS_PAGE_SIZE,
  CATEGORY_LIMIT,
} from '@karuyomi/contracts';

const MAX_REVISION = 0xffff_ffff;
type SnapshotRow = {
  account_revision: number;
  manga_json: string | null;
  progress_json: string | null;
  bookmarked: number;
  catalog_json: string;
};
type MutationRow = {
  request_hash: string;
  response_json: string;
  kind: string;
};

// Relations are authoritative. Manga JSON stores no second category or cover reference.
const catalogSql = `json_object('revision', COALESCE((SELECT categories_revision FROM account_state WHERE subject = ?1), 0),
  'categories', json((SELECT json_group_array(json_object('id', id, 'name', name)) FROM
    (SELECT id, name FROM categories WHERE subject = ?1 ORDER BY sort_order, id))))`;
function categoryIdsSql(mangaKeySql: string) {
  return `(SELECT json_group_array(category_id) FROM (
    SELECT mc.category_id FROM manga_categories mc JOIN categories c ON c.subject = mc.subject AND c.id = mc.category_id
    WHERE mc.subject = ?1 AND mc.manga_key = ${mangaKeySql} ORDER BY c.sort_order, c.id))`;
}
function mangaSql(alias: string) {
  return `json_set(${alias}.state_json, '$.categoryIds', json(${categoryIdsSql(`${alias}.manga_key`)}),
    '$.customCover', json((SELECT descriptor_json FROM cover_assets WHERE subject = ?1 AND manga_key = ${alias}.manga_key)))`;
}

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
    (SELECT ${mangaSql('m')} FROM manga_state m WHERE subject = ?1 AND manga_key = ?2) manga_json,
    (SELECT state_json FROM chapter_progress WHERE subject = ?1 AND manga_key = ?2 AND chapter_key = ?3) progress_json,
    EXISTS (SELECT 1 FROM chapter_bookmarks WHERE subject = ?1 AND manga_key = ?2 AND chapter_key = ?3) bookmarked,
    ${catalogSql} catalog_json`,
    )
    .bind(subject, mangaKey, chapterKey)
    .first<SnapshotRow>();
  if (!row)
    throw new StateError(ErrorCode.UNAVAILABLE, 'State is unavailable', 503);
  return create(MangaStateResponseSchema, {
    schemaVersion: businessSchemaVersion,
    accountRevision: row.account_revision,
    categoryCatalog: fromJsonString(CategoryCatalogSchema, row.catalog_json),
    manga: row.manga_json
      ? fromJsonString(MangaStateSchema, row.manga_json)
      : create(MangaStateSchema, { mangaKey }),
    ...(chapterKey
      ? { bookmark: { chapterKey, bookmarked: row.bookmarked === 1 } }
      : {}),
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
    ${catalogSql} catalog_json,
    (SELECT json_group_array(json(state_json)) FROM (
      SELECT ${mangaSql('m')} state_json FROM manga_state m WHERE subject = ?1 AND favorite = 1 AND manga_key > ?2
      ORDER BY manga_key LIMIT ?3
    )) entries_json`,
    )
    .bind(subject, afterKey, LIBRARY_PAGE_SIZE + 1)
    .first<{
      account_revision: number;
      entries_json: string;
      catalog_json: string;
    }>();
  if (!row)
    throw new StateError(ErrorCode.UNAVAILABLE, 'Library is unavailable', 503);
  const response = fromJsonString(
    LibraryPageResponseSchema,
    JSON.stringify({
      schemaVersion: businessSchemaVersion,
      accountRevision: row.account_revision,
      categoryCatalog: JSON.parse(row.catalog_json),
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

export async function readBookmarkPage(
  db: D1Database,
  subject: string,
  mangaKey: string,
  afterKey: string,
  revision?: number,
) {
  // Account revision and bounded chapter keys are observed in one snapshot.
  const row = await db
    .prepare(
      `SELECT
    COALESCE((SELECT revision FROM account_state WHERE subject = ?1), 0) account_revision,
    (SELECT json_group_array(json_object('chapterKey', chapter_key, 'bookmarked', json('true'))) FROM (
      SELECT chapter_key FROM chapter_bookmarks WHERE subject = ?1 AND manga_key = ?2 AND chapter_key > ?3
      ORDER BY chapter_key LIMIT ?4
    )) entries_json`,
    )
    .bind(subject, mangaKey, afterKey, BOOKMARK_PAGE_SIZE + 1)
    .first<{ account_revision: number; entries_json: string }>();
  if (!row)
    throw new StateError(
      ErrorCode.UNAVAILABLE,
      'Bookmarks are unavailable',
      503,
    );
  const response = fromJsonString(
    BookmarkPageResponseSchema,
    JSON.stringify({
      schemaVersion: businessSchemaVersion,
      accountRevision: row.account_revision,
      mangaKey,
      entries: JSON.parse(row.entries_json),
    }),
  );
  if (revision !== undefined && revision !== response.accountRevision) {
    response.entries = [];
    response.error = {
      $typeName: 'karuyomi.v1.BusinessStateError',
      code: ErrorCode.REVISION_CONFLICT,
      message: 'Bookmarks changed; restart pagination',
      retryable: false,
    };
    return response;
  }
  if (response.entries.length > BOOKMARK_PAGE_SIZE) {
    response.entries.length = BOOKMARK_PAGE_SIZE;
    response.nextKey = response.entries.at(-1)?.chapterKey ?? '';
  }
  return response;
}

export async function readChapterProgressPage(
  db: D1Database,
  subject: string,
  mangaKey: string,
  afterKey: string,
  revision?: number,
) {
  // Account revision and bounded chapter keys are observed in one snapshot.
  const row = await db
    .prepare(
      `SELECT
    COALESCE((SELECT revision FROM account_state WHERE subject = ?1), 0) account_revision,
    (SELECT json_group_array(json(state_json)) FROM (
      SELECT state_json FROM chapter_progress WHERE subject = ?1 AND manga_key = ?2 AND chapter_key > ?3
      ORDER BY chapter_key LIMIT ?4
    )) entries_json`,
    )
    .bind(subject, mangaKey, afterKey, CHAPTER_PROGRESS_PAGE_SIZE + 1)
    .first<{ account_revision: number; entries_json: string }>();
  if (!row)
    throw new StateError(
      ErrorCode.UNAVAILABLE,
      'Chapter progress is unavailable',
      503,
    );
  const response = fromJsonString(
    ChapterProgressPageResponseSchema,
    JSON.stringify({
      schemaVersion: businessSchemaVersion,
      accountRevision: row.account_revision,
      mangaKey,
      entries: JSON.parse(row.entries_json),
    }),
  );
  if (revision !== undefined && revision !== response.accountRevision) {
    response.entries = [];
    response.error = {
      $typeName: 'karuyomi.v1.BusinessStateError',
      code: ErrorCode.REVISION_CONFLICT,
      message: 'Chapter progress changed; restart pagination',
      retryable: false,
    };
    return response;
  }
  if (response.entries.length > CHAPTER_PROGRESS_PAGE_SIZE) {
    response.entries.length = CHAPTER_PROGRESS_PAGE_SIZE;
    response.nextKey = response.entries.at(-1)?.chapterKey ?? '';
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
    normalizedX: anchor.normalizedX,
    viewportX: anchor.viewportX,
    viewportY: anchor.viewportY,
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
  if (operation.case === 'setChapterRead') {
    if (previous?.epoch === MAX_REVISION)
      throw new StateError(
        ErrorCode.LIMIT_EXCEEDED,
        'Progress epoch is exhausted',
        409,
      );
    return create(ChapterProgressStateSchema, {
      ...(operation.value.read ? previous : {}),
      chapterKey: operation.value.chapterKey,
      epoch: (previous?.epoch ?? 0) + 1,
      completed: operation.value.read,
    });
  }
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
    completed: previous?.completed === true || progress.completed,
  });
}

function chapterFor(mutation: StateMutation): string {
  const operation = mutation.operation;
  if (operation.case === 'setBookmark' || operation.case === 'setChapterRead')
    return operation.value.chapterKey;
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
    categoryCatalog: state.categoryCatalog,
    ...(state.manga ? { manga: state.manga } : {}),
    ...(state.progress ? { progress: state.progress } : {}),
    ...(state.bookmark ? { bookmark: state.bookmark } : {}),
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
  uploadCover?: () => Promise<string>,
): Promise<{
  status: 200 | 400 | 409 | 413 | 503;
  response: StateMutationResponse;
}> {
  const requestHash = await hashText(
    'manga\n' + toJsonString(StateMutationSchema, mutation),
  );
  const findMutation = () =>
    db
      .prepare(
        'SELECT kind, request_hash, response_json FROM state_mutations WHERE subject = ? AND mutation_id = ?',
      )
      .bind(subject, mutation.mutationId)
      .first<MutationRow>();
  const existing = await findMutation();
  if (existing?.kind === 'manga' && existing.request_hash === requestHash)
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
  let manga: MangaState = clone(MangaStateSchema, oldManga);
  let progress: ChapterProgressState | undefined;
  let bookmark: ChapterBookmark | undefined;
  let coverObjectKey: string | undefined;
  let migration:
    | {
        sourceMangaKey: string;
        expectedSourceRevision: number;
        expectedCatalogRevision: number;
        categories: string[];
        readChapters: string[];
        bookmarks: string[];
      }
    | undefined;
  try {
    const operation = mutation.operation;
    if (operation.case === 'migrateFrom') {
      const input = operation.value;
      if (!input.targetMetadata)
        throw new StateError(
          ErrorCode.INVALID_INPUT,
          'Migration requires target metadata',
        );
      await validateMetadataKey(mutation.mangaKey, input.targetMetadata);
      const source = await readMangaState(db, subject, input.sourceMangaKey);
      if (!source.manga?.metadata)
        throw new StateError(
          ErrorCode.INVALID_INPUT,
          'Migration source metadata is required',
        );
      if (source.manga.revision !== input.expectedSourceRevision)
        throw new StateError(
          ErrorCode.REVISION_CONFLICT,
          'Migration source revision changed',
          409,
        );
      if (state.categoryCatalog?.revision !== input.expectedCatalogRevision)
        throw new StateError(
          ErrorCode.REVISION_CONFLICT,
          'Category catalog changed',
          409,
        );
      const categories = input.copyCategories ? source.manga.categoryIds : [];
      const members = new Set([...manga.categoryIds, ...categories]);
      manga.categoryIds = state.categoryCatalog.categories
        .filter((category) => members.has(category.id))
        .map((category) => category.id);
      // Existing target business state is preserved. Only an absent metadata
      // snapshot is populated from the user's confirmed original Source DTO.
      manga.metadata ??= input.targetMetadata;
      if (!manga.favorite) manga.addedAtSeconds = Math.floor(Date.now() / 1000);
      manga.favorite = true;
      const mappings = JSON.stringify(input.chapters);
      const rows = await db
        .prepare(
          `SELECT
        json_extract(mapping.value, '$.targetChapterKey') target_key,
        json_extract(mapping.value, '$.copyRead') copy_read,
        json_extract(mapping.value, '$.copyBookmark') copy_bookmark,
        COALESCE(json_extract(source_progress.state_json, '$.completed'), 0) source_completed,
        target_progress.chapter_key IS NOT NULL target_has_progress,
        EXISTS (SELECT 1 FROM chapter_bookmarks WHERE subject = ?1 AND manga_key = ?2
          AND chapter_key = json_extract(mapping.value, '$.sourceChapterKey')) source_bookmarked,
        EXISTS (SELECT 1 FROM chapter_bookmarks WHERE subject = ?1 AND manga_key = ?3
          AND chapter_key = json_extract(mapping.value, '$.targetChapterKey')) target_bookmarked
        FROM json_each(?4) mapping
        LEFT JOIN chapter_progress source_progress ON source_progress.subject = ?1 AND source_progress.manga_key = ?2
          AND source_progress.chapter_key = json_extract(mapping.value, '$.sourceChapterKey')
        LEFT JOIN chapter_progress target_progress ON target_progress.subject = ?1 AND target_progress.manga_key = ?3
          AND target_progress.chapter_key = json_extract(mapping.value, '$.targetChapterKey')`,
        )
        .bind(subject, input.sourceMangaKey, mutation.mangaKey, mappings)
        .all<{
          target_key: string;
          copy_read: number;
          copy_bookmark: number;
          source_completed: number;
          target_has_progress: number;
          source_bookmarked: number;
          target_bookmarked: number;
        }>();
      migration = {
        sourceMangaKey: input.sourceMangaKey,
        expectedSourceRevision: input.expectedSourceRevision,
        expectedCatalogRevision: input.expectedCatalogRevision,
        categories,
        readChapters: rows.results
          .filter(
            (row) =>
              row.copy_read === 1 &&
              row.source_completed === 1 &&
              row.target_has_progress === 0,
          )
          .map((row) => row.target_key),
        bookmarks: rows.results
          .filter(
            (row) =>
              row.copy_bookmark === 1 &&
              row.source_bookmarked === 1 &&
              row.target_bookmarked === 0,
          )
          .map((row) => row.target_key),
      };
    } else if (operation.case === 'setCustomCover') {
      const cover = operation.value.cover;
      if (cover) {
        if (!uploadCover)
          throw new StateError(
            ErrorCode.INVALID_INPUT,
            'Cover images require multipart upload',
          );
        const used = await db
          .prepare(
            'SELECT manga_key, descriptor_json FROM cover_assets WHERE subject = ? AND asset_id = ?',
          )
          .bind(subject, cover.assetId)
          .first<{ manga_key: string; descriptor_json: string }>();
        const descriptorJson = toJsonString(CustomCoverSchema, cover);
        if (
          used &&
          (used.manga_key !== mutation.mangaKey ||
            used.descriptor_json !== descriptorJson)
        )
          throw new StateError(
            ErrorCode.INVALID_INPUT,
            'Cover identity is already in use',
          );
        coverObjectKey = await uploadCover();
        manga.customCover = cover;
      } else delete manga.customCover;
    } else if (operation.case === 'setFavorite') {
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
    } else if (operation.case === 'setBookmark') {
      bookmark = create(ChapterBookmarkSchema, {
        chapterKey: operation.value.chapterKey,
        bookmarked: operation.value.bookmarked,
      });
    } else if (operation.case === 'setCategories') {
      const catalog = state.categoryCatalog;
      if (
        !catalog ||
        operation.value.expectedCatalogRevision !== catalog.revision
      )
        throw new StateError(
          ErrorCode.REVISION_CONFLICT,
          'Category catalog changed',
          409,
        );
      if (
        !manga.metadata ||
        operation.value.categoryIds.some(
          (id) => !catalog.categories.some((category) => category.id === id),
        )
      )
        throw new StateError(
          ErrorCode.INVALID_INPUT,
          'Manga metadata and existing categories are required',
        );
      manga.categoryIds = catalog.categories
        .filter((category) => operation.value.categoryIds.includes(category.id))
        .map((category) => category.id);
    } else if (operation.case === 'setChapterRead') {
      progress = nextProgress(mutation, state.progress);
    } else if (
      operation.case === 'saveProgress' ||
      operation.case === 'resetProgress'
    ) {
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
    ...(bookmark ? { bookmark } : {}),
    ...(migration
      ? {
          migration: create(MigrationResultSchema, {
            copiedReadChapters: migration.readChapters.length,
            copiedBookmarks: migration.bookmarks.length,
          }),
        }
      : {}),
  });
  const nonce = crypto.randomUUID();
  const winner =
    'EXISTS (SELECT 1 FROM state_mutations WHERE subject = ?1 AND mutation_id = ?2 AND attempt_nonce = ?3)';
  const assignment =
    mutation.operation.case === 'setCategories'
      ? mutation.operation.value
      : undefined;
  const coverAssignment =
    mutation.operation.case === 'setCustomCover'
      ? mutation.operation.value
      : undefined;
  const cover = coverAssignment?.cover;
  const assignmentGate = migration
    ? `AND EXISTS (SELECT 1 FROM manga_state WHERE subject = ?1 AND manga_key = ?9 AND revision = ?10)
    AND COALESCE((SELECT categories_revision FROM account_state WHERE subject = ?1), 0) = ?11`
    : assignment
      ? `AND COALESCE((SELECT categories_revision FROM account_state WHERE subject = ?1), 0) = ?9
    AND (SELECT count(*) FROM categories WHERE subject = ?1 AND id IN (SELECT value FROM json_each(?10))) = json_array_length(?10)`
      : cover
        ? `AND NOT EXISTS (SELECT 1 FROM cover_assets WHERE subject = ?1 AND asset_id = ?9 AND (manga_key <> ?6 OR descriptor_json <> ?10))`
        : '';
  const storedManga = clone(MangaStateSchema, manga);
  storedManga.categoryIds = [];
  delete storedManga.customCover;
  const gateBindings = [
    subject,
    mutation.mutationId,
    requestHash,
    nonce,
    toJsonString(StateMutationResponseSchema, response),
    mutation.mangaKey,
    mutation.expectedRevision,
    MAX_REVISION,
    ...(migration
      ? [
          migration.sourceMangaKey,
          migration.expectedSourceRevision,
          migration.expectedCatalogRevision,
        ]
      : assignment
        ? [
            assignment.expectedCatalogRevision,
            JSON.stringify(assignment.categoryIds),
          ]
        : cover
          ? [cover.assetId, toJsonString(CustomCoverSchema, cover)]
          : []),
  ];
  const statements = [
    db
      .prepare(
        'INSERT OR IGNORE INTO account_state(subject, revision) VALUES (?, 0)',
      )
      .bind(subject),
    db
      .prepare(
        `INSERT OR IGNORE INTO state_mutations(subject, mutation_id, request_hash, attempt_nonce, response_json, kind)
      SELECT ?1, ?2, ?3, ?4, ?5, 'manga' WHERE COALESCE((SELECT revision FROM manga_state WHERE subject = ?1 AND manga_key = ?6), 0) = ?7
      AND (SELECT revision FROM account_state WHERE subject = ?1) < ?8 ${assignmentGate}`,
      )
      .bind(...gateBindings),
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
        toJsonString(MangaStateSchema, storedManga),
      ),
  ];
  if (migration) {
    // All mapping effects use three bounded JSON arrays, not a statement per
    // chapter. The same nonce gates them behind source/target/catalog CAS.
    statements.push(
      db
        .prepare(
          `INSERT OR IGNORE INTO manga_categories(subject, manga_key, category_id)
        SELECT ?1, ?4, value FROM json_each(?5) WHERE ${winner}`,
        )
        .bind(
          subject,
          mutation.mutationId,
          nonce,
          mutation.mangaKey,
          JSON.stringify(migration.categories),
        ),
      db
        .prepare(
          `INSERT INTO chapter_progress(subject, manga_key, chapter_key, state_json)
        SELECT ?1, ?4, value, json_object('chapterKey', value, 'epoch', 1, 'completed', json('true'))
        FROM json_each(?5) WHERE ${winner}
        ON CONFLICT(subject, manga_key, chapter_key) DO NOTHING`,
        )
        .bind(
          subject,
          mutation.mutationId,
          nonce,
          mutation.mangaKey,
          JSON.stringify(migration.readChapters),
        ),
      db
        .prepare(
          `INSERT OR IGNORE INTO chapter_bookmarks(subject, manga_key, chapter_key)
        SELECT ?1, ?4, value FROM json_each(?5) WHERE ${winner}`,
        )
        .bind(
          subject,
          mutation.mutationId,
          nonce,
          mutation.mangaKey,
          JSON.stringify(migration.bookmarks),
        ),
    );
  }
  if (coverAssignment) {
    if (cover && coverObjectKey)
      statements.push(
        db
          .prepare(
            `INSERT INTO cover_assets(subject, manga_key, asset_id, object_key, descriptor_json)
      SELECT ?1, ?4, ?5, ?6, ?7 WHERE ${winner}
      ON CONFLICT(subject, manga_key) DO UPDATE SET asset_id = excluded.asset_id, object_key = excluded.object_key, descriptor_json = excluded.descriptor_json`,
          )
          .bind(
            subject,
            mutation.mutationId,
            nonce,
            mutation.mangaKey,
            cover.assetId,
            coverObjectKey,
            toJsonString(CustomCoverSchema, cover),
          ),
      );
    else
      statements.push(
        db
          .prepare(
            `DELETE FROM cover_assets WHERE subject = ?1 AND manga_key = ?4 AND ${winner}`,
          )
          .bind(subject, mutation.mutationId, nonce, mutation.mangaKey),
      );
  }
  if (assignment)
    statements.push(
      db
        .prepare(
          `DELETE FROM manga_categories WHERE subject = ?1 AND manga_key = ?4 AND ${winner}`,
        )
        .bind(subject, mutation.mutationId, nonce, mutation.mangaKey),
      db
        .prepare(
          `INSERT INTO manga_categories(subject, manga_key, category_id)
      SELECT ?1, ?4, value FROM json_each(?5) WHERE ${winner}`,
        )
        .bind(
          subject,
          mutation.mutationId,
          nonce,
          mutation.mangaKey,
          JSON.stringify(assignment.categoryIds),
        ),
    );
  if (bookmark)
    statements.push(
      bookmark.bookmarked
        ? db
            .prepare(
              `INSERT OR IGNORE INTO chapter_bookmarks(subject, manga_key, chapter_key)
    SELECT ?1, ?4, ?5 WHERE ${winner}`,
            )
            .bind(
              subject,
              mutation.mutationId,
              nonce,
              mutation.mangaKey,
              bookmark.chapterKey,
            )
        : db
            .prepare(
              `DELETE FROM chapter_bookmarks WHERE subject = ?1 AND manga_key = ?4 AND chapter_key = ?5 AND ${winner}`,
            )
            .bind(
              subject,
              mutation.mutationId,
              nonce,
              mutation.mangaKey,
              bookmark.chapterKey,
            ),
    );
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
    (SELECT revision FROM account_state WHERE subject = ?1), '$.categoryCatalog', json(${catalogSql}),
    '$.manga.categoryIds', json(${categoryIdsSql('?4')})) WHERE subject = ?1 AND mutation_id = ?2 AND attempt_nonce = ?3`,
      )
      .bind(subject, mutation.mutationId, nonce, mutation.mangaKey),
  );
  // D1 batches are transactional. The nonce gates every effect so a duplicate
  // request or concurrent loser cannot increment revisions or apply stale data.
  await db.batch(statements);
  const committed = await findMutation();
  if (committed?.kind === 'manga' && committed.request_hash === requestHash)
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

export async function readCategoryCatalog(db: D1Database, subject: string) {
  const row = await db
    .prepare(
      `SELECT
    COALESCE((SELECT revision FROM account_state WHERE subject = ?1), 0) account_revision,
    ${catalogSql} catalog_json`,
    )
    .bind(subject)
    .first<{ account_revision: number; catalog_json: string }>();
  if (!row)
    throw new StateError(
      ErrorCode.UNAVAILABLE,
      'Categories are unavailable',
      503,
    );
  return create(CategoryCatalogResponseSchema, {
    schemaVersion: businessSchemaVersion,
    accountRevision: row.account_revision,
    categoryCatalog: fromJsonString(CategoryCatalogSchema, row.catalog_json),
  });
}

export async function applyCategoryMutation(
  db: D1Database,
  subject: string,
  mutation: CategoryMutation,
): Promise<{
  status: 200 | 400 | 409 | 413 | 503;
  response: CategoryMutationResponse;
}> {
  const requestHash = await hashText(
    'category\n' + toJsonString(CategoryMutationSchema, mutation),
  );
  const findMutation = () =>
    db
      .prepare(
        'SELECT kind, request_hash, response_json FROM state_mutations WHERE subject = ? AND mutation_id = ?',
      )
      .bind(subject, mutation.mutationId)
      .first<MutationRow>();
  const existing = await findMutation();
  if (existing?.kind === 'category' && existing.request_hash === requestHash)
    return {
      status: 200,
      response: fromJsonString(
        CategoryMutationResponseSchema,
        existing.response_json,
      ),
    };
  const state = await readCategoryCatalog(db, subject);
  const failure = (error: StateError, canonical = state) => ({
    status: error.status,
    response: create(CategoryMutationResponseSchema, {
      schemaVersion: businessSchemaVersion,
      mutationId: mutation.mutationId,
      accountRevision: canonical.accountRevision,
      categoryCatalog: canonical.categoryCatalog,
      error: {
        code: error.code,
        message: error.message,
        retryable: error.status === 503,
      },
    }),
  });
  if (existing)
    return failure(
      new StateError(
        ErrorCode.IDEMPOTENCY_CONFLICT,
        'Mutation ID was used for different content',
        409,
      ),
    );
  const catalog = state.categoryCatalog;
  if (!catalog)
    throw new StateError(
      ErrorCode.UNAVAILABLE,
      'Categories are unavailable',
      503,
    );
  if (catalog.revision !== mutation.expectedRevision)
    return failure(
      new StateError(
        ErrorCode.REVISION_CONFLICT,
        'Category catalog changed',
        409,
      ),
    );
  if (
    catalog.revision === MAX_REVISION ||
    state.accountRevision === MAX_REVISION
  )
    return failure(
      new StateError(
        ErrorCode.LIMIT_EXCEEDED,
        'State revision is exhausted',
        409,
      ),
    );
  const operation = mutation.operation;
  let ids = catalog.categories.map((category) => category.id);
  if (operation.case === 'createCategory') {
    const category = operation.value.category;
    if (!category || ids.includes(category.id))
      return failure(
        new StateError(
          ErrorCode.INVALID_INPUT,
          'A new category identity is required',
        ),
      );
    if (ids.length >= CATEGORY_LIMIT)
      return failure(
        new StateError(
          ErrorCode.LIMIT_EXCEEDED,
          'Category catalog is full',
          413,
        ),
      );
    ids = [...ids, category.id];
  } else if (
    operation.case === 'renameCategory' ||
    operation.case === 'deleteCategory'
  ) {
    if (!ids.includes(operation.value.categoryId))
      return failure(
        new StateError(ErrorCode.INVALID_INPUT, 'Category does not exist'),
      );
    if (operation.case === 'deleteCategory')
      ids = ids.filter((id) => id !== operation.value.categoryId);
  } else if (operation.case === 'reorderCategories') {
    if (
      operation.value.categoryIds.length !== ids.length ||
      ids.some((id) => !operation.value.categoryIds.includes(id))
    )
      return failure(
        new StateError(
          ErrorCode.INVALID_INPUT,
          'Reorder must contain every category exactly once',
        ),
      );
    ids = operation.value.categoryIds;
  } else
    return failure(
      new StateError(
        ErrorCode.INVALID_INPUT,
        'A category operation is required',
      ),
    );
  const nonce = crypto.randomUUID();
  const winner =
    'EXISTS (SELECT 1 FROM state_mutations WHERE subject = ?1 AND mutation_id = ?2 AND attempt_nonce = ?3)';
  const deleteCategoryId =
    operation.case === 'deleteCategory' ? operation.value.categoryId : '';
  const response = create(CategoryMutationResponseSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: mutation.mutationId,
  });
  const statements = [
    db
      .prepare(
        'INSERT OR IGNORE INTO account_state(subject, revision, categories_revision) VALUES (?, 0, 0)',
      )
      .bind(subject),
    db
      .prepare(
        `INSERT OR IGNORE INTO state_mutations(subject, mutation_id, request_hash, attempt_nonce, response_json, kind)
      SELECT ?1, ?2, ?3, ?4, ?5, 'category'
      WHERE (SELECT categories_revision FROM account_state WHERE subject = ?1) = ?6
      AND (SELECT revision FROM account_state WHERE subject = ?1) < ?7 AND ?6 < ?7
      AND NOT EXISTS (SELECT 1 FROM manga_state m JOIN manga_categories mc ON m.subject = mc.subject AND m.manga_key = mc.manga_key
        WHERE m.subject = ?1 AND mc.category_id = ?8 AND m.revision >= ?7)`,
      )
      .bind(
        subject,
        mutation.mutationId,
        requestHash,
        nonce,
        toJsonString(CategoryMutationResponseSchema, response),
        mutation.expectedRevision,
        MAX_REVISION,
        deleteCategoryId,
      ),
    db
      .prepare(
        `UPDATE account_state SET revision = revision + 1, categories_revision = categories_revision + 1
      WHERE subject = ?1 AND ${winner}`,
      )
      .bind(subject, mutation.mutationId, nonce),
  ];
  if (operation.case === 'createCategory') {
    const category = operation.value.category;
    if (!category)
      throw new StateError(ErrorCode.INVALID_INPUT, 'A category is required');
    statements.push(
      db
        .prepare(
          `INSERT INTO categories(subject, id, name, sort_order) SELECT ?1, ?4, ?5, ?6 WHERE ${winner}`,
        )
        .bind(
          subject,
          mutation.mutationId,
          nonce,
          category.id,
          category.name,
          ids.length - 1,
        ),
    );
  } else if (operation.case === 'renameCategory') {
    statements.push(
      db
        .prepare(
          `UPDATE categories SET name = ?5 WHERE subject = ?1 AND id = ?4 AND ${winner}`,
        )
        .bind(
          subject,
          mutation.mutationId,
          nonce,
          operation.value.categoryId,
          operation.value.name,
        ),
    );
  } else if (operation.case === 'deleteCategory') {
    // Membership can change after the initial catalog read. Select affected
    // rows inside this transaction, before removing any relation, and patch
    // only their revisions so progress/resume/metadata remain untouched.
    statements.push(
      db
        .prepare(
          `UPDATE manga_state SET revision = revision + 1, state_json = json_set(state_json, '$.revision', revision + 1)
        WHERE subject = ?1 AND ${winner} AND manga_key IN (
          SELECT manga_key FROM manga_categories WHERE subject = ?1 AND category_id = ?4)`,
        )
        .bind(subject, mutation.mutationId, nonce, operation.value.categoryId),
      db
        .prepare(
          `DELETE FROM manga_categories WHERE subject = ?1 AND category_id = ?4 AND ${winner}`,
        )
        .bind(subject, mutation.mutationId, nonce, operation.value.categoryId),
      db
        .prepare(
          `DELETE FROM categories WHERE subject = ?1 AND id = ?4 AND ${winner}`,
        )
        .bind(subject, mutation.mutationId, nonce, operation.value.categoryId),
    );
  }
  statements.push(
    db
      .prepare(
        `UPDATE categories SET sort_order = (SELECT key FROM json_each(?4) WHERE value = categories.id)
      WHERE subject = ?1 AND ${winner}`,
      )
      .bind(subject, mutation.mutationId, nonce, JSON.stringify(ids)),
    db
      .prepare(
        `UPDATE state_mutations SET response_json = json_set(response_json, '$.accountRevision',
      (SELECT revision FROM account_state WHERE subject = ?1), '$.categoryCatalog', json(${catalogSql}))
      WHERE subject = ?1 AND mutation_id = ?2 AND attempt_nonce = ?3`,
      )
      .bind(subject, mutation.mutationId, nonce),
  );
  await db.batch(statements);
  const committed = await findMutation();
  if (committed?.kind === 'category' && committed.request_hash === requestHash)
    return {
      status: 200,
      response: fromJsonString(
        CategoryMutationResponseSchema,
        committed.response_json,
      ),
    };
  const canonical = await readCategoryCatalog(db, subject);
  return failure(
    new StateError(
      committed ? ErrorCode.IDEMPOTENCY_CONFLICT : ErrorCode.REVISION_CONFLICT,
      committed
        ? 'Mutation ID was used for different content'
        : 'Category catalog changed',
      409,
    ),
    canonical,
  );
}
