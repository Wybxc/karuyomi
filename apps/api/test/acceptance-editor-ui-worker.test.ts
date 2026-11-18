import { create, toJsonString } from '@bufbuild/protobuf';
import {
  businessSchemaVersion,
  bootstrapSchema,
  categoryCatalogResponseSchema,
  categoryMutationResponseSchema,
  settingsMutationResponseSchema,
  settingsResponseSchema,
  sourcePreferencesMutationResponseSchema,
  sourcePreferencesResponseSchema,
  mangaStateResponseSchema,
  stateMutationResponseSchema,
} from '@karuyomi/contracts';
import {
  BusinessStateErrorCode,
  CategoryMutationSchema,
  CategorySchema,
  LibraryMetadataSchema,
  ReaderMode,
  SettingsMutationSchema,
  SourcePreferencesMutationSchema,
  StateMutationSchema,
} from '@karuyomi/protocol';
import { applyD1Migrations, createExecutionContext } from 'cloudflare:test';
import { env } from 'cloudflare:workers';
import { exportJWK, exportPKCS8, generateKeyPair } from 'jose';
import { createHash } from 'node:crypto';
import { afterEach, beforeAll, beforeEach, expect, test } from 'vitest';
import acceptance from './acceptance-entry.ts';
import {
  prepareEditorUi,
  setEditorUiMode,
  editorUiAttempts,
} from './acceptance-editor-ui.ts';

const origin = 'http://127.0.0.1:44127';
const mangaKey = 'a'.repeat(64);
const mangaPath = '/api/settings/manga/' + mangaKey;
let subject: string;
let credentials: { PROBE_ACCESS_JWKS: string; ACCEPTANCE_PRIVATE_KEY: string };

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

beforeEach(async () => {
  subject = 'editor-ui-' + crypto.randomUUID();
  await prepareEditorUi(env.DB);
});
afterEach(async () => {
  await env.DB.exec(
    'DROP TABLE IF EXISTS acceptance_editor_ui_attempts; DROP TABLE IF EXISTS acceptance_editor_ui_control',
  );
});

function request(
  path: string,
  body?: string | FormData,
  fixture = true,
  requestOrigin = origin,
  signal?: AbortSignal,
) {
  return acceptance.fetch(
    new Request(requestOrigin + path, {
      method: body === undefined ? 'GET' : 'POST',
      headers: {
        Origin: origin,
        'X-App-Request': '1',
        'X-App-Subject': subject,
        ...(typeof body === 'string'
          ? { 'Content-Type': 'application/json' }
          : {}),
      },
      ...(body === undefined ? {} : { body }),
      ...(signal === undefined ? {} : { signal }),
    }),
    {
      ...env,
      ...credentials,
      APP_ORIGIN: origin,
      ACCEPTANCE_SUBJECT: subject,
      ...(fixture ? { ACCEPTANCE_EDITOR_UI: '1' as const } : {}),
    },
    createExecutionContext(),
  );
}

function command(expectedRevision = 0) {
  return toJsonString(
    SettingsMutationSchema,
    create(SettingsMutationSchema, {
      schemaVersion: businessSchemaVersion,
      mutationId: crypto.randomUUID(),
      expectedRevision,
      operation: {
        case: 'setManga',
        value: { mangaKey, overrides: { mode: ReaderMode.RIGHT_TO_LEFT } },
      },
    }),
  );
}

async function snapshot() {
  const reply = await request(mangaPath, undefined, false);
  expect(reply.status).toBe(200);
  return settingsResponseSchema.parse(await reply.json());
}

const preferencePackage = 'eu.kanade.tachiyomi.extension.zh.komiic';
const preferenceCatalog = {
  catalogUrl: origin + '/extensions/index.json',
  repoId: 'keiyoushi',
};
const preferencePath = '/api/source-preferences/packages/' + preferencePackage;
const preferenceRead =
  preferencePath + '?' + new URLSearchParams(preferenceCatalog);
const preferenceWrite = '/api/source-preferences/mutations';
const buildManifestPath = '/extensions/builds/test-build/manifest.json';

test('an extension readiness gate delays only the canonical manifest read and then uses Static Assets', async () => {
  await setEditorUiMode(env.DB, 'hold-read', 'extension-manifest');
  const ordinary = await request(buildManifestPath, undefined, false);
  expect(ordinary.status).toBe(404);
  let delivered = false;
  const pending = request(buildManifestPath).then((reply) => {
    delivered = true;
    return reply;
  });
  try {
    expect((await entered())[0]).toMatchObject({
      path: buildManifestPath,
      mode: 'hold-read',
      method: 'GET',
      worker_status: null,
      client_status: null,
    });
    expect(delivered).toBe(false);
    const queried = await request(buildManifestPath + '?unused=1');
    const unrelated = await request('/extensions/preference-rules.json');
    expect(queried.status).toBe(ordinary.status);
    expect(unrelated.status).toBe(200);
    expect(await editorUiAttempts(env.DB)).toHaveLength(1);
  } finally {
    await setEditorUiMode(env.DB, 'pass', 'extension-manifest');
  }
  const response = await pending;
  expect(response.status).toBe(ordinary.status);
  expect(await response.text()).toBe(await ordinary.text());
  expect((await editorUiAttempts(env.DB))[0]).toMatchObject({
    worker_status: 404,
    client_status: 404,
  });
});

