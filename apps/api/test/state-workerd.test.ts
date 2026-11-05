import { create, toJson, type MessageInitShape } from '@bufbuild/protobuf';
import {
  BusinessStateErrorCode as ErrorCode,
  AppTheme,
  ReaderBackground,
  ReaderFit,
  ReaderInputPreset,
  ReaderMode,
  ReaderPageLayout,
  SettingsMutationSchema,
  type SettingsMutation,
  LibraryMetadataSchema,
  StateMutationSchema,
  type StateMutation,
  CategoryMutationSchema,
  type CategoryMutation,
} from '@karuyomi/protocol';
import {
  businessSchemaVersion,
  settingsResponseSchema,
  settingsMutationResponseSchema,
  bookmarkPageResponseSchema,
  chapterProgressPageResponseSchema,
  libraryPageResponseSchema,
  mangaStateResponseSchema,
  stateMutationResponseSchema,
  categoryCatalogResponseSchema,
  categoryMutationResponseSchema,
} from '@karuyomi/contracts';
import { env, exports } from 'cloudflare:workers';
import { applyD1Migrations } from 'cloudflare:test';
import { exportJWK, generateKeyPair, SignJWT } from 'jose';
import { createHash } from 'node:crypto';
import { beforeAll, expect, test } from 'vitest';

const origin = 'https://read.example.com';
let keys: Awaited<ReturnType<typeof generateKeyPair>>;

beforeAll(async () => {
  keys = await generateKeyPair('RS256');
  const jwk = await exportJWK(keys.publicKey);
  jwk.kid = 'state-fixture';
  env.PROBE_ACCESS_JWKS = JSON.stringify({ keys: [jwk] });
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
}, 30_000);

async function client(subject: string = crypto.randomUUID()) {
  const token = await new SignJWT({ email: 'owner@example.com' })
    .setProtectedHeader({ alg: 'RS256', kid: 'state-fixture' })
    .setSubject(subject)
    .setIssuer('https://example.cloudflareaccess.com')
    .setAudience('state-fixture')
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(keys.privateKey);
  const headers = {
    'Cf-Access-Jwt-Assertion': token,
    'X-App-Subject': subject,
  };
  return {
    subject,
    async request(
      path: string,
      options: {
        method?: string;
        headers?: Record<string, string>;
        body?: string;
      } = {},
    ) {
      const merged = new Headers(headers);
      new Headers(options.headers).forEach((value, key) =>
        merged.set(key, value),
      );
      return exports.default.fetch(`${origin}${path}`, {
        ...options,
        headers: [...merged.entries()],
      });
    },
    async mutate(mutation: StateMutation) {
      const response = await this.request('/api/state/mutations', {
        method: 'POST',
        headers: {
          Origin: origin,
          'X-App-Request': '1',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(toJson(StateMutationSchema, mutation)),
      });
      return {
        status: response.status,
        body: stateMutationResponseSchema.parse(await response.json()),
      };
    },
    async state(mangaKey: string, chapterKey = '') {
      const response = await this.request(
        `/api/state/manga/${mangaKey}?chapterKey=${encodeURIComponent(chapterKey)}`,
      );
      expect(response.status).toBe(200);
      return mangaStateResponseSchema.parse(await response.json());
    },
    async bookmarks(mangaKey: string, query = '') {
      const response = await this.request(
        `/api/state/manga/${mangaKey}/bookmarks${query}`,
      );
      return {
        status: response.status,
        body: bookmarkPageResponseSchema.parse(await response.json()),
      };
    },
    async progress(mangaKey: string, query = '') {
      const response = await this.request(
        `/api/state/manga/${mangaKey}/progress${query}`,
      );
      return {
        status: response.status,
        body: chapterProgressPageResponseSchema.parse(await response.json()),
      };
    },
    async library(query = '') {
      const response = await this.request(`/api/library${query}`);
      return {
        status: response.status,
        body: libraryPageResponseSchema.parse(await response.json()),
      };
    },
    async settings(mangaKey?: string) {
      const response = await this.request(
        mangaKey ? `/api/settings/manga/${mangaKey}` : '/api/settings',
      );
      expect(response.status).toBe(200);
      return settingsResponseSchema.parse(await response.json());
    },
    async mutateSettings(mutation: SettingsMutation) {
      const response = await this.request('/api/settings/mutations', {
        method: 'POST',
        headers: {
          Origin: origin,
          'X-App-Request': '1',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(toJson(SettingsMutationSchema, mutation)),
      });
      return {
        status: response.status,
        body: settingsMutationResponseSchema.parse(await response.json()),
      };
    },
    async categories() {
      const response = await this.request('/api/categories');
      expect(response.status).toBe(200);
      return categoryCatalogResponseSchema.parse(await response.json());
    },
    async mutateCategory(mutation: CategoryMutation) {
      const response = await this.request('/api/categories/mutations', {
        method: 'POST',
        headers: {
          Origin: origin,
          'X-App-Request': '1',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(toJson(CategoryMutationSchema, mutation)),
      });
      return {
        status: response.status,
        body: categoryMutationResponseSchema.parse(await response.json()),
      };
    },
  };
}

function metadata(name = crypto.randomUUID()) {
  return create(LibraryMetadataSchema, {
    packageName: 'eu.kanade.test',
    sourceId: '123',
    sourceName: 'Test source',
    sourceLang: 'en',
    manga: {
      url: `/manga/${name}`,
      title: name,
      memoJson: '{"opaque":"source-owned"}',
    },
  });
}

function favorite(
  revision = 0,
  value = metadata(),
  enabled = true,
): StateMutation {
  const mangaKey = createHash('sha256')
    .update(
      JSON.stringify([value.packageName, value.sourceId, value.manga?.url]),
    )
    .digest('hex');
  return create(StateMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    mangaKey,
    expectedRevision: revision,
    operation: {
      case: 'setFavorite',
      value: { metadata: value, favorite: enabled },
    },
  });
}

function save(
  mangaKey: string,
  revision: number,
  index = 1,
  epoch = 0,
  pages = ['first', 'middle', 'last'],
  observed = true,
  coordinates: {
    normalizedOffset?: number;
    normalizedX?: number;
    viewportX?: number;
    viewportY?: number;
  } = {},
): StateMutation {
  const anchor = {
    chapterKey: 'chapter-1',
    pageKey: pages[index] ?? '',
    pageIndexHint: index,
    manifestVersion: `manifest-${pages.join('-')}`,
    normalizedOffset: 0.4,
    ...coordinates,
  };
  return create(StateMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    mangaKey,
    expectedRevision: revision,
    operation: {
      case: 'saveProgress',
      value: {
        snapshot: {
          chapterKey: 'chapter-1',
          manifestVersion: `manifest-${pages.join('-')}`,
          pageKeys: pages,
        },
        progress: {
          chapterKey: 'chapter-1',
          epoch,
          current: anchor,
          ...(observed ? { furthest: anchor } : {}),
        },
        reversedOrder: true,
      },
    },
  });
}

test('two independent clients observe server-owned favorite, progress and removal in both directions', async () => {
  const first = await client();
  const second = await client(first.subject);
  const add = favorite();
  expect((await first.mutate(add)).body.manga?.revision).toBe(1);
  expect(
    (await second.library()).body.entries[0]?.metadata?.manga?.memoJson,
  ).toBe('{"opaque":"source-owned"}');
  const progress = await second.mutate(save(add.mangaKey, 1));
  expect(progress.body.progress?.epoch).toBe(0);
  expect(
    (await first.state(add.mangaKey, 'chapter-1')).progress?.current?.pageKey,
  ).toBe('middle');
  const remove = favorite(
    2,
    add.operation.case === 'setFavorite'
      ? add.operation.value.metadata
      : undefined,
    false,
  );
  expect((await first.mutate(remove)).body.manga?.revision).toBe(3);
  expect((await second.library()).body.entries).toEqual([]);
  const preserved = await second.state(add.mangaKey, 'chapter-1');
  expect(preserved.progress?.current?.pageKey).toBe('middle');
  expect(preserved.manga?.resume?.reversedOrder).toBe(true);
  expect(preserved.accountRevision).toBe(3);
});

test('concurrent CAS has one winner and durable retry returns the original response', async () => {
  const first = await client();
  const second = await client(first.subject);
  const add = favorite();
  const competing = create(StateMutationSchema, {
    ...add,
    mutationId: crypto.randomUUID(),
  });
  const results = await Promise.all([
    first.mutate(add),
    second.mutate(competing),
  ]);
  expect(results.map((result) => result.status).sort()).toEqual([200, 409]);
  const winner = results[0]?.status === 200 ? add : competing;
  const acknowledged = results.find((result) => result.status === 200);
  const saved = await first.mutate(save(add.mangaKey, 1));
  expect(saved.body.manga?.revision).toBe(2);
  // Simulate a lost response: the client retries the exact request after later writes.
  const retry = await second.mutate(winner);
  expect(retry.status).toBe(200);
  expect(retry.body).toEqual(acknowledged?.body);
  expect((await second.state(add.mangaKey)).manga?.revision).toBe(2);
  const changed = create(StateMutationSchema, {
    ...winner,
    expectedRevision: 2,
  });
  expect((await first.mutate(changed)).body.error?.code).toBe(
    ErrorCode.IDEMPOTENCY_CONFLICT,
  );
});

test('unfavorited progress, per-chapter rows, server reset epoch and page-key projection', async () => {
  const reader = await client();
  const key = favorite().mangaKey;
  const initial = await reader.mutate(save(key, 0, 2));
  expect(initial.status).toBe(200);
  expect(initial.body.manga?.metadata).toBeUndefined();
  const reordered = await reader.mutate(
    save(key, 1, 0, 0, ['middle', 'last', 'first']),
  );
  expect(reordered.body.progress?.furthest?.pageKey).toBe('last');
  expect(reordered.body.progress?.furthest?.pageIndexHint).toBe(1);
  const reset = create(StateMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    mangaKey: key,
    expectedRevision: 2,
    operation: {
      case: 'resetProgress',
      value: {
        snapshot: {
          chapterKey: 'chapter-1',
          manifestVersion: 'reset',
          pageKeys: ['first', 'middle', 'last'],
        },
      },
    },
  });
  const resetResult = await reader.mutate(reset);
  expect(resetResult.body.progress?.epoch).toBe(1);
  expect(resetResult.body.progress?.furthest).toBeUndefined();
  expect((await reader.mutate(reset)).body).toEqual(resetResult.body);
  const stale = await reader.mutate(save(key, 3, 2, 0));
  expect(stale.status).toBe(409);
  expect(stale.body.error?.code).toBe(ErrorCode.STALE_EPOCH);
  expect(stale.body.progress?.epoch).toBe(1);
  expect((await reader.mutate(save(key, 3, 1, 1))).status).toBe(200);
  const secondChapter = save(key, 4, 2);
  if (secondChapter.operation.case !== 'saveProgress')
    throw new Error('Missing save operation');
  const secondProgress = secondChapter.operation.value.progress;
  const secondSnapshot = secondChapter.operation.value.snapshot;
  if (!secondProgress?.current || !secondSnapshot)
    throw new Error('Missing progress fixture');
  secondSnapshot.chapterKey = 'chapter-2';
  secondProgress.chapterKey = 'chapter-2';
  secondProgress.current.chapterKey = 'chapter-2';
  if (secondProgress.furthest) secondProgress.furthest.chapterKey = 'chapter-2';
  expect((await reader.mutate(secondChapter)).status).toBe(200);
  expect(
    (await reader.state(key, 'chapter-1')).progress?.current?.pageKey,
  ).toBe('middle');
  expect((await reader.state(key, 'chapter-1')).progress?.epoch).toBe(1);
  expect(
    (await reader.state(key, 'chapter-2')).progress?.current?.pageKey,
  ).toBe('last');
  expect((await reader.state(key, 'chapter-2')).manga?.resume?.chapterKey).toBe(
    'chapter-2',
  );
  expect((await reader.library()).body.entries).toEqual([]);
});

