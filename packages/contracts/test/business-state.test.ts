import { expect, test } from 'vitest';
import {
  settingsMutationSchema,
  settingsResponseSchema,
  settingsMutationResponseSchema,
  bookmarkPageResponseSchema,
  chapterProgressPageResponseSchema,
  stateMutationResponseSchema,
  categoryMutationSchema,
  categoryCatalogResponseSchema,
  mangaStateResponseSchema,
  stateMutationSchema,
} from '../src/business-state.ts';

const id = 'f99489f0-3f30-4d7c-8cb1-0f456c40319d';
const other = '5c70b182-c978-4650-b1d0-6c87c33c1048';
const base = {
  schemaVersion: 1,
  mutationId: 'a281b912-5bdb-4640-b7bc-d33bd721f8c4',
  expectedRevision: 0,
};
const create = (name: string, categoryId = id) => ({
  ...base,
  createCategory: { category: { id: categoryId, name } },
});

test('category names count Unicode scalars and UTF-8 bytes, require trimmed valid text and UUIDv4 identities', () => {
  expect(() =>
    categoryMutationSchema.parse(create('😀'.repeat(64))),
  ).not.toThrow();
  expect(() =>
    categoryMutationSchema.parse(create('字'.repeat(85))),
  ).not.toThrow();
  expect(() =>
    categoryMutationSchema.parse(create('a'.repeat(100))),
  ).not.toThrow();
  for (const name of [
    '',
    ' trailing ',
    'a'.repeat(101),
    '😀'.repeat(65),
    '\ud800',
  ]) {
    expect(() => categoryMutationSchema.parse(create(name))).toThrow();
  }
  expect(() =>
    categoryMutationSchema.parse(create('ok', id.replace('-4d7c-', '-1d7c-'))),
  ).toThrow();
});

test('category operations reject duplicates, over-budget lists, missing operations and multiple oneof values', () => {
  for (const request of [
    base,
    { ...create('name'), deleteCategory: { categoryId: id } },
    { ...base, reorderCategories: { categoryIds: [id, id] } },
    {
      ...base,
      reorderCategories: {
        categoryIds: Array.from({ length: 65 }, () => crypto.randomUUID()),
      },
    },
    { ...base, renameCategory: { categoryId: id, name: ' wrong ' } },
    { ...base, deleteCategory: { categoryId: 'invalid' } },
  ])
    expect(() => categoryMutationSchema.parse(request)).toThrow();
  expect(() =>
    categoryMutationSchema.parse({
      ...base,
      reorderCategories: { categoryIds: [] },
    }),
  ).not.toThrow();
  expect(() =>
    stateMutationSchema.parse({
      ...base,
      mangaKey: 'a'.repeat(64),
      setCategories: { categoryIds: [id], expectedCatalogRevision: 4294967296 },
    }),
  ).toThrow();
  expect(() =>
    stateMutationSchema.parse({
      ...base,
      mangaKey: 'a'.repeat(64),
      setCategories: { categoryIds: [id, id], expectedCatalogRevision: 0 },
    }),
  ).toThrow();
});

test('successful state replies require a bounded catalog and category identities projected in its order', () => {
  const categories = [
    { id, name: '同名' },
    { id: other, name: '同名' },
  ];
  const response = {
    schemaVersion: 1,
    accountRevision: 1,
    manga: { mangaKey: 'a'.repeat(64), categoryIds: [id, other] },
    categoryCatalog: { revision: 1, categories },
  };
  expect(() => mangaStateResponseSchema.parse(response)).not.toThrow();
  expect(() =>
    mangaStateResponseSchema.parse({ ...response, categoryCatalog: undefined }),
  ).toThrow();
  expect(() =>
    mangaStateResponseSchema.parse({
      ...response,
      manga: { ...response.manga, categoryIds: [other, id] },
    }),
  ).toThrow();
  expect(() =>
    mangaStateResponseSchema.parse({
      ...response,
      manga: { ...response.manga, categoryIds: [crypto.randomUUID()] },
    }),
  ).toThrow();
  expect(() =>
    categoryCatalogResponseSchema.parse({
      schemaVersion: 1,
      categoryCatalog: { categories: [categories[0], categories[0]] },
    }),
  ).toThrow();
});

