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
import {
  buildIdSchema,
  validId,
  validSourceId,
  validateExtensionCatalogUrl,
  validateCatalogReference,
} from './static-control.ts';
export { validateExtensionCatalogUrl } from './static-control.ts';

export const businessSchemaVersion = 1;
export const BUSINESS_REQUEST_LIMIT = 128 * 1024;
export const BUSINESS_RESPONSE_LIMIT = 2 * 1024 * 1024;
export const LIBRARY_METADATA_LIMIT = 96 * 1024;
export const LIBRARY_PAGE_SIZE = 8;
export const BOOKMARK_PAGE_SIZE = 64;
export const CHAPTER_PROGRESS_PAGE_SIZE = 64;
export const CHAPTER_PAGE_LIMIT = 2048;
export const CATEGORY_LIMIT = 64;
export const MIGRATION_CHAPTER_LIMIT = 256;
export const FAVORITE_SOURCE_LIMIT = 128;
export const INSTALLED_EXTENSION_LIMIT = 128;
export const EXTENSION_REPOSITORY_LIMIT = 16;
export const EXTENSION_CATALOG_URL_LIMIT = 2048;
export const COVER_BYTE_LIMIT = 1024 * 1024;
export const COVER_DIMENSION_LIMIT = 4096;

const mutationId = z.uuid();
const mangaKey = z.string().regex(/^[a-f0-9]{64}$/);
const canonicalUuidV4 = z.uuidv4().lowercase();

