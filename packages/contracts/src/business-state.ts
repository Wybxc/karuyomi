import * as pb from '@karuyomi/protocol';
import { z } from 'zod';
import {
  codec,
  jsonText,
  messageJson,
  parseMessage,
  requireCondition,
  requireFields,
  SOURCE_MEMO_LIMIT,
  validateJsonDepth,
} from './codec.ts';
import { validId, validSourceId } from './static-control.ts';

export const businessSchemaVersion = 1;
export const BUSINESS_REQUEST_LIMIT = 128 * 1024;
export const BUSINESS_RESPONSE_LIMIT = 2 * 1024 * 1024;
export const LIBRARY_METADATA_LIMIT = 96 * 1024;
export const LIBRARY_PAGE_SIZE = 8;
export const BOOKMARK_PAGE_SIZE = 64;
export const CHAPTER_PROGRESS_PAGE_SIZE = 64;
export const CHAPTER_PAGE_LIMIT = 2048;
export const CATEGORY_LIMIT = 64;

const mutationId = z.uuid();
const mangaKey = z.string().regex(/^[a-f0-9]{64}$/);
const categoryId = z.uuidv4();

function categoryIds(values: string[]): void {
  requireCondition(
    values.length <= CATEGORY_LIMIT && new Set(values).size === values.length,
    'Category identities must be unique and within budget',
  );
  values.forEach((id) => categoryId.parse(id));
}

function categoryName(value: string): void {
  requireCondition(
    value === value.trim() &&
      value.length > 0 &&
      [...value].length <= 100 &&
      new TextEncoder().encode(value).byteLength <= 256 &&
      [...value].every((scalar) => {
        const point = scalar.codePointAt(0)!;
        return point < 0xd800 || point > 0xdfff;
      }),
    'Category name must be trimmed and within budget',
  );
}

export function validateCategoryCatalog(value: pb.CategoryCatalog): void {
  uint32(value.revision);
  categoryIds(value.categories.map((category) => category.id));
  value.categories.forEach((category) => categoryName(category.name));
}

function validateMemberships(
  manga: pb.MangaState,
  catalog: pb.CategoryCatalog,
): void {
  const projected = catalog.categories
    .filter((category) => manga.categoryIds.includes(category.id))
    .map((category) => category.id);
  requireCondition(
    JSON.stringify(projected) === JSON.stringify(manga.categoryIds),
    'Manga categories must follow the current catalog',
  );
}

export const categoryMutationSchema = codec<pb.CategoryMutation>((input) => {
  const value = parseMessage(
    pb.CategoryMutationSchema,
    input,
    BUSINESS_REQUEST_LIMIT,
  );
  requireCondition(
    value.schemaVersion === businessSchemaVersion,
    'Unsupported business state schema',
  );
  mutationId.parse(value.mutationId);
  uint32(value.expectedRevision);
  switch (value.operation.case) {
    case 'createCategory':
      requireFields(value.operation.value, ['category']);
      categoryId.parse(value.operation.value.category.id);
      categoryName(value.operation.value.category.name);
      break;
    case 'renameCategory':
      categoryId.parse(value.operation.value.categoryId);
      categoryName(value.operation.value.name);
      break;
    case 'reorderCategories':
      categoryIds(value.operation.value.categoryIds);
      break;
    case 'deleteCategory':
      categoryId.parse(value.operation.value.categoryId);
      break;
    default:
      throw new Error('A category mutation operation is required');
  }
  return value;
});

function uint32(value: number): void {
  requireCondition(
    Number.isInteger(value) && value >= 0 && value <= 0xffff_ffff,
    'Business revision or epoch exceeds uint32',
  );
}

