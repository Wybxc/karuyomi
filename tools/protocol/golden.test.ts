import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import {
  fromBinary,
  fromJson,
  fromJsonString,
  create,
  toBinary,
  toJson,
  type DescMessage,
  type JsonObject,
  type JsonValue,
} from '@bufbuild/protobuf';
import {
  BootstrapSchema,
  BuildManifestSchema,
  ChapterSchema,
  ChapterListSchema,
  ControlRequestSchema,
  ControlResponseSchema,
  ExtensionIndexSchema,
  ImageFrameControlSchema,
  ImageResourceSchema,
  MangaSchema,
  PageListSchema,
  SourceCallSchema,
  SourceInfoSchema,
  SourceResultSchema,
  WorkerCommandSchema,
  WorkerResponseSchema,
  StateMutationSchema,
  StateMutationResponseSchema,
  MangaStateResponseSchema,
  LibraryPageResponseSchema,
  ChapterProgressPageResponseSchema,
  CategoryMutationSchema,
  CategoryMutationResponseSchema,
  CategoryCatalogResponseSchema,
} from '@karuyomi/protocol';
import * as contract from '../../packages/contracts/src/index.ts';
import { fileURLToPath } from 'node:url';
const ROOT = fileURLToPath(new URL('../../', import.meta.url));
import { execaSync as execSync } from 'execa';
import {
  chapter,
  buildId,
  generation,
  goldenFixtures,
  manga,
  memoJson,
  pageList,
  sourceId,
  type GoldenFixture,
  type GoldenType,
  businessMangaKey,
  businessMutationId,
  businessSnapshot,
  businessProgress,
  businessAnchor,
  libraryMetadata,
} from './fixtures.ts';

const schemas: Record<GoldenType, DescMessage> = {
  ControlRequest: ControlRequestSchema,
  ControlResponse: ControlResponseSchema,
  SourceCall: SourceCallSchema,
  SourceResult: SourceResultSchema,
  SourceInfo: SourceInfoSchema,
  Manga: MangaSchema,
  Chapter: ChapterSchema,
  PageList: PageListSchema,
  ImageResource: ImageResourceSchema,
  BuildManifest: BuildManifestSchema,
  ExtensionIndex: ExtensionIndexSchema,
  Bootstrap: BootstrapSchema,
  ImageFrameControl: ImageFrameControlSchema,
  WorkerCommand: WorkerCommandSchema,
  WorkerResponse: WorkerResponseSchema,
  StateMutation: StateMutationSchema,
  StateMutationResponse: StateMutationResponseSchema,
  MangaStateResponse: MangaStateResponseSchema,
  LibraryPageResponse: LibraryPageResponseSchema,
  ChapterProgressPageResponse: ChapterProgressPageResponseSchema,
  CategoryMutation: CategoryMutationSchema,
  CategoryMutationResponse: CategoryMutationResponseSchema,
  CategoryCatalogResponse: CategoryCatalogResponseSchema,
};

function canonical(fixture: GoldenFixture): JsonValue {
  const schema = schemas[fixture.type];
  return toJson(schema, fromJson(schema, fixture.value));
}

function dart(fixtures: ReadonlyArray<{ type: GoldenType; value: JsonValue }>) {
  const binary = process.platform === 'win32' ? 'dart.bat' : 'dart';
  const command = process.env.FLUTTER_ROOT
    ? path.join(process.env.FLUTTER_ROOT, 'bin', binary)
    : existsSync(path.join(ROOT, '.fvm/flutter_sdk/bin', binary))
      ? path.join(ROOT, '.fvm/flutter_sdk/bin', binary)
      : binary;
  return execSync(command, ['run', 'tool/protocol_crosswire.dart'], {
    cwd: path.join(ROOT, 'packages/source_runtime'),
    shell: false,
    preferLocal: false,
    stripFinalNewline: false,
    verbose: 'none',
    env: process.env,
    extendEnv: false,
    stdin: 'pipe',
    input: fixtures.map((fixture) => JSON.stringify(fixture)).join('\n') + '\n',
    encoding: 'utf8',
    timeout: 120000,
    maxBuffer: 16 * 1024 * 1024,
    reject: false,
  });
}

function dartRoundTrip(fixtures: GoldenFixture[]): string[] {
  const output = dart(fixtures);
  if (output.failed && output.exitCode === undefined) throw output;
  assert.equal(output.exitCode, 0, output.stderr);
  const lines = output.stdout.trim().split('\n');
  assert.equal(
    lines.length,
    fixtures.length,
    'Dart must return exactly one value per fixture',
  );
  return lines;
}