test('Source preferences confirm a real write before faulting only its canonical read', async () => {
  const mutation = create(SourcePreferencesMutationSchema, {
    schemaVersion: businessSchemaVersion,
    mutationId: crypto.randomUUID(),
    catalog: preferenceCatalog,
    packageName: preferencePackage,
    sourceId: '792932060924485302',
    expectedRevision: 0,
    entries: [
      {
        key: 'preferred_mirror',
        value: { value: { case: 'text', value: '1' } },
      },
    ],
  });
  const body = toJsonString(SourcePreferencesMutationSchema, mutation);
  await setEditorUiMode(env.DB, 'confirm-read-failure', 'preferences');
  const reply = await request(preferenceWrite, body);
  expect(reply.status).toBe(200);
  const ack = sourcePreferencesMutationResponseSchema.parse(await reply.json());
  expect(ack.mutationId).toBe(mutation.mutationId);
  expect(ack.preferences?.revision).toBe(1);
  expect(ack.preferences?.entries).toEqual(mutation.entries);
  expect((await request(preferenceRead)).status).toBe(503);
  expect((await request(preferenceRead + '&unrelated=1')).status).toBe(200);
  expect((await request('/api/settings')).status).toBe(200);
  const independent = sourcePreferencesResponseSchema.parse(
    await (await request(preferenceRead, undefined, false)).json(),
  );
  expect(independent.sources).toEqual([ack.preferences]);
  await setEditorUiMode(env.DB, 'pass', 'preferences');
  const readBack = sourcePreferencesResponseSchema.parse(
    await (await request(preferenceRead)).json(),
  );
  expect(readBack).toEqual(independent);
  const audit = (await editorUiAttempts(env.DB)).filter((row) =>
    row.path.startsWith('/api/source-preferences/'),
  );
  expect(audit).toEqual([
    expect.objectContaining({
      method: 'POST',
      body,
      mode: 'confirm-read-failure',
      worker_status: 200,
      client_status: 200,
    }),
    expect.objectContaining({
      method: 'GET',
      body: null,
      mode: 'fail-read',
      worker_status: null,
      client_status: 503,
    }),
    expect.objectContaining({
      method: 'GET',
      body: null,
      mode: 'pass',
      worker_status: 200,
      client_status: 200,
    }),
  ]);
}, 15_000);

const coverPath = '/api/state/manga/' + mangaKey;
const image = Uint8Array.from(
  Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aZ1sAAAAASUVORK5CYII=',
    'base64',
  ),
);

async function coverSnapshot() {
  const reply = await request(coverPath, undefined, false);
  expect(reply.status).toBe(200);
  return mangaStateResponseSchema.parse(await reply.json());
}

function clearCommand(expectedRevision = 1) {
  return toJsonString(
    StateMutationSchema,
    create(StateMutationSchema, {
      schemaVersion: businessSchemaVersion,
      mutationId: crypto.randomUUID(),
      mangaKey,
      expectedRevision,
      operation: { case: 'setCustomCover', value: {} },
    }),
  );
}

async function seedCover() {
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', image));
  const cover = {
    assetId: crypto.randomUUID(),
    contentType: 'image/png',
    byteLength: image.byteLength,
    sha256: Array.from(digest, (value) =>
      value.toString(16).padStart(2, '0'),
    ).join(''),
  };
  const form = new FormData();
  form.set(
    'mutation',
    toJsonString(
      StateMutationSchema,
      create(StateMutationSchema, {
        schemaVersion: businessSchemaVersion,
        mutationId: crypto.randomUUID(),
        mangaKey,
        operation: { case: 'setCustomCover', value: { cover } },
      }),
    ),
  );
  form.set('image', new File([image], 'cover.png', { type: 'image/png' }));
  const saved = await request('/api/covers/' + mangaKey, form, false);
  expect(saved.status).toBe(200);
  expect(
    stateMutationResponseSchema.parse(await saved.json()).manga?.customCover,
  ).toMatchObject(cover);
  return cover;
}

async function entered() {
  for (let attempt = 0; attempt < 30; attempt++) {
    const audit = await editorUiAttempts(env.DB);
    if (audit.length > 0) return audit;
    await new Promise<void>((resolve) => setTimeout(resolve, 50));
  }
  throw new Error('Editor UI request did not enter the fixture');
}

async function seedMigration() {
  const metadata = (sourceId: string) =>
    create(LibraryMetadataSchema, {
      packageName: 'eu.kanade.test',
      sourceId,
      sourceName: 'Test source ' + sourceId,
      sourceLang: 'en',
      manga: { url: '/comic', title: 'Comic ' + sourceId },
    });
  const key = (value: ReturnType<typeof metadata>) =>
    createHash('sha256')
      .update(
        JSON.stringify([value.packageName, value.sourceId, value.manga?.url]),
      )
      .digest('hex');
  const sourceMetadata = metadata('1');
  const targetMetadata = metadata('2');
  const sourceKey = key(sourceMetadata);
  const targetKey = key(targetMetadata);
  const favorite = toJsonString(
    StateMutationSchema,
    create(StateMutationSchema, {
      schemaVersion: businessSchemaVersion,
      mutationId: crypto.randomUUID(),
      mangaKey: sourceKey,
      operation: {
        case: 'setFavorite',
        value: { favorite: true, metadata: sourceMetadata },
      },
    }),
  );
  expect((await request('/api/state/mutations', favorite, false)).status).toBe(
    200,
  );
  const command = () =>
    toJsonString(
      StateMutationSchema,
      create(StateMutationSchema, {
        schemaVersion: businessSchemaVersion,
        mutationId: crypto.randomUUID(),
        mangaKey: targetKey,
        operation: {
          case: 'migrateFrom',
          value: {
            sourceMangaKey: sourceKey,
            expectedSourceRevision: 1,
            expectedCatalogRevision: 0,
            targetMetadata,
            copyCategories: true,
          },
        },
      }),
    );
  const snapshot = async () => {
    const source = await request(
      '/api/state/manga/' + sourceKey,
      undefined,
      false,
    );
    const target = await request(
      '/api/state/manga/' + targetKey,
      undefined,
      false,
    );
    expect(source.status).toBe(200);
    expect(target.status).toBe(200);
    return {
      source: mangaStateResponseSchema.parse(await source.json()),
      target: mangaStateResponseSchema.parse(await target.json()),
    };
  };
  return { sourceKey, targetKey, targetMetadata, command, snapshot };
}