export function validateLibraryMetadata(value: pb.LibraryMetadata): void {
  validId(value.packageName);
  validSourceId(value.sourceId);
  requireCondition(
    value.sourceName.length > 0 &&
      value.sourceName.length <= 256 &&
      value.sourceLang.length > 0 &&
      value.sourceLang.length <= 64,
    'Invalid Source metadata',
  );
  requireFields(value, ['manga']);
  requireCondition(
    value.manga.url.length > 0 &&
      value.manga.url.length <= 16_384 &&
      value.manga.title.length > 0,
    'Explicit manga reference and title are required',
  );
  requireCondition(
    value.manga.updateStrategy === '' ||
      value.manga.updateStrategy === 'ALWAYS_UPDATE' ||
      value.manga.updateStrategy === 'ONLY_FETCH_ONCE',
    'Unknown manga update strategy',
  );
  const memo = value.manga.memoJson;
  if (memo !== undefined) {
    requireCondition(
      new TextEncoder().encode(memo).byteLength <= SOURCE_MEMO_LIMIT,
      'Source memo exceeds its byte budget',
    );
    const parsed: unknown = JSON.parse(memo);
    validateJsonDepth(parsed);
    requireCondition(
      parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed),
      'Source memo must be a JSON object',
    );
  }
  jsonText(
    messageJson(pb.LibraryMetadataSchema, value),
    LIBRARY_METADATA_LIMIT,
  );
}

export function validateReadingAnchor(value: pb.ReadingAnchor): void {
  validId(value.chapterKey);
  validId(value.pageKey);
  validId(value.manifestVersion);
  uint32(value.pageIndexHint);
  requireCondition(
    value.pageIndexHint < CHAPTER_PAGE_LIMIT &&
      Number.isFinite(value.normalizedOffset) &&
      value.normalizedOffset >= 0 &&
      value.normalizedOffset <= 1,
    'Invalid reading anchor',
  );
}

export function validateChapterBookmark(value: pb.ChapterBookmark): void {
  validId(value.chapterKey);
}

export function validateChapterProgress(value: pb.ChapterProgressState): void {
  validId(value.chapterKey);
  uint32(value.epoch);
  if (value.current) {
    validateReadingAnchor(value.current);
    requireCondition(
      value.current.chapterKey === value.chapterKey,
      'Current anchor belongs to a different chapter',
    );
  }
  if (value.furthest) {
    requireFields(value, ['current']);
    validateReadingAnchor(value.furthest);
    requireCondition(
      value.furthest.chapterKey === value.chapterKey,
      'Furthest anchor belongs to a different chapter',
    );
  }
}

export function validateChapterSnapshot(value: pb.ChapterSnapshot): void {
  validId(value.chapterKey);
  validId(value.manifestVersion);
  requireCondition(
    value.pageKeys.length > 0 &&
      value.pageKeys.length <= CHAPTER_PAGE_LIMIT &&
      new Set(value.pageKeys).size === value.pageKeys.length,
    'Chapter snapshot pages must be nonempty and unique',
  );
  value.pageKeys.forEach(validId);
}

export function validateMangaState(value: pb.MangaState): void {
  mangaKey.parse(value.mangaKey);
  uint32(value.revision);
  uint32(value.addedAtSeconds);
  if (value.metadata) validateLibraryMetadata(value.metadata);
  requireCondition(
    !value.favorite || value.metadata !== undefined,
    'Favorite manga requires Source metadata',
  );
  if (value.resume) validId(value.resume.chapterKey);
  categoryIds(value.categoryIds);
}

export const stateMutationSchema = codec<pb.StateMutation>((input) => {
  const value = parseMessage(
    pb.StateMutationSchema,
    input,
    BUSINESS_REQUEST_LIMIT,
  );
  requireCondition(
    value.schemaVersion === businessSchemaVersion,
    'Unsupported business state schema',
  );
  mutationId.parse(value.mutationId);
  mangaKey.parse(value.mangaKey);
  uint32(value.expectedRevision);
  switch (value.operation.case) {
    case 'setFavorite':
      if (value.operation.value.metadata)
        validateLibraryMetadata(value.operation.value.metadata);
      break;
    case 'updateMetadata':
      validateLibraryMetadata(value.operation.value);
      break;
    case 'saveProgress': {
      const operation = value.operation.value;
      requireFields(operation, ['snapshot', 'progress']);
      validateChapterSnapshot(operation.snapshot);
      validateChapterProgress(operation.progress);
      requireFields(operation.progress, ['current']);
      const current = operation.progress.current;
      requireCondition(
        operation.progress.chapterKey === operation.snapshot.chapterKey &&
          current.manifestVersion === operation.snapshot.manifestVersion &&
          operation.snapshot.pageKeys[current.pageIndexHint] ===
            current.pageKey,
        'Current progress does not match its chapter snapshot',
      );
      break;
    }
    case 'resetProgress':
      requireFields(value.operation.value, ['snapshot']);
      validateChapterSnapshot(value.operation.value.snapshot);
      break;
    case 'setBookmark':
    case 'setChapterRead':
      validId(value.operation.value.chapterKey);
      break;
    case 'setCategories':
      categoryIds(value.operation.value.categoryIds);
      uint32(value.operation.value.expectedCatalogRevision);
      break;
    default:
      throw new Error('A business state mutation operation is required');
  }
  return value;
});