test('generated TS ProtoJSON and binary codecs preserve the golden matrix', () => {
  for (const fixture of goldenFixtures) {
    const schema = schemas[fixture.type];
    const message = fromJson(schema, fixture.value);
    assert.deepEqual(
      toJson(schema, fromBinary(schema, toBinary(schema, message))),
      canonical(fixture),
      fixture.name,
    );
  }
});

test(
  'TS → Dart → TS and Dart → TS → Dart preserve generated ProtoJSON',
  { timeout: 120000 },
  () => {
    const originals = dartRoundTrip(goldenFixtures);
    const canonicalFixtures: GoldenFixture[] = goldenFixtures.map((fixture) => {
      const value = canonical(fixture);
      assert.ok(
        value !== null && typeof value === 'object' && !Array.isArray(value),
      );
      return { ...fixture, value };
    });
    const fromTs = dartRoundTrip(canonicalFixtures);
    const fromDart: GoldenFixture[] = [];
    for (let index = 0; index < goldenFixtures.length; index++) {
      const fixture = goldenFixtures[index];
      const original = originals[index];
      const ts = fromTs[index];
      assert.ok(fixture && original && ts, 'Crosswire fixture was lost');
      const schema = schemas[fixture.type];
      const decoded = toJson(schema, fromJsonString(schema, original));
      assert.deepEqual(
        decoded,
        canonical(fixture),
        `Dart → TS: ${fixture.name}`,
      );
      assert.deepEqual(
        toJson(schema, fromJsonString(schema, ts)),
        decoded,
        `TS → Dart → TS: ${fixture.name}`,
      );
      assert.ok(
        decoded !== null &&
          typeof decoded === 'object' &&
          !Array.isArray(decoded),
      );
      fromDart.push({ ...fixture, value: decoded });
    }
    const again = dartRoundTrip(fromDart);
    for (let index = 0; index < goldenFixtures.length; index++) {
      const fixture = goldenFixtures[index];
      const encoded = again[index];
      assert.ok(fixture && encoded);
      assert.deepEqual(
        toJson(
          schemas[fixture.type],
          fromJsonString(schemas[fixture.type], encoded),
        ),
        canonical(fixture),
        `Dart → TS → Dart: ${fixture.name}`,
      );
    }
  },
);

test('opaque memo numeric lexemes and optional scalar presence are exact', () => {
  const decodedManga = fromJson(MangaSchema, manga);
  const decodedChapter = fromJson(ChapterSchema, chapter);
  assert.equal(decodedManga.memoJson, memoJson);
  assert.equal(decodedChapter.memoJson, memoJson);
  assert.equal(decodedChapter.dateUpload, '-9223372036854775808');
  assert.equal(decodedChapter.chapterNumber, 0);
  assert.equal(decodedManga.author, '');
  assert.equal(
    fromJson(MangaSchema, { url: '/a', title: '' }).author,
    undefined,
  );
  assert.equal(
    fromJson(MangaSchema, { url: '/a', title: '', author: null }).author,
    undefined,
  );
  assert.equal(fromJson(ChapterSchema, { url: '/a' }).chapterNumber, undefined);
  assert.equal(
    fromJson(ChapterSchema, { url: '/a', chapterNumber: null }).chapterNumber,
    undefined,
  );
  assert.equal(
    fromJson(SourceInfoSchema, { id: '9223372036854775807' }).id,
    '9223372036854775807',
  );
  assert.equal(
    fromJson(SourceInfoSchema, { supportsLatest: false }).supportsLatest,
    false,
  );
  assert.equal(fromJson(SourceInfoSchema, {}).supportsLatest, undefined);
});

