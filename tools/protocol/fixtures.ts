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
  | 'WorkerResponse'
  | 'StateMutation'
  | 'StateMutationResponse'
  | 'MangaStateResponse'
  | 'LibraryPageResponse'
  | 'ChapterProgressPageResponse'
  | 'CategoryMutation'
  | 'CategoryMutationResponse'
  | 'CategoryCatalogResponse'
  | 'SettingsMutation'
  | 'SettingsResponse'
  | 'SettingsMutationResponse'
  | 'SourcePreferencesMutation'
  | 'SourcePreferencesResponse'
  | 'SourcePreferencesMutationResponse'
  | 'ExtensionNetworkPoliciesResponse';

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
export const catalog: JsonObject = {
  catalogUrl: 'https://read.example.com/extensions/index.json',
  repoId: 'keiyoushi',
};

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
  byteLength: 65536,
  url: 'blob:https://reader.invalid/golden',
};

const descriptor: JsonObject = {
  buildId,
  packageName,
  repoId: 'keiyoushi',
  version: '1.6.1',
  sourceIds: [sourceId, '-9223372036854775808', '9223372036854775807'],
  sources: [
    { id: sourceId, name: 'Golden 源', lang: 'zh' },
    { id: '-9223372036854775808', name: 'Minimum', lang: 'en' },
    { id: '9223372036854775807', name: 'Maximum', lang: 'all' },
  ],
  manifestPath: `/extensions/builds/${buildId}/manifest.json`,
};

