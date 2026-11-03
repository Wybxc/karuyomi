import type { JsonObject } from '@bufbuild/protobuf';
import {
  hostAbi,
  protocolVersion,
  runtimeBaseline,
} from '../../packages/contracts/src/generated.ts';

export type GoldenType =
  | 'ControlRequest'
  | 'ControlResponse'
  | 'SourceCall'
  | 'SourceResult'
  | 'SourceInfo'
  | 'Manga'
  | 'Chapter'
  | 'PageList'
  | 'ImageResource'
  | 'BuildManifest'
  | 'ExtensionIndex'
  | 'Bootstrap'
  | 'ImageFrameControl'
  | 'WorkerCommand'
  | 'WorkerResponse';

export interface GoldenFixture {
  name: string;
  type: GoldenType;
  value: JsonObject;
}

export const memoJson =
  '{"large":9007199254740993,"max":9223372036854775807,"min":-9223372036854775808,' +
  '"decimal":123.4500,"exponent":1e+1000,"nested":{"items":[null,true,"漫画😀"]}}';
export const sourceId = '9007199254740993';
export const generation = 'generation-golden';
export const buildId = 'ext-golden-0123456789abcdef';
const requestId = 'request-golden';
const packageName = 'eu.kanade.tachiyomi.extension.en.golden';
const sha256 = 'a'.repeat(64);
const encodedSha256 = 'b'.repeat(64);
const materialSha256 = 'c'.repeat(64);

export const manga: JsonObject = {
  url: '/manga/漫画?a=1&b=2',
  title: 'Title 😀',
  author: '',
  artist: 'Artist',
  description: 'Line one\nLine two',
  genre: 'Fantasy, Drama',
  genres: ['Fantasy', 'Drama'],
  status: -7,
  thumbnailUrl: '',
  initialized: false,
  updateStrategy: 'ONLY_FETCH_ONCE',
  memoJson,
};

export const chapter: JsonObject = {
  url: '/chapter/zero',
  name: 'Chapter 0',
  chapterNumber: 0,
  scanlator: '',
  dateUpload: '-9223372036854775808',
  sourceOrder: 0,
  memoJson,
};

export const pageList: JsonObject = {
  pageSessionId: 'session-golden',
  pages: [
    { pageKey: 'p-0', index: 0, sourceIndex: -7, url: '' },
    { pageKey: 'p-1', index: 1, sourceIndex: -7, url: '/page/1', imageUrl: '' },
    {
      pageKey: 'p-2',
      index: 2,
      sourceIndex: 2147483647,
      url: '/page/2',
      imageUrl: 'https://example.invalid/processed-input',
    },
  ],
};

export const imageResource: JsonObject = {
  resourceId: 'resource-golden',
  generation,
  mimeType: 'image/png',
  byteLength: 65536,
  width: 1024,
  height: 2048,
  url: 'blob:https://reader.invalid/golden',
};

const descriptor: JsonObject = {
  buildId,
  packageName,
  repoId: 'keiyoushi/extensions-source',
  version: '1.6.1',
  sourceIds: [sourceId, '-9223372036854775808', '9223372036854775807'],
  manifestPath: `/extensions/builds/${buildId}/manifest.json`,
};

export const buildManifest: JsonObject = {
  protocolVersion,
  hostAbi,
  runtimeBaseline,
  bridgeVersion: 2,
  buildId,
  packageName,
  repoId: 'keiyoushi/extensions-source',
  version: '1.6.1',
  storageSchema: '1',
  sourceIds: [sourceId],
  bundle: {
    path: `/extensions/artifacts/${sha256}.gz`,
    sha256,
    size: 4096,
    contentType: 'text/javascript',
    encoding: 'gzip',
    encodedSha256,
    encodedSize: 1024,
  },
  hostScripts: [
    {
      path: `/runtime/materials/${materialSha256}`,
      sha256: materialSha256,
      size: 128,
      contentType: 'text/javascript',
      logicalName: 'crypto-bridge.js',
    },
  ],
  resources: [],
};

const error: JsonObject = {
  code: 'RUNTIME_ERROR_CODE_SOURCE_ERROR',
  message: 'Source rejected the request 漫画',
  retryable: false,
  javaClass: 'java.io.IOException',
};

const calls: ReadonlyArray<readonly [string, JsonObject]> = [
  ['popular', { page: 1 }],
  ['latest', { page: 2147483647 }],
  ['search', { page: 2, query: '漫画 😀' }],
  ['details', { manga }],
  ['chapters', { manga }],
  ['pages', { chapter }],
];

const sources: JsonObject[] = [
  {
    id: sourceId,
    name: 'Golden',
    lang: 'en',
    supportsLatest: false,
    baseUrl: '',
  },
  { id: '-9223372036854775808', name: 'Minimum', lang: 'all' },
  {
    id: '9223372036854775807',
    name: 'Maximum',
    lang: 'ja',
    supportsLatest: true,
  },
];

const session: JsonObject = {
  protocolVersion,
  workerInstanceId: 'worker-golden',
  generation,
  buildId,
  sources,
  capabilities: ['source.invoke', 'image.acquire'],
};

const imageRequest: JsonObject = {
  requestId,
  sourceId,
  pageSessionId: 'session-golden',
  pageKey: 'p-0',
  generation,
  timeoutMs: 30000,
};
const envelope: JsonObject = {
  protocolVersion,
  workerInstanceId: 'worker-golden',
  generation,
  buildId,
  requestId,
};