test('bookmark mutations and replies validate chapter identity without requiring metadata or progress', () => {
  for (const bookmarked of [true, false]) {
    expect(
      stateMutationSchema.parse({
        ...base,
        mangaKey: 'a'.repeat(64),
        setBookmark: { chapterKey: 'snapshot-chapter-1', bookmarked },
      }).operation.case,
    ).toBe('setBookmark');
    expect(
      stateMutationResponseSchema.parse({
        schemaVersion: 1,
        mutationId: base.mutationId,
        accountRevision: 1,
        manga: { mangaKey: 'a'.repeat(64), revision: 1 },
        categoryCatalog: {},
        bookmark: { chapterKey: 'snapshot-chapter-1', bookmarked },
      }).bookmark?.bookmarked,
    ).toBe(bookmarked);
  }
  for (const chapterKey of ['', 'x'.repeat(201)]) {
    expect(() =>
      stateMutationSchema.parse({
        ...base,
        mangaKey: 'a'.repeat(64),
        setBookmark: { chapterKey, bookmarked: true },
      }),
    ).toThrow();
    expect(() =>
      mangaStateResponseSchema.parse({
        schemaVersion: 1,
        manga: { mangaKey: 'a'.repeat(64) },
        categoryCatalog: {},
        bookmark: { chapterKey, bookmarked: true },
      }),
    ).toThrow();
  }
});

test('bookmark pages are bounded, marked, ordered by SQLite UTF-8 identity, and cursor-aligned', () => {
  const page = {
    schemaVersion: 1,
    accountRevision: 2,
    mangaKey: 'a'.repeat(64),
    entries: [
      { chapterKey: 'a', bookmarked: true },
      { chapterKey: 'b', bookmarked: true },
    ],
    nextKey: 'b',
  };
  expect(() => bookmarkPageResponseSchema.parse(page)).not.toThrow();
  expect(() =>
    bookmarkPageResponseSchema.parse({
      ...page,
      entries: [
        { chapterKey: '\ue000', bookmarked: true },
        { chapterKey: '😀', bookmarked: true },
      ],
      nextKey: '😀',
    }),
  ).not.toThrow();
  for (const invalid of [
    { ...page, mangaKey: 'wrong' },
    { ...page, entries: [page.entries[0], page.entries[0]] },
    { ...page, entries: page.entries.slice().reverse() },
    { ...page, entries: [{ chapterKey: 'a', bookmarked: false }], nextKey: '' },
    { ...page, nextKey: 'c' },
    {
      ...page,
      entries: Array.from({ length: 65 }, (_, index) => ({
        chapterKey: String(index).padStart(3, '0'),
        bookmarked: true,
      })),
      nextKey: '',
    },
    { ...page, accountRevision: 4294967296 },
    {
      ...page,
      error: {
        code: 'BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT',
        message: 'changed',
      },
    },
  ])
    expect(() => bookmarkPageResponseSchema.parse(invalid)).toThrow();
  expect(() =>
    bookmarkPageResponseSchema.parse({
      schemaVersion: 1,
      error: {
        code: 'BUSINESS_STATE_ERROR_CODE_UNAVAILABLE',
        message: 'identity changed',
      },
    }),
  ).not.toThrow();
});

const globalSettingsValues = {
  theme: 'APP_THEME_SYSTEM',
  reader: {
    mode: 'READER_MODE_LEFT_TO_RIGHT',
    pageLayout: 'READER_PAGE_LAYOUT_AUTO',
    background: 'READER_BACKGROUND_BLACK',
    fit: 'READER_FIT_CONTAIN',
    cropBorders: false,
    dimPercent: 0,
    tapZones: 'READER_INPUT_PRESET_STANDARD',
    keyboard: 'READER_INPUT_PRESET_STANDARD',
  },
};