function validateError(value: pb.BusinessStateError): void {
  requireCondition(
    Number.isInteger(value.code) &&
      value.code >= pb.BusinessStateErrorCode.INVALID_INPUT &&
      value.code <= pb.BusinessStateErrorCode.LIMIT_EXCEEDED &&
      value.message.length > 0 &&
      value.message.length <= 1024,
    'Invalid business state error',
  );
}

function validateResponse(value: {
  schemaVersion: number;
  accountRevision: number;
  manga?: pb.MangaState | undefined;
  progress?: pb.ChapterProgressState | undefined;
  bookmark?: pb.ChapterBookmark | undefined;
  error?: pb.BusinessStateError | undefined;
  categoryCatalog?: pb.CategoryCatalog | undefined;
}): void {
  requireCondition(
    value.schemaVersion === businessSchemaVersion,
    'Unsupported business state schema',
  );
  uint32(value.accountRevision);
  if (value.error) validateError(value.error);
  else requireFields(value, ['manga', 'categoryCatalog']);
  if (value.manga) validateMangaState(value.manga);
  if (value.progress) validateChapterProgress(value.progress);
  if (value.bookmark) {
    validateChapterBookmark(value.bookmark);
    requireCondition(
      !value.progress ||
        value.progress.chapterKey === value.bookmark.chapterKey,
      'Bookmark and progress belong to different chapters',
    );
  }
  if (value.categoryCatalog) {
    validateCategoryCatalog(value.categoryCatalog);
    if (value.manga) validateMemberships(value.manga, value.categoryCatalog);
  }
}

export const stateMutationResponseSchema = codec<pb.StateMutationResponse>(
  (input) => {
    const value = parseMessage(
      pb.StateMutationResponseSchema,
      input,
      BUSINESS_RESPONSE_LIMIT,
    );
    if (!value.error || value.mutationId !== '')
      mutationId.parse(value.mutationId);
    validateResponse(value);
    return value;
  },
);

export const mangaStateResponseSchema = codec<pb.MangaStateResponse>(
  (input) => {
    const value = parseMessage(
      pb.MangaStateResponseSchema,
      input,
      BUSINESS_RESPONSE_LIMIT,
    );
    validateResponse(value);
    return value;
  },
);

export const bookmarkPageResponseSchema = codec<pb.BookmarkPageResponse>(
  (input) => {
    const value = parseMessage(
      pb.BookmarkPageResponseSchema,
      input,
      BUSINESS_RESPONSE_LIMIT,
    );
    requireCondition(
      value.schemaVersion === businessSchemaVersion,
      'Unsupported business state schema',
    );
    uint32(value.accountRevision);
    if (!value.error || value.mangaKey !== '') mangaKey.parse(value.mangaKey);
    if (value.error) {
      validateError(value.error);
      requireCondition(
        value.entries.length === 0 && value.nextKey === '',
        'Failed bookmark page cannot contain entries',
      );
    }
    requireCondition(
      value.entries.length <= BOOKMARK_PAGE_SIZE &&
        new Set(value.entries.map((entry) => entry.chapterKey)).size ===
          value.entries.length,
      'Invalid bookmark page',
    );
    let previousKey: Uint8Array | undefined;
    for (const entry of value.entries) {
      validateChapterBookmark(entry);
      requireCondition(
        entry.bookmarked,
        'Bookmark pages contain marked chapters only',
      );
      // SQLite BINARY orders UTF-8 bytes, including non-ASCII chapter identities.
      const key = new TextEncoder().encode(entry.chapterKey);
      if (previousKey) {
        const different = previousKey.findIndex(
          (byte, index) => byte !== key[index],
        );
        requireCondition(
          different < 0
            ? previousKey.length < key.length
            : previousKey[different]! < (key[different] ?? -1),
          'Bookmark page keys must be unique and ordered',
        );
      }
      previousKey = key;
    }
    if (value.nextKey !== '') {
      validId(value.nextKey);
      requireCondition(
        value.nextKey === value.entries.at(-1)?.chapterKey,
        'Bookmark cursor must identify its last entry',
      );
    }
    return value;
  },
);

