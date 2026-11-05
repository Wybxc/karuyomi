import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

const _metadataLimit = 96 * 1024;
const _responseLimit = 2 * 1024 * 1024;
const _pageLimit = 2048;
const _libraryPageSize = 8;
const _bookmarkPageSize = 64;
final _mangaKey = RegExp(r'^[a-f0-9]{64}$');
final _sourceId = RegExp(r'^-?\d{1,19}$');
final _minSourceId = BigInt.parse('-9223372036854775808');
final _maxSourceId = BigInt.parse('9223372036854775807');
final _categoryId = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void validateBusinessCategoryId(String value) =>
    _require(_categoryId.hasMatch(value), 'Invalid category identity');

void validateBusinessCategoryName(String value) => _require(
  value.isNotEmpty &&
      value.trim() == value &&
      value.runes.length <= 100 &&
      utf8.encode(value).length <= 256,
  'Invalid category name',
);

void validateBusinessCategoryIds(Iterable<String> values) {
  _require(values.length <= 64, 'Category associations exceed budget');
  final unique = <String>{};
  for (final id in values) {
    validateBusinessCategoryId(id);
    _require(unique.add(id), 'Duplicate category identity');
  }
}

void validateBusinessCategoryCatalog(wire.CategoryCatalog value) {
  validateBusinessRevision(value.revision);
  validateBusinessCategoryIds(value.categories.map((category) => category.id));
  for (final category in value.categories) {
    validateBusinessCategoryName(category.name);
  }
}

void validateBusinessMangaCategories(
  wire.MangaState manga,
  wire.CategoryCatalog catalog,
) {
  var previous = -1;
  for (final id in manga.categoryIds) {
    final index = catalog.categories.indexWhere(
      (category) => category.id == id,
    );
    _require(index > previous, 'Manga categories do not match catalog order');
    previous = index;
  }
}

void validateBusinessCategoryMutation(wire.CategoryMutation value) {
  validateBusinessRevision(value.expectedRevision);
  switch (value.whichOperation()) {
    case wire.CategoryMutation_Operation.createCategory:
      _require(value.createCategory.hasCategory(), 'Category is required');
      validateBusinessCategoryId(value.createCategory.category.id);
      validateBusinessCategoryName(value.createCategory.category.name);
    case wire.CategoryMutation_Operation.renameCategory:
      validateBusinessCategoryId(value.renameCategory.categoryId);
      validateBusinessCategoryName(value.renameCategory.name);
    case wire.CategoryMutation_Operation.reorderCategories:
      validateBusinessCategoryIds(value.reorderCategories.categoryIds);
    case wire.CategoryMutation_Operation.deleteCategory:
      validateBusinessCategoryId(value.deleteCategory.categoryId);
    case wire.CategoryMutation_Operation.notSet:
      throw const FormatException('Category operation is required');
  }
}

void _require(bool condition, String message) {
  if (!condition) throw FormatException(message);
}

void _identity(String value) => _require(
  value.isNotEmpty && value.length <= 200,
  'Invalid business resource identity',
);

void _key(String value) => _require(
  _mangaKey.hasMatch(value),
  'Business manga identity must be a canonical SHA-256 digest',
);

void validateBusinessChapterKey(String value) => _identity(value);

void validateBusinessBookmark(
  wire.ChapterBookmark value, {
  String? chapterKey,
}) {
  _identity(value.chapterKey);
  _require(
    chapterKey == null || value.chapterKey == chapterKey,
    'Bookmark belongs to another chapter',
  );
}

void validateBusinessBookmarkPage(
  wire.BookmarkPageResponse value, {
  required String mangaKey,
  String afterKey = '',
}) {
  _require(value.schemaVersion == 1, 'Unsupported business state schema');
  validateBusinessRevision(value.accountRevision);
  _key(value.mangaKey);
  _require(value.mangaKey == mangaKey, 'Bookmark page manga mismatch');
  _require(
    value.entries.length <= _bookmarkPageSize,
    'Bookmark page exceeds its entry budget',
  );
  if (afterKey.isNotEmpty) _identity(afterKey);
  if (value.hasError()) {
    validateBusinessError(value.error);
    _require(
      value.entries.isEmpty && value.nextKey.isEmpty,
      'Failed bookmark page cannot contain entries',
    );
  }
  // Match SQLite BINARY's UTF-8 ordering for opaque historical chapter keys.
  String order(String key) => String.fromCharCodes(utf8.encode(key));
  var previous = order(afterKey);
  for (final bookmark in value.entries) {
    validateBusinessBookmark(bookmark);
    _require(bookmark.bookmarked, 'Bookmark pages contain only saved chapters');
    final current = order(bookmark.chapterKey);
    _require(previous.compareTo(current) < 0, 'Bookmark keys must be ordered');
    previous = current;
  }
  if (value.nextKey.isNotEmpty) {
    _identity(value.nextKey);
    _require(
      value.entries.isNotEmpty &&
          value.nextKey == value.entries.last.chapterKey,
      'Bookmark cursor must identify its last entry',
    );
  }
  wire.encodeProtoJson(value, maxBytes: _responseLimit);
}