const invalidFixtures: GoldenFixture[] = [
  {
    name: 'business-revision-overflow',
    type: 'StateMutation',
    value: { expectedRevision: 4294967296 },
  },
  {
    name: 'business-revision-fraction',
    type: 'StateMutation',
    value: { expectedRevision: 1.5 },
  },
  {
    name: 'business-identity-is-transport-only',
    type: 'StateMutation',
    value: { subject: 'body-subject' },
  },
  {
    name: 'business-two-operations',
    type: 'StateMutation',
    value: { resetProgress: {}, saveProgress: {} },
  },
  {
    name: 'source-resource-has-no-image-metadata',
    type: 'ImageResource',
    value: {
      resourceId: 'opaque',
      generation,
      byteLength: 1,
      url: 'blob:opaque',
      mimeType: 'image/png',
    },
  },
  {
    name: 'image-meta-is-empty',
    type: 'ImageFrameControl',
    value: { meta: { seq: 0 } },
  },
  {
    name: 'worker-has-no-encoded-selection',
    type: 'WorkerCommand',
    value: { acquireImage: { encodedOnly: true } },
  },
  {
    name: 'unknown-field',
    type: 'Manga',
    value: { url: '/a', unexpected: true },
  },
  {
    name: 'numeric-opaque-source-id',
    type: 'SourceInfo',
    value: { id: 9007199254740992 },
  },
  { name: 'numeric-opaque-date', type: 'Chapter', value: { dateUpload: 42 } },
  {
    name: 'memo-object-instead-of-string',
    type: 'Manga',
    value: { memoJson: { n: 1 } },
  },
  { name: 'int32-overflow', type: 'Manga', value: { status: 2147483648 } },
  {
    name: 'negative-unsigned-order',
    type: 'Chapter',
    value: { sourceOrder: -1 },
  },
  {
    name: 'unknown-error-name',
    type: 'ControlResponse',
    value: { error: { code: 'invented_error' } },
  },
  {
    name: 'two-control-commands',
    type: 'ControlRequest',
    value: { ready: {}, dispose: {} },
  },
  {
    name: 'two-source-operations',
    type: 'SourceCall',
    value: { popular: { page: 1 }, latest: { page: 1 } },
  },
  {
    name: 'two-source-payloads',
    type: 'SourceResult',
    value: { manga: {}, chapters: {} },
  },
  {
    name: 'two-response-arms',
    type: 'ControlResponse',
    value: { closed: { closed: true }, released: { released: true } },
  },
  {
    name: 'two-image-frames',
    type: 'ImageFrameControl',
    value: { data: { seq: 1, byteLength: 1 }, end: { seq: 2, totalBytes: 1 } },
  },
  {
    name: 'snake-and-camel-field-aliases',
    type: 'Chapter',
    value: { dateUpload: '1', date_upload: '2' },
  },
];

test(
  'generated codecs reject invalid field types, aliases and conflicting oneofs',
  { timeout: 120000 },
  () => {
    for (const fixture of invalidFixtures) {
      assert.throws(
        () => fromJson(schemas[fixture.type], fixture.value),
        fixture.name,
      );
      const result = dart([fixture]);
      if (result.failed && result.exitCode === undefined) throw result;
      assert.equal(
        result.exitCode,
        1,
        `Dart accepted ${fixture.name}: ${result.stdout}`,
      );
      assert.match(result.stderr, /Protocol fixture rejected:/, fixture.name);
    }
  },
);

test('generated JSON string decoder rejects duplicate raw keys before information is lost', () => {
  assert.throws(
    () => fromJsonString(MangaSchema, '{"url":"first","url":"second"}'),
    /duplicate/i,
  );
});

test('product semantic validators accept the generated golden matrix', () => {
  const parsers: Partial<Record<GoldenType, (input: unknown) => unknown>> = {
    ControlRequest: contract.parseControlRequest,
    ControlResponse: contract.parseControlResponse,
    SourceCall: contract.sourceCallSchema.parse,
    SourceResult: contract.sourceResultSchema.parse,
    SourceInfo: contract.sourceInfoSchema.parse,
    PageList: contract.pageListSchema.parse,
    ImageResource: contract.imageResourceSchema.parse,
    BuildManifest: contract.buildManifestSchema.parse,
    ExtensionIndex: contract.extensionIndexSchema.parse,
    Bootstrap: contract.bootstrapSchema.parse,
    WorkerCommand: contract.workerCommandSchema.parse,
    WorkerResponse: contract.workerResponseSchema.parse,
    StateMutation: contract.stateMutationSchema.parse,
    StateMutationResponse: contract.stateMutationResponseSchema.parse,
    MangaStateResponse: contract.mangaStateResponseSchema.parse,
    LibraryPageResponse: contract.libraryPageResponseSchema.parse,
    ChapterProgressPageResponse:
      contract.chapterProgressPageResponseSchema.parse,
    CategoryMutation: contract.categoryMutationSchema.parse,
    CategoryMutationResponse: contract.categoryMutationResponseSchema.parse,
    CategoryCatalogResponse: contract.categoryCatalogResponseSchema.parse,
  };
  for (const fixture of goldenFixtures) {
    const parse = parsers[fixture.type];
    if (parse) assert.doesNotThrow(() => parse(fixture.value), fixture.name);
  }
});