test('settings mutations require typed complete defaults and preserve per-field override presence', () => {
  const global = { ...base, setGlobal: globalSettingsValues };
  expect(() => settingsMutationSchema.parse(global)).not.toThrow();
  const manga = {
    ...base,
    setManga: { mangaKey: 'a'.repeat(64), overrides: {} },
  };
  expect(settingsMutationSchema.parse(manga).operation.case).toBe('setManga');
  const explicit = settingsMutationSchema.parse({
    ...manga,
    setManga: {
      ...manga.setManga,
      overrides: {
        pageLayout: 'READER_PAGE_LAYOUT_AUTO',
        dimPercent: 0,
        fit: 'READER_FIT_CONTAIN',
        cropBorders: false,
      },
    },
  });
  if (explicit.operation.case !== 'setManga')
    throw new Error('Missing manga settings');
  expect(explicit.operation.value.overrides?.mode).toBeUndefined();
  expect(explicit.operation.value.overrides?.pageLayout).toBe(1);
  expect(explicit.operation.value.overrides?.dimPercent).toBe(0);
  expect(explicit.operation.value.overrides?.fit).toBe(1);
  expect(explicit.operation.value.overrides?.cropBorders).toBe(false);
  const inherited = settingsMutationSchema.parse(manga);
  if (inherited.operation.case !== 'setManga')
    throw new Error('Missing manga settings');
  expect(inherited.operation.value.overrides?.dimPercent).toBeUndefined();
  expect(inherited.operation.value.overrides?.fit).toBeUndefined();
  expect(inherited.operation.value.overrides?.cropBorders).toBeUndefined();
  for (const value of [
    base,
    { ...global, setManga: manga.setManga },
    { ...base, setGlobal: { ...globalSettingsValues, theme: 0 } },
    { ...base, setGlobal: { ...globalSettingsValues, theme: 99 } },
    { ...base, setGlobal: { theme: 'APP_THEME_DARK' } },
    {
      ...base,
      setGlobal: {
        ...globalSettingsValues,
        reader: { mode: 'READER_MODE_WEBTOON' },
      },
    },
    { ...manga, setManga: { mangaKey: 'bad', overrides: {} } },
    { ...manga, setManga: { mangaKey: 'a'.repeat(64) } },
    { ...manga, setManga: { ...manga.setManga, overrides: { mode: 0 } } },
    { ...manga, setManga: { ...manga.setManga, overrides: { pageLayout: 4 } } },
    ...[
      { cropBorders: 0 },
      { cropBorders: 1 },
      { cropBorders: 'false' },
      { cropBorders: 'true' },
      { cropBorders: {} },
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
    ].flatMap((fields) => [
      { ...manga, setManga: { ...manga.setManga, overrides: fields } },
      {
        ...global,
        setGlobal: {
          ...globalSettingsValues,
          reader: { ...globalSettingsValues.reader, ...fields },
        },
      },
    ]),
    { ...global, expectedRevision: 4294967296 },
  ])
    expect(() => settingsMutationSchema.parse(value)).toThrow();
});

test('settings replies verify the complete snapshot and effective defaults/overrides', () => {
  const defaults = {
    schemaVersion: 1,
    accountRevision: 3,
    global: { revision: 1, values: globalSettingsValues },
    effectiveReader: globalSettingsValues.reader,
  };
  expect(() => settingsResponseSchema.parse(defaults)).not.toThrow();
  const manga = {
    ...defaults,
    manga: {
      mangaKey: 'a'.repeat(64),
      revision: 2,
      overrides: { mode: 'READER_MODE_RIGHT_TO_LEFT' },
    },
    effectiveReader: {
      ...globalSettingsValues.reader,
      mode: 'READER_MODE_RIGHT_TO_LEFT',
    },
  };
  expect(() =>
    settingsMutationResponseSchema.parse({
      ...manga,
      mutationId: base.mutationId,
    }),
  ).not.toThrow();
  const croppedDefaults = {
    ...globalSettingsValues,
    reader: { ...globalSettingsValues.reader, cropBorders: true },
  };
  expect(() =>
    settingsResponseSchema.parse({
      ...manga,
      global: { ...defaults.global, values: croppedDefaults },
      manga: {
        ...manga.manga,
        overrides: { mode: 'READER_MODE_RIGHT_TO_LEFT', cropBorders: false },
      },
    }),
  ).not.toThrow();
  for (const value of [
    { ...defaults, global: undefined },
    { ...defaults, global: { revision: 4, values: globalSettingsValues } },
    { ...defaults, global: { revision: 1 } },
    { ...defaults, effectiveReader: undefined },
    { ...manga, manga: { ...manga.manga, revision: 4 } },
    { ...manga, manga: { ...manga.manga, overrides: undefined } },
    { ...manga, effectiveReader: globalSettingsValues.reader },
    ...[
      { cropBorders: true },
      { fit: 'READER_FIT_WIDTH' },
      { background: 'READER_BACKGROUND_WHITE' },
      { dimPercent: 1 },
      { tapZones: 'READER_INPUT_PRESET_DISABLED' },
      { keyboard: 'READER_INPUT_PRESET_REVERSED' },
    ].map((fields) => ({
      ...manga,
      effectiveReader: { ...manga.effectiveReader, ...fields },
    })),
    {
      ...manga,
      effectiveReader: {
        ...manga.effectiveReader,
        pageLayout: 'READER_PAGE_LAYOUT_DOUBLE',
      },
    },
  ])
    expect(() => settingsResponseSchema.parse(value)).toThrow();
  expect(() =>
    settingsResponseSchema.parse({
      schemaVersion: 1,
      error: {
        code: 'BUSINESS_STATE_ERROR_CODE_UNAVAILABLE',
        message: 'unavailable',
      },
    }),
  ).not.toThrow();
});