test('navigation does not mark pages observed and absent furthest anchors remain unresolved across manifests', async () => {
  const reader = await client();
  const key = favorite().mangaKey;
  const navigation = await reader.mutate(
    save(key, 0, 2, 0, ['first', 'middle', 'last'], false),
  );
  expect(navigation.body.progress?.current?.pageKey).toBe('last');
  expect(navigation.body.progress?.furthest).toBeUndefined();
  const observed = save(key, 1, 2);
  if (
    observed.operation.case !== 'saveProgress' ||
    !observed.operation.value.progress
  )
    throw new Error('Missing progress');
  observed.operation.value.progress.completed = true;
  const finished = await reader.mutate(observed);
  expect(finished.body.progress?.furthest?.pageKey).toBe('last');
  expect(finished.body.progress?.completed).toBe(true);
  const missing = await reader.mutate(
    save(key, 2, 0, 0, ['first', 'new-page']),
  );
  expect(missing.body.progress?.furthest).toEqual(
    finished.body.progress?.furthest,
  );
  expect(missing.body.progress?.completed).toBe(true);
  const found = await reader.mutate(
    save(key, 3, 0, 0, ['last', 'first', 'new-page'], false),
  );
  expect(found.body.progress?.furthest?.pageKey).toBe('last');
  expect(found.body.progress?.furthest?.pageIndexHint).toBe(0);
  expect(found.body.progress?.furthest?.manifestVersion).toBe(
    'manifest-last-first-new-page',
  );
});

test('concurrent writes to different manga persist their own account revisions', async () => {
  const first = await client();
  const second = await client(first.subject);
  const left = favorite();
  const right = favorite();
  const results = await Promise.all([first.mutate(left), second.mutate(right)]);
  expect(results.map((result) => result.status)).toEqual([200, 200]);
  expect(results.map((result) => result.body.accountRevision).sort()).toEqual([
    1, 2,
  ]);
  expect((await first.mutate(left)).body).toEqual(results[0]?.body);
  expect((await second.mutate(right)).body).toEqual(results[1]?.body);
  const shared = save(left.mangaKey, 1);
  const duplicated = await Promise.all([
    first.mutate(shared),
    second.mutate(shared),
  ]);
  expect(duplicated.map((result) => result.status)).toEqual([200, 200]);
  expect(duplicated[0]?.body).toEqual(duplicated[1]?.body);
  expect((await first.library()).body.accountRevision).toBe(3);
});

test('subject-scoped state never follows a caller-supplied identity', async () => {
  const owner = await client();
  const other = await client();
  const mutation = favorite();
  await owner.mutate(mutation);
  expect((await other.state(mutation.mangaKey)).manga?.revision).toBe(0);
  expect((await other.library()).body.entries).toEqual([]);
  const forgedSubject = await other.request('/api/library', {
    headers: { 'X-App-Subject': owner.subject },
  });
  expect(forgedSubject.status).toBe(403);
  const missingToken = await exports.default.fetch(`${origin}/api/library`, {
    headers: { 'X-App-Subject': owner.subject },
  });
  expect(missingToken.status).toBe(401);
  const missingOrigin = await owner.request('/api/state/mutations', {
    method: 'POST',
    body: '{}',
  });
  expect(missingOrigin.status).toBe(403);
});

test('small library pages use a single account revision and reject mixed snapshots', async () => {
  const reader = await client();
  const mutations = Array.from({ length: 9 }, () => favorite());
  for (const mutation of mutations)
    expect((await reader.mutate(mutation)).status).toBe(200);
  const page = await reader.library();
  expect(page.body.entries).toHaveLength(8);
  expect(page.body.nextKey).not.toBe('');
  const nextQuery = `?afterKey=${page.body.nextKey}&revision=${page.body.accountRevision}`;
  expect((await reader.library(nextQuery)).body.entries).toHaveLength(1);
  const first = mutations[0];
  if (!first) throw new Error('Missing mutation');
  await reader.mutate(save(first.mangaKey, 1));
  const stalePage = await reader.library(nextQuery);
  expect(stalePage.status).toBe(409);
  expect(stalePage.body.error?.code).toBe(ErrorCode.REVISION_CONFLICT);
  expect(stalePage.body.entries).toEqual([]);
});

test('a D1 batch failure rolls back state, idempotency and both revisions', async () => {
  const reader = await client();
  const mutation = save(favorite().mangaKey, 0);
  const db = env.DB;
  await db.exec(
    `CREATE TRIGGER fail_progress BEFORE INSERT ON chapter_progress WHEN NEW.subject = '${reader.subject}' BEGIN SELECT RAISE(ABORT, 'controlled batch failure'); END`,
  );
  const failed = await reader.mutate(mutation);
  expect(failed.status).toBe(503);
  const canonical = await reader.state(mutation.mangaKey, 'chapter-1');
  expect(canonical.accountRevision).toBe(0);
  expect(canonical.manga?.revision).toBe(0);
  expect(canonical.progress).toBeUndefined();
  expect(
    await db
      .prepare('SELECT count(*) count FROM state_mutations WHERE subject = ?')
      .bind(reader.subject)
      .first('count'),
  ).toBe(0);
  await db.exec('DROP TRIGGER fail_progress');
  const retried = await reader.mutate(mutation);
  expect(retried.status).toBe(200);
  expect(retried.body.accountRevision).toBe(1);
  expect(retried.body.manga?.revision).toBe(1);
});