async function seedLibraryScope(scope: 'categories' | 'classification') {
  const mangas = await seedMigration();
  const category = create(CategorySchema, {
    id: crypto.randomUUID(),
    name: '待读',
  });
  const categoryBody = (mutationId: string) =>
    toJsonString(
      CategoryMutationSchema,
      create(CategoryMutationSchema, {
        schemaVersion: businessSchemaVersion,
        mutationId,
        operation: { case: 'createCategory', value: { category } },
      }),
    );
  if (scope === 'classification') {
    expect(
      (
        await request(
          '/api/state/mutations',
          toJsonString(
            StateMutationSchema,
            create(StateMutationSchema, {
              schemaVersion: businessSchemaVersion,
              mutationId: crypto.randomUUID(),
              mangaKey: mangas.targetKey,
              operation: {
                case: 'setFavorite',
                value: {
                  favorite: true,
                  metadata: mangas.targetMetadata,
                },
              },
            }),
          ),
          false,
        )
      ).status,
    ).toBe(200);
    expect(
      (
        await request(
          '/api/categories/mutations',
          categoryBody(crypto.randomUUID()),
          false,
        )
      ).status,
    ).toBe(200);
  }
  const command = () => {
    const mutationId = crypto.randomUUID();
    return {
      mutationId,
      body:
        scope === 'categories'
          ? categoryBody(mutationId)
          : toJsonString(
              StateMutationSchema,
              create(StateMutationSchema, {
                schemaVersion: businessSchemaVersion,
                mutationId,
                mangaKey: mangas.sourceKey,
                expectedRevision: 1,
                operation: {
                  case: 'setCategories',
                  value: {
                    categoryIds: [category.id],
                    expectedCatalogRevision: 1,
                  },
                },
              }),
            ),
    };
  };
  const read = async () => {
    const categories = await request('/api/categories', undefined, false);
    expect(categories.status).toBe(200);
    return {
      ...(await mangas.snapshot()),
      categories: categoryCatalogResponseSchema.parse(await categories.json()),
    };
  };
  const before = await read();
  const committed = structuredClone(before);
  for (const state of Object.values(committed)) state.accountRevision++;
  if (scope === 'categories') {
    for (const state of Object.values(committed)) {
      if (!state.categoryCatalog) throw new Error('Category catalog missing');
      state.categoryCatalog.revision = 1;
      state.categoryCatalog.categories = [category];
    }
  } else {
    if (!committed.source.manga) throw new Error('Favorite missing');
    committed.source.manga.revision = 2;
    committed.source.manga.categoryIds = [category.id];
  }
  return {
    before,
    committed,
    read,
    command,
    path:
      scope === 'categories'
        ? '/api/categories/mutations'
        : '/api/state/mutations',
    readPath:
      scope === 'categories'
        ? '/api/categories'
        : '/api/state/manga/' + mangas.sourceKey,
  };
}

test.each(['categories', 'classification'] as const)(
  '%s automatically delivers a delayed ACK after its real D1 transaction',
  async (scope) => {
    const fixture = await seedLibraryScope(scope);
    await setEditorUiMode(env.DB, 'delay-confirm', scope);
    const original = fixture.command();
    let delivered = false;
    const pending = request(fixture.path, original.body).then((reply) => {
      delivered = true;
      return reply;
    });
    try {
      await entered();
      for (let attempt = 0; attempt < 30; attempt++) {
        if (
          (await fixture.read()).source.accountRevision ===
          fixture.committed.source.accountRevision
        )
          break;
        await new Promise<void>((resolve) => setTimeout(resolve, 50));
      }
      expect(await fixture.read()).toEqual(fixture.committed);
      expect(delivered).toBe(false);
    } finally {
      await pending;
    }
    const reply = await pending;
    expect(reply.status).toBe(200);
    const json = await reply.json();
    const ack =
      scope === 'categories'
        ? categoryMutationResponseSchema.parse(json)
        : stateMutationResponseSchema.parse(json);
    expect(ack.mutationId).toBe(original.mutationId);
    expect(await editorUiAttempts(env.DB)).toEqual([
      expect.objectContaining({
        body: original.body,
        mode: 'delay-confirm',
        worker_status: 200,
        client_status: 200,
      }),
    ]);
  },
  15_000,
);

test.each(['categories', 'classification'] as const)(
  '%s confirms the real write before automatically failing its read-back',
  async (scope) => {
    const fixture = await seedLibraryScope(scope);
    await setEditorUiMode(env.DB, 'confirm-read-failure', scope);
    const original = fixture.command();
    const reply = await request(fixture.path, original.body);
    expect(reply.status).toBe(200);
    const json = await reply.json();
    const ack =
      scope === 'categories'
        ? categoryMutationResponseSchema.parse(json)
        : stateMutationResponseSchema.parse(json);
    expect(ack.mutationId).toBe(original.mutationId);
    expect((await request(fixture.readPath)).status).toBe(503);
    expect((await request('/api/library')).status).toBe(503);
    expect(await fixture.read()).toEqual(fixture.committed);
    await setEditorUiMode(env.DB, 'pass', scope);
    expect((await request(fixture.readPath)).status).toBe(200);
    expect(await fixture.read()).toEqual(fixture.committed);
    const audit = await editorUiAttempts(env.DB);
    expect(audit).toHaveLength(4);
    expect(audit[0]).toMatchObject({
      method: 'POST',
      body: original.body,
      mode: 'confirm-read-failure',
      worker_status: 200,
      client_status: 200,
    });
    expect(audit.slice(1, 3)).toEqual(
      [1, 2].map(() =>
        expect.objectContaining({
          method: 'GET',
          mode: 'fail-read',
          worker_status: null,
          client_status: 503,
        }),
      ),
    );
    expect(audit[3]).toMatchObject({
      method: 'GET',
      mode: 'pass',
      worker_status: 200,
      client_status: 200,
    });
  },
  15_000,
);