function sourceCall(request: JsonObject): JsonObject {
  return { requestId: 'request-golden', sourceId, generation, ...request };
}

test('business presence, error categories and ACK meaning fail closed', () => {
  assert.throws(() => contract.sourceCallSchema.parse(sourceCall({})));
  assert.throws(() =>
    contract.sourceResultSchema.parse({ requestId: 'r', generation, buildId }),
  );
  assert.throws(() => contract.parseControlRequest({ requestId: 'r' }));
  assert.throws(() => contract.parseControlResponse({ requestId: 'r' }));
  for (const code of [0, 999, -1])
    assert.throws(() =>
      contract.parseControlResponse({
        requestId: 'r',
        error: { code, message: 'Unknown error' },
      }),
    );
  for (const field of ['closed', 'released', 'completed'])
    assert.throws(() =>
      contract.parseControlResponse({
        requestId: 'r',
        [field]: { [field]: false },
      }),
    );
  assert.throws(() => contract.closedSchema.parse({ released: true }));
  assert.throws(() => contract.releasedSchema.parse({ closed: true }));
  for (const page of [0, 2147483648])
    assert.throws(() =>
      contract.sourceCallSchema.parse(sourceCall({ popular: { page } })),
    );
  assert.throws(() =>
    contract.sourceCallSchema.parse(sourceCall({ details: {} })),
  );
  assert.throws(() =>
    contract.sourceCallSchema.parse(sourceCall({ pages: {} })),
  );
  for (const dateUpload of [
    '9223372036854775808',
    '-9223372036854775809',
    '1.5',
  ])
    assert.throws(() =>
      contract.sourceCallSchema.parse(
        sourceCall({ pages: { chapter: { ...chapter, dateUpload } } }),
      ),
    );
  for (const chapterNumber of [-1, 'NaN', 'Infinity'])
    assert.throws(() =>
      contract.sourceCallSchema.parse(
        sourceCall({ pages: { chapter: { ...chapter, chapterNumber } } }),
      ),
    );

  const call = contract.sourceCallSchema.parse(
    sourceCall({ details: { manga } }),
  );
  assert.throws(() =>
    contract.sourceResultFor(call, buildId, {
      case: 'chapters',
      value: create(ChapterListSchema),
    }),
  );
  const invocation = contract.javaSourceInvocation(call);
  assert.equal(invocation.operation, 'details');
  assert.equal(
    fromJsonString(MangaSchema, JSON.stringify(manga)).memoJson,
    memoJson,
  );
  assert.ok(invocation.argsJson.includes('9007199254740993'));
});