void validateBusinessChapterProgressPage(
  wire.ChapterProgressPageResponse value, {
  required String mangaKey,
  String afterKey = '',
}) {
  _require(value.schemaVersion == 1, 'Unsupported business state schema');
  validateBusinessRevision(value.accountRevision);
  _key(value.mangaKey);
  _require(value.mangaKey == mangaKey, 'Progress page manga mismatch');
  _require(
    value.entries.length <= 64,
    'Progress page exceeds its entry budget',
  );
  if (afterKey.isNotEmpty) _identity(afterKey);
  if (value.hasError()) {
    validateBusinessError(value.error);
    _require(
      value.entries.isEmpty && value.nextKey.isEmpty,
      'Failed progress page cannot contain entries',
    );
  }
  String order(String key) => String.fromCharCodes(utf8.encode(key));
  var previous = order(afterKey);
  for (final progress in value.entries) {
    validateBusinessProgress(progress);
    final current = order(progress.chapterKey);
    _require(
      previous.compareTo(current) < 0,
      'Progress chapter keys must be ordered',
    );
    previous = current;
  }
  if (value.nextKey.isNotEmpty) {
    _identity(value.nextKey);
    _require(
      value.entries.isNotEmpty &&
          value.nextKey == value.entries.last.chapterKey,
      'Progress cursor must identify its last entry',
    );
  }
  wire.encodeProtoJson(value, maxBytes: _responseLimit);
}

void validateBusinessRevision(int value) => _require(
  value >= 0 && value <= 0xffffffff,
  'Business revision or epoch exceeds uint32',
);

void validateBusinessMetadata(wire.LibraryMetadata value) {
  _identity(value.packageName);
  _require(_sourceId.hasMatch(value.sourceId), 'Invalid Source identity');
  final id = BigInt.parse(value.sourceId);
  _require(
    id >= _minSourceId && id <= _maxSourceId,
    'Source identity exceeds signed int64',
  );
  _require(
    value.sourceName.isNotEmpty &&
        value.sourceName.length <= 256 &&
        value.sourceLang.isNotEmpty &&
        value.sourceLang.length <= 64,
    'Invalid Source metadata',
  );
  _require(value.hasManga(), 'Library metadata requires a Source manga');
  final manga = value.manga;
  _require(
    manga.url.isNotEmpty && manga.url.length <= 16384 && manga.title.isNotEmpty,
    'Explicit manga reference and title are required',
  );
  _require(
    manga.updateStrategy == '' ||
        manga.updateStrategy == 'ALWAYS_UPDATE' ||
        manga.updateStrategy == 'ONLY_FETCH_ONCE',
    'Unknown manga update strategy',
  );
  if (manga.hasMemoJson()) wire.checkSourceMemo(manga.memoJson);
  wire.encodeProtoJson(value, maxBytes: _metadataLimit);
}

void validateBusinessAnchor(wire.ReadingAnchor value) {
  _identity(value.chapterKey);
  _identity(value.pageKey);
  _identity(value.manifestVersion);
  validateBusinessRevision(value.pageIndexHint);
  _require(
    value.pageIndexHint < _pageLimit &&
        [
          value.normalizedOffset,
          value.normalizedX,
          value.viewportX,
          value.viewportY,
        ].every(
          (coordinate) =>
              coordinate.isFinite && coordinate >= 0 && coordinate <= 1,
        ),
    'Invalid reading anchor',
  );
}

void validateBusinessProgress(
  wire.ChapterProgressState value, {
  String? chapterKey,
}) {
  _identity(value.chapterKey);
  validateBusinessRevision(value.epoch);
  _require(
    chapterKey == null || value.chapterKey == chapterKey,
    'Progress belongs to another chapter',
  );
  if (value.hasCurrent()) {
    validateBusinessAnchor(value.current);
    _require(
      value.current.chapterKey == value.chapterKey,
      'Current anchor belongs to another chapter',
    );
  }
  _require(
    !value.hasFurthest() || value.hasCurrent(),
    'Furthest requires a current anchor',
  );
  if (value.hasFurthest()) {
    validateBusinessAnchor(value.furthest);
    _require(
      value.furthest.chapterKey == value.chapterKey,
      'Furthest anchor belongs to another chapter',
    );
  }
}