test.each(['categories', 'classification'] as const)(
  '%s confirms one write before losing the next committed ACK without duplicating a retry',
  async (scope) => {
    const fixture = await seedLibraryScope(scope);
    await setEditorUiMode(env.DB, 'confirm-next-loss', scope);
    const first = fixture.command();
    const firstReply = await request(fixture.path, first.body);
    expect(firstReply.status).toBe(200);
    expect(await fixture.read()).toEqual(fixture.committed);
    const category =
      fixture.committed.categories.categoryCatalog?.categories[0];
    const target = fixture.committed.target.manga;
    if (!category || !target)
      throw new Error('Confirmed library fixture missing');
    const secondId = crypto.randomUUID();
    const secondBody =
      scope === 'categories'
        ? toJsonString(
            CategoryMutationSchema,
            create(CategoryMutationSchema, {
              schemaVersion: businessSchemaVersion,
              mutationId: secondId,
              expectedRevision: 1,
              operation: {
                case: 'renameCategory',
                value: { categoryId: category.id, name: '已读' },
              },
            }),
          )
        : toJsonString(
            StateMutationSchema,
            create(StateMutationSchema, {
              schemaVersion: businessSchemaVersion,
              mutationId: secondId,
              mangaKey: target.mangaKey,
              expectedRevision: target.revision,
              operation: {
                case: 'setCategories',
                value: {
                  categoryIds: [category.id],
                  expectedCatalogRevision: 1,
                },
              },
            }),
          );
    const afterBoth = structuredClone(fixture.committed);
    for (const state of Object.values(afterBoth)) {
      state.accountRevision++;
      if (scope === 'categories') {
        if (!state.categoryCatalog?.categories[0])
          throw new Error('Category missing');
        state.categoryCatalog.revision = 2;
        state.categoryCatalog.categories[0].name = '已读';
      }
    }
    if (scope === 'classification') {
      if (!afterBoth.target.manga) throw new Error('Target missing');
      afterBoth.target.manga.revision++;
      afterBoth.target.manga.categoryIds = [category.id];
    }
    const lost = await request(fixture.path, secondBody);
    expect(lost.status).toBe(502);
    expect(await fixture.read()).toEqual(afterBoth);
    await setEditorUiMode(env.DB, 'pass', scope);
    const retry = await request(fixture.path, secondBody);
    expect(retry.status).toBe(200);
    const json = await retry.json();
    const ack =
      scope === 'categories'
        ? categoryMutationResponseSchema.parse(json)
        : stateMutationResponseSchema.parse(json);
    expect(ack.mutationId).toBe(secondId);
    expect(await fixture.read()).toEqual(afterBoth);
    expect(await editorUiAttempts(env.DB)).toEqual([
      expect.objectContaining({
        body: first.body,
        mode: 'confirm-next-loss',
        worker_status: 200,
        client_status: 200,
      }),
      expect.objectContaining({
        body: secondBody,
        mode: 'lose-confirm',
        worker_status: 200,
        client_status: 502,
      }),
      expect.objectContaining({
        body: secondBody,
        mode: 'pass',
        worker_status: 200,
        client_status: 200,
      }),
    ]);
  },
  15_000,
);

test.each([
  ['categories', '/api/categories'],
  ['categories', '/api/library'],
  ['classification', coverPath],
  ['classification', '/api/library'],
] as const)(
  'an automatic %s read delay returns the original %s response',
  async (scope, path) => {
    const fixture = await seedLibraryScope(scope);
    const expected = await (await request(path, undefined, false)).json();
    await setEditorUiMode(env.DB, 'delay-read', scope);
    let delivered = false;
    const pending = request(path).then((reply) => {
      delivered = true;
      return reply;
    });
    try {
      await entered();
      expect(delivered).toBe(false);
    } finally {
      await pending;
    }
    const reply = await pending;
    expect(reply.status).toBe(200);
    expect(await reply.json()).toEqual(expected);
    expect(await fixture.read()).toEqual(fixture.before);
    expect(await editorUiAttempts(env.DB)).toEqual([
      expect.objectContaining({
        path,
        method: 'GET',
        mode: 'delay-read',
        worker_status: 200,
        client_status: 200,
      }),
    ]);
  },
  15_000,
);

test.each([
  'delay-read',
  'delay-confirm',
  'confirm-read-failure',
  'confirm-next-loss',
] as const)(
  'an aborted %s request cannot outlive its automatic gate',
  async (mode) => {
    const fixture = await seedLibraryScope('categories');
    await setEditorUiMode(env.DB, mode, 'categories');
    const controller = new AbortController();
    const original = fixture.command();
    const saving = mode !== 'delay-read';
    const pending = request(
      saving ? fixture.path : fixture.readPath,
      saving ? original.body : undefined,
      true,
      origin,
      controller.signal,
    );
    const rejected = expect(pending).rejects.toThrow();
    try {
      await entered();
      if (saving) {
        for (let attempt = 0; attempt < 30; attempt++) {
          if (
            (await fixture.read()).source.accountRevision ===
            fixture.committed.source.accountRevision
          )
            break;
          await new Promise<void>((resolve) => setTimeout(resolve, 50));
        }
        expect(await fixture.read()).toEqual(fixture.committed);
      }
    } finally {
      controller.abort();
      await rejected;
    }
    expect((await editorUiAttempts(env.DB))[0]).toMatchObject({
      mode,
      worker_status: null,
      client_status: null,
    });
    expect(await fixture.read()).toEqual(
      saving ? fixture.committed : fixture.before,
    );
  },
  15_000,
);

test.each(['confirm-read-failure', 'confirm-next-loss'] as const)(
  'an explicit control change wins over a scheduled %s fault',
  async (mode) => {
    const fixture = await seedLibraryScope('categories');
    await setEditorUiMode(env.DB, mode, 'categories');
    const original = fixture.command();
    const pending = request(fixture.path, original.body);
    try {
      await entered();
      for (let attempt = 0; attempt < 30; attempt++) {
        if (
          (await fixture.read()).source.accountRevision ===
          fixture.committed.source.accountRevision
        )
          break;
        await new Promise<void>((resolve) => setTimeout(resolve, 50));
      }
      expect(await fixture.read()).toEqual(fixture.committed);
    } finally {
      await setEditorUiMode(env.DB, 'pass', 'categories');
      await pending;
    }
    expect((await pending).status).toBe(200);
    expect((await request(fixture.path, original.body)).status).toBe(200);
    expect((await request(fixture.readPath)).status).toBe(200);
    expect(await fixture.read()).toEqual(fixture.committed);
  },
  15_000,
);

