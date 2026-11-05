import { create, toJson, type MessageInitShape } from '@bufbuild/protobuf';
import {
  BusinessStateErrorCode as ErrorCode,
  LibraryMetadataSchema,
  StateMutationSchema,
  type StateMutation,
  CategoryMutationSchema,
  type CategoryMutation,
} from '@karuyomi/protocol';
import {
  businessSchemaVersion,
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
    async library(query = '') {
      const response = await this.request(`/api/library${query}`);
      return {
        status: response.status,
        body: libraryPageResponseSchema.parse(await response.json()),
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
): StateMutation {
  const anchor = {
    chapterKey: 'chapter-1',
    pageKey: pages[index] ?? '',
    pageIndexHint: index,
    manifestVersion: `manifest-${pages.join('-')}`,
    normalizedOffset: 0.4,
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
  expect(missing.body.progress?.completed).toBe(false);
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