test('metadata updates use the stable source identity and malformed or oversized input cannot write state', async () => {
  const reader = await client();
  const add = favorite();
  expect((await reader.mutate(add)).status).toBe(200);
  const original =
    add.operation.case === 'setFavorite'
      ? add.operation.value.metadata
      : undefined;
  if (!original?.manga) throw new Error('Missing metadata');
  const updated = create(LibraryMetadataSchema, {
    ...original,
    manga: { ...original.manga, title: 'Updated on another device' },
  });
  const update = create(StateMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    mangaKey: add.mangaKey,
    expectedRevision: 1,
    operation: { case: 'updateMetadata', value: updated },
  });
  expect((await reader.mutate(update)).body.manga?.revision).toBe(2);
  expect((await reader.state(add.mangaKey)).manga?.metadata?.manga?.title).toBe(
    'Updated on another device',
  );
  const wrongIdentity = create(StateMutationSchema, {
    ...update,
    mutationId: crypto.randomUUID(),
    expectedRevision: 2,
    operation: { case: 'updateMetadata', value: metadata() },
  });
  expect((await reader.mutate(wrongIdentity)).body.error?.code).toBe(
    ErrorCode.INVALID_INPUT,
  );
  for (const body of [
    '{',
    JSON.stringify({ extra: true }),
    ' '.repeat(128 * 1024 + 1),
  ]) {
    const response = await reader.request('/api/state/mutations', {
      method: 'POST',
      headers: {
        Origin: origin,
        'X-App-Request': '1',
        'Content-Type': 'application/json',
      },
      body,
    });
    expect([400, 413]).toContain(response.status);
    expect(
      stateMutationResponseSchema.parse(await response.json()).error,
    ).toBeDefined();
  }
  expect((await reader.state(add.mangaKey)).manga?.revision).toBe(2);
});

function category(
  name = '分类',
  expectedRevision = 0,
  id = crypto.randomUUID(),
) {
  return create(CategoryMutationSchema, {
    schemaVersion: 1,
    mutationId: crypto.randomUUID(),
    expectedRevision,
    operation: { case: 'createCategory', value: { category: { id, name } } },
  });
}
function categoryCommand(
  expectedRevision: number,
  operation: NonNullable<
    MessageInitShape<typeof CategoryMutationSchema>['operation']
  >,
) {
  return create(CategoryMutationSchema, {
    schemaVersion: 1,
    mutationId: crypto.randomUUID(),
    expectedRevision,
    operation,
  });
}
function assign(
  mangaKey: string,
  expectedRevision: number,
  expectedCatalogRevision: number,
  categoryIds: string[],
) {
  return create(StateMutationSchema, {
    schemaVersion: 1,
    mutationId: crypto.randomUUID(),
    mangaKey,
    expectedRevision,
    operation: {
      case: 'setCategories',
      value: { categoryIds, expectedCatalogRevision },
    },
  });
}
function createdId(mutation: CategoryMutation) {
  if (
    mutation.operation.case !== 'createCategory' ||
    !mutation.operation.value.category
  )
    throw new Error('Missing create category');
  return mutation.operation.value.category.id;
}

test('category catalog has independent CAS, ordering and current snapshot membership projection', async () => {
  const first = await client();
  const second = await client(first.subject);
  expect((await first.categories()).categoryCatalog?.revision).toBe(0);
  const a = category('同名');
  const b = category('同名', 1);
  expect((await first.mutateCategory(a)).body.categoryCatalog?.revision).toBe(
    1,
  );
  expect((await second.mutateCategory(b)).status).toBe(200);
  const ids = [createdId(a), createdId(b)];
  const add = favorite();
  await first.mutate(add);
  expect(
    (await first.mutate(assign(add.mangaKey, 1, 2, ids.slice().reverse()))).body
      .manga?.categoryIds,
  ).toEqual(ids);
  const renamed = await second.mutateCategory(
    categoryCommand(2, {
      case: 'renameCategory',
      value: { categoryId: ids[0]!, name: '工作日' },
    }),
  );
  expect(renamed.body.categoryCatalog?.revision).toBe(3);
  const reordered = await second.mutateCategory(
    categoryCommand(3, {
      case: 'reorderCategories',
      value: { categoryIds: ids.slice().reverse() },
    }),
  );
  expect(
    reordered.body.categoryCatalog?.categories.map((value) => value.id),
  ).toEqual(ids.slice().reverse());
  const state = await first.state(add.mangaKey);
  expect(state.manga?.revision).toBe(2);
  expect(state.manga?.categoryIds).toEqual(ids.slice().reverse());
  expect(state.categoryCatalog).toEqual(reordered.body.categoryCatalog);
  expect((await first.library()).body.entries[0]?.categoryIds).toEqual(
    ids.slice().reverse(),
  );
  const db = env.DB;
  const stored = await db
    .prepare(
      'SELECT state_json FROM manga_state WHERE subject = ? AND manga_key = ?',
    )
    .bind(first.subject, add.mangaKey)
    .first<string>('state_json');
  expect(JSON.parse(stored ?? '{}').categoryIds).toBeUndefined();
  expect(
    (await first.mutate(assign(add.mangaKey, 2, 2, []))).body.error?.code,
  ).toBe(ErrorCode.REVISION_CONFLICT);
  expect(
    (await first.mutate(assign(add.mangaKey, 1, 4, []))).body.error?.code,
  ).toBe(ErrorCode.REVISION_CONFLICT);
  expect(
    (await first.mutate(assign(add.mangaKey, 2, 4, [crypto.randomUUID()])))
      .status,
  ).toBe(400);
});

test('category CAS has one winner, retries keep original snapshots and mutation UUIDs cannot cross message kinds', async () => {
  const first = await client();
  const second = await client(first.subject);
  const a = category();
  const b = category();
  const results = await Promise.all([
    first.mutateCategory(a),
    second.mutateCategory(b),
  ]);
  expect(results.map((result) => result.status).sort()).toEqual([200, 409]);
  const winner = results[0]?.status === 200 ? a : b;
  const acknowledged = results.find((result) => result.status === 200)?.body;
  await second.mutateCategory(category('later', 1));
  expect((await first.mutateCategory(winner)).body).toEqual(acknowledged);
  const reused = favorite();
  reused.mutationId = winner.mutationId;
  expect((await first.mutate(reused)).body.error?.code).toBe(
    ErrorCode.IDEMPOTENCY_CONFLICT,
  );
  const mangaMutation = favorite();
  await first.mutate(mangaMutation);
  const inverse = category('inverse', 2);
  inverse.mutationId = mangaMutation.mutationId;
  expect((await first.mutateCategory(inverse)).body.error?.code).toBe(
    ErrorCode.IDEMPOTENCY_CONFLICT,
  );
  expect((await first.categories()).categoryCatalog?.revision).toBe(2);
});

test('category deletion atomically changes relationship and both manga revision representations without changing progress', async () => {
  const first = await client();
  const add = favorite();
  await first.mutate(add);
  const saved = await first.mutate(save(add.mangaKey, 1));
  const created = category();
  await first.mutateCategory(created);
  const id = createdId(created);
  await first.mutate(assign(add.mangaKey, 2, 1, [id]));
  const removed = await first.mutateCategory(
    categoryCommand(1, { case: 'deleteCategory', value: { categoryId: id } }),
  );
  expect(removed.status).toBe(200);
  expect(removed.body.categoryCatalog?.categories).toEqual([]);
  const state = await first.state(add.mangaKey, 'chapter-1');
  expect(state.manga?.revision).toBe(4);
  expect(state.manga?.categoryIds).toEqual([]);
  expect(state.progress).toEqual(saved.body.progress);
  expect(state.manga?.resume).toEqual(saved.body.manga?.resume);
  expect(state.manga?.metadata).toEqual(saved.body.manga?.metadata);
  expect(state.manga?.favorite).toBe(true);
  const db = env.DB;
  const row = await db
    .prepare(
      "SELECT revision, json_extract(state_json, '$.revision') json_revision FROM manga_state WHERE subject = ? AND manga_key = ?",
    )
    .bind(first.subject, add.mangaKey)
    .first();
  expect(row).toEqual({ revision: 4, json_revision: 4 });
  expect(
    await db
      .prepare('SELECT count(*) n FROM manga_categories WHERE subject = ?')
      .bind(first.subject)
      .first('n'),
  ).toBe(0);
  expect((await first.mutate(assign(add.mangaKey, 3, 1, [id]))).status).toBe(
    409,
  );
});