export const chapterProgressPageResponseSchema =
  codec<pb.ChapterProgressPageResponse>((input) => {
    const value = parseMessage(
      pb.ChapterProgressPageResponseSchema,
      input,
      BUSINESS_RESPONSE_LIMIT,
    );
    requireCondition(
      value.schemaVersion === businessSchemaVersion,
      'Unsupported business state schema',
    );
    uint32(value.accountRevision);
    if (!value.error || value.mangaKey !== '') mangaKey.parse(value.mangaKey);
    if (value.error) {
      validateError(value.error);
      requireCondition(
        value.entries.length === 0 && value.nextKey === '',
        'Failed chapter progress page cannot contain entries',
      );
    }
    requireCondition(
      value.entries.length <= CHAPTER_PROGRESS_PAGE_SIZE &&
        new Set(value.entries.map((entry) => entry.chapterKey)).size ===
          value.entries.length,
      'Invalid chapter progress page',
    );
    let previousKey: Uint8Array | undefined;
    for (const entry of value.entries) {
      validateChapterProgress(entry);
      // SQLite BINARY orders UTF-8 bytes, including non-ASCII chapter identities.
      const key = new TextEncoder().encode(entry.chapterKey);
      if (previousKey) {
        const different = previousKey.findIndex(
          (byte, index) => byte !== key[index],
        );
        requireCondition(
          different < 0
            ? previousKey.length < key.length
            : previousKey[different]! < (key[different] ?? -1),
          'Chapter progress page keys must be unique and ordered',
        );
      }
      previousKey = key;
    }
    if (value.nextKey !== '') {
      validId(value.nextKey);
      requireCondition(
        value.nextKey === value.entries.at(-1)?.chapterKey,
        'Chapter progress cursor must identify its last entry',
      );
    }
    return value;
  });

export const libraryPageResponseSchema = codec<pb.LibraryPageResponse>(
  (input) => {
    const value = parseMessage(
      pb.LibraryPageResponseSchema,
      input,
      BUSINESS_RESPONSE_LIMIT,
    );
    requireCondition(
      value.schemaVersion === businessSchemaVersion,
      'Unsupported business state schema',
    );
    uint32(value.accountRevision);
    if (!value.error) requireFields(value, ['categoryCatalog']);
    if (value.categoryCatalog) validateCategoryCatalog(value.categoryCatalog);
    if (value.error) {
      validateError(value.error);
      requireCondition(
        value.entries.length === 0 && value.nextKey === '',
        'Failed library page cannot contain entries',
      );
    }
    requireCondition(
      value.entries.length <= LIBRARY_PAGE_SIZE &&
        new Set(value.entries.map((entry) => entry.mangaKey)).size ===
          value.entries.length,
      'Invalid library page',
    );
    let previousKey: string | undefined;
    for (const entry of value.entries) {
      validateMangaState(entry);
      if (value.categoryCatalog)
        validateMemberships(entry, value.categoryCatalog);
      requireCondition(entry.favorite, 'Library entries must be favorites');
      requireCondition(
        previousKey === undefined || previousKey < entry.mangaKey,
        'Library page keys must be unique and ordered',
      );
      previousKey = entry.mangaKey;
    }
    if (value.nextKey !== '') {
      mangaKey.parse(value.nextKey);
      requireCondition(
        value.nextKey === value.entries.at(-1)?.mangaKey,
        'Library cursor must identify its last entry',
      );
    }
    return value;
  },
);