test.each(['categories', 'classification'] as const)(
  '%s waits for ACK delivery after its real D1 transaction, retaining unrelated works',
  async (scope) => {
    const fixture = await seedLibraryScope(scope);
    await setEditorUiMode(env.DB, 'hold-confirm', scope);
    const original = fixture.command();
    let delivered = false;
    const pending = request(fixture.path, original.body).then((reply) => {
      delivered = true;
      return reply;
    });
    try {
      await entered();
      for (let attempt = 0; attempt < 30; attempt++) {
        if (
          (await fixture.read()).source.accountRevision ===
          fixture.committed.source.accountRevision
        )
          break;
        await new Promise<void>((resolve) => setTimeout(resolve, 50));
      }
      expect(await fixture.read()).toEqual(fixture.committed);
      expect(delivered).toBe(false);
    } finally {
      await setEditorUiMode(env.DB, 'pass', scope);
      await pending;
    }
    const reply = await pending;
    expect(reply.status).toBe(200);
    const json = await reply.json();
    const ack =
      scope === 'categories'
        ? categoryMutationResponseSchema.parse(json)
        : stateMutationResponseSchema.parse(json);
    expect(ack.mutationId).toBe(original.mutationId);
    expect(await editorUiAttempts(env.DB)).toEqual([
      expect.objectContaining({
        body: original.body,
        mode: 'hold-confirm',
        worker_status: 200,
        client_status: 200,
      }),
    ]);
  },
);

test.each(['categories', 'classification'] as const)(
  '%s retries the identical lost ACK without applying twice; fresh stale commands still conflict',
  async (scope) => {
    const fixture = await seedLibraryScope(scope);
    const original = fixture.command();
    await setEditorUiMode(env.DB, 'lose-confirm', scope);
    expect((await request(fixture.path, original.body)).status).toBe(502);
    expect(await fixture.read()).toEqual(fixture.committed);
    await setEditorUiMode(env.DB, 'pass', scope);
    const retry = await request(fixture.path, original.body);
    expect(retry.status).toBe(200);
    const json = await retry.json();
    const ack =
      scope === 'categories'
        ? categoryMutationResponseSchema.parse(json)
        : stateMutationResponseSchema.parse(json);
    expect(ack.mutationId).toBe(original.mutationId);
    expect(await fixture.read()).toEqual(fixture.committed);
    const stale = fixture.command();
    expect(stale.mutationId).not.toBe(original.mutationId);
    const conflict = await request(fixture.path, stale.body);
    expect(conflict.status).toBe(409);
    const raw = await conflict.json();
    const failure =
      scope === 'categories'
        ? categoryMutationResponseSchema.parse(raw)
        : stateMutationResponseSchema.parse(raw);
    expect(failure.error?.code).toBe(BusinessStateErrorCode.REVISION_CONFLICT);
    expect(await fixture.read()).toEqual(fixture.committed);
    expect(await editorUiAttempts(env.DB)).toEqual([
      expect.objectContaining({
        body: original.body,
        worker_status: 200,
        client_status: 502,
      }),
      expect.objectContaining({
        body: original.body,
        worker_status: 200,
        client_status: 200,
      }),
      expect.objectContaining({
        body: stale.body,
        worker_status: 409,
        client_status: 409,
      }),
    ]);
  },
);

test.each(['categories', 'classification'] as const)(
  '%s read failure, rejection and expired login preserve catalog and both works',
  async (scope) => {
    const fixture = await seedLibraryScope(scope);
    await setEditorUiMode(env.DB, 'fail-read', scope);
    expect((await request(fixture.readPath)).status).toBe(503);
    expect((await request('/api/library')).status).toBe(503);
    expect(await fixture.read()).toEqual(fixture.before);
    const original = fixture.command();
    await setEditorUiMode(env.DB, 'reject-save', scope);
    const rejected = await request(fixture.path, original.body);
    expect(rejected.status).toBe(400);
    const json = await rejected.json();
    const ack =
      scope === 'categories'
        ? categoryMutationResponseSchema.parse(json)
        : stateMutationResponseSchema.parse(json);
    expect(ack.mutationId).toBe(original.mutationId);
    expect(ack.error?.code).toBe(BusinessStateErrorCode.INVALID_INPUT);
    expect(await fixture.read()).toEqual(fixture.before);
    await setEditorUiMode(env.DB, 'login-required', scope);
    const expired = await request(fixture.path, original.body);
    expect(expired.status).toBe(401);
    expect(expired.headers.get('Content-Type')).toBe('text/html');
    expect(await fixture.read()).toEqual(fixture.before);
    expect((await request('/api/settings')).status).toBe(200);
    expect((await request(fixture.readPath + '?unrelated=1')).status).toBe(200);
    expect(await editorUiAttempts(env.DB)).toEqual([
      expect.objectContaining({
        method: 'GET',
        mode: 'fail-read',
        worker_status: null,
        client_status: 503,
      }),
      expect.objectContaining({
        path: '/api/library',
        method: 'GET',
        mode: 'fail-read',
        worker_status: null,
        client_status: 503,
      }),
      expect.objectContaining({
        body: original.body,
        mode: 'reject-save',
        worker_status: null,
        client_status: 400,
      }),
      expect.objectContaining({
        body: original.body,
        mode: 'login-required',
        worker_status: null,
        client_status: 401,
      }),
      expect.objectContaining({
        path: '/api/settings',
        mode: 'pass',
        worker_status: 200,
        client_status: 200,
      }),
    ]);
  },
);