test('racing category deletion and new membership cannot leave dangling categories or overwrite progress', async () => {
  for (let attempt = 0; attempt < 8; attempt++) {
    const first = await client();
    const second = await client(first.subject);
    const add = favorite();
    await first.mutate(add);
    const created = category();
    await first.mutateCategory(created);
    const id = createdId(created);
    const [assigned, deleted] = await Promise.all([
      first.mutate(assign(add.mangaKey, 1, 1, [id])),
      second.mutateCategory(
        categoryCommand(1, {
          case: 'deleteCategory',
          value: { categoryId: id },
        }),
      ),
    ]);
    expect(deleted.status).toBe(200);
    expect([200, 409]).toContain(assigned.status);
    const state = await first.state(add.mangaKey);
    expect(state.manga?.categoryIds).toEqual([]);
    expect(state.manga?.revision).toBe(assigned.status === 200 ? 3 : 1);
    expect(state.categoryCatalog?.categories).toEqual([]);
  }
});

test('category mutation failure rolls back catalog, relationships, manga JSON and all revisions', async () => {
  const first = await client();
  const created = category();
  await first.mutateCategory(created);
  const id = createdId(created);
  const add = favorite();
  await first.mutate(add);
  await first.mutate(assign(add.mangaKey, 1, 1, [id]));
  const before = await first.state(add.mangaKey);
  const db = env.DB;
  await db.exec(
    `CREATE TRIGGER fail_category_delete BEFORE DELETE ON categories WHEN OLD.subject = '${first.subject}' BEGIN SELECT RAISE(ABORT, 'controlled category failure'); END`,
  );
  const request = categoryCommand(1, {
    case: 'deleteCategory',
    value: { categoryId: id },
  });
  expect((await first.mutateCategory(request)).status).toBe(503);
  expect(await first.state(add.mangaKey)).toEqual(before);
  expect(
    await db
      .prepare(
        'SELECT count(*) n FROM state_mutations WHERE subject = ? AND mutation_id = ?',
      )
      .bind(first.subject, request.mutationId)
      .first('n'),
  ).toBe(0);
  await db.exec('DROP TRIGGER fail_category_delete');
  expect((await first.mutateCategory(request)).status).toBe(200);
});

test('catalog changes invalidate pagination, empty shelves expose categories and subject boundaries remain enforced', async () => {
  const first = await client();
  const other = await client();
  const created = category();
  await first.mutateCategory(created);
  const empty = await first.library();
  expect(empty.body.entries).toEqual([]);
  expect(empty.body.categoryCatalog?.categories[0]?.id).toBe(
    createdId(created),
  );
  expect((await other.categories()).categoryCatalog?.categories).toEqual([]);
  const forged = await other.request('/api/categories', {
    headers: { 'X-App-Subject': first.subject },
  });
  expect(forged.status).toBe(403);
  for (let index = 0; index < 9; index++) await first.mutate(favorite());
  const page = await first.library();
  await first.mutateCategory(category('new category', 1));
  const stale = await first.library(
    `?afterKey=${page.body.nextKey}&revision=${page.body.accountRevision}`,
  );
  expect(stale.status).toBe(409);
  expect(stale.body.entries).toEqual([]);
  const invalidReorder = await first.mutateCategory(
    categoryCommand(2, {
      case: 'reorderCategories',
      value: { categoryIds: [] },
    }),
  );
  expect(invalidReorder.status).toBe(400);
});

function bookmark(
  mangaKey: string,
  expectedRevision: number,
  chapterKey: string,
  bookmarked = true,
) {
  return create(StateMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    mangaKey,
    expectedRevision,
    operation: { case: 'setBookmark', value: { chapterKey, bookmarked } },
  });
}

test('independent clients bookmark an unfavorited manga without metadata, preserve progress, and remove by chapter identity', async () => {
  const first = await client();
  const second = await client(first.subject);
  const add = favorite();
  const empty = await first.state(add.mangaKey, 'chapter-1');
  expect(empty.bookmark?.bookmarked).toBe(false);
  expect(empty.manga?.revision).toBe(0);
  const marked = await first.mutate(bookmark(add.mangaKey, 0, 'chapter-1'));
  expect(marked.status).toBe(200);
  expect(marked.body.bookmark).toMatchObject({
    chapterKey: 'chapter-1',
    bookmarked: true,
  });
  expect(marked.body.progress).toBeUndefined();
  expect(marked.body.manga?.metadata).toBeUndefined();
  expect(marked.body.manga?.resume).toBeUndefined();
  expect((await second.library()).body.entries).toEqual([]);
  expect(
    (await second.state(add.mangaKey, 'chapter-1')).bookmark?.bookmarked,
  ).toBe(true);
  await second.mutate(
    favorite(
      1,
      add.operation.case === 'setFavorite'
        ? add.operation.value.metadata
        : undefined,
    ),
  );
  const progress = await second.mutate(save(add.mangaKey, 2));
  const extra = await first.mutate(bookmark(add.mangaKey, 3, 'snapshot-other'));
  expect(extra.body.manga?.resume).toEqual(progress.body.manga?.resume);
  expect((await second.state(add.mangaKey, 'chapter-1')).progress).toEqual(
    progress.body.progress,
  );
  const reset = create(StateMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    mangaKey: add.mangaKey,
    expectedRevision: 4,
    operation: {
      case: 'resetProgress',
      value: {
        snapshot: {
          chapterKey: 'chapter-1',
          manifestVersion: 'reset',
          pageKeys: ['first', 'last'],
        },
      },
    },
  });
  const resetResult = await first.mutate(reset);
  expect(resetResult.body.progress?.epoch).toBe(1);
  await second.mutate(
    favorite(
      5,
      add.operation.case === 'setFavorite'
        ? add.operation.value.metadata
        : undefined,
      false,
    ),
  );
  const preserved = await first.state(add.mangaKey, 'chapter-1');
  expect(preserved.bookmark?.bookmarked).toBe(true);
  expect(preserved.progress).toEqual(resetResult.body.progress);
  expect(preserved.manga?.resume).toEqual(resetResult.body.manga?.resume);
  expect((await second.library()).body.entries).toEqual([]);
  expect(
    (await second.bookmarks(add.mangaKey)).body.entries.map(
      (entry) => entry.chapterKey,
    ),
  ).toEqual(['chapter-1', 'snapshot-other']);
  const removed = await first.mutate(
    bookmark(add.mangaKey, 6, 'chapter-1', false),
  );
  expect(removed.body.bookmark?.bookmarked).toBe(false);
  const canonical = await second.state(add.mangaKey, 'chapter-1');
  expect(canonical.bookmark?.bookmarked).toBe(false);
  expect(canonical.progress).toEqual(resetResult.body.progress);
  expect(canonical.manga?.resume).toEqual(resetResult.body.manga?.resume);
  expect(
    (await second.bookmarks(add.mangaKey)).body.entries.map(
      (entry) => entry.chapterKey,
    ),
  ).toEqual(['snapshot-other']);
});

test('bookmark CAS has one winner and an old idempotent acknowledgement cannot resurrect a deleted bookmark', async () => {
  const first = await client();
  const second = await client(first.subject);
  const key = favorite().mangaKey;
  const a = bookmark(key, 0, 'chapter-1');
  const b = bookmark(key, 0, 'chapter-1');
  const results = await Promise.all([first.mutate(a), second.mutate(b)]);
  expect(results.map((result) => result.status).sort()).toEqual([200, 409]);
  const winner = results[0]?.status === 200 ? a : b;
  const acknowledged = results.find((result) => result.status === 200)?.body;
  const losing = results[0]?.status === 409 ? results[0] : results[1];
  expect(losing?.body.bookmark?.bookmarked).toBe(true);
  const removed = await second.mutate(bookmark(key, 1, 'chapter-1', false));
  expect(removed.body.manga?.revision).toBe(2);
  expect((await first.mutate(winner)).body).toEqual(acknowledged);
  const canonical = await first.state(key, 'chapter-1');
  expect(canonical.manga?.revision).toBe(2);
  expect(canonical.bookmark?.bookmarked).toBe(false);
  expect((await first.bookmarks(key)).body.entries).toEqual([]);
  const stale = await first.mutate(bookmark(key, 0, 'chapter-1'));
  expect(stale.status).toBe(409);
  expect(stale.body.bookmark?.bookmarked).toBe(false);
  const changed = create(StateMutationSchema, {
    ...winner,
    expectedRevision: 2,
  });
  expect((await first.mutate(changed)).body.error?.code).toBe(
    ErrorCode.IDEMPOTENCY_CONFLICT,
  );
  expect((await second.state(key, 'chapter-1')).bookmark?.bookmarked).toBe(
    false,
  );
});