void validateBusinessManga(wire.MangaState value) {
  _key(value.mangaKey);
  validateBusinessRevision(value.revision);
  validateBusinessRevision(value.addedAtSeconds);
  validateBusinessCategoryIds(value.categoryIds);
  if (value.hasMetadata()) {
    validateBusinessMetadata(value.metadata);
    final expectedKey = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              value.metadata.packageName,
              value.metadata.sourceId,
              value.metadata.manga.url,
            ]),
          ),
        )
        .toString();
    _require(
      value.mangaKey == expectedKey,
      'Metadata does not match manga identity',
    );
  }
  _require(
    !value.favorite || value.hasMetadata(),
    'Favorite manga requires Source metadata',
  );
  if (value.hasResume()) _identity(value.resume.chapterKey);
}

void validateBusinessError(wire.BusinessStateError value) => _require(
  value.code.value >=
          wire
              .BusinessStateErrorCode
              .BUSINESS_STATE_ERROR_CODE_INVALID_INPUT
              .value &&
      value.code.value <=
          wire
              .BusinessStateErrorCode
              .BUSINESS_STATE_ERROR_CODE_LIMIT_EXCEEDED
              .value &&
      value.message.isNotEmpty &&
      value.message.length <= 1024,
  'Invalid business state error',
);

void validateBusinessLibraryPage(wire.LibraryPageResponse value) {
  _require(value.schemaVersion == 1, 'Unsupported business state schema');
  validateBusinessRevision(value.accountRevision);
  _require(
    value.entries.length <= _libraryPageSize,
    'Library page exceeds its entry budget',
  );
  if (value.hasError()) {
    validateBusinessError(value.error);
    _require(
      value.entries.isEmpty && value.nextKey.isEmpty,
      'Failed library page cannot contain entries',
    );
  }
  _require(
    value.hasError() || value.hasCategoryCatalog(),
    'Missing category catalog',
  );
  if (value.hasCategoryCatalog()) {
    validateBusinessCategoryCatalog(value.categoryCatalog);
    _require(
      value.categoryCatalog.revision <= value.accountRevision,
      'Category catalog exceeds account revision',
    );
  }
  String? previousKey;
  for (final manga in value.entries) {
    validateBusinessManga(manga);
    _require(
      manga.revision <= value.accountRevision,
      'Manga exceeds account revision',
    );
    validateBusinessMangaCategories(manga, value.categoryCatalog);
    _require(manga.favorite, 'Library entries must be favorites');
    _require(
      previousKey == null || previousKey.compareTo(manga.mangaKey) < 0,
      'Library page keys must be unique and ordered',
    );
    previousKey = manga.mangaKey;
  }
  if (value.nextKey.isNotEmpty) {
    _key(value.nextKey);
    _require(
      value.entries.isNotEmpty && value.nextKey == value.entries.last.mangaKey,
      'Library cursor must identify its last entry',
    );
  }
  wire.encodeProtoJson(value, maxBytes: _responseLimit);
}

void validateBusinessMangaKey(String value) => _key(value);

void validateBusinessReaderSettings(wire.ReaderSettings value) {
  _require(
    value.mode.value >= 1 && value.mode.value <= 4,
    'Invalid reader mode',
  );
  _require(
    value.pageLayout.value >= 1 && value.pageLayout.value <= 3,
    'Invalid reader page layout',
  );
  _require(value.fit.value >= 1 && value.fit.value <= 3, 'Invalid reader fit');
  _require(
    value.background.value >= 1 && value.background.value <= 3,
    'Invalid reader background',
  );
  _require(
    value.dimPercent >= 0 && value.dimPercent <= 80,
    'Invalid reader dimming',
  );
  for (final preset in [value.tapZones, value.keyboard]) {
    _require(
      preset.value >= 1 && preset.value <= 3,
      'Invalid reader input preset',
    );
  }
}

void validateBusinessReaderOverrides(wire.ReaderSettingsOverride value) {
  if (value.hasMode()) {
    _require(
      value.mode.value >= 1 && value.mode.value <= 4,
      'Invalid reader mode override',
    );
  }
  if (value.hasPageLayout()) {
    _require(
      value.pageLayout.value >= 1 && value.pageLayout.value <= 3,
      'Invalid reader page layout override',
    );
  }
  if (value.hasFit()) {
    _require(
      value.fit.value >= 1 && value.fit.value <= 3,
      'Invalid reader fit override',
    );
  }
  if (value.hasBackground()) {
    _require(
      value.background.value >= 1 && value.background.value <= 3,
      'Invalid reader background override',
    );
  }
  if (value.hasDimPercent()) {
    _require(
      value.dimPercent >= 0 && value.dimPercent <= 80,
      'Invalid reader dimming override',
    );
  }
  if (value.hasTapZones()) {
    _require(
      value.tapZones.value >= 1 && value.tapZones.value <= 3,
      'Invalid reader tap preset override',
    );
  }
  if (value.hasKeyboard()) {
    _require(
      value.keyboard.value >= 1 && value.keyboard.value <= 3,
      'Invalid reader keyboard preset override',
    );
  }
}