test('UTF-8 request/memo, page-window and image transfer budgets are bounded', () => {
  const boundaryMemo = '{"v":"' + 'é'.repeat(32764) + '"}';
  assert.equal(Buffer.byteLength(boundaryMemo), contract.SOURCE_MEMO_LIMIT);
  assert.doesNotThrow(() =>
    contract.sourceCallSchema.parse(
      sourceCall({ details: { manga: { ...manga, memoJson: boundaryMemo } } }),
    ),
  );
  for (const invalid of [
    boundaryMemo.replace('"}', 'a"}'),
    '[]',
    'null',
    '1',
    '{',
  ])
    assert.throws(() =>
      contract.sourceCallSchema.parse(
        sourceCall({ details: { manga: { ...manga, memoJson: invalid } } }),
      ),
    );
  const request = {
    requestId: 'r',
    invoke: sourceCall({ search: { page: 1, query: '' } }),
  };
  const remaining =
    contract.SOURCE_ARGUMENT_LIMIT - Buffer.byteLength(JSON.stringify(request));
  request.invoke.search = {
    page: 1,
    query: 'é'.repeat(Math.floor(remaining / 2)) + 'a'.repeat(remaining % 2),
  };
  assert.equal(
    Buffer.byteLength(JSON.stringify(request)),
    contract.SOURCE_ARGUMENT_LIMIT,
  );
  assert.doesNotThrow(() => contract.parseControlRequest(request));
  assert.throws(() =>
    contract.parseControlRequest({
      ...request,
      invoke: {
        ...request.invoke,
        search: {
          page: 1,
          query:
            'é'.repeat(Math.floor(remaining / 2)) +
            'a'.repeat(remaining % 2) +
            'a',
        },
      },
    }),
  );

  const pages = Array.from({ length: 2048 }, (_, index) => ({
    pageKey: `p-${index}`,
    index,
    sourceIndex: -1,
    url: '',
  }));
  assert.doesNotThrow(() =>
    contract.pageListSchema.parse({ pageSessionId: 's', pages }),
  );
  assert.throws(() =>
    contract.pageListSchema.parse({
      pageSessionId: 's',
      pages: [...pages, { pageKey: 'overflow', index: 2048 }],
    }),
  );
  assert.throws(() =>
    contract.pageListSchema.parse({
      ...pageList,
      pages: [
        { pageKey: 'p', index: 0 },
        { pageKey: 'p', index: 1 },
      ],
    }),
  );
  assert.throws(() =>
    contract.pageListSchema.parse({
      pageSessionId: 's',
      pages: [{ pageKey: 'p', index: 1 }],
    }),
  );
  assert.throws(() =>
    contract.pageListSchema.parse({
      pageSessionId: 's',
      pages: [
        {
          pageKey: 'p',
          index: 0,
          url: 'é'.repeat(contract.PAGE_LIST_JSON_LIMIT / 2),
        },
      ],
    }),
  );

  const resource = {
    resourceId: 'resource',
    generation,
    byteLength: contract.IMAGE_BODY_LIMIT,
  };
  assert.doesNotThrow(() => contract.processedImageSchema.parse(resource));
  assert.throws(() =>
    contract.processedImageSchema.parse({
      ...resource,
      byteLength: resource.byteLength + 1,
    }),
  );
  assert.throws(() =>
    contract.processedImageSchema.parse({ ...resource, byteLength: 0 }),
  );
  assert.throws(() =>
    contract.processedImageSchema.parse({ ...resource, mimeType: 'text/html' }),
  );
  const data = new ArrayBuffer(contract.IMAGE_CHUNK_LIMIT);
  assert.doesNotThrow(() =>
    contract.imageFrameSchema.parse({
      control: { data: { seq: 1, byteLength: data.byteLength } },
      buffer: data,
    }),
  );
  assert.throws(() =>
    contract.imageFrameSchema.parse({
      control: { data: { seq: 1, byteLength: 1 } },
      buffer: data,
    }),
  );
  assert.throws(() =>
    contract.imageFrameSchema.parse({
      control: { data: { seq: 1, byteLength: data.byteLength + 1 } },
      buffer: new ArrayBuffer(data.byteLength + 1),
    }),
  );
  assert.throws(() =>
    contract.imageFrameSchema.parse({
      control: { end: { seq: 1, totalBytes: 1 } },
      buffer: new ArrayBuffer(1),
    }),
  );
});

test('Worker envelopes bind Source and image request/generation/build identities', () => {
  const envelope = {
    protocolVersion: contract.protocolVersion,
    workerInstanceId: 'worker',
    generation,
    buildId,
    requestId: 'request-golden',
  };
  const invoke = sourceCall({ popular: { page: 1 } });
  for (const mismatch of [{ requestId: 'other' }, { generation: 'other' }])
    assert.throws(() =>
      contract.workerCommandSchema.parse({
        envelope,
        invoke: { ...invoke, ...mismatch },
      }),
    );
  const source = {
    requestId: 'request-golden',
    generation,
    buildId,
    mangaPage: { mangas: [], hasNextPage: false },
  };
  for (const mismatch of [
    { requestId: 'other' },
    { generation: 'other' },
    { buildId: 'other' },
  ])
    assert.throws(() =>
      contract.workerResponseSchema.parse({
        envelope,
        source: { ...source, ...mismatch },
      }),
    );
  const image = {
    resourceId: 'resource',
    generation: 'other',
    byteLength: 1,
  };
  assert.throws(() => contract.workerResponseSchema.parse({ envelope, image }));
  assert.throws(() =>
    contract.workerCommandSchema.parse({
      envelope: { ...envelope, protocolVersion: contract.protocolVersion + 1 },
      shutdown: {},
    }),
  );
});