export const goldenFixtures: GoldenFixture[] = [
  { name: 'manga-full-opaque-memo', type: 'Manga', value: manga },
  {
    name: 'manga-absent-optionals',
    type: 'Manga',
    value: { url: '/minimal', title: '', updateStrategy: 'ALWAYS_UPDATE' },
  },
  { name: 'chapter-zero-and-minimum-long', type: 'Chapter', value: chapter },
  {
    name: 'chapter-absent-number-and-maximum-long',
    type: 'Chapter',
    value: { url: '/chapter/max', name: '', dateUpload: '9223372036854775807' },
  },
  {
    name: 'page-original-index-and-presence',
    type: 'PageList',
    value: pageList,
  },
  { name: 'image-resource', type: 'ImageResource', value: imageResource },
  {
    name: 'static-build-manifest',
    type: 'BuildManifest',
    value: buildManifest,
  },
  {
    name: 'static-current-index',
    type: 'ExtensionIndex',
    value: { schemaVersion: 1, builds: [descriptor] },
  },
  {
    name: 'bootstrap',
    type: 'Bootstrap',
    value: {
      protocolVersion,
      identity: { subject: 'subject-golden', email: 'owner@example.invalid' },
      expiresAt: 1800000000000,
      stage: 'BOOTSTRAP_STAGE_P0',
    },
  },
  ...sources.map((value, index): GoldenFixture => ({
    name: `source-id-${index}`,
    type: 'SourceInfo',
    value,
  })),
  ...calls.flatMap(([operation, args]): GoldenFixture[] => {
    const call: JsonObject = {
      requestId,
      sourceId,
      timeoutMs: 30000,
      generation,
      [operation]: args,
    };
    return [
      { name: `source-call-${operation}`, type: 'SourceCall', value: call },
      {
        name: `control-invoke-${operation}`,
        type: 'ControlRequest',
        value: { requestId, invoke: call },
      },
      {
        name: `worker-invoke-${operation}`,
        type: 'WorkerCommand',
        value: { envelope, invoke: call },
      },
    ];
  }),
  ...(
    [
      ['mangaPage', { mangas: [manga], hasNextPage: true }],
      ['manga', manga],
      ['chapters', { chapters: [chapter] }],
      ['pageList', pageList],
    ] satisfies Array<[string, JsonObject]>
  ).flatMap(([payload, value]): GoldenFixture[] => {
    const result: JsonObject = {
      requestId,
      generation,
      buildId,
      [payload]: value,
    };
    return [
      { name: `source-result-${payload}`, type: 'SourceResult', value: result },
      {
        name: `control-source-${payload}`,
        type: 'ControlResponse',
        value: { requestId, source: result },
      },
    ];
  }),
  ...(
    [
      ['ready', {}],
      [
        'open',
        {
          manifestPath: descriptor.manifestPath ?? '',
          identity: 'owner',
          userAgent: '',
        },
      ],
      ['cancel', { requestId, generation }],
      ['acquireImage', imageRequest],
      ['cancelImage', { requestId, generation }],
      ['releaseImage', { resourceId: 'resource-golden', generation }],
      ['closePageSession', { pageSessionId: 'session-golden', generation }],
      ['rebuild', {}],
      [
        'fetchApi',
        {
          path: '/api/bootstrap',
          method: 'GET',
          headers: { 'X-App-Request': '1' },
        },
      ],
      ['dispose', {}],
    ] satisfies Array<[string, JsonObject]>
  ).map(([command, value]): GoldenFixture => ({
    name: `control-request-${command}`,
    type: 'ControlRequest',
    value: { requestId, [command]: value },
  })),
  ...(
    [
      [
        'hello',
        {
          protocolVersion,
          hostAbi,
          runtimeBaseline,
          generation,
          sourceReady: false,
        },
      ],
      ['session', session],
      ['image', imageResource],
      ['released', { released: true }],
      ['closed', { closed: true }],
      ['completed', { completed: true }],
      [
        'api',
        {
          status: 200,
          headers: { 'content-type': 'application/json' },
          body: '{}',
          redirected: false,
        },
      ],
      ['error', error],
    ] satisfies Array<[string, JsonObject]>
  ).map(([result, value]): GoldenFixture => ({
    name: `control-response-${result}`,
    type: 'ControlResponse',
    value: { requestId, [result]: value },
  })),
  ...(
    [
      ['meta', { seq: 0, mimeType: 'image/png' }],
      ['data', { seq: 1, byteLength: 65536 }],
      ['end', { seq: 2, totalBytes: 65536 }],
      [
        'ack',
        {
          seq: 2,
          resource: {
            resourceId: 'resource-golden',
            generation,
            mimeType: 'image/png',
            byteLength: 65536,
            width: 1024,
            height: 2048,
          },
        },
      ],
      ['abort', error],
    ] satisfies Array<[string, JsonObject]>
  ).map(([frame, value]): GoldenFixture => ({
    name: `image-frame-${frame}`,
    type: 'ImageFrameControl',
    value: { [frame]: value },
  })),
  ...(
    [
      ['open', { manifest: buildManifest, userAgent: 'Golden/1.0' }],
      [
        'acquireImage',
        { request: imageRequest, resourceId: 'resource-golden' },
      ],
      ['closePageSession', { pageSessionId: 'session-golden', generation }],
      ['shutdown', {}],
    ] satisfies Array<[string, JsonObject]>
  ).map(([command, value]): GoldenFixture => ({
    name: `worker-command-${command}`,
    type: 'WorkerCommand',
    value: { envelope, [command]: value },
  })),
  ...(
    [
      ['session', session],
      [
        'image',
        {
          resourceId: 'resource-golden',
          generation,
          mimeType: 'image/png',
          byteLength: 65536,
          width: 1024,
          height: 2048,
        },
      ],
      ['closed', { closed: true }],
      ['error', error],
    ] satisfies Array<[string, JsonObject]>
  ).map(([result, value]): GoldenFixture => ({
    name: `worker-response-${result}`,
    type: 'WorkerResponse',
    value: { envelope, [result]: value },
  })),
];