function validateCategoryResponse(value: {
  schemaVersion: number;
  accountRevision: number;
  categoryCatalog?: pb.CategoryCatalog | undefined;
  error?: pb.BusinessStateError | undefined;
}): void {
  requireCondition(
    value.schemaVersion === businessSchemaVersion,
    'Unsupported business state schema',
  );
  uint32(value.accountRevision);
  if (value.error) validateError(value.error);
  else requireFields(value, ['categoryCatalog']);
  if (value.categoryCatalog) validateCategoryCatalog(value.categoryCatalog);
}

export const categoryCatalogResponseSchema = codec<pb.CategoryCatalogResponse>(
  (input) => {
    const value = parseMessage(
      pb.CategoryCatalogResponseSchema,
      input,
      BUSINESS_RESPONSE_LIMIT,
    );
    validateCategoryResponse(value);
    return value;
  },
);

export const categoryMutationResponseSchema =
  codec<pb.CategoryMutationResponse>((input) => {
    const value = parseMessage(
      pb.CategoryMutationResponseSchema,
      input,
      BUSINESS_RESPONSE_LIMIT,
    );
    if (!value.error || value.mutationId !== '')
      mutationId.parse(value.mutationId);
    validateCategoryResponse(value);
    return value;
  });

export function validateReaderSettings(value: pb.ReaderSettings): void {
  requireCondition(
    Number.isInteger(value.mode) &&
      value.mode >= pb.ReaderMode.LEFT_TO_RIGHT &&
      value.mode <= pb.ReaderMode.WEBTOON,
    'Unknown reader mode',
  );
  requireCondition(
    Number.isInteger(value.pageLayout) &&
      value.pageLayout >= pb.ReaderPageLayout.AUTO &&
      value.pageLayout <= pb.ReaderPageLayout.DOUBLE,
    'Unknown reader page layout',
  );
  requireCondition(
    Number.isInteger(value.background) &&
      value.background >= pb.ReaderBackground.BLACK &&
      value.background <= pb.ReaderBackground.THEME,
    'Unknown reader background',
  );
  requireCondition(
    Number.isInteger(value.dimPercent) &&
      value.dimPercent >= 0 &&
      value.dimPercent <= 80,
    'Reader dimming exceeds its range',
  );
  for (const preset of [value.tapZones, value.keyboard])
    requireCondition(
      Number.isInteger(preset) &&
        preset >= pb.ReaderInputPreset.STANDARD &&
        preset <= pb.ReaderInputPreset.DISABLED,
      'Unknown reader input preset',
    );
}

export function validateReaderSettingsOverride(
  value: pb.ReaderSettingsOverride,
): void {
  if (value.mode !== undefined)
    requireCondition(
      Number.isInteger(value.mode) &&
        value.mode >= pb.ReaderMode.LEFT_TO_RIGHT &&
        value.mode <= pb.ReaderMode.WEBTOON,
      'Unknown reader mode override',
    );
  if (value.pageLayout !== undefined)
    requireCondition(
      Number.isInteger(value.pageLayout) &&
        value.pageLayout >= pb.ReaderPageLayout.AUTO &&
        value.pageLayout <= pb.ReaderPageLayout.DOUBLE,
      'Unknown reader page layout override',
    );
  if (value.background !== undefined)
    requireCondition(
      Number.isInteger(value.background) &&
        value.background >= pb.ReaderBackground.BLACK &&
        value.background <= pb.ReaderBackground.THEME,
      'Unknown reader background override',
    );
  if (value.dimPercent !== undefined)
    requireCondition(
      Number.isInteger(value.dimPercent) &&
        value.dimPercent >= 0 &&
        value.dimPercent <= 80,
      'Reader dimming override exceeds its range',
    );
  for (const preset of [value.tapZones, value.keyboard])
    if (preset !== undefined)
      requireCondition(
        Number.isInteger(preset) &&
          preset >= pb.ReaderInputPreset.STANDARD &&
          preset <= pb.ReaderInputPreset.DISABLED,
        'Unknown reader input preset override',
      );
}