test('chapter read mutations need no pages while anchorless replies never weaken save-progress input validation', () => {
  const mangaKey = 'a'.repeat(64);
  for (const read of [true, false]) {
    expect(
      stateMutationSchema.parse({
        ...base,
        mangaKey,
        setChapterRead: { chapterKey: 'chapter-1', read },
      }).operation.case,
    ).toBe('setChapterRead');
    expect(
      stateMutationResponseSchema.parse({
        schemaVersion: 1,
        mutationId: base.mutationId,
        accountRevision: 1,
        manga: { mangaKey, revision: 1 },
        categoryCatalog: {},
        progress: { chapterKey: 'chapter-1', epoch: 1, completed: read },
      }).progress?.completed,
    ).toBe(read);
  }
  const anchor = {
    chapterKey: 'chapter-1',
    pageKey: 'page-1',
    manifestVersion: 'manifest-1',
  };
  for (const chapterKey of ['', 'x'.repeat(201)]) {
    expect(() =>
      stateMutationSchema.parse({
        ...base,
        mangaKey,
        setChapterRead: { chapterKey, read: true },
      }),
    ).toThrow();
  }
  expect(() =>
    stateMutationSchema.parse({
      ...base,
      mangaKey,
      saveProgress: {
        snapshot: {
          chapterKey: 'chapter-1',
          manifestVersion: 'manifest-1',
          pageKeys: ['page-1'],
        },
        progress: { chapterKey: 'chapter-1', epoch: 1, completed: true },
      },
    }),
  ).toThrow();
  expect(() =>
    mangaStateResponseSchema.parse({
      schemaVersion: 1,
      manga: { mangaKey },
      categoryCatalog: {},
      progress: { chapterKey: 'chapter-1', epoch: 1, furthest: anchor },
    }),
  ).toThrow();
});

test('chapter progress pages retain unread epochs, bound ordered UTF-8 identities and align their cursor', () => {
  const page = {
    schemaVersion: 1,
    accountRevision: 2,
    mangaKey: 'a'.repeat(64),
    entries: [
      { chapterKey: 'a', epoch: 1, completed: true },
      { chapterKey: 'b', epoch: 2, completed: false },
    ],
    nextKey: 'b',
  };
  expect(() => chapterProgressPageResponseSchema.parse(page)).not.toThrow();
  expect(() =>
    chapterProgressPageResponseSchema.parse({
      ...page,
      entries: [{ chapterKey: '\ue000' }, { chapterKey: '😀' }],
      nextKey: '😀',
    }),
  ).not.toThrow();
  for (const invalid of [
    { ...page, mangaKey: 'wrong' },
    { ...page, entries: [page.entries[0], page.entries[0]] },
    { ...page, entries: page.entries.slice().reverse() },
    { ...page, nextKey: 'c' },
    { ...page, entries: [{ chapterKey: 'a', epoch: 4294967296 }], nextKey: '' },
    {
      ...page,
      entries: Array.from({ length: 65 }, (_, index) => ({
        chapterKey: String(index).padStart(3, '0'),
      })),
      nextKey: '',
    },
    { ...page, accountRevision: 4294967296 },
    {
      ...page,
      error: {
        code: 'BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT',
        message: 'changed',
      },
    },
  ])
    expect(() => chapterProgressPageResponseSchema.parse(invalid)).toThrow();
  expect(() =>
    chapterProgressPageResponseSchema.parse({
      schemaVersion: 1,
      error: {
        code: 'BUSINESS_STATE_ERROR_CODE_UNAVAILABLE',
        message: 'identity changed',
      },
    }),
  ).not.toThrow();
});