test('bookmark pages bind both first and later pages to one account revision and enforce their own identity', async () => {
  const owner = await client();
  const other = await client();
  const key = favorite().mangaKey;
  const empty = await owner.bookmarks(key);
  expect(empty.body.entries).toEqual([]);
  expect(empty.body.mangaKey).toBe(key);
  for (let index = 0; index < 65; index++)
    expect(
      (
        await owner.mutate(
          bookmark(key, index, `chapter-${String(index).padStart(3, '0')}`),
        )
      ).status,
    ).toBe(200);
  const state = await owner.state(key);
  const page = await owner.bookmarks(key, `?revision=${state.accountRevision}`);
  expect(page.body.entries).toHaveLength(64);
  expect(page.body.entries.every((entry) => entry.bookmarked)).toBe(true);
  expect(page.body.nextKey).toBe('chapter-063');
  const nextQuery = `?afterKey=${page.body.nextKey}&revision=${page.body.accountRevision}`;
  const next = await owner.bookmarks(key, nextQuery);
  expect(next.body.entries.map((entry) => entry.chapterKey)).toEqual([
    'chapter-064',
  ]);
  expect(next.body.nextKey).toBe('');
  expect((await other.bookmarks(key)).body.entries).toEqual([]);
  expect((await other.state(key, 'chapter-000')).bookmark?.bookmarked).toBe(
    false,
  );
  const forged = await other.request(`/api/state/manga/${key}/bookmarks`, {
    headers: { 'X-App-Subject': owner.subject },
  });
  expect(forged.status).toBe(403);
  expect(bookmarkPageResponseSchema.parse(await forged.json()).entries).toEqual(
    [],
  );
  await owner.mutate(bookmark(key, 65, 'chapter-000', false));
  for (const query of [nextQuery, `?revision=${page.body.accountRevision}`]) {
    const stale = await owner.bookmarks(key, query);
    expect(stale.status).toBe(409);
    expect(stale.body.error?.code).toBe(ErrorCode.REVISION_CONFLICT);
    expect(stale.body.entries).toEqual([]);
    expect(stale.body.nextKey).toBe('');
  }
  for (const query of [
    '?afterKey=chapter-001',
    '?revision=-1',
    '?revision=4294967296',
    `?afterKey=${'x'.repeat(201)}&revision=66`,
  ])
    expect((await owner.bookmarks(key, query)).status).toBe(400);
});

test('a failed bookmark batch leaves no bookmark, manga revision, account revision or idempotent result', async () => {
  const reader = await client();
  const key = favorite().mangaKey;
  const command = bookmark(key, 0, 'chapter-1');
  await env.DB.exec(
    `CREATE TRIGGER fail_bookmark BEFORE INSERT ON chapter_bookmarks WHEN NEW.subject = '${reader.subject}' BEGIN SELECT RAISE(ABORT, 'controlled bookmark failure'); END`,
  );
  try {
    expect((await reader.mutate(command)).status).toBe(503);
    const canonical = await reader.state(key, 'chapter-1');
    expect(canonical.accountRevision).toBe(0);
    expect(canonical.manga?.revision).toBe(0);
    expect(canonical.bookmark?.bookmarked).toBe(false);
    expect(
      await env.DB.prepare(
        'SELECT count(*) count FROM state_mutations WHERE subject = ?',
      )
        .bind(reader.subject)
        .first('count'),
    ).toBe(0);
  } finally {
    await env.DB.exec('DROP TRIGGER fail_bookmark');
  }
  const retried = await reader.mutate(command);
  expect(retried.status).toBe(200);
  expect(retried.body.manga?.revision).toBe(1);
  expect(retried.body.accountRevision).toBe(1);
  expect((await reader.state(key, 'chapter-1')).bookmark?.bookmarked).toBe(
    true,
  );
});

function globalSettings(
  expectedRevision = 0,
  theme = AppTheme.DARK,
  mode = ReaderMode.WEBTOON,
  pageLayout = ReaderPageLayout.DOUBLE,
) {
  return create(SettingsMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    expectedRevision,
    operation: {
      case: 'setGlobal',
      value: {
        theme,
        reader: {
          mode,
          pageLayout,
          background: ReaderBackground.BLACK,
          fit: ReaderFit.CONTAIN,
          dimPercent: 0,
          tapZones: ReaderInputPreset.STANDARD,
          keyboard: ReaderInputPreset.STANDARD,
        },
      },
    },
  });
}
function mangaSettings(
  mangaKey: string,
  expectedRevision = 0,
  overrides: {
    mode?: ReaderMode;
    pageLayout?: ReaderPageLayout;
    background?: ReaderBackground;
    fit?: ReaderFit;
    dimPercent?: number;
    tapZones?: ReaderInputPreset;
    keyboard?: ReaderInputPreset;
  } = {},
) {
  return create(SettingsMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    expectedRevision,
    operation: { case: 'setManga', value: { mangaKey, overrides } },
  });
}

test('settings reads do not write, defaults inherit per field, and clearing overrides retains their CAS revision', async () => {
  const first = await client();
  const second = await client(first.subject);
  const key = favorite().mangaKey;
  const initial = await first.settings();
  expect(initial.global?.revision).toBe(0);
  expect(initial.global?.values?.theme).toBe(AppTheme.SYSTEM);
  expect(initial.effectiveReader).toMatchObject({
    mode: ReaderMode.LEFT_TO_RIGHT,
    pageLayout: ReaderPageLayout.AUTO,
  });
  expect(initial.manga).toBeUndefined();
  const empty = await first.settings(key);
  expect(empty.manga).toMatchObject({
    mangaKey: key,
    revision: 0,
    overrides: {},
  });
  expect(empty.effectiveReader).toEqual(initial.effectiveReader);
  expect(
    await env.DB.prepare(
      'SELECT count(*) count FROM reader_settings WHERE subject = ?',
    )
      .bind(first.subject)
      .first('count'),
  ).toBe(0);
  expect(
    await env.DB.prepare(
      'SELECT count(*) count FROM account_state WHERE subject = ?',
    )
      .bind(first.subject)
      .first('count'),
  ).toBe(0);
  expect((await first.mutateSettings(globalSettings())).status).toBe(200);
  const override = await second.mutateSettings(
    mangaSettings(key, 0, {
      mode: ReaderMode.RIGHT_TO_LEFT,
      pageLayout: ReaderPageLayout.AUTO,
    }),
  );
  expect(override.body.manga?.revision).toBe(1);
  expect(override.body.effectiveReader).toMatchObject({
    mode: ReaderMode.RIGHT_TO_LEFT,
    pageLayout: ReaderPageLayout.AUTO,
  });
  expect(
    (
      await first.mutateSettings(
        globalSettings(
          1,
          AppTheme.LIGHT,
          ReaderMode.CONTINUOUS,
          ReaderPageLayout.SINGLE,
        ),
      )
    ).status,
  ).toBe(200);
  const inherited = await second.mutateSettings(
    mangaSettings(key, 1, { mode: ReaderMode.RIGHT_TO_LEFT }),
  );
  expect(inherited.body.manga?.overrides?.pageLayout).toBeUndefined();
  expect(inherited.body.effectiveReader).toMatchObject({
    mode: ReaderMode.RIGHT_TO_LEFT,
    pageLayout: ReaderPageLayout.SINGLE,
  });
  const cleared = await first.mutateSettings(mangaSettings(key, 2));
  expect(cleared.body.manga?.revision).toBe(3);
  expect(cleared.body.effectiveReader).toMatchObject({
    mode: ReaderMode.CONTINUOUS,
    pageLayout: ReaderPageLayout.SINGLE,
  });
  expect(cleared.body.manga?.overrides?.mode).toBeUndefined();
  const stale = await second.mutateSettings(
    mangaSettings(key, 0, { mode: ReaderMode.WEBTOON }),
  );
  expect(stale.status).toBe(409);
  expect(stale.body.manga?.revision).toBe(3);
  expect((await second.settings(key)).manga?.overrides?.mode).toBeUndefined();
  expect((await first.state(key)).manga?.revision).toBe(0);
  expect((await first.library()).body.entries).toEqual([]);
  expect(
    await env.DB.prepare(
      'SELECT revision FROM reader_settings WHERE subject = ? AND scope_key = ?',
    )
      .bind(first.subject, key)
      .first('revision'),
  ).toBe(3);
});