test('business state controls enforce identities, uint32, snapshots and transport budgets', () => {
  const mutation = {
    schemaVersion: 1,
    mutationId: businessMutationId,
    mangaKey: businessMangaKey,
    expectedRevision: 0,
    saveProgress: { snapshot: businessSnapshot, progress: businessProgress },
  };
  assert.doesNotThrow(() => contract.stateMutationSchema.parse(mutation));
  for (const change of [
    { schemaVersion: 0 },
    { mutationId: 'not-a-uuid' },
    { mangaKey: 'not-a-canonical-key' },
    { expectedRevision: -1 },
    { expectedRevision: 4294967296 },
    { expectedRevision: 1.5 },
    { subject: 'untrusted-identity' },
    { resetProgress: { snapshot: businessSnapshot } },
  ])
    assert.throws(() =>
      contract.stateMutationSchema.parse({ ...mutation, ...change }),
    );
  for (const current of [
    { ...businessAnchor, normalizedOffset: 1.01 },
    { ...businessAnchor, normalizedOffset: 'NaN' },
    { ...businessAnchor, pageIndexHint: 0 },
    {
      ...businessAnchor,
      chapterKey: 'wrong-chapter',
    },
    {
      ...businessAnchor,
      manifestVersion: 'old-manifest',
    },
  ])
    assert.throws(() =>
      contract.stateMutationSchema.parse({
        ...mutation,
        saveProgress: {
          snapshot: businessSnapshot,
          progress: { ...businessProgress, current },
        },
      }),
    );
  assert.throws(() =>
    contract.stateMutationSchema.parse({
      ...mutation,
      saveProgress: {
        snapshot: { ...businessSnapshot, pageKeys: ['p-1', 'p-1'] },
        progress: businessProgress,
      },
    }),
  );
  assert.throws(() =>
    contract.stateMutationSchema.parse({
      ...mutation,
      saveProgress: {
        snapshot: {
          ...businessSnapshot,
          pageKeys: Array.from({ length: 2049 }, (_, index) => `p-${index}`),
        },
        progress: businessProgress,
      },
    }),
  );
  assert.throws(() =>
    contract.stateMutationSchema.parse({
      ...mutation,
      saveProgress: {
        snapshot: businessSnapshot,
        progress: { ...businessProgress, epoch: 4294967296 },
      },
    }),
  );
  const memo = JSON.stringify({
    payload: 'x'.repeat(contract.SOURCE_MEMO_LIMIT - 14),
  });
  assert.equal(
    new TextEncoder().encode(memo).byteLength,
    contract.SOURCE_MEMO_LIMIT,
  );
  const setFavorite = {
    metadata: { ...libraryMetadata, manga: { ...manga, memoJson: memo } },
    favorite: true,
  };
  assert.throws(() =>
    contract.stateMutationSchema.parse({
      schemaVersion: 1,
      mutationId: businessMutationId,
      mangaKey: businessMangaKey,
      setFavorite: {
        metadata: { ...libraryMetadata, manga: { ...manga, title: '' } },
        favorite: true,
      },
    }),
  );
  assert.doesNotThrow(() =>
    contract.stateMutationSchema.parse({
      schemaVersion: 1,
      mutationId: businessMutationId,
      mangaKey: businessMangaKey,
      setFavorite,
    }),
  );
  assert.throws(() =>
    contract.stateMutationSchema.parse({
      schemaVersion: 1,
      mutationId: businessMutationId,
      mangaKey: businessMangaKey,
      setFavorite: {
        ...setFavorite,
        metadata: {
          ...libraryMetadata,
          manga: {
            ...manga,
            memoJson: JSON.stringify({
              payload: 'x'.repeat(contract.SOURCE_MEMO_LIMIT),
            }),
          },
        },
      },
    }),
  );
  assert.throws(() =>
    contract.stateMutationSchema.parse({
      schemaVersion: 1,
      mutationId: businessMutationId,
      mangaKey: businessMangaKey,
      setFavorite: {
        metadata: {
          ...libraryMetadata,
          sourceName: 'é'.repeat(contract.BUSINESS_REQUEST_LIMIT),
        },
        favorite: true,
      },
    }),
  );
  assert.doesNotThrow(() =>
    contract.stateMutationResponseSchema.parse({
      schemaVersion: 1,
      error: {
        code: 'BUSINESS_STATE_ERROR_CODE_INVALID_INPUT',
        message: 'Could not parse mutation',
      },
    }),
  );
  assert.throws(() =>
    contract.mangaStateResponseSchema.parse({ schemaVersion: 1 }),
  );
  assert.throws(() =>
    contract.mangaStateResponseSchema.parse({
      schemaVersion: 1,
      error: { code: 999, message: 'Unknown error' },
    }),
  );
});
