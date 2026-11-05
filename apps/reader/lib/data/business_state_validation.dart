import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

const _metadataLimit = 96 * 1024;
const _responseLimit = 2 * 1024 * 1024;
const _pageLimit = 2048;
const _libraryPageSize = 8;
final _mangaKey = RegExp(r'^[a-f0-9]{64}$');
final _sourceId = RegExp(r'^-?\d{1,19}$');
final _minSourceId = BigInt.parse('-9223372036854775808');
final _maxSourceId = BigInt.parse('9223372036854775807');

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
        value.normalizedOffset.isFinite &&
        value.normalizedOffset >= 0 &&
        value.normalizedOffset <= 1,
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
  _require(value.hasCurrent(), 'Progress requires a current anchor');
  validateBusinessAnchor(value.current);
  _require(
    value.current.chapterKey == value.chapterKey,
    'Current anchor belongs to another chapter',
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
  String? previousKey;
  for (final manga in value.entries) {
    validateBusinessManga(manga);
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