test('appearance and fit preferences preserve explicit zero, inherit all fields and reject invalid writes without touching reading state', async () => {
  const reader = await client();
  const command = favorite();
  const key = command.mangaKey;
  await reader.mutate(command);
  await reader.mutate(save(key, 1));
  const before = await reader.state(key, 'chapter-1');
  const defaults = await reader.settings(key);
  expect(defaults.effectiveReader).toMatchObject({
    background: ReaderBackground.BLACK,
    fit: ReaderFit.CONTAIN,
    dimPercent: 0,
    tapZones: ReaderInputPreset.STANDARD,
    keyboard: ReaderInputPreset.STANDARD,
  });
  const global = globalSettings();
  if (global.operation.case !== 'setGlobal' || !global.operation.value.reader)
    throw new Error('Missing reader defaults');
  Object.assign(global.operation.value.reader, {
    background: ReaderBackground.THEME,
    fit: ReaderFit.WIDTH,
    dimPercent: 80,
    tapZones: ReaderInputPreset.REVERSED,
    keyboard: ReaderInputPreset.DISABLED,
  });
  expect((await reader.mutateSettings(global)).status).toBe(200);
  const overrides = mangaSettings(key, 0, {
    background: ReaderBackground.WHITE,
    fit: ReaderFit.CONTAIN,
    dimPercent: 0,
    tapZones: ReaderInputPreset.DISABLED,
    keyboard: ReaderInputPreset.REVERSED,
  });
  const saved = await reader.mutateSettings(overrides);
  expect(saved.status).toBe(200);
  expect(saved.body.effectiveReader).toMatchObject({
    background: ReaderBackground.WHITE,
    fit: ReaderFit.CONTAIN,
    dimPercent: 0,
    tapZones: ReaderInputPreset.DISABLED,
    keyboard: ReaderInputPreset.REVERSED,
  });
  expect(saved.body.manga?.overrides?.dimPercent).toBe(0);
  expect(saved.body.manga?.overrides?.fit).toBe(ReaderFit.CONTAIN);
  expect((await reader.mutateSettings(overrides)).body).toEqual(saved.body);
  const preserved = await reader.state(key, 'chapter-1');
  expect(preserved.manga).toEqual(before.manga);
  expect(preserved.progress).toEqual(before.progress);
  const cleared = await reader.mutateSettings(mangaSettings(key, 1));
  expect(cleared.body.manga?.overrides?.dimPercent).toBeUndefined();
  expect(cleared.body.manga?.overrides?.fit).toBeUndefined();
  expect(cleared.body.effectiveReader).toEqual(global.operation.value.reader);
  const revision = cleared.body.accountRevision;
  for (const invalid of [
    { fit: 0 },
    { fit: 4 },
    { fit: 1.5 },
    { background: 0 },
    { background: 4 },
    { tapZones: 0 },
    { keyboard: 4 },
    { dimPercent: -1 },
    { dimPercent: 81 },
    { dimPercent: 0.5 },
  ]) {
    const response = await reader.request('/api/settings/mutations', {
      method: 'POST',
      headers: {
        Origin: origin,
        'X-App-Request': '1',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        schemaVersion: 1,
        mutationId: crypto.randomUUID(),
        expectedRevision: 2,
        setManga: { mangaKey: key, overrides: invalid },
      }),
    });
    expect(response.status).toBe(400);
  }
  const after = await reader.settings(key);
  expect(after.accountRevision).toBe(revision);
  expect(after.manga?.revision).toBe(2);
  expect(after.effectiveReader).toEqual(cleared.body.effectiveReader);
});

test('global, manga and reading-progress writes have independent CAS and each ACK is one committed snapshot', async () => {
  const first = await client();
  const second = await client(first.subject);
  const key = favorite().mangaKey;
  const [global, manga] = await Promise.all([
    first.mutateSettings(globalSettings()),
    second.mutateSettings(
      mangaSettings(key, 0, { mode: ReaderMode.RIGHT_TO_LEFT }),
    ),
  ]);
  expect([global.status, manga.status]).toEqual([200, 200]);
  expect(
    [global.body.accountRevision, manga.body.accountRevision].sort(),
  ).toEqual([1, 2]);
  expect(manga.body.manga?.revision).toBe(1);
  expect(
    (manga.body.global?.revision ?? 0) + (manga.body.manga?.revision ?? 0),
  ).toBe(manga.body.accountRevision);
  expect(manga.body.global?.revision).toBe(
    manga.body.accountRevision === 1 ? 0 : 1,
  );
  expect(manga.body.effectiveReader?.pageLayout).toBe(
    manga.body.accountRevision === 1
      ? ReaderPageLayout.AUTO
      : ReaderPageLayout.DOUBLE,
  );
  const canonical = await first.settings(key);
  expect(canonical.global?.revision).toBe(1);
  expect(canonical.manga?.revision).toBe(1);
  expect(canonical.effectiveReader).toMatchObject({
    mode: ReaderMode.RIGHT_TO_LEFT,
    pageLayout: ReaderPageLayout.DOUBLE,
  });
  const progress = await second.mutate(save(key, 0));
  expect(progress.status).toBe(200);
  expect(
    (await first.mutateSettings(globalSettings(1, AppTheme.LIGHT))).status,
  ).toBe(200);
  expect(
    (
      await second.mutateSettings(
        mangaSettings(key, 1, { pageLayout: ReaderPageLayout.SINGLE }),
      )
    ).status,
  ).toBe(200);
  const preserved = await first.state(key, 'chapter-1');
  expect(preserved.manga?.revision).toBe(1);
  expect(preserved.progress).toEqual(progress.body.progress);
  expect(preserved.accountRevision).toBe(5);
});

test('settings CAS has one winner, durable retries retain their snapshot, and UUIDs cannot cross scopes or message kinds', async () => {
  const first = await client();
  const second = await client(first.subject);
  const a = globalSettings();
  const b = globalSettings(0, AppTheme.LIGHT);
  const results = await Promise.all([
    first.mutateSettings(a),
    second.mutateSettings(b),
  ]);
  expect(results.map((result) => result.status).sort()).toEqual([200, 409]);
  const winner = results[0]?.status === 200 ? a : b;
  const acknowledged = results.find((result) => result.status === 200)?.body;
  expect(
    (await first.mutateSettings(globalSettings(1, AppTheme.SYSTEM))).status,
  ).toBe(200);
  expect((await second.mutateSettings(winner)).body).toEqual(acknowledged);
  expect((await second.settings()).global?.revision).toBe(2);
  const changed = create(SettingsMutationSchema, {
    ...winner,
    expectedRevision: 2,
  });
  expect((await first.mutateSettings(changed)).body.error?.code).toBe(
    ErrorCode.IDEMPOTENCY_CONFLICT,
  );
  const differentScope = mangaSettings(favorite().mangaKey);
  differentScope.mutationId = winner.mutationId;
  expect((await first.mutateSettings(differentScope)).body.error?.code).toBe(
    ErrorCode.IDEMPOTENCY_CONFLICT,
  );
  const reusedFavorite = favorite();
  reusedFavorite.mutationId = winner.mutationId;
  expect((await first.mutate(reusedFavorite)).body.error?.code).toBe(
    ErrorCode.IDEMPOTENCY_CONFLICT,
  );
  const mangaCommand = favorite();
  await first.mutate(mangaCommand);
  const reusedSettings = globalSettings(2);
  reusedSettings.mutationId = mangaCommand.mutationId;
  expect((await first.mutateSettings(reusedSettings)).body.error?.code).toBe(
    ErrorCode.IDEMPOTENCY_CONFLICT,
  );
});

