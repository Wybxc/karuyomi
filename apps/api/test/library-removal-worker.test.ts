import { create, toJson, type MessageInitShape } from '@bufbuild/protobuf';
import {
  CategoryMutationSchema,
  StateMutationSchema,
} from '@karuyomi/protocol';
import {
  businessSchemaVersion,
  categoryMutationResponseSchema,
  mangaStateResponseSchema,
  stateMutationResponseSchema,
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
  jwk.kid = 'removal-fixture';
  env.PROBE_ACCESS_JWKS = JSON.stringify({ keys: [jwk] });
  await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);
}, 30_000);

test('metadata-free shelf removal preserves source metadata, categories, resume, progress and bookmarks', async () => {
  const subject = crypto.randomUUID();
  const token = await new SignJWT({ email: 'owner@example.com' })
    .setProtectedHeader({ alg: 'RS256', kid: 'removal-fixture' })
    .setSubject(subject)
    .setIssuer('https://example.cloudflareaccess.com')
    .setAudience('state-fixture')
    .setIssuedAt()
    .setExpirationTime('5m')
    .sign(keys.privateKey);
  const metadata = {
    packageName: 'eu.kanade.test',
    sourceId: '123',
    sourceName: 'Test source',
    sourceLang: 'en',
    manga: {
      url: '/metadata-free-removal',
      title: 'Keep source title',
      memoJson: '{"opaque":"keep"}',
    },
  };
  const mangaKey = createHash('sha256')
    .update(
      JSON.stringify([
        metadata.packageName,
        metadata.sourceId,
        metadata.manga.url,
      ]),
    )
    .digest('hex');
  const headers = {
    'Cf-Access-Jwt-Assertion': token,
    'X-App-Subject': subject,
  };
  async function post(path: string, body: string) {
    return exports.default.fetch(`${origin}${path}`, {
      method: 'POST',
      headers: {
        ...headers,
        Origin: origin,
        'X-App-Request': '1',
        'Content-Type': 'application/json',
      },
      body,
    });
  }
  async function mutate(
    expectedRevision: number,
    operation: NonNullable<
      MessageInitShape<typeof StateMutationSchema>['operation']
    >,
  ) {
    const command = create(StateMutationSchema, {
      schemaVersion: businessSchemaVersion,
      mutationId: crypto.randomUUID(),
      mangaKey,
      expectedRevision,
      operation,
    });
    const response = await post(
      '/api/state/mutations',
      JSON.stringify(toJson(StateMutationSchema, command)),
    );
    expect(response.status).toBe(200);
    return stateMutationResponseSchema.parse(await response.json());
  }
  async function state() {
    const response = await exports.default.fetch(
      `${origin}/api/state/manga/${mangaKey}?chapterKey=chapter-1`,
      { headers },
    );
    expect(response.status).toBe(200);
    return mangaStateResponseSchema.parse(await response.json());
  }
  await mutate(0, { case: 'setFavorite', value: { metadata, favorite: true } });
  const anchor = {
    chapterKey: 'chapter-1',
    pageKey: 'page-2',
    manifestVersion: 'manifest-1',
    pageIndexHint: 1,
    normalizedOffset: 0.4,
  };
  await mutate(1, {
    case: 'saveProgress',
    value: {
      snapshot: {
        chapterKey: 'chapter-1',
        manifestVersion: 'manifest-1',
        pageKeys: ['page-1', 'page-2'],
      },
      progress: { chapterKey: 'chapter-1', current: anchor, furthest: anchor },
      reversedOrder: true,
    },
  });
  const categoryId = crypto.randomUUID();
  const category = create(CategoryMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    expectedRevision: 0,
    operation: {
      case: 'createCategory',
      value: { category: { id: categoryId, name: 'Keep category' } },
    },
  });
  const created = await post(
    '/api/categories/mutations',
    JSON.stringify(toJson(CategoryMutationSchema, category)),
  );
  expect(created.status).toBe(200);
  expect(
    categoryMutationResponseSchema.parse(await created.json()).categoryCatalog
      ?.revision,
  ).toBe(1);
  await mutate(2, {
    case: 'setCategories',
    value: { expectedCatalogRevision: 1, categoryIds: [categoryId] },
  });
  await mutate(3, {
    case: 'setBookmark',
    value: { chapterKey: 'chapter-1', bookmarked: true },
  });
  const before = await state();
  const removed = await mutate(4, {
    case: 'setFavorite',
    value: { favorite: false },
  });
  expect(removed.manga).toEqual({
    ...before.manga,
    favorite: false,
    revision: 5,
  });
  const after = await state();
  expect(after.manga).toEqual(removed.manga);
  expect(after.progress).toEqual(before.progress);
  expect(after.bookmark).toEqual(before.bookmark);
  expect(after.categoryCatalog).toEqual(before.categoryCatalog);
  expect(after.accountRevision).toBe(before.accountRevision + 1);
  // Re-favoriting can reuse existing authoritative metadata as well.
  expect(
    (await mutate(5, { case: 'setFavorite', value: { favorite: true } })).manga
      ?.metadata,
  ).toEqual(before.manga?.metadata);
  // Missing metadata is still invalid when no existing manga metadata can supply it.
  const missing = create(StateMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    mangaKey: 'a'.repeat(64),
    operation: { case: 'setFavorite', value: { favorite: true } },
  });
  const rejected = await post(
    '/api/state/mutations',
    JSON.stringify(toJson(StateMutationSchema, missing)),
  );
  expect(rejected.status).toBe(400);
  expect(
    stateMutationResponseSchema.parse(await rejected.json()).error?.message,
  ).toBe('Favorites require metadata');
});