test('fixture stays opt-in, loopback-only, scoped and absent from other APIs', async () => {
  await setEditorUiMode(env.DB, 'fail-read', 'manga');
  expect((await request(mangaPath, undefined, false)).status).toBe(200);
  expect((await request('/api/settings')).status).toBe(200);
  expect((await request('/api/library')).status).toBe(200);
  await request(mangaPath, undefined, true, 'https://read.example.com');
  const audit = await editorUiAttempts(env.DB);
  expect(audit).toHaveLength(1);
  expect(audit[0]).toMatchObject({
    path: '/api/settings',
    mode: 'pass',
    worker_status: 200,
    client_status: 200,
  });
  await expect(setEditorUiMode(env.DB, 'unknown', 'manga')).rejects.toThrow(
    'Expected',
  );
  await expect(setEditorUiMode(env.DB, 'pass', 'other')).rejects.toThrow(
    'Expected',
  );
});

test.each([
  ['hold-confirm', 'cover'],
  ['lose-confirm', 'migration'],
  ['reject-save', 'cover'],
  ['login-required', 'connection'],
  ['hold-confirm', 'categories'],
  ['lose-confirm', 'classification'],
  ['reject-save', 'categories'],
  ['login-required', 'classification'],
  ['delay-read', 'categories'],
  ['delay-confirm', 'categories'],
  ['confirm-read-failure', 'classification'],
  ['confirm-next-loss', 'classification'],
])(
  'unrelated progress is audited without %s faults in %s',
  async (mode, scope) => {
    await setEditorUiMode(env.DB, mode, scope);
    const anchor = {
      chapterKey: 'chapter-1',
      manifestVersion: 'manifest-1',
      pageKey: 'one',
    };
    const body = toJsonString(
      StateMutationSchema,
      create(StateMutationSchema, {
        schemaVersion: businessSchemaVersion,
        mutationId: crypto.randomUUID(),
        mangaKey,
        operation: {
          case: 'saveProgress',
          value: {
            snapshot: {
              chapterKey: anchor.chapterKey,
              manifestVersion: anchor.manifestVersion,
              pageKeys: ['one'],
            },
            progress: {
              chapterKey: anchor.chapterKey,
              current: anchor,
              furthest: anchor,
            },
          },
        },
      }),
    );
    for (let attempt = 0; attempt < 2; attempt++) {
      const reply = await request('/api/state/mutations', body);
      expect(reply.status).toBe(200);
      const saved = stateMutationResponseSchema.parse(await reply.json());
      expect(saved.accountRevision).toBe(1);
      expect(saved.manga?.revision).toBe(1);
      expect(saved.progress?.current?.pageKey).toBe('one');
    }
    expect(await editorUiAttempts(env.DB)).toEqual(
      [1, 2].map((sequence) => ({
        sequence,
        path: '/api/state/mutations',
        method: 'POST',
        mode: 'pass',
        body,
        worker_status: 200,
        client_status: 200,
      })),
    );
  },
);

test.each([
  ['connection', '/api/bootstrap'],
  ['manga', mangaPath],
  ['cover', coverPath],
  ['migration', coverPath],
  ['categories', '/api/categories'],
  ['classification', coverPath],
  ['categories', '/api/library'],
  ['classification', '/api/library'],
])(
  'reading %s remains pending until an explicit stdin-controlled generation change',
  async (scope, path) => {
    await setEditorUiMode(env.DB, 'hold-read', scope);
    let delivered = false;
    const pending = request(path).then((reply) => {
      delivered = true;
      return reply;
    });
    try {
      expect((await entered())[0]).toMatchObject({
        mode: 'hold-read',
        method: 'GET',
        worker_status: null,
        client_status: null,
      });
      expect(delivered).toBe(false);
    } finally {
      await setEditorUiMode(env.DB, 'pass', scope);
    }
    expect((await pending).status).toBe(200);
    expect((await editorUiAttempts(env.DB))[0]).toMatchObject({
      worker_status: 200,
      client_status: 200,
    });
  },
);

test.each([
  ['connection', '/api/bootstrap'],
  ['manga', mangaPath],
  ['cover', coverPath],
  ['migration', coverPath],
  ['categories', '/api/categories'],
  ['classification', coverPath],
  ['categories', '/api/library'],
  ['classification', '/api/library'],
  ['extension-manifest', buildManifestPath],
])(
  'an aborted %s reader leaves the gate without dispatching a late request',
  async (scope, path) => {
    await setEditorUiMode(env.DB, 'hold-read', scope);
    const controller = new AbortController();
    const pending = request(path, undefined, true, origin, controller.signal);
    const rejected = expect(pending).rejects.toThrow();
    await entered();
    controller.abort();
    await rejected;
    expect((await editorUiAttempts(env.DB))[0]).toMatchObject({
      worker_status: null,
      client_status: null,
    });
  },
);

test('connection faults preserve real identity and state outside the exact bootstrap read', async () => {
  const before = await snapshot();
  for (const [mode, status] of [
    ['fail-read', 503],
    ['login-required', 401],
    ['access-denied', 403],
  ] as const) {
    await setEditorUiMode(env.DB, mode, 'connection');
    const reply = await request('/api/bootstrap');
    expect(reply.status).toBe(status);
    const normal = await request('/api/bootstrap', undefined, false);
    expect(normal.status).toBe(200);
    expect(bootstrapSchema.parse(await normal.json()).identity.subject).toBe(
      subject,
    );
    const queried = await request('/api/bootstrap?probe=1');
    expect(queried.status).toBe(200);
    expect(bootstrapSchema.parse(await queried.json()).identity.subject).toBe(
      subject,
    );
    expect(await snapshot()).toEqual(before);
  }
  const attempts = await editorUiAttempts(env.DB);
  expect(attempts.filter((row) => row.path === '/api/bootstrap')).toEqual([
    expect.objectContaining({
      method: 'GET',
      mode: 'fail-read',
      body: null,
      worker_status: null,
      client_status: 503,
    }),
    expect.objectContaining({
      method: 'GET',
      mode: 'login-required',
      body: null,
      worker_status: null,
      client_status: 401,
    }),
    expect.objectContaining({
      method: 'GET',
      mode: 'access-denied',
      body: null,
      worker_status: null,
      client_status: 403,
    }),
  ]);
  expect(attempts.every((row) => row.method === 'GET')).toBe(true);
});