test('settings require the verified subject and write headers, and reject malformed, unknown or oversized values', async () => {
  const owner = await client();
  const other = await client();
  const key = favorite().mangaKey;
  await owner.mutateSettings(globalSettings());
  await owner.mutateSettings(
    mangaSettings(key, 0, { mode: ReaderMode.RIGHT_TO_LEFT }),
  );
  expect((await other.settings()).global?.revision).toBe(0);
  expect((await other.settings(key)).manga?.revision).toBe(0);
  for (const path of ['/api/settings', `/api/settings/manga/${key}`]) {
    const forged = await other.request(path, {
      headers: { 'X-App-Subject': owner.subject },
    });
    expect(forged.status).toBe(403);
    expect(
      settingsResponseSchema.parse(await forged.json()).error,
    ).toBeDefined();
  }
  const forgedWrite = await other.request('/api/settings/mutations', {
    method: 'POST',
    headers: {
      Origin: origin,
      'X-App-Request': '1',
      'X-App-Subject': owner.subject,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(toJson(SettingsMutationSchema, globalSettings())),
  });
  expect(forgedWrite.status).toBe(403);
  expect(
    settingsMutationResponseSchema.parse(await forgedWrite.json()).error,
  ).toBeDefined();
  expect(
    (
      await owner.request('/api/settings/mutations', {
        method: 'POST',
        body: '{}',
      })
    ).status,
  ).toBe(403);
  const values = toJson(SettingsMutationSchema, globalSettings(1));
  for (const body of [
    '{',
    JSON.stringify({ ...values, unexpected: true }),
    JSON.stringify({
      ...values,
      setGlobal: { theme: 99, reader: { mode: 1, pageLayout: 1 } },
    }),
    ' '.repeat(128 * 1024 + 1),
  ]) {
    const reply = await owner.request('/api/settings/mutations', {
      method: 'POST',
      headers: {
        Origin: origin,
        'X-App-Request': '1',
        'Content-Type': 'application/json',
      },
      body,
    });
    expect([400, 413]).toContain(reply.status);
    expect(
      settingsMutationResponseSchema.parse(await reply.json()).error,
    ).toBeDefined();
  }
  const badKey = await owner.request('/api/settings/manga/not-a-key');
  expect(badKey.status).toBe(400);
  expect(settingsResponseSchema.parse(await badKey.json()).error).toBeDefined();
  expect((await owner.settings()).global?.revision).toBe(1);
});

test('a settings batch failure rolls back values, scope/account revisions and its idempotency result', async () => {
  const reader = await client();
  const command = globalSettings();
  await env.DB.exec(
    `CREATE TRIGGER fail_settings BEFORE INSERT ON reader_settings WHEN NEW.subject = '${reader.subject}' BEGIN SELECT RAISE(ABORT, 'controlled settings failure'); END`,
  );
  try {
    expect((await reader.mutateSettings(command)).status).toBe(503);
    const canonical = await reader.settings();
    expect(canonical.accountRevision).toBe(0);
    expect(canonical.global?.revision).toBe(0);
    expect(canonical.global?.values?.theme).toBe(AppTheme.SYSTEM);
    expect(
      await env.DB.prepare(
        'SELECT count(*) count FROM state_mutations WHERE subject = ?',
      )
        .bind(reader.subject)
        .first('count'),
    ).toBe(0);
  } finally {
    await env.DB.exec('DROP TRIGGER fail_settings');
  }
  const retried = await reader.mutateSettings(command);
  expect(retried.status).toBe(200);
  expect(retried.body.accountRevision).toBe(1);
  expect(retried.body.global?.revision).toBe(1);
  expect(retried.body.global?.values?.theme).toBe(AppTheme.DARK);
});

function chapterRead(
  mangaKey: string,
  expectedRevision: number,
  chapterKey: string,
  read = true,
) {
  return create(StateMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    mangaKey,
    expectedRevision,
    operation: { case: 'setChapterRead', value: { chapterKey, read } },
  });
}

test('unopened chapters can be marked read or unread without metadata, pages or resume, and ordinary saves preserve chapter read state', async () => {
  const first = await client();
  const second = await client(first.subject);
  const key = favorite().mangaKey;
  const marked = await first.mutate(chapterRead(key, 0, 'chapter-1'));
  expect(marked.status).toBe(200);
  expect(marked.body.progress).toMatchObject({
    chapterKey: 'chapter-1',
    epoch: 1,
    completed: true,
  });
  expect(marked.body.progress?.current).toBeUndefined();
  expect(marked.body.progress?.furthest).toBeUndefined();
  expect(marked.body.manga?.metadata).toBeUndefined();
  expect(marked.body.manga?.resume).toBeUndefined();
  expect(marked.body.manga?.favorite).toBe(false);
  expect((await second.state(key, 'chapter-1')).progress).toEqual(
    marked.body.progress,
  );
  const saved = await second.mutate(
    save(key, 1, 0, 1, ['first', 'new-last'], false),
  );
  expect(saved.status).toBe(200);
  expect(saved.body.progress?.completed).toBe(true);
  expect(saved.body.progress?.furthest).toBeUndefined();
  const unread = await first.mutate(chapterRead(key, 2, 'chapter-1', false));
  expect(unread.status).toBe(200);
  expect(unread.body.progress).toMatchObject({ epoch: 2, completed: false });
  expect(unread.body.progress?.current).toBeUndefined();
  expect(unread.body.progress?.furthest).toBeUndefined();
  expect(unread.body.manga?.resume).toEqual(saved.body.manga?.resume);
  const stale = await second.mutate(save(key, 3, 1, 1));
  expect(stale.status).toBe(409);
  expect(stale.body.error?.code).toBe(ErrorCode.STALE_EPOCH);
  expect(stale.body.progress).toEqual(unread.body.progress);
  const reopened = await second.mutate(
    save(key, 3, 0, 2, ['first', 'last'], false),
  );
  expect(reopened.body.progress).toMatchObject({ epoch: 2, completed: false });
  expect(reopened.body.progress?.current?.pageKey).toBe('first');
  expect(reopened.body.progress?.furthest).toBeUndefined();
  expect((await first.library()).body.entries).toEqual([]);
});

test('manual read preserves real anchors and other business fields, while unread and reset clear completion in their new epoch', async () => {
  const reader = await client();
  const add = favorite();
  await reader.mutate(add);
  const saved = await reader.mutate(save(add.mangaKey, 1));
  const created = category();
  await reader.mutateCategory(created);
  await reader.mutate(assign(add.mangaKey, 2, 1, [createdId(created)]));
  await reader.mutate(bookmark(add.mangaKey, 3, 'chapter-1'));
  const before = await reader.state(add.mangaKey, 'chapter-1');
  const marked = await reader.mutate(chapterRead(add.mangaKey, 4, 'chapter-1'));
  expect(marked.status).toBe(200);
  expect(marked.body.progress?.epoch).toBe(1);
  expect(marked.body.progress?.current).toEqual(saved.body.progress?.current);
  expect(marked.body.progress?.furthest).toEqual(saved.body.progress?.furthest);
  const after = await reader.state(add.mangaKey, 'chapter-1');
  expect(after.manga).toEqual({ ...before.manga, revision: 5 });
  expect(after.bookmark).toEqual(before.bookmark);
  const reset = await reader.mutate(
    create(StateMutationSchema, {
      schemaVersion: businessSchemaVersion,
      mutationId: crypto.randomUUID(),
      mangaKey: add.mangaKey,
      expectedRevision: 5,
      operation: {
        case: 'resetProgress',
        value: {
          snapshot: {
            chapterKey: 'chapter-1',
            manifestVersion: 'reset',
            pageKeys: ['first', 'last'],
          },
        },
      },
    }),
  );
  expect(reset.status).toBe(200);
  expect(reset.body.progress).toMatchObject({ epoch: 2, completed: false });
  expect(reset.body.progress?.current?.pageKey).toBe('first');
  expect(reset.body.progress?.furthest).toBeUndefined();
});