export function validateGlobalSettingsValues(
  value: pb.GlobalSettingsValues,
): void {
  requireCondition(
    Number.isInteger(value.theme) &&
      value.theme >= pb.AppTheme.SYSTEM &&
      value.theme <= pb.AppTheme.DARK,
    'Unknown application theme',
  );
  requireFields(value, ['reader']);
  validateReaderSettings(value.reader);
}

export const settingsMutationSchema = codec<pb.SettingsMutation>((input) => {
  const value = parseMessage(
    pb.SettingsMutationSchema,
    input,
    BUSINESS_REQUEST_LIMIT,
  );
  requireCondition(
    value.schemaVersion === businessSchemaVersion,
    'Unsupported business state schema',
  );
  mutationId.parse(value.mutationId);
  uint32(value.expectedRevision);
  switch (value.operation.case) {
    case 'setGlobal':
      validateGlobalSettingsValues(value.operation.value);
      break;
    case 'setManga':
      mangaKey.parse(value.operation.value.mangaKey);
      requireFields(value.operation.value, ['overrides']);
      validateReaderSettingsOverride(value.operation.value.overrides);
      break;
    default:
      throw new Error('A settings operation is required');
  }
  return value;
});

function validateSettingsResponse(value: {
  schemaVersion: number;
  accountRevision: number;
  global?: pb.GlobalSettings | undefined;
  manga?: pb.MangaReaderSettings | undefined;
  effectiveReader?: pb.ReaderSettings | undefined;
  error?: pb.BusinessStateError | undefined;
}): void {
  requireCondition(
    value.schemaVersion === businessSchemaVersion,
    'Unsupported business state schema',
  );
  uint32(value.accountRevision);
  if (value.error) validateError(value.error);
  if (!value.error || value.global || value.manga || value.effectiveReader)
    requireFields(value, ['global', 'effectiveReader']);
  if (value.global) {
    uint32(value.global.revision);
    requireCondition(
      value.global.revision <= value.accountRevision,
      'Global settings exceed account revision',
    );
    requireFields(value.global, ['values']);
    validateGlobalSettingsValues(value.global.values);
  }
  if (value.manga) {
    mangaKey.parse(value.manga.mangaKey);
    uint32(value.manga.revision);
    requireCondition(
      value.manga.revision <= value.accountRevision,
      'Manga settings exceed account revision',
    );
    requireFields(value.manga, ['overrides']);
    validateReaderSettingsOverride(value.manga.overrides);
  }
  if (value.effectiveReader) {
    validateReaderSettings(value.effectiveReader);
    const defaults = value.global?.values?.reader;
    requireCondition(
      value.effectiveReader.mode ===
        (value.manga?.overrides?.mode ?? defaults?.mode) &&
        value.effectiveReader.pageLayout ===
          (value.manga?.overrides?.pageLayout ?? defaults?.pageLayout) &&
        value.effectiveReader.background ===
          (value.manga?.overrides?.background ?? defaults?.background) &&
        value.effectiveReader.dimPercent ===
          (value.manga?.overrides?.dimPercent ?? defaults?.dimPercent) &&
        value.effectiveReader.tapZones ===
          (value.manga?.overrides?.tapZones ?? defaults?.tapZones) &&
        value.effectiveReader.keyboard ===
          (value.manga?.overrides?.keyboard ?? defaults?.keyboard),
      'Effective reader settings do not match their defaults and overrides',
    );
  }
}

export const settingsResponseSchema = codec<pb.SettingsResponse>((input) => {
  const value = parseMessage(
    pb.SettingsResponseSchema,
    input,
    BUSINESS_RESPONSE_LIMIT,
  );
  validateSettingsResponse(value);
  return value;
});

export const settingsMutationResponseSchema =
  codec<pb.SettingsMutationResponse>((input) => {
    const value = parseMessage(
      pb.SettingsMutationResponseSchema,
      input,
      BUSINESS_RESPONSE_LIMIT,
    );
    if (!value.error || value.mutationId !== '')
      mutationId.parse(value.mutationId);
    validateSettingsResponse(value);
    return value;
  });