export const buildManifest: JsonObject = {
  protocolVersion,
  hostAbi,
  runtimeBaseline,
  bridgeVersion: 2,
  buildId,
  packageName,
  repoId: 'keiyoushi',
  version: '1.6.1',
  storageSchema: '1',
  sourceIds: [sourceId],
  sources: [{ id: sourceId, name: 'Golden 源', lang: 'zh' }],
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

export const filterSnapshot: JsonObject = {
  snapshotId: 'filter-snapshot-golden',
  nodes: [
    { name: '标题', header: {} },
    { name: '', separator: {} },
    { name: '文字', text: { state: '' } },
    { name: '勾选', checkBox: { state: false } },
    { name: '三态', triState: { state: 0 } },
    { name: '单选', select: { options: ['全部', '选项😀'], state: 0 } },
    { name: '排序', sort: { options: ['更新', '名称'], state: {} } },
    {
      name: '分组',
      group: {
        nodes: [
          { name: '标签', checkBox: { state: true } },
          {
            name: '显式首项',
            sort: {
              options: ['最新'],
              state: { selection: { index: 0, ascending: false } },
            },
          },
        ],
      },
    },
  ],
};
export const filterSelection: JsonObject = {
  snapshotId: 'filter-snapshot-golden',
  updates: [
    { path: [2], text: '' },
    { path: [3], checkBox: false },
    { path: [4], triState: 0 },
    { path: [5], select: 0 },
    { path: [6], sort: {} },
    { path: [7, 0], checkBox: true },
    { path: [7, 1], sort: { selection: { index: 0, ascending: false } } },
  ],
};

const calls: ReadonlyArray<readonly [string, JsonObject]> = [
  ['popular', { page: 1 }],
  ['latest', { page: 2147483647 }],
  ['search', { page: 2, query: '漫画 😀', filters: filterSelection }],
  ['getFilters', { retainedSnapshotId: 'filter-snapshot-golden' }],
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
  catalog,
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

export const libraryMetadata: JsonObject = {
  packageName,
  sourceId,
  sourceName: 'Golden',
  sourceLang: 'en',
  manga,
};
export const businessMangaKey = 'd'.repeat(64);
export const businessMutationId = 'f6c8c7ed-7db8-41d2-9e44-494281e61fd9';
export const businessAnchor: JsonObject = {
  chapterKey: 'chapter-golden',
  pageKey: 'p-1',
  manifestVersion: 'manifest-golden',
  pageIndexHint: 1,
  normalizedOffset: 0.75,
  normalizedX: 0.6,
  viewportX: 0.25,
  viewportY: 0.2,
};
export const businessProgress: JsonObject = {
  chapterKey: 'chapter-golden',
  current: businessAnchor,
  furthest: { ...businessAnchor, normalizedOffset: 1 },
  epoch: 4294967295,
  completed: true,
};
export const businessSnapshot: JsonObject = {
  chapterKey: 'chapter-golden',
  manifestVersion: 'manifest-golden',
  pageKeys: ['p-0', 'p-1'],
};
export const businessCover: JsonObject = {
  assetId: '35b6103d-08f4-4604-b958-42fe15c50377',
  contentType: 'image/png',
  byteLength: 1048576,
  sha256: 'a'.repeat(64),
};
export const businessManga: JsonObject = {
  mangaKey: businessMangaKey,
  revision: 4294967295,
  metadata: libraryMetadata,
  favorite: true,
  addedAtSeconds: 4294967295,
  resume: { chapterKey: 'chapter-golden', reversedOrder: true },
  categoryIds: ['f99489f0-3f30-4d7c-8cb1-0f456c40319d'],
  customCover: businessCover,
};
const categoryCatalog: JsonObject = {
  revision: 3,
  categories: [
    { id: 'f99489f0-3f30-4d7c-8cb1-0f456c40319d', name: '漫画😀' },
    { id: '5c70b182-c978-4650-b1d0-6c87c33c1048', name: '漫画😀' },
  ],
};
const businessMutation: JsonObject = {
  schemaVersion: 1,
  mutationId: businessMutationId,
  mangaKey: businessMangaKey,
  expectedRevision: 0,
};

const globalReader: JsonObject = {
  mode: 'READER_MODE_RIGHT_TO_LEFT',
  pageLayout: 'READER_PAGE_LAYOUT_AUTO',
  background: 'READER_BACKGROUND_WHITE',
  dimPercent: 60,
  tapZones: 'READER_INPUT_PRESET_REVERSED',
  keyboard: 'READER_INPUT_PRESET_STANDARD',
  fit: 'READER_FIT_WIDTH',
  cropBorders: true,
};
const globalSettingsValues: JsonObject = {
  repositories: [
    {
      catalogUrl: 'http://[::1]:8787/extensions/index.json',
      repoId: 'other',
      name: 'Other 仓库',
    },
  ],
  theme: 'APP_THEME_SYSTEM',
  reader: globalReader,
  installedExtensions: [
    {
      catalogUrl: 'https://read.example.com/extensions/index.json',
      repoId: 'keiyoushi',
      packageName,
      buildId,
      bundleSha256: sha256,
      enabled: true,
    },
    {
      catalogUrl: 'http://[::1]:8787/extensions/index.json',
      repoId: 'other',
      packageName: `${packageName}.other`,
      buildId: 'ext-other-selected',
      bundleSha256: encodedSha256,
      enabled: false,
    },
  ],
  favoriteSources: [
    { packageName, sourceId, sourceName: 'Source 漫画', sourceLang: 'zh-Hant' },
    {
      packageName: `${packageName}.other`,
      sourceId: '-9223372036854775808',
      sourceName: 'Other',
      sourceLang: 'all',
    },
  ],
};
const readerOverrides: JsonObject = {
  background: 'READER_BACKGROUND_THEME',
  dimPercent: 0,
  keyboard: 'READER_INPUT_PRESET_DISABLED',
  fit: 'READER_FIT_CONTAIN',
  cropBorders: false,
};
const settingsSnapshot: JsonObject = {
  schemaVersion: 1,
  accountRevision: 8,
  global: { revision: 3, values: globalSettingsValues },
  manga: {
    mangaKey: businessMangaKey,
    revision: 2,
    overrides: readerOverrides,
  },
  effectiveReader: { ...globalReader, ...readerOverrides },
};

const preferenceEntries: JsonObject[] = [
  { key: 'off', value: { boolean: false } },
  { key: 'empty', value: { text: '' } },
  { key: 'int', value: { integer: -2147483648 } },
  { key: 'long', value: { longInteger: '9223372036854775807' } },
  { key: 'float', value: { decimal: 1.5 } },
  { key: 'set', value: { strings: { values: [] } } },
];
const preferenceBootstrap: JsonObject = {
  packageName,
  sources: [{ sourceId, entries: preferenceEntries }],
};
const preferenceSnapshot: JsonObject = {
  snapshotId: 'preferences-golden',
  nodes: [
    {
      key: 'off',
      title: '开关',
      enabled: true,
      visible: true,
      syncScope: 'PREFERENCE_SYNC_SCOPE_ACCOUNT',
      defaultValue: { boolean: false },
      toggle: { value: false },
    },
    {
      key: 'empty',
      title: '凭证',
      enabled: true,
      visible: true,
      syncScope: 'PREFERENCE_SYNC_SCOPE_CLIENT_SESSION',
      text: { value: '', secret: true, inputType: 129 },
    },
    {
      key: 'choice',
      syncScope: 'PREFERENCE_SYNC_SCOPE_CLIENT_SESSION',
      choice: {
        options: [{ label: '镜像', value: '1' }],
        value: 'unavailable',
      },
    },
    {
      syncScope: 'PREFERENCE_SYNC_SCOPE_CLIENT_SESSION',
      group: {
        nodes: [
          {
            key: 'multi',
            syncScope: 'PREFERENCE_SYNC_SCOPE_CLIENT_SESSION',
            multiChoice: { options: [], values: [] },
          },
        ],
      },
    },
    { syncScope: 'PREFERENCE_SYNC_SCOPE_CLIENT_SESSION', action: {} },
    {
      syncScope: 'PREFERENCE_SYNC_SCOPE_CLIENT_SESSION',
      unsupported: { reason: 'Activity is unavailable' },
    },
  ],
  syncValues: [preferenceEntries[0]!],
  sessionValues: preferenceEntries.slice(1),
};
const preferenceBusinessPackage = 'eu.kanade.tachiyomi.extension.zh.komiic';
const preferenceBusinessEntries: JsonObject[] = [
  { key: 'preferred_mirror', value: { text: '' } },
  { key: 'CHAPTER_FILTER', value: { text: '0' } },
];
const sourcePreferences: JsonObject = {
  packageName: preferenceBusinessPackage,
  sourceId,
  revision: 1,
  entries: preferenceBusinessEntries,
};

export const goldenFixtures: GoldenFixture[] = [
  {
    name: 'search-slot-search',
    type: 'ControlRequest',
    value: {
      requestId,
      slotId: 'RUNTIME_SLOT_SEARCH',
      invoke: {
        requestId,
        generation,
        sourceId,
        search: { page: 1, query: '漫画' },
      },
    },
  },
  {
    name: 'search-slot-result',
    type: 'ControlResponse',
    value: {
      requestId,
      slotId: 'RUNTIME_SLOT_SEARCH',
      source: {
        requestId,
        generation,
        buildId,
        mangaPage: { mangas: [manga], hasNextPage: false },
      },
    },
  },
  {
    name: 'extension-network-policy-readiness',
    type: 'ExtensionNetworkPoliciesResponse',
    value: {
      schemaVersion: 1,
      catalog,
      builds: [{ buildId, packageName, bundleSha256: sha256 }],
    },
  },
  {
    name: 'preferences-open-bootstrap',
    type: 'ControlRequest',
    value: {
      slotId: 'RUNTIME_SLOT_FOREGROUND',
      requestId,
      open: {
        catalog,
        manifestPath: `/extensions/builds/${buildId}/manifest.json`,
        identity: 'golden-owner',
        expectedBuildId: buildId,
        expectedBundleSha256: sha256,
        preferenceBootstrap,
      },
    },
  },
  {
    name: 'preferences-worker-bootstrap',
    type: 'WorkerCommand',
    value: {
      envelope,
      open: {
        catalog,
        manifest: buildManifest,
        userAgent: 'Golden/1.0',
        preferenceBootstrap,
      },
    },
  },
  {
    name: 'preferences-read',
    type: 'SourceCall',
    value: { requestId, generation, sourceId, getPreferences: {} },
  },
  {
    name: 'preferences-change-empty',
    type: 'SourceCall',
    value: {
      requestId,
      generation,
      sourceId,
      editPreference: {
        snapshotId: 'preferences-golden',
        path: [3, 0],
        change: { strings: { values: [] } },
      },
    },
  },
  {
    name: 'preferences-click',
    type: 'SourceCall',
    value: {
      requestId,
      generation,
      sourceId,
      editPreference: {
        snapshotId: 'preferences-golden',
        path: [4],
        click: {},
      },
    },
  },
  {
    name: 'preferences-snapshot',
    type: 'SourceResult',
    value: { requestId, generation, buildId, preferences: preferenceSnapshot },
  },
  {
    name: 'preferences-veto-result',
    type: 'SourceResult',
    value: {
      requestId,
      generation,
      buildId,
      preferenceEdit: {
        accepted: false,
        clickHandled: false,
        snapshot: preferenceSnapshot,
      },
    },
  },
  {
    name: 'preferences-business-mutation',
    type: 'SourcePreferencesMutation',
    value: {
      schemaVersion: 1,
      mutationId: businessMutationId,
      catalog,
      packageName: preferenceBusinessPackage,
      sourceId,
      expectedRevision: 0,
      entries: preferenceBusinessEntries,
    },
  },
  {
    name: 'preferences-business-response',
    type: 'SourcePreferencesResponse',
    value: {
      schemaVersion: 1,
      catalog,
      packageName: preferenceBusinessPackage,
      accountRevision: 2,
      syncRules: [
        { key: 'preferred_mirror', kind: 'PREFERENCE_VALUE_KIND_TEXT' },
        { key: 'CHAPTER_FILTER', kind: 'PREFERENCE_VALUE_KIND_TEXT' },
      ],
      sources: [sourcePreferences],
    },
  },
  {
    name: 'preferences-business-ack',
    type: 'SourcePreferencesMutationResponse',
    value: {
      schemaVersion: 1,
      mutationId: businessMutationId,
      accountRevision: 2,
      catalog,
      syncRules: [
        { key: 'preferred_mirror', kind: 'PREFERENCE_VALUE_KIND_TEXT' },
        { key: 'CHAPTER_FILTER', kind: 'PREFERENCE_VALUE_KIND_TEXT' },
      ],
      preferences: sourcePreferences,
    },
  },

  {
    name: 'settings-global-all-preferences',
    type: 'SettingsMutation',
    value: {
      schemaVersion: 1,
      mutationId: businessMutationId,
      expectedRevision: 3,
      setGlobal: globalSettingsValues,
    },
  },
  ...[readerOverrides, {}].map((overrides, index): GoldenFixture => ({
    name:
      index === 0
        ? 'settings-override-explicit-zero'
        : 'settings-clear-inherit',
    type: 'SettingsMutation',
    value: {
      schemaVersion: 1,
      mutationId: businessMutationId,
      expectedRevision: 2,
      setManga: { mangaKey: businessMangaKey, overrides },
    },
  })),
  {
    name: 'settings-override-fit-height',
    type: 'SettingsMutation',
    value: {
      schemaVersion: 1,
      mutationId: businessMutationId,
      expectedRevision: 2,
      setManga: {
        mangaKey: businessMangaKey,
        overrides: { fit: 'READER_FIT_HEIGHT' },
      },
    },
  },
  {
    name: 'settings-default-zero-dimming',
    type: 'SettingsResponse',
    value: {
      schemaVersion: 1,
      global: {
        values: {
          theme: 'APP_THEME_SYSTEM',
          reader: {
            mode: 'READER_MODE_LEFT_TO_RIGHT',
            pageLayout: 'READER_PAGE_LAYOUT_AUTO',
            background: 'READER_BACKGROUND_BLACK',
            dimPercent: 0,
            tapZones: 'READER_INPUT_PRESET_STANDARD',
            keyboard: 'READER_INPUT_PRESET_STANDARD',
            fit: 'READER_FIT_CONTAIN',
          },
        },
      },
      effectiveReader: {
        mode: 'READER_MODE_LEFT_TO_RIGHT',
        pageLayout: 'READER_PAGE_LAYOUT_AUTO',
        background: 'READER_BACKGROUND_BLACK',
        dimPercent: 0,
        tapZones: 'READER_INPUT_PRESET_STANDARD',
        keyboard: 'READER_INPUT_PRESET_STANDARD',
        fit: 'READER_FIT_CONTAIN',
      },
    },
  },
  {
    name: 'settings-effective-field-inheritance',
    type: 'SettingsResponse',
    value: settingsSnapshot,
  },
  {
    name: 'settings-confirmed-explicit-zero',
    type: 'SettingsMutationResponse',
    value: { ...settingsSnapshot, mutationId: businessMutationId },
  },
  ...(
    [
      ['setFavorite', { metadata: libraryMetadata, favorite: false }],
      [
        'migrateFrom',
        {
          sourceMangaKey: 'b'.repeat(64),
          expectedSourceRevision: 0,
          expectedCatalogRevision: 3,
          targetMetadata: libraryMetadata,
          copyCategories: true,
          chapters: [
            {
              sourceChapterKey: 'source-read',
              targetChapterKey: 'target-read',
              copyRead: true,
              copyBookmark: false,
            },
            {
              sourceChapterKey: 'source-bookmark',
              targetChapterKey: 'target-bookmark',
              copyRead: false,
              copyBookmark: true,
            },
          ],
        },
      ],
      ['updateMetadata', libraryMetadata],
      [
        'saveProgress',
        {
          snapshot: businessSnapshot,
          progress: businessProgress,
          reversedOrder: true,
        },
      ],
      ['resetProgress', { snapshot: businessSnapshot, reversedOrder: false }],
      ['setChapterRead', { chapterKey: 'chapter-golden', read: true }],
      ['setCustomCover', { cover: businessCover }],
      [
        'setCategories',
        {
          categoryIds: ['f99489f0-3f30-4d7c-8cb1-0f456c40319d'],
          expectedCatalogRevision: 3,
        },
      ],
    ] satisfies Array<[string, JsonObject]>
  ).map(([operation, value]): GoldenFixture => ({
    name: `business-mutation-${operation}`,
    type: 'StateMutation',
    value: { ...businessMutation, [operation]: value },
  })),
  {
    name: 'business-migration-confirmed',
    type: 'StateMutationResponse',
    value: {
      schemaVersion: 1,
      mutationId: businessMutationId,
      accountRevision: 7,
      manga: businessManga,
      categoryCatalog,
      migration: { copiedReadChapters: 1, copiedBookmarks: 0 },
    },
  },
  {
    name: 'business-mutation-mark-unread-default-false',
    type: 'StateMutation',
    value: {
      ...businessMutation,
      setChapterRead: { chapterKey: 'chapter-golden', read: false },
    },
  },
  {
    name: 'business-mutation-clear-custom-cover',
    type: 'StateMutation',
    value: { ...businessMutation, setCustomCover: {} },
  },
  {
    name: 'business-mutation-remove-favorite-without-metadata',
    type: 'StateMutation',
    value: { ...businessMutation, setFavorite: { favorite: false } },
  },
  ...[false, true].map((completed): GoldenFixture => ({
    name: `business-mutation-unpositioned-${completed ? 'read' : 'unread'}`,
    type: 'StateMutationResponse',
    value: {
      schemaVersion: 1,
      mutationId: businessMutationId,
      accountRevision: 7,
      manga: businessManga,
      progress: { chapterKey: 'chapter-golden', epoch: 1, completed },
      categoryCatalog,
    },
  })),
  {
    name: 'business-chapter-progress-page-with-unpositioned-state',
    type: 'ChapterProgressPageResponse',
    value: {
      schemaVersion: 1,
      accountRevision: 7,
      mangaKey: businessMangaKey,
      entries: [
        { chapterKey: 'chapter-a', epoch: 1, completed: true },
        { chapterKey: 'chapter-b', epoch: 2, completed: false },
        businessProgress,
      ],
      nextKey: 'chapter-golden',
    },
  },
  {
    name: 'business-mutation-confirmed-uint32-maximum',
    type: 'StateMutationResponse',
    value: {
      schemaVersion: 1,
      mutationId: businessMutationId,
      accountRevision: 4294967295,
      manga: businessManga,
      progress: businessProgress,
      categoryCatalog,
    },
  },
  {
    name: 'business-state-empty-first-read',
    type: 'MangaStateResponse',
    value: {
      schemaVersion: 1,
      accountRevision: 0,
      manga: { mangaKey: businessMangaKey, revision: 0 },
      categoryCatalog: {},
    },
  },
  {
    name: 'business-library-page',
    type: 'LibraryPageResponse',
    value: {
      schemaVersion: 1,
      accountRevision: 7,
      entries: [businessManga],
      nextKey: businessMangaKey,
      categoryCatalog,
    },
  },
  {
    name: 'business-mutation-typed-conflict',
    type: 'StateMutationResponse',
    value: {
      schemaVersion: 1,
      mutationId: businessMutationId,
      accountRevision: 7,
      manga: businessManga,
      categoryCatalog,
      error: {
        code: 'BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT',
        message: 'Changed on another device',
        retryable: false,
      },
    },
  },
  ...(
    [
      [
        'createCategory',
        {
          category: {
            id: 'f99489f0-3f30-4d7c-8cb1-0f456c40319d',
            name: '漫画😀',
          },
        },
      ],
      [
        'renameCategory',
        { categoryId: 'f99489f0-3f30-4d7c-8cb1-0f456c40319d', name: '以后读' },
      ],
      [
        'reorderCategories',
        {
          categoryIds: [
            '5c70b182-c978-4650-b1d0-6c87c33c1048',
            'f99489f0-3f30-4d7c-8cb1-0f456c40319d',
          ],
        },
      ],
      [
        'deleteCategory',
        { categoryId: 'f99489f0-3f30-4d7c-8cb1-0f456c40319d' },
      ],
    ] satisfies Array<[string, JsonObject]>
  ).map(([operation, value]): GoldenFixture => ({
    name: `category-mutation-${operation}`,
    type: 'CategoryMutation',
    value: {
      schemaVersion: 1,
      mutationId: businessMutationId,
      expectedRevision: 3,
      [operation]: value,
    },
  })),
  {
    name: 'category-empty-first-read',
    type: 'CategoryCatalogResponse',
    value: { schemaVersion: 1, categoryCatalog: {} },
  },
  {
    name: 'category-confirmed-catalog',
    type: 'CategoryMutationResponse',
    value: {
      schemaVersion: 1,
      mutationId: businessMutationId,
      accountRevision: 7,
      categoryCatalog,
    },
  },
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
    value: { schemaVersion: 1, repoId: 'keiyoushi', builds: [descriptor] },
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
        value: { requestId, slotId: 'RUNTIME_SLOT_FOREGROUND', invoke: call },
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
      ['filters', filterSnapshot],
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
        value: { requestId, slotId: 'RUNTIME_SLOT_FOREGROUND', source: result },
      },
    ];
  }),
  ...(
    [
      ['ready', {}],
      [
        'open',
        {
          catalog,
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
      [
        'prepareBuild',
        { preparationId: 'prepare-golden', build: descriptor, catalog },
      ],
      ['cancelPreparation', { preparationId: 'prepare-golden' }],
      ['extensionCache', {}],
      ['forgetExtensionArtifact', { sha256 }],
      ['closeBuild', { buildId, generation }],
    ] satisfies Array<[string, JsonObject]>
  ).map(([command, value]): GoldenFixture => ({
    name: `control-request-${command}`,
    type: 'ControlRequest',
    value: { requestId, slotId: 'RUNTIME_SLOT_FOREGROUND', [command]: value },
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
      [
        'preparedBuild',
        { build: descriptor, bundleSha256: sha256, byteLength: 1024, catalog },
      ],
      [
        'extensionCache',
        {
          artifacts: [
            { sha256, byteLength: 1024, contentType: 'text/javascript' },
          ],
          totalBytes: 1024,
          maxBytes: 268435456,
          maxArtifacts: 128,
        },
      ],
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
    value: { requestId, slotId: 'RUNTIME_SLOT_FOREGROUND', [result]: value },
  })),
  ...(
    [
      ['meta', {}],
      ['data', { seq: 1, byteLength: 65536 }],
      ['end', { seq: 2, totalBytes: 65536 }],
      [
        'ack',
        {
          seq: 2,
          resource: {
            resourceId: 'resource-golden',
            generation,
            byteLength: 65536,
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
      ['open', { manifest: buildManifest, userAgent: 'Golden/1.0', catalog }],
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
          byteLength: 65536,
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