test('read markers have one CAS winner and durable retries cannot repeat an epoch change or resurrect old read state', async () => {
  const first = await client();
  const second = await client(first.subject);
  const key = favorite().mangaKey;
  const read = chapterRead(key, 0, 'chapter-1');
  const unread = chapterRead(key, 0, 'chapter-1', false);
  const results = await Promise.all([
    first.mutate(read),
    second.mutate(unread),
  ]);
  expect(results.map((result) => result.status).sort()).toEqual([200, 409]);
  const winner = results[0]?.status === 200 ? read : unread;
  const acknowledged = results.find((result) => result.status === 200)?.body;
  const later = await first.mutate(chapterRead(key, 1, 'chapter-1', false));
  expect(later.body.progress).toMatchObject({ epoch: 2, completed: false });
  expect((await second.mutate(winner)).body).toEqual(acknowledged);
  const current = await first.state(key, 'chapter-1');
  expect(current.manga?.revision).toBe(2);
  expect(current.progress).toEqual(later.body.progress);
  const changed = create(StateMutationSchema, {
    ...winner,
    expectedRevision: 2,
  });
  expect((await first.mutate(changed)).body.error?.code).toBe(
    ErrorCode.IDEMPOTENCY_CONFLICT,
  );
});

test('progress pages include unread epochs, bound snapshot pagination and enforce verified subjects', async () => {
  const owner = await client();
  const other = await client();
  const key = favorite().mangaKey;
  expect((await owner.progress(key)).body.entries).toEqual([]);
  for (let index = 0; index < 65; index++) {
    expect(
      (
        await owner.mutate(
          chapterRead(
            key,
            index,
            `chapter-${String(index).padStart(3, '0')}`,
            index % 2 === 0,
          ),
        )
      ).status,
    ).toBe(200);
  }
  const state = await owner.state(key);
  const page = await owner.progress(key, `?revision=${state.accountRevision}`);
  expect(page.status).toBe(200);
  expect(page.body.entries).toHaveLength(64);
  expect(page.body.entries[1]).toMatchObject({
    chapterKey: 'chapter-001',
    epoch: 1,
    completed: false,
  });
  expect(page.body.nextKey).toBe('chapter-063');
  const nextQuery = `?afterKey=${page.body.nextKey}&revision=${page.body.accountRevision}`;
  const next = await owner.progress(key, nextQuery);
  expect(next.body.entries.map((entry) => entry.chapterKey)).toEqual([
    'chapter-064',
  ]);
  expect(next.body.nextKey).toBe('');
  expect((await other.progress(key)).body.entries).toEqual([]);
  const forged = await other.request(`/api/state/manga/${key}/progress`, {
    headers: { 'X-App-Subject': owner.subject },
  });
  expect(forged.status).toBe(403);
  expect(
    chapterProgressPageResponseSchema.parse(await forged.json()).entries,
  ).toEqual([]);
  await owner.mutate(chapterRead(key, 65, 'chapter-000', false));
  for (const query of [nextQuery, `?revision=${page.body.accountRevision}`]) {
    const stale = await owner.progress(key, query);
    expect(stale.status).toBe(409);
    expect(stale.body.error?.code).toBe(ErrorCode.REVISION_CONFLICT);
    expect(stale.body.entries).toEqual([]);
    expect(stale.body.nextKey).toBe('');
  }
  for (const query of [
    '?afterKey=chapter-001',
    '?revision=-1',
    '?revision=4294967296',
    `?afterKey=${'x'.repeat(201)}&revision=66`,
  ]) {
    expect((await owner.progress(key, query)).status).toBe(400);
  }
});

test('failed read-marker writes roll back chapter state, revisions and idempotency before an exact retry', async () => {
  const reader = await client();
  const key = favorite().mangaKey;
  const command = chapterRead(key, 0, 'chapter-1', false);
  await env.DB.exec(
    `CREATE TRIGGER fail_read_marker BEFORE INSERT ON chapter_progress WHEN NEW.subject = '${reader.subject}' BEGIN SELECT RAISE(ABORT, 'controlled read-marker failure'); END`,
  );
  try {
    expect((await reader.mutate(command)).status).toBe(503);
    const canonical = await reader.state(key, 'chapter-1');
    expect(canonical.accountRevision).toBe(0);
    expect(canonical.manga?.revision).toBe(0);
    expect(canonical.progress).toBeUndefined();
    expect(
      await env.DB.prepare(
        'SELECT count(*) count FROM state_mutations WHERE subject = ?',
      )
        .bind(reader.subject)
        .first('count'),
    ).toBe(0);
  } finally {
    await env.DB.exec('DROP TRIGGER fail_read_marker');
  }
  const retried = await reader.mutate(command);
  expect(retried.status).toBe(200);
  expect(retried.body.accountRevision).toBe(1);
  expect(retried.body.progress).toMatchObject({ epoch: 1, completed: false });
  expect((await reader.mutate(command)).body).toEqual(retried.body);
});

test('exhausted chapter epochs reject both read and unread markers without changing any state', async () => {
  const reader = await client();
  const key = favorite().mangaKey;
  await reader.mutate(chapterRead(key, 0, 'chapter-1'));
  await env.DB.prepare(
    "UPDATE chapter_progress SET state_json = json_set(state_json, '$.epoch', 4294967295) WHERE subject = ? AND manga_key = ? AND chapter_key = 'chapter-1'",
  )
    .bind(reader.subject, key)
    .run();
  const before = await reader.state(key, 'chapter-1');
  for (const read of [true, false]) {
    const rejected = await reader.mutate(
      chapterRead(key, 1, 'chapter-1', read),
    );
    expect(rejected.status).toBe(409);
    expect(rejected.body.error?.code).toBe(ErrorCode.LIMIT_EXCEEDED);
    expect(rejected.body.progress).toEqual(before.progress);
  }
  expect(await reader.state(key, 'chapter-1')).toEqual(before);
});

test('D1 retains two-dimensional current and furthest anchors across projection, clients and invalid writes', async () => {
  const reader = await client();
  const key = favorite().mangaKey;
  const pages = ['first', 'middle', 'last'];
  const coordinates = {
    normalizedOffset: 0.7,
    normalizedX: 0.2,
    viewportX: 0.6,
    viewportY: 0.8,
  };
  const initial = await reader.mutate(
    save(key, 0, 1, 0, pages, true, coordinates),
  );
  expect(initial.status).toBe(200);
  const horizontal = await reader.mutate(
    save(key, 1, 1, 0, pages, true, {
      ...coordinates,
      normalizedX: 0.9,
      viewportX: 0.3,
    }),
  );
  expect(horizontal.body.progress?.current).toMatchObject({
    ...coordinates,
    normalizedX: 0.9,
    viewportX: 0.3,
  });
  expect(horizontal.body.progress?.furthest).toMatchObject(coordinates);
  const reordered = await reader.mutate(
    save(key, 2, 2, 0, ['last', 'middle', 'first'], false, {
      normalizedOffset: 0.4,
      normalizedX: 1,
      viewportX: 1,
      viewportY: 0.5,
    }),
  );
  expect(reordered.body.progress?.current).toMatchObject({
    pageKey: 'first',
    pageIndexHint: 2,
    normalizedOffset: 0.4,
    normalizedX: 1,
    viewportX: 1,
    viewportY: 0.5,
  });
  expect(reordered.body.progress?.furthest).toMatchObject({
    ...coordinates,
    pageKey: 'middle',
    pageIndexHint: 1,
    manifestVersion: 'manifest-last-middle-first',
  });
  const second = await client(reader.subject);
  const canonical = await second.state(key, 'chapter-1');
  expect(canonical.progress).toEqual(reordered.body.progress);
  expect((await second.progress(key)).body.entries[0]).toEqual(
    canonical.progress,
  );
  for (const invalid of [
    { normalizedOffset: 1.1 },
    { normalizedX: -0.1 },
    { viewportX: 'NaN' },
    { viewportY: 'Infinity' },
  ]) {
    const json = {
      schemaVersion: 1,
      mutationId: crypto.randomUUID(),
      expectedRevision: 3,
      mangaKey: key,
      saveProgress: {
        snapshot: {
          chapterKey: 'chapter-1',
          manifestVersion: 'invalid',
          pageKeys: pages,
        },
        progress: {
          chapterKey: 'chapter-1',
          current: {
            chapterKey: 'chapter-1',
            pageKey: 'middle',
            manifestVersion: 'invalid',
            pageIndexHint: 1,
            ...coordinates,
            ...invalid,
          },
        },
      },
    };
    const response = await reader.request('/api/state/mutations', {
      method: 'POST',
      headers: {
        Origin: origin,
        'X-App-Request': '1',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(json),
    });
    expect(response.status).toBe(400);
  }
  expect(await second.state(key, 'chapter-1')).toEqual(canonical);
  expect(
    await env.DB.prepare(
      'SELECT count(*) count FROM state_mutations WHERE subject = ?',
    )
      .bind(reader.subject)
      .first('count'),
  ).toBe(3);
});