void validateBusinessGlobalSettings(wire.GlobalSettingsValues value) {
  _require(
    value.theme.value >= 1 && value.theme.value <= 3,
    'Invalid application theme',
  );
  _require(value.hasReader(), 'Missing global reader defaults');
  validateBusinessReaderSettings(value.reader);
}

void validateBusinessSettingsMutation(wire.SettingsMutation value) {
  _require(value.schemaVersion == 1, 'Unsupported settings schema');
  validateBusinessRevision(value.expectedRevision);
  switch (value.whichOperation()) {
    case wire.SettingsMutation_Operation.setGlobal:
      validateBusinessGlobalSettings(value.setGlobal);
    case wire.SettingsMutation_Operation.setManga:
      _key(value.setManga.mangaKey);
      _require(value.setManga.hasOverrides(), 'Missing reader overrides');
      validateBusinessReaderOverrides(value.setManga.overrides);
    case wire.SettingsMutation_Operation.notSet:
      throw const FormatException('Settings operation is required');
  }
  wire.encodeProtoJson(value);
}

void validateBusinessSettingsResponse(
  wire.SettingsResponse value, {
  String? mangaKey,
}) {
  _require(value.schemaVersion == 1, 'Unsupported settings schema');
  validateBusinessRevision(value.accountRevision);
  if (mangaKey != null) _key(mangaKey);
  if (value.hasError()) {
    validateBusinessError(value.error);
    // Authentication and transport failures need not carry a state snapshot.
    if (!value.hasGlobal() &&
        !value.hasManga() &&
        !value.hasEffectiveReader()) {
      return;
    }
  }
  _require(
    value.hasGlobal() && value.hasEffectiveReader(),
    'Missing confirmed settings',
  );
  final global = value.global;
  validateBusinessRevision(global.revision);
  _require(
    global.revision <= value.accountRevision,
    'Global settings exceed account revision',
  );
  _require(global.hasValues(), 'Missing global settings values');
  validateBusinessGlobalSettings(global.values);
  _require(
    value.hasManga() == (mangaKey != null),
    'Settings response scope mismatch',
  );
  wire.ReaderSettingsOverride? overrides;
  if (mangaKey != null) {
    final manga = value.manga;
    _key(manga.mangaKey);
    _require(manga.mangaKey == mangaKey, 'Settings manga identity mismatch');
    validateBusinessRevision(manga.revision);
    _require(
      manga.revision <= value.accountRevision,
      'Manga settings exceed account revision',
    );
    _require(manga.hasOverrides(), 'Missing manga reader overrides');
    validateBusinessReaderOverrides(manga.overrides);
    overrides = manga.overrides;
  }
  validateBusinessReaderSettings(value.effectiveReader);
  _require(
    value.effectiveReader.mode ==
            (overrides?.hasMode() == true
                ? overrides!.mode
                : global.values.reader.mode) &&
        value.effectiveReader.pageLayout ==
            (overrides?.hasPageLayout() == true
                ? overrides!.pageLayout
                : global.values.reader.pageLayout) &&
        value.effectiveReader.background ==
            (overrides?.hasBackground() == true
                ? overrides!.background
                : global.values.reader.background) &&
        value.effectiveReader.dimPercent ==
            (overrides?.hasDimPercent() == true
                ? overrides!.dimPercent
                : global.values.reader.dimPercent) &&
        value.effectiveReader.tapZones ==
            (overrides?.hasTapZones() == true
                ? overrides!.tapZones
                : global.values.reader.tapZones) &&
        value.effectiveReader.keyboard ==
            (overrides?.hasKeyboard() == true
                ? overrides!.keyboard
                : global.values.reader.keyboard) &&
        value.effectiveReader.fit ==
            (overrides?.hasFit() == true
                ? overrides!.fit
                : global.values.reader.fit) &&
        value.effectiveReader.cropBorders ==
            (overrides?.hasCropBorders() == true
                ? overrides!.cropBorders
                : global.values.reader.cropBorders),
    'Effective reader settings do not match confirmed values',
  );
  wire.encodeProtoJson(value, maxBytes: _responseLimit);
}