test('reading anchors validate all source and viewport coordinates on both request and response boundaries', () => {
  const anchor = {
    chapterKey: 'chapter-1',
    pageKey: 'page-1',
    manifestVersion: 'manifest-1',
    normalizedOffset: 0.4,
    normalizedX: 1,
    viewportX: 0.5,
    viewportY: 0,
  };
  const mutation = (current: typeof anchor) => ({
    ...base,
    mangaKey: 'a'.repeat(64),
    saveProgress: {
      snapshot: {
        chapterKey: anchor.chapterKey,
        manifestVersion: anchor.manifestVersion,
        pageKeys: [anchor.pageKey],
      },
      progress: { chapterKey: anchor.chapterKey, current },
    },
  });
  const response = (current: typeof anchor) => ({
    schemaVersion: 1,
    manga: { mangaKey: 'a'.repeat(64) },
    categoryCatalog: {},
    progress: { chapterKey: anchor.chapterKey, current },
  });
  expect(() => stateMutationSchema.parse(mutation(anchor))).not.toThrow();
  expect(() => mangaStateResponseSchema.parse(response(anchor))).not.toThrow();
  for (const field of [
    'normalizedOffset',
    'normalizedX',
    'viewportX',
    'viewportY',
  ]) {
    for (const coordinate of [-0.1, 1.1, 'NaN', 'Infinity', '-Infinity']) {
      const invalid = { ...anchor, [field]: coordinate };
      expect(() => stateMutationSchema.parse(mutation(invalid))).toThrow();
      expect(() => mangaStateResponseSchema.parse(response(invalid))).toThrow();
    }
  }
});

test('custom covers preserve set/clear presence and validate descriptor identities, formats and byte budgets at every state boundary', () => {
  const cover = {
    assetId: id,
    contentType: 'image/png',
    byteLength: 1024,
    sha256: 'a'.repeat(64),
  };
  const command = {
    ...base,
    mangaKey: 'a'.repeat(64),
    setCustomCover: { cover },
  };
  const parsed = stateMutationSchema.parse(command);
  expect(parsed.operation).toMatchObject({
    case: 'setCustomCover',
    value: { cover },
  });
  const removed = stateMutationSchema.parse({
    ...command,
    setCustomCover: {},
  }).operation;
  expect(removed.case).toBe('setCustomCover');
  if (removed.case === 'setCustomCover')
    expect(removed.value.cover).toBeUndefined();
  const response = {
    schemaVersion: 1,
    manga: { mangaKey: command.mangaKey, customCover: cover },
    categoryCatalog: {},
  };
  expect(
    mangaStateResponseSchema.parse(response).manga?.customCover,
  ).toMatchObject(cover);
  for (const invalid of [
    { ...cover, assetId: 'invalid' },
    { ...cover, contentType: 'image/gif' },
    { ...cover, byteLength: 0 },
    { ...cover, byteLength: 1048577 },
    { ...cover, byteLength: 1.1 },
    { ...cover, sha256: 'A'.repeat(64) },
    { ...cover, sha256: 'a'.repeat(63) },
  ]) {
    expect(() =>
      stateMutationSchema.parse({
        ...command,
        setCustomCover: { cover: invalid },
      }),
    ).toThrow();
    expect(() =>
      mangaStateResponseSchema.parse({
        ...response,
        manga: { ...response.manga, customCover: invalid },
      }),
    ).toThrow();
  }
});