test('confirmation gate holds delivery after the real D1 transaction commits', async () => {
  await setEditorUiMode(env.DB, 'hold-confirm', 'manga');
  const body = command();
  let delivered = false;
  const pending = request('/api/settings/mutations', body).then((reply) => {
    delivered = true;
    return reply;
  });
  try {
    await entered();
    for (
      let attempt = 0;
      attempt < 30 && (await snapshot()).manga?.revision !== 1;
      attempt++
    ) {
      await new Promise<void>((resolve) => setTimeout(resolve, 50));
    }
    expect((await snapshot()).manga?.revision).toBe(1);
    expect(delivered).toBe(false);
  } finally {
    await setEditorUiMode(env.DB, 'pass', 'manga');
  }
  const ack = settingsMutationResponseSchema.parse(
    await (await pending).json(),
  );
  expect(ack.manga?.revision).toBe(1);
  expect((await editorUiAttempts(env.DB))[0]?.body).toBe(body);
});

test('lost committed ACK retries exact body once, while stale fresh commands still conflict', async () => {
  await setEditorUiMode(env.DB, 'lose-confirm', 'manga');
  const body = command();
  expect((await request('/api/settings/mutations', body)).status).toBe(502);
  expect((await snapshot()).manga?.revision).toBe(1);
  await setEditorUiMode(env.DB, 'pass', 'manga');
  const retry = await request('/api/settings/mutations', body);
  expect(retry.status).toBe(200);
  expect(
    settingsMutationResponseSchema.parse(await retry.json()).manga?.revision,
  ).toBe(1);
  const stale = await request('/api/settings/mutations', command());
  expect(stale.status).toBe(409);
  expect(
    settingsMutationResponseSchema.parse(await stale.json()).error?.code,
  ).toBe(BusinessStateErrorCode.REVISION_CONFLICT);
  expect((await snapshot()).manga?.revision).toBe(1);
  const audit = await editorUiAttempts(env.DB);
  expect(audit[0]).toMatchObject({
    body,
    worker_status: 200,
    client_status: 502,
  });
  expect(audit[1]).toMatchObject({
    body,
    worker_status: 200,
    client_status: 200,
  });
});

test('read failure, pre-dispatch rejection and login HTML never create a settings write', async () => {
  await setEditorUiMode(env.DB, 'fail-read', 'manga');
  expect((await request(mangaPath)).status).toBe(503);
  await setEditorUiMode(env.DB, 'reject-save', 'manga');
  const rejected = await request('/api/settings/mutations', command());
  expect(rejected.status).toBe(400);
  expect(
    settingsMutationResponseSchema.parse(await rejected.json()).error,
  ).toMatchObject({
    code: BusinessStateErrorCode.INVALID_INPUT,
    retryable: false,
  });
  expect((await snapshot()).manga?.revision).toBe(0);
  await setEditorUiMode(env.DB, 'login-required', 'manga');
  const login = await request(mangaPath);
  expect(login.status).toBe(401);
  expect(login.headers.get('content-type')).toBe('text/html');
  await setEditorUiMode(env.DB, 'pass', 'manga');
  expect((await snapshot()).manga?.revision).toBe(0);
  expect(
    (await editorUiAttempts(env.DB)).every((row) => row.worker_status === null),
  ).toBe(true);
});

test('cover confirmation waits after the real clear commits and never retains image bytes in the audit', async () => {
  await seedCover();
  await setEditorUiMode(env.DB, 'hold-confirm', 'cover');
  const body = clearCommand();
  let delivered = false;
  const pending = request('/api/state/mutations', body).then((reply) => {
    delivered = true;
    return reply;
  });
  try {
    await entered();
    for (
      let attempt = 0;
      attempt < 30 && (await coverSnapshot()).manga?.revision !== 2;
      attempt++
    ) {
      await new Promise<void>((resolve) => setTimeout(resolve, 50));
    }
    const committed = await coverSnapshot();
    expect(committed.accountRevision).toBe(2);
    expect(committed.manga?.customCover).toBeUndefined();
    expect(delivered).toBe(false);
  } finally {
    await setEditorUiMode(env.DB, 'pass', 'cover');
  }
  const ack = stateMutationResponseSchema.parse(await (await pending).json());
  expect(ack.manga?.revision).toBe(2);
  expect(await editorUiAttempts(env.DB)).toEqual([
    expect.objectContaining({
      method: 'POST',
      path: '/api/state/mutations',
      body,
      worker_status: 200,
      client_status: 200,
    }),
  ]);
});

test('lost cover clear ACK retries the identical command without another revision and rejects a fresh stale command', async () => {
  await seedCover();
  await setEditorUiMode(env.DB, 'lose-confirm', 'cover');
  const body = clearCommand();
  expect((await request('/api/state/mutations', body)).status).toBe(502);
  const committed = await coverSnapshot();
  expect(committed.manga?.revision).toBe(2);
  expect(committed.manga?.customCover).toBeUndefined();
  await setEditorUiMode(env.DB, 'pass', 'cover');
  const retry = await request('/api/state/mutations', body);
  expect(retry.status).toBe(200);
  expect(
    stateMutationResponseSchema.parse(await retry.json()).manga?.revision,
  ).toBe(2);
  const stale = await request('/api/state/mutations', clearCommand());
  expect(stale.status).toBe(409);
  expect(
    stateMutationResponseSchema.parse(await stale.json()).error?.code,
  ).toBe(BusinessStateErrorCode.REVISION_CONFLICT);
  expect(await coverSnapshot()).toEqual(committed);
  expect((await editorUiAttempts(env.DB)).slice(0, 2)).toEqual([
    expect.objectContaining({ body, worker_status: 200, client_status: 502 }),
    expect.objectContaining({ body, worker_status: 200, client_status: 200 }),
  ]);
});