function categoryIds(values: string[]): void {
  requireCondition(
    values.length <= CATEGORY_LIMIT && new Set(values).size === values.length,
    'Category identities must be unique and within budget',
  );
  values.forEach((id) => canonicalUuidV4.parse(id));
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
      canonicalUuidV4.parse(value.operation.value.category.id);
      categoryName(value.operation.value.category.name);
      break;
    case 'renameCategory':
      canonicalUuidV4.parse(value.operation.value.categoryId);
      categoryName(value.operation.value.name);
      break;
    case 'reorderCategories':
      categoryIds(value.operation.value.categoryIds);
      break;
    case 'deleteCategory':
      canonicalUuidV4.parse(value.operation.value.categoryId);
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
      [
        value.normalizedOffset,
        value.normalizedX,
        value.viewportX,
        value.viewportY,
      ].every(
        (coordinate) =>
          Number.isFinite(coordinate) && coordinate >= 0 && coordinate <= 1,
      ),
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

export function validateCustomCover(value: pb.CustomCover): void {
  canonicalUuidV4.parse(value.assetId);
  z.enum(['image/jpeg', 'image/png']).parse(value.contentType);
  z.int().min(1).max(COVER_BYTE_LIMIT).parse(value.byteLength);
  z.string()
    .regex(/^[a-f0-9]{64}$/)
    .parse(value.sha256);
}

export function validateMangaState(value: pb.MangaState): void {
  mangaKey.parse(value.mangaKey);
  uint32(value.revision);
  uint32(value.addedAtSeconds);
  if (value.metadata) validateLibraryMetadata(value.metadata);
  if (value.customCover) validateCustomCover(value.customCover);
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
    case 'migrateFrom': {
      const operation = value.operation.value;
      mangaKey.parse(operation.sourceMangaKey);
      requireCondition(
        operation.sourceMangaKey !== value.mangaKey,
        'Migration requires distinct source and target manga',
      );
      uint32(operation.expectedSourceRevision);
      uint32(operation.expectedCatalogRevision);
      requireFields(operation, ['targetMetadata']);
      validateLibraryMetadata(operation.targetMetadata);
      requireCondition(
        operation.chapters.length <= MIGRATION_CHAPTER_LIMIT &&
          new Set(operation.chapters.map((chapter) => chapter.sourceChapterKey))
            .size === operation.chapters.length &&
          new Set(operation.chapters.map((chapter) => chapter.targetChapterKey))
            .size === operation.chapters.length,
        'Migration chapter mapping must be bounded and one-to-one',
      );
      for (const chapter of operation.chapters) {
        validId(chapter.sourceChapterKey);
        validId(chapter.targetChapterKey);
        requireCondition(
          chapter.copyRead || chapter.copyBookmark,
          'A migration chapter must select read state or bookmark',
        );
      }
      break;
    }
    case 'setCustomCover':
      if (value.operation.value.cover)
        validateCustomCover(value.operation.value.cover);
      break;
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
    if (value.migration) {
      requireCondition(
        !value.error && !value.progress && !value.bookmark,
        'Migration result cannot contain an error or single-chapter result',
      );
      uint32(value.migration.copiedReadChapters);
      uint32(value.migration.copiedBookmarks);
      requireCondition(
        value.migration.copiedReadChapters <= MIGRATION_CHAPTER_LIMIT &&
          value.migration.copiedBookmarks <= MIGRATION_CHAPTER_LIMIT,
        'Migration result exceeds chapter budget',
      );
    }
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
    Number.isInteger(value.fit) &&
      value.fit >= pb.ReaderFit.CONTAIN &&
      value.fit <= pb.ReaderFit.HEIGHT,
    'Unknown reader fit',
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
  if (value.fit !== undefined)
    requireCondition(
      Number.isInteger(value.fit) &&
        value.fit >= pb.ReaderFit.CONTAIN &&
        value.fit <= pb.ReaderFit.HEIGHT,
      'Unknown reader fit override',
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

export function validateFavoriteSource(value: pb.FavoriteSource): void {
  validId(value.packageName);
  validSourceId(value.sourceId);
  requireCondition(
    value.sourceName.length > 0 &&
      value.sourceName.length <= 256 &&
      value.sourceLang.length > 0 &&
      value.sourceLang.length <= 64,
    'Invalid favorite Source display metadata',
  );
}

export function validateFavoriteSources(values: pb.FavoriteSource[]): void {
  requireCondition(
    values.length <= FAVORITE_SOURCE_LIMIT,
    'Favorite Sources exceed their count budget',
  );
  const identities = new Set<string>();
  for (const source of values) {
    validateFavoriteSource(source);
    const identity = JSON.stringify([source.packageName, source.sourceId]);
    requireCondition(
      !identities.has(identity),
      'Duplicate favorite Source identity',
    );
    identities.add(identity);
  }
}

export function validateInstalledExtension(value: pb.InstalledExtension): void {
  validateExtensionCatalogUrl(value.catalogUrl);
  buildIdSchema.parse(value.repoId);
  validId(value.packageName);
  buildIdSchema.parse(value.buildId);
  z.string()
    .regex(/^[a-f0-9]{64}$/)
    .parse(value.bundleSha256);
  requireCondition(
    typeof value.enabled === 'boolean',
    'Invalid extension enabled state',
  );
}

export function validateInstalledExtensions(
  values: pb.InstalledExtension[],
): void {
  requireCondition(
    values.length <= INSTALLED_EXTENSION_LIMIT,
    'Installed extensions exceed their count budget',
  );
  const packages = new Set<string>();
  for (const extension of values) {
    validateInstalledExtension(extension);
    requireCondition(
      !packages.has(extension.packageName),
      'An installed package has more than one selected build',
    );
    packages.add(extension.packageName);
  }
}

export function validateExtensionRepositories(
  values: readonly pb.ExtensionRepository[],
): void {
  requireCondition(
    values.length <= EXTENSION_REPOSITORY_LIMIT,
    'Too many extension repositories',
  );
  const urls = new Set<string>();
  const ids = new Set<string>();
  for (const value of values) {
    validateCatalogReference(value);
    requireCondition(
      value.repoId !== 'keiyoushi',
      'Default repository identity is implicit',
    );
    requireCondition(
      value.name.length > 0 &&
        value.name.length <= 100 &&
        value.name === value.name.trim(),
      'Invalid repository display name',
    );
    requireCondition(
      !urls.has(value.catalogUrl) && !ids.has(value.repoId),
      'Duplicate repository URL or identity',
    );
    urls.add(value.catalogUrl);
    ids.add(value.repoId);
  }
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
  validateFavoriteSources(value.favoriteSources);
  validateInstalledExtensions(value.installedExtensions);
  validateExtensionRepositories(value.repositories);
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
          (value.manga?.overrides?.keyboard ?? defaults?.keyboard) &&
        value.effectiveReader.fit ===
          (value.manga?.overrides?.fit ?? defaults?.fit) &&
        value.effectiveReader.cropBorders ===
          (value.manga?.overrides?.cropBorders ?? defaults?.cropBorders),
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