test('cover read/rejection/login faults keep the confirmed cover and other scopes stay real', async () => {
  const cover = await seedCover();
  const before = await coverSnapshot();
  await setEditorUiMode(env.DB, 'fail-read', 'cover');
  expect((await request(coverPath)).status).toBe(503);
  expect((await request('/api/settings')).status).toBe(200);
  expect((await request(mangaPath)).status).toBe(200);
  await setEditorUiMode(env.DB, 'reject-save', 'cover');
  const rejected = await request('/api/state/mutations', clearCommand());
  expect(rejected.status).toBe(400);
  expect(
    stateMutationResponseSchema.parse(await rejected.json()).error,
  ).toMatchObject({
    code: BusinessStateErrorCode.INVALID_INPUT,
    retryable: false,
  });
  expect(await coverSnapshot()).toEqual(before);
  await setEditorUiMode(env.DB, 'login-required', 'cover');
  const login = await request(coverPath);
  expect(login.status).toBe(401);
  expect(login.headers.get('content-type')).toBe('text/html');
  expect((await request('/api/covers/' + cover.assetId)).status).toBe(401);
  expect(await coverSnapshot()).toEqual(before);
});

test('cover byte failure preserves the record and retries the same private resource', async () => {
  const cover = await seedCover();
  const before = await coverSnapshot();
  const path = '/api/covers/' + cover.assetId;
  await setEditorUiMode(env.DB, 'fail-image', 'cover');
  expect((await request(path)).status).toBe(503);
  expect((await request(coverPath)).status).toBe(200);
  expect(await coverSnapshot()).toEqual(before);
  await setEditorUiMode(env.DB, 'pass', 'cover');
  const retry = await request(path);
  expect(retry.status).toBe(200);
  expect(new Uint8Array(await retry.arrayBuffer())).toEqual(image);
  expect(await coverSnapshot()).toEqual(before);
  expect(
    (await editorUiAttempts(env.DB)).every((row) => row.body === null),
  ).toBe(true);
});

test('migration confirmation waits for delivery after the target commits and preserves the original', async () => {
  const migration = await seedMigration();
  const before = await migration.snapshot();
  await setEditorUiMode(env.DB, 'hold-confirm', 'migration');
  const body = migration.command();
  let delivered = false;
  const pending = request('/api/state/mutations', body).then((reply) => {
    delivered = true;
    return reply;
  });
  try {
    await entered();
    for (
      let attempt = 0;
      attempt < 30 && (await migration.snapshot()).target.manga?.revision !== 1;
      attempt++
    ) {
      await new Promise<void>((resolve) => setTimeout(resolve, 50));
    }
    const committed = await migration.snapshot();
    expect(committed.target.manga?.favorite).toBe(true);
    expect(committed.target.manga?.revision).toBe(1);
    expect(committed.target.accountRevision).toBe(2);
    expect(committed.source.manga).toEqual(before.source.manga);
    expect(delivered).toBe(false);
  } finally {
    await setEditorUiMode(env.DB, 'pass', 'migration');
  }
  const ack = stateMutationResponseSchema.parse(await (await pending).json());
  expect(ack.manga?.mangaKey).toBe(migration.targetKey);
  expect(ack.manga?.revision).toBe(1);
  expect(ack.migration).toMatchObject({
    copiedReadChapters: 0,
    copiedBookmarks: 0,
  });
  expect(await editorUiAttempts(env.DB)).toEqual([
    expect.objectContaining({ body, worker_status: 200, client_status: 200 }),
  ]);
});

test('lost migration ACK retries the same command without applying twice and fresh stale commands conflict', async () => {
  const migration = await seedMigration();
  await setEditorUiMode(env.DB, 'lose-confirm', 'migration');
  const body = migration.command();
  expect((await request('/api/state/mutations', body)).status).toBe(502);
  const committed = await migration.snapshot();
  expect(committed.target.manga?.revision).toBe(1);
  await setEditorUiMode(env.DB, 'pass', 'migration');
  expect((await request('/api/state/mutations', body)).status).toBe(200);
  expect(await migration.snapshot()).toEqual(committed);
  const stale = await request('/api/state/mutations', migration.command());
  expect(stale.status).toBe(409);
  expect(
    stateMutationResponseSchema.parse(await stale.json()).error?.code,
  ).toBe(BusinessStateErrorCode.REVISION_CONFLICT);
  expect(await migration.snapshot()).toEqual(committed);
  expect((await editorUiAttempts(env.DB)).slice(0, 2)).toEqual([
    expect.objectContaining({ body, worker_status: 200, client_status: 502 }),
    expect.objectContaining({ body, worker_status: 200, client_status: 200 }),
  ]);
});

test('migration read/rejection/login faults preserve both works and leave settings on its real path', async () => {
  const migration = await seedMigration();
  const before = await migration.snapshot();
  await setEditorUiMode(env.DB, 'fail-read', 'migration');
  expect(
    (await request('/api/state/manga/' + migration.sourceKey)).status,
  ).toBe(503);
  expect(
    (await request('/api/state/manga/' + migration.targetKey)).status,
  ).toBe(503);
  expect((await request('/api/settings')).status).toBe(200);
  expect((await request(mangaPath)).status).toBe(200);
  await setEditorUiMode(env.DB, 'reject-save', 'migration');
  const rejected = await request('/api/state/mutations', migration.command());
  expect(rejected.status).toBe(400);
  expect(
    stateMutationResponseSchema.parse(await rejected.json()).error,
  ).toMatchObject({
    code: BusinessStateErrorCode.INVALID_INPUT,
    retryable: false,
  });
  expect(await migration.snapshot()).toEqual(before);
  await setEditorUiMode(env.DB, 'login-required', 'migration');
  const login = await request('/api/state/manga/' + migration.sourceKey);
  expect(login.status).toBe(401);
  expect(login.headers.get('content-type')).toBe('text/html');
  expect(await migration.snapshot()).toEqual(before);
});
