import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:uuid/uuid.dart';

import '../runtime/cover_transport.dart';
import '../runtime/runtime_platform_types.dart';
import 'business_state_validation.dart';
import 'reading_progress.dart';
import 'source_preferences_validation.dart';

part 'business_state_migration.dart';

const _schemaVersion = 1;
const _responseLimit = 2 * 1024 * 1024;

final class BusinessStateException implements Exception {
  BusinessStateException(
    this.error, {
    this.manga,
    this.progress,
    this.bookmark,
    this.conflictedChapterKey,
  });
  final wire.BusinessStateError error;
  final wire.MangaState? manga;
  final wire.ChapterProgressState? progress;
  final wire.ChapterBookmark? bookmark;
  final String? conflictedChapterKey;
  bool get staleEpoch =>
      error.code ==
      wire.BusinessStateErrorCode.BUSINESS_STATE_ERROR_CODE_STALE_EPOCH;
  bool get conflict =>
      error.code ==
          wire
              .BusinessStateErrorCode
              .BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT ||
      staleEpoch;
  @override
  String toString() => error.message;
}

final class BusinessPendingMutationException extends StateError {
  BusinessPendingMutationException(this.mangaKey, String message)
    : super(message);
  final String mangaKey;
}

final class BusinessStateTransportException implements Exception {
  const BusinessStateTransportException(this.status);
  final int status;
  @override
  String toString() => 'Business state request failed ($status)';
}

final class _PendingMutation {
  _PendingMutation(
    this.fingerprint,
    this.request,
    this.body,
    this.accountRevision,
    this.requireExactRevision,
    this.coverBytes,
  );
  final String fingerprint;
  final wire.StateMutation request;
  final String body;
  final int accountRevision;
  final bool requireExactRevision;
  final Uint8List? coverBytes;
  bool rejected = false;
  bool sent = false;
  BusinessStateException? failure;
}

final class BusinessLibrarySnapshot {
  BusinessLibrarySnapshot(this.entries, this.categoryCatalog);
  final List<wire.MangaState> entries;
  final wire.CategoryCatalog categoryCatalog;
}

final class BusinessBookmarksSnapshot {
  BusinessBookmarksSnapshot({
    required this.manga,
    required this.accountRevision,
    required this.entries,
  });
  final wire.MangaState manga;
  final int accountRevision;
  final List<wire.ChapterBookmark> entries;
}

final class BusinessChapterProgressSnapshot {
  BusinessChapterProgressSnapshot({
    required this.manga,
    required this.accountRevision,
    required this.entries,
  });
  final wire.MangaState manga;
  final int accountRevision;
  final List<wire.ChapterProgressState> entries;
}

final class _PendingCategoryMutation {
  _PendingCategoryMutation(this.fingerprint, this.request, this.body);
  final String fingerprint;
  final wire.CategoryMutation request;
  final String body;
  BusinessStateException? rejection;
}

final class _PendingSettingsMutation {
  _PendingSettingsMutation(this.fingerprint, this.request, this.body);
  final String fingerprint;
  final wire.SettingsMutation request;
  final String body;
  BusinessStateException? rejection;
}

final class _PendingSourcePreferencesMutation {
  _PendingSourcePreferencesMutation(this.fingerprint, this.request, this.body);
  final String fingerprint;
  final wire.SourcePreferencesMutation request;
  final String body;
  BusinessStateException? rejection;
}

/// A session cache bound to one confirmed origin and Access subject. All
/// repositories share it so their writes use one revision per manga.
final class BusinessStateClient {
  BusinessStateClient({
    required ApiFetch api,
    required ProgressIdentity identity,
    CoverTransport? covers,
  }) : this._(api, identity, covers);

  BusinessStateClient._(this._api, this.identity, this._covers);

  ApiFetch _api;
  ApiFetch get api => _api;
  final ProgressIdentity identity;
  CoverTransport? _covers;
  final _changes = StreamController<void>.broadcast(sync: true);
  final _manga = <String, wire.MangaState>{};
  final _remoteRevisions = <String, int>{};
  final _pending = <String, _PendingMutation>{};
  final _queues = <String, Future<void>>{};
  final _migrationClaims = <String, Object>{};
  final _uuid = const Uuid();
  final _pendingSettings = <String, _PendingSettingsMutation>{};
  final _sourcePreferences = <String, wire.SourcePreferencesResponse>{};
  final _pendingSourcePreferences =
      <String, _PendingSourcePreferencesMutation>{};
  final _settings = <String, wire.SettingsResponse>{};
  final _settingsChanges = StreamController<wire.SettingsResponse>.broadcast(
    sync: true,
  );
  List<wire.MangaState> _library = const [];
  wire.CategoryCatalog _catalog = wire.CategoryCatalog()..freeze();
  wire.CategoryCatalog _libraryCatalog = wire.CategoryCatalog()..freeze();
  _PendingCategoryMutation? _pendingCategory;
  int _accountRevision = 0;
  bool _closed = false;
  Future<void>? _refreshing;

  bool hasOnlyLocalChangesSince(
    String key, {
    required int basedOnRevision,
    required int revision,
  }) =>
      _manga[key]?.revision == revision &&
      basedOnRevision <= revision &&
      basedOnRevision >= (_remoteRevisions[key] ?? 0);

  void rebindApi(
    ApiFetch api, {
    required ProgressIdentity verifiedIdentity,
    CoverTransport? covers,
  }) {
    _ensureOpen();
    if (verifiedIdentity.key != identity.key) {
      throw ArgumentError('A business session cannot change identity');
    }
    _api = api;
    _covers = covers;
  }

  Map<String, String> get _headers => {
    'X-App-Request': '1',
    'X-App-Subject': identity.subject,
    'Accept': 'application/json',
  };

  Stream<List<wire.MangaState>> watchLibrary() =>
      watchLibrarySnapshot().map((view) => view.entries);

  BusinessLibrarySnapshot get _librarySnapshot =>
      BusinessLibrarySnapshot(_library, _libraryCatalog);

  Stream<BusinessLibrarySnapshot> watchLibrarySnapshot() =>
      Stream.multi((sink) {
        final subscription = _changes.stream.listen(
          (_) => sink.add(_librarySnapshot),
          onError: sink.addError,
          onDone: sink.close,
        );
        sink.onCancel = subscription.cancel;
        refreshLibrary().then(
          (_) {
            if (!_closed) sink.add(_librarySnapshot);
          },
          onError: (Object error, StackTrace stack) =>
              sink.addError(error, stack),
        );
      });

  Stream<wire.MangaState?> watchManga(String key) => Stream.multi((sink) {
    final subscription = _changes.stream.listen(
      (_) => sink.add(_manga[key]),
      onError: sink.addError,
      onDone: sink.close,
    );
    sink.onCancel = subscription.cancel;
    readManga(key).then(
      (value) => sink.add(value.hasManga() ? value.manga : null),
      onError: (Object error, StackTrace stack) => sink.addError(error, stack),
    );
  });

  Future<void> refreshLibrary() {
    _ensureOpen();
    return _refreshing ??= _refreshLibrary().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<void> _refreshLibrary() async {
    // A changing shelf invalidates its cursor. Restart a bounded number of
    // times rather than mixing pages from separate account revisions.
    for (var attempt = 0; attempt < 3; attempt++) {
      final entries = <wire.MangaState>[];
      final cursors = <String>{};
      String afterKey = '';
      int? revision;
      wire.CategoryCatalog? catalog;
      var restart = false;
      do {
        final path = Uri(
          path: '/api/library',
          queryParameters: {
            if (afterKey.isNotEmpty) 'afterKey': afterKey,
            if (revision != null) 'revision': '$revision',
          },
        ).toString();
        final reply = await _get(path);
        final page = wire.decodeProtoJson(
          wire.LibraryPageResponse(),
          jsonDecode(reply.body),
          maxBytes: _responseLimit,
        );
        validateBusinessLibraryPage(page);
        if (page.hasError()) {
          final error = BusinessStateException(page.error);
          if (error.conflict) {
            restart = true;
            break;
          }
          throw error;
        }
        _success(reply);
        if ((revision != null && revision != page.accountRevision) ||
            page.accountRevision < _accountRevision) {
          restart = true;
          break;
        }
        if (catalog != null && catalog != page.categoryCatalog) {
          throw const FormatException(
            'Library pages contain different category catalogs',
          );
        }
        catalog = page.categoryCatalog;
        revision = page.accountRevision;
        for (final manga in page.entries) {
          if (afterKey.isNotEmpty && manga.mangaKey.compareTo(afterKey) <= 0) {
            throw const FormatException('Library page predates its cursor');
          }
          if (!manga.favorite || !manga.hasMetadata()) {
            throw const FormatException(
              'Library contains a non-favorite or missing metadata',
            );
          }
          if (entries.any((entry) => entry.mangaKey == manga.mangaKey)) {
            throw const FormatException('Duplicate library entry');
          }
          entries.add(manga.deepCopy()..freeze());
        }
        afterKey = page.nextKey;
        if (afterKey.isNotEmpty && !cursors.add(afterKey)) {
          throw const FormatException('Library cursor repeated');
        }
        if (entries.length > 10000 || cursors.length > 1000) {
          throw const FormatException('Library exceeds session budget');
        }
      } while (afterKey.isNotEmpty);
      if (restart) continue;
      _ensureOpen();
      if (catalog!.revision < _catalog.revision) continue;
      _acceptCatalog(catalog);
      _libraryCatalog = _catalog;
      _accountRevision = revision ?? _accountRevision;
      final keys = entries.map((entry) => entry.mangaKey).toSet();
      _manga.removeWhere((key, value) => value.favorite && !keys.contains(key));
      for (final entry in entries) {
        _accept(entry);
      }
      entries.sort(_compareShelf);
      _library = List.unmodifiable(entries);
      _pending.removeWhere(
        (_, pending) =>
            pending.rejected &&
            !pending.request.hasMigrateFrom() &&
            _mutationChapter(pending.request) == null,
      );
      if (_pendingCategory?.rejection != null) _pendingCategory = null;
      _changes.add(null);
      return;
    }
    throw StateError('Library changed repeatedly; refresh again');
  }

  ({String chapterKey, bool bookmarked, int basedOnRevision, bool retryable})?
  pendingBookmark(String key) {
    if (_closed) return null;
    final pending = _pending[key];
    if (pending == null || !pending.request.hasSetBookmark()) return null;
    return (
      chapterKey: pending.request.setBookmark.chapterKey,
      bookmarked: pending.request.setBookmark.bookmarked,
      basedOnRevision: pending.request.expectedRevision,
      retryable: !pending.rejected,
    );
  }

  /// Read the manga CAS and every bookmark page at one account revision.
  Future<BusinessBookmarksSnapshot> readBookmarks(
    String key, {
    bool Function()? shouldContinue,
    bool updateSession = true,
  }) => _serial(key, () async {
    for (var attempt = 0; attempt < 3; attempt++) {
      _checkContinue(shouldContinue);
      final state = await _readManga(
        key,
        shouldContinue: shouldContinue,
        accept: updateSession,
      );
      _checkContinue(shouldContinue);
      final revision = state.accountRevision;
      final entries = <wire.ChapterBookmark>[];
      final cursors = <String>{};
      var afterKey = '';
      var restart = false;
      do {
        final path = Uri(
          path: '/api/state/manga/$key/bookmarks',
          queryParameters: {
            if (afterKey.isNotEmpty) 'afterKey': afterKey,
            'revision': '$revision',
          },
        ).toString();
        _checkContinue(shouldContinue);
        final reply = await _get(path);
        _checkContinue(shouldContinue);
        final page = wire.decodeProtoJson(
          wire.BookmarkPageResponse(),
          jsonDecode(reply.body),
          maxBytes: _responseLimit,
        );
        validateBusinessBookmarkPage(page, mangaKey: key, afterKey: afterKey);
        if (page.hasError()) {
          final failure = BusinessStateException(page.error);
          if (failure.conflict) {
            restart = true;
            break;
          }
          throw failure;
        }
        _success(reply);
        if (page.accountRevision != revision || revision < _accountRevision) {
          restart = true;
          break;
        }
        entries.addAll(page.entries.map((entry) => entry.deepCopy()..freeze()));
        afterKey = page.nextKey;
        if (afterKey.isNotEmpty && !cursors.add(afterKey)) {
          throw const FormatException('Bookmark cursor repeated');
        }
        if (entries.length > 10000 || cursors.length > 1000) {
          throw const FormatException('Bookmarks exceed session budget');
        }
      } while (afterKey.isNotEmpty);
      if (restart) continue;
      _ensureOpen();
      final rejected = _pending[key];
      if (updateSession &&
          rejected != null &&
          rejected.rejected &&
          rejected.request.hasSetBookmark()) {
        _pending.remove(key);
      }
      return BusinessBookmarksSnapshot(
        manga: state.manga.deepCopy()..freeze(),
        accountRevision: revision,
        entries: List.unmodifiable(entries),
      );
    }
    throw StateError('Bookmarks changed repeatedly; refresh again');
  });

  /// Read all stored chapter statuses and the manga CAS at one account revision.
  Future<BusinessChapterProgressSnapshot> readChapterProgress(
    String key, {
    bool Function()? shouldContinue,
    bool updateSession = true,
  }) => _serial(key, () async {
    for (var attempt = 0; attempt < 3; attempt++) {
      _checkContinue(shouldContinue);
      final state = await _readManga(
        key,
        shouldContinue: shouldContinue,
        accept: updateSession,
      );
      _checkContinue(shouldContinue);
      final revision = state.accountRevision;
      final entries = <wire.ChapterProgressState>[];
      final cursors = <String>{};
      var afterKey = '';
      var restart = false;
      do {
        final path = Uri(
          path: '/api/state/manga/$key/progress',
          queryParameters: {
            if (afterKey.isNotEmpty) 'afterKey': afterKey,
            'revision': '$revision',
          },
        ).toString();
        _checkContinue(shouldContinue);
        final reply = await _get(path);
        _checkContinue(shouldContinue);
        final page = wire.decodeProtoJson(
          wire.ChapterProgressPageResponse(),
          jsonDecode(reply.body),
          maxBytes: _responseLimit,
        );
        validateBusinessChapterProgressPage(
          page,
          mangaKey: key,
          afterKey: afterKey,
        );
        if (page.hasError()) {
          final failure = BusinessStateException(page.error);
          if (failure.conflict) {
            restart = true;
            break;
          }
          throw failure;
        }
        _success(reply);
        if (page.accountRevision != revision || revision < _accountRevision) {
          restart = true;
          break;
        }
        entries.addAll(page.entries.map((entry) => entry.deepCopy()..freeze()));
        afterKey = page.nextKey;
        if (afterKey.isNotEmpty && !cursors.add(afterKey)) {
          throw const FormatException('Progress cursor repeated');
        }
        if (entries.length > 10000 || cursors.length > 1000) {
          throw const FormatException(
            'Chapter progress exceeds session budget',
          );
        }
      } while (afterKey.isNotEmpty);
      if (restart) continue;
      _ensureOpen();
      final rejected = _pending[key];
      if (updateSession &&
          rejected != null &&
          rejected.rejected &&
          rejected.request.hasSetChapterRead()) {
        _pending.remove(key);
      }
      return BusinessChapterProgressSnapshot(
        manga: state.manga.deepCopy()..freeze(),
        accountRevision: revision,
        entries: List.unmodifiable(entries),
      );
    }
    throw StateError('Chapter progress changed repeatedly; refresh again');
  });

  Future<wire.MangaStateResponse> readManga(
    String key, {
    String? chapterKey,
    bool Function()? shouldContinue,
    bool updateSession = true,
  }) => _serial(
    key,
    () => _readManga(
      key,
      chapterKey: chapterKey,
      shouldContinue: shouldContinue,
      accept: updateSession,
    ),
  );

  /// Inspect foreground state without advancing a writer's CAS view or
  /// resolving a rejected mutation owned by another reader or repository.
  Future<wire.MangaStateResponse> inspectManga(
    String key, {
    required String chapterKey,
  }) => _serial(
    key,
    () => _readManga(key, chapterKey: chapterKey, accept: false),
  );

  Future<wire.MangaStateResponse> _readManga(
    String key, {
    String? chapterKey,
    bool accept = true,
    bool Function()? shouldContinue,
    int? knownLocalRevision,
  }) async {
    _checkContinue(shouldContinue);
    if (chapterKey != null) validateBusinessChapterKey(chapterKey);
    final path = Uri(
      path: '/api/state/manga/$key',
      queryParameters: {'chapterKey': ?chapterKey},
    ).toString();
    final reply = await _get(path);
    _checkContinue(shouldContinue);
    final value = wire.decodeProtoJson(
      wire.MangaStateResponse(),
      jsonDecode(reply.body),
      maxBytes: _responseLimit,
    );
    _version(value.schemaVersion);
    validateBusinessRevision(value.accountRevision);
    if (value.hasError()) {
      validateBusinessError(value.error);
      throw BusinessStateException(value.error);
    }
    _success(reply);
    if (!value.hasManga() ||
        value.manga.mangaKey != key ||
        (value.hasProgress() && value.progress.chapterKey != chapterKey) ||
        (chapterKey != null &&
            (!value.hasBookmark() ||
                value.bookmark.chapterKey != chapterKey)) ||
        (chapterKey == null && value.hasBookmark())) {
      throw const FormatException('Business state response identity mismatch');
    }
    validateBusinessManga(value.manga);
    if (value.hasBookmark()) {
      validateBusinessBookmark(value.bookmark, chapterKey: chapterKey);
    }
    _validateCatalog(
      value.hasCategoryCatalog(),
      value.categoryCatalog,
      value.accountRevision,
    );
    validateBusinessMangaCategories(value.manga, value.categoryCatalog);
    if (value.hasProgress()) {
      validateBusinessProgress(value.progress, chapterKey: chapterKey);
    }
    if (value.manga.revision < (_manga[key]?.revision ?? 0) ||
        value.accountRevision < _accountRevision ||
        value.accountRevision < value.manga.revision) {
      throw StateError('Business state response predates this session');
    }
    if (value.categoryCatalog.revision < _catalog.revision) {
      throw StateError('Business category response predates this session');
    }
    if (!accept) return value;
    _acceptCatalog(value.categoryCatalog);
    _accept(value.manga, local: value.manga.revision == knownLocalRevision);
    _accountRevision = value.accountRevision > _accountRevision
        ? value.accountRevision
        : _accountRevision;
    await _updateLibraryConfirmed(value.manga, value.categoryCatalog);
    _ensureOpen();
    final rejected = _pending[key];
    if (rejected != null &&
        rejected.rejected &&
        !rejected.request.hasMigrateFrom()) {
      final rejectedChapter = _mutationChapter(rejected.request);
      // A shelf/resume read cannot resolve a reader's stale chapter view.
      // Only loading that chapter explicitly permits a new progress mutation.
      if (rejectedChapter == null || rejectedChapter == chapterKey) {
        _pending.remove(key);
      }
    }
    _changes.add(null);
    return value;
  }

  ({
    wire.CustomCover? cover,
    Uint8List? bytes,
    int basedOnRevision,
    bool retryable,
  })?
  pendingCover(String key) {
    _ensureOpen();
    final pending = _pending[key];
    if (pending == null || !pending.request.hasSetCustomCover()) return null;
    return (
      cover: pending.request.setCustomCover.hasCover()
          ? pending.request.setCustomCover.cover
          : null,
      bytes: pending.coverBytes,
      basedOnRevision: pending.request.expectedRevision,
      retryable: !pending.rejected,
    );
  }

  Future<wire.StateMutationResponse> retryCover(String key) => _serial(key, () {
    final pending = _pending[key];
    if (pending == null || !pending.request.hasSetCustomCover()) {
      throw StateError('No pending custom cover operation');
    }
    return _send(pending);
  });

  bool hasPendingMetadata(String key) =>
      !_closed && (_pending[key]?.request.hasUpdateMetadata() ?? false);

  /// Explicitly retries only the original metadata command, with its UUID and CAS.
  Future<wire.StateMutationResponse> retryMetadata(String key) =>
      _serial(key, () {
        final pending = _pending[key];
        if (pending == null || !pending.request.hasUpdateMetadata()) {
          throw StateError('No pending metadata operation');
        }
        return _send(pending);
      });

  Future<Uint8List> readCover(wire.CustomCover cover) async {
    _ensureOpen();
    validateBusinessCustomCover(cover);
    final transport = _covers;
    if (transport == null) throw StateError('Cover transport is unavailable');
    final bytes = await transport.readCover(
      assetId: cover.assetId,
      subject: identity.subject,
      sha256: cover.sha256,
      byteLength: cover.byteLength,
    );
    _ensureOpen();
    return bytes;
  }

  /// Operation objects contain no transport identity or revision. A failed
  /// attempt retains its exact request and UUID, including after a lost reply.
  Future<wire.StateMutationResponse> mutate(
    wire.StateMutation operation, {
    int? basedOnRevision,
    bool requireExactRevision = false,
    bool allowPendingReplay = true,
    Uint8List? coverBytes,
  }) {
    final command = operation.deepCopy();
    if (command.hasMigrateFrom()) {
      throw ArgumentError('Use the migration command with both manga queues');
    }
    _assertNoMigration(command.mangaKey);
    if (command.mangaKey.isEmpty) throw ArgumentError('Missing manga key');
    command.clearMutationId();
    command.clearExpectedRevision();
    command.schemaVersion = _schemaVersion;
    if (requireExactRevision) {
      if (basedOnRevision == null) {
        throw ArgumentError('Exact mutation requires its confirmed revision');
      }
      validateBusinessRevision(basedOnRevision);
    }
    if (command.hasSetBookmark()) {
      validateBusinessChapterKey(command.setBookmark.chapterKey);
      if (basedOnRevision == null) {
        throw ArgumentError('Bookmark requires its confirmed revision');
      }
      validateBusinessRevision(basedOnRevision);
    }
    if (command.hasSetChapterRead()) {
      validateBusinessChapterKey(command.setChapterRead.chapterKey);
      if (!requireExactRevision) {
        throw ArgumentError('Chapter read changes require an exact revision');
      }
    }
    if (command.hasSetCustomCover()) {
      if (!requireExactRevision) {
        throw ArgumentError('Custom cover changes require an exact revision');
      }
      validateBusinessMangaKey(command.mangaKey);
      if (command.setCustomCover.hasCover()) {
        validateBusinessCustomCover(command.setCustomCover.cover);
        if (coverBytes == null ||
            coverBytes.length != command.setCustomCover.cover.byteLength) {
          throw ArgumentError(
            'Custom cover upload requires its original bytes',
          );
        }
        if (_covers == null) throw StateError('Cover transport is unavailable');
      } else if (coverBytes != null) {
        throw ArgumentError('Clearing a custom cover cannot upload bytes');
      }
    } else if (coverBytes != null) {
      throw ArgumentError('Only a custom cover mutation can upload bytes');
    }
    final upload = coverBytes == null
        ? null
        : Uint8List.fromList(coverBytes).asUnmodifiableView();
    final fingerprint = jsonEncode(wire.encodeProtoJson(command));
    return _serial(command.mangaKey, () async {
      _assertNoMigration(command.mangaKey);
      final previous = _pending[command.mangaKey];
      if (previous != null) {
        if (!allowPendingReplay) {
          throw BusinessPendingMutationException(
            command.mangaKey,
            '该漫画有未确认的原操作，请显式处理原操作后再更新资料。',
          );
        }
        if ((requireExactRevision || previous.requireExactRevision) &&
            (!requireExactRevision ||
                !previous.requireExactRevision ||
                previous.fingerprint != fingerprint ||
                basedOnRevision != previous.request.expectedRevision)) {
          throw BusinessPendingMutationException(
            command.mangaKey,
            '该漫画有未确认的原操作，请先处理原操作后再开始新的修改。',
          );
        }
        if ((previous.request.hasSetCategories() ||
                previous.request.hasSetBookmark()) &&
            previous.fingerprint != fingerprint) {
          throw StateError(
            previous.request.hasSetBookmark()
                ? '请先处理该漫画的未确认书签修改。'
                : '请先处理书架中的未确认分类修改。',
          );
        }
        final result = await _send(previous);
        if (previous.fingerprint == fingerprint) return result;
      }
      if (!_manga.containsKey(command.mangaKey)) {
        await _readManga(command.mangaKey);
      }
      if (basedOnRevision != null &&
          (requireExactRevision || command.hasSetCategories()
              ? basedOnRevision != _manga[command.mangaKey]!.revision
              : command.hasSetBookmark()
              ? !hasOnlyLocalChangesSince(
                  command.mangaKey,
                  basedOnRevision: basedOnRevision,
                  revision: _manga[command.mangaKey]!.revision,
                )
              : basedOnRevision < (_remoteRevisions[command.mangaKey] ?? 0))) {
        throw BusinessStateException(
          wire.BusinessStateError(
            code: wire
                .BusinessStateErrorCode
                .BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
            message: 'The reader view predates a confirmed server update',
          ),
          manga: _manga[command.mangaKey],
          conflictedChapterKey: _mutationChapter(command),
        );
      }
      command.expectedRevision = _manga[command.mangaKey]!.revision;
      command.mutationId = _uuid.v4();
      command.freeze();
      final pending = _PendingMutation(
        fingerprint,
        command,
        jsonEncode(wire.encodeProtoJson(command)),
        _accountRevision,
        requireExactRevision,
        upload,
      );
      _pending[command.mangaKey] = pending;
      return _send(pending);
    });
  }

  Future<wire.StateMutationResponse> _send(_PendingMutation pending) async {
    _ensureOpen();
    if (pending.rejected && pending.failure != null) throw pending.failure!;
    if (!pending.request.hasMigrateFrom()) {
      _assertNoMigration(pending.request.mangaKey);
    }
    final retry = pending.sent;
    pending.sent = true;
    final upload = pending.coverBytes;
    final ApiReply reply;
    if (upload != null) {
      final transport = _covers;
      if (transport == null) throw StateError('Cover transport is unavailable');
      reply = await transport.uploadCover(
        mangaKey: pending.request.mangaKey,
        mutation: pending.body,
        subject: identity.subject,
        bytes: upload,
        contentType: pending.request.setCustomCover.cover.contentType,
      );
    } else {
      reply = await api.fetchApi(
        '/api/state/mutations',
        method: 'POST',
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: pending.body,
      );
    }
    _ensureOpen();
    _budget(reply);
    final value = wire.decodeProtoJson(
      wire.StateMutationResponse(),
      jsonDecode(reply.body),
      maxBytes: _responseLimit,
    );
    _version(value.schemaVersion);
    validateBusinessRevision(value.accountRevision);
    if (value.mutationId != pending.request.mutationId ||
        (value.hasManga() &&
            value.manga.mangaKey != pending.request.mangaKey)) {
      throw const FormatException(
        'Business mutation response identity mismatch',
      );
    }
    if (value.hasBookmark()) {
      validateBusinessBookmark(
        value.bookmark,
        chapterKey: _mutationChapter(pending.request),
      );
    }
    if (value.hasError()) {
      validateBusinessError(value.error);
      if (value.hasCategoryCatalog()) {
        _validateCatalog(true, value.categoryCatalog, value.accountRevision);
      }
      if (value.hasManga()) {
        validateBusinessManga(value.manga);
        _validateCatalog(
          value.hasCategoryCatalog(),
          value.categoryCatalog,
          value.accountRevision,
        );
        validateBusinessMangaCategories(value.manga, value.categoryCatalog);
      }
      if (value.hasProgress()) {
        validateBusinessProgress(
          value.progress,
          chapterKey: _operationChapter(pending.request),
        );
      }
      pending.rejected = !value.error.retryable;
      final failure = BusinessStateException(
        value.error,
        manga: value.hasManga() ? value.manga : null,
        progress: value.hasProgress() ? value.progress : null,
        bookmark: value.hasBookmark() ? value.bookmark : null,
        conflictedChapterKey: _mutationChapter(pending.request),
      );
      pending.failure = failure;
      throw failure;
    }
    _success(reply);
    if (!value.hasManga() ||
        (pending.requireExactRevision
            ? value.manga.revision != pending.request.expectedRevision + 1
            : value.manga.revision <= pending.request.expectedRevision) ||
        value.accountRevision < value.manga.revision ||
        value.accountRevision < pending.accountRevision) {
      throw const FormatException('Mutation did not confirm a new revision');
    }
    if (pending.request.hasMigrateFrom()) {
      _validateMigrationAck(pending.request.migrateFrom, value);
    }
    validateBusinessManga(value.manga);
    _validateCatalog(
      value.hasCategoryCatalog(),
      value.categoryCatalog,
      value.accountRevision,
    );
    validateBusinessMangaCategories(value.manga, value.categoryCatalog);
    if (pending.requireExactRevision) {
      final request = pending.request;
      if (request.hasSetFavorite() &&
          value.manga.favorite != request.setFavorite.favorite) {
        throw const FormatException('Mutation response favorite mismatch');
      }
      if (request.hasSetCategories()) {
        final expected = request.setCategories.categoryIds.toSet();
        final actual = value.manga.categoryIds.toSet();
        if (expected.length != actual.length || !actual.containsAll(expected)) {
          throw const FormatException('Mutation response categories mismatch');
        }
      }
    }
    if (!_coverMatches(pending.request, value.manga)) {
      throw const FormatException('Mutation response custom cover mismatch');
    }
    final expectedChapter = _operationChapter(pending.request);
    final chapterRead = pending.request.hasSetChapterRead()
        ? pending.request.setChapterRead
        : null;
    if (chapterRead != null &&
        (!value.hasProgress() ||
            value.progress.completed != chapterRead.read ||
            value.progress.epoch == 0 ||
            (!chapterRead.read &&
                (value.progress.hasCurrent() ||
                    value.progress.hasFurthest())))) {
      throw const FormatException(
        'Mutation response chapter read state mismatch',
      );
    }
    final bookmark = pending.request.hasSetBookmark()
        ? pending.request.setBookmark
        : null;
    if (bookmark != null &&
        (!value.hasBookmark() ||
            value.bookmark.chapterKey != bookmark.chapterKey ||
            value.bookmark.bookmarked != bookmark.bookmarked)) {
      throw const FormatException('Mutation response bookmark mismatch');
    }
    if (bookmark == null && value.hasBookmark()) {
      throw const FormatException('Unexpected mutation bookmark');
    }
    if (expectedChapter != null &&
        (!value.hasProgress() ||
            value.progress.chapterKey != expectedChapter ||
            (chapterRead == null && !value.progress.hasCurrent()) ||
            (value.progress.hasCurrent() &&
                value.progress.current.chapterKey != expectedChapter) ||
            (value.progress.hasFurthest() &&
                value.progress.furthest.chapterKey != expectedChapter))) {
      throw const FormatException(
        'Mutation response progress identity mismatch',
      );
    }
    if (value.hasProgress()) {
      validateBusinessProgress(value.progress, chapterKey: expectedChapter);
    }
    // Idempotency confirms that the original write happened, not that its
    // result is still current. Refresh ambiguous retries and known old replies
    // before acknowledging a draft, even if a shelf refresh evicted this key.
    final current =
        retry ||
            value.accountRevision < _accountRevision ||
            value.categoryCatalog.revision < _catalog.revision
        ? await _readManga(
            pending.request.mangaKey,
            chapterKey: _mutationChapter(pending.request),
            knownLocalRevision: value.manga.revision,
          )
        : null;
    final bookmarkChanged =
        bookmark != null &&
        current != null &&
        current.bookmark.bookmarked != bookmark.bookmarked;
    final coverChanged =
        current != null && !_coverMatches(pending.request, current.manga);
    if (bookmarkChanged ||
        coverChanged ||
        (bookmark == null &&
            value.manga.revision <
                (_manga[value.manga.mangaKey]?.revision ?? 0))) {
      final latestProgress = current?.hasProgress() == true
          ? current!.progress
          : null;
      final staleEpoch =
          value.hasProgress() &&
          latestProgress != null &&
          value.progress.epoch != latestProgress.epoch;
      final failure = BusinessStateException(
        wire.BusinessStateError(
          code: staleEpoch
              ? wire
                    .BusinessStateErrorCode
                    .BUSINESS_STATE_ERROR_CODE_STALE_EPOCH
              : wire
                    .BusinessStateErrorCode
                    .BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
          message: 'Manga changed after this mutation was applied',
        ),
        manga: _manga[value.manga.mangaKey],
        progress: latestProgress,
        bookmark: current?.hasBookmark() == true ? current!.bookmark : null,
        conflictedChapterKey: _mutationChapter(pending.request),
      );
      pending.rejected = true;
      pending.failure = failure;
      throw failure;
    }
    final confirmedCatalog = current?.categoryCatalog ?? value.categoryCatalog;
    _acceptCatalog(confirmedCatalog);
    _accept(current?.manga ?? value.manga, local: true);
    _accountRevision = value.accountRevision > _accountRevision
        ? value.accountRevision
        : _accountRevision;
    await _updateLibraryConfirmed(
      _manga[value.manga.mangaKey]!,
      confirmedCatalog,
    );
    _ensureOpen();
    _pending.remove(pending.request.mangaKey);
    _changes.add(null);
    if (bookmark != null && current != null) {
      return wire.StateMutationResponse(
        schemaVersion: _schemaVersion,
        mutationId: value.mutationId,
        accountRevision: current.accountRevision,
        manga: current.manga,
        categoryCatalog: current.categoryCatalog,
        bookmark: current.bookmark,
      );
    }
    return value;
  }

  /// Catalog commands have their own queue, independent of manga progress and
  /// associations. A retry retains the exact UUID, CAS and serialized body.
  Future<wire.CategoryMutationResponse> mutateCategories(
    wire.CategoryMutation operation,
  ) {
    _assertNoMigrationCatalog();
    final command = operation.deepCopy();
    command.clearMutationId();
    command.schemaVersion = _schemaVersion;
    validateBusinessCategoryMutation(command);
    final fingerprint = jsonEncode(wire.encodeProtoJson(command));
    return _serial('categories', () async {
      _assertNoMigrationCatalog();
      final previous = _pendingCategory;
      if (previous != null) {
        if (previous.fingerprint != fingerprint) {
          throw StateError('请先处理书架中的未确认分类修改。');
        }
        return _sendCategories(previous);
      }
      command.mutationId = _uuid.v4();
      command.freeze();
      final pending = _PendingCategoryMutation(
        fingerprint,
        command,
        jsonEncode(wire.encodeProtoJson(command)),
      );
      _pendingCategory = pending;
      return _sendCategories(pending);
    });
  }

  Future<wire.CategoryCatalogResponse> readCategories() =>
      _serial('categories', _readCategories);

  Future<wire.CategoryCatalogResponse> _readCategories() async {
    final reply = await _get('/api/categories');
    final value = wire.decodeProtoJson(
      wire.CategoryCatalogResponse(),
      jsonDecode(reply.body),
      maxBytes: _responseLimit,
    );
    _version(value.schemaVersion);
    validateBusinessRevision(value.accountRevision);
    if (value.hasError()) {
      validateBusinessError(value.error);
      throw BusinessStateException(value.error);
    }
    _success(reply);
    _validateCatalog(
      value.hasCategoryCatalog(),
      value.categoryCatalog,
      value.accountRevision,
    );
    if (value.accountRevision < _accountRevision ||
        value.categoryCatalog.revision < _catalog.revision) {
      throw StateError('Business category response predates this session');
    }
    _acceptCatalog(value.categoryCatalog);
    _accountRevision = value.accountRevision;
    // Directory reads can invalidate every displayed association. Publish the
    // catalog together with a shelf from the same authoritative snapshot.
    await refreshLibrary();
    _ensureOpen();
    return value;
  }

  Future<wire.CategoryMutationResponse> _sendCategories(
    _PendingCategoryMutation pending,
  ) async {
    _ensureOpen();
    if (pending.rejection != null) throw pending.rejection!;
    final reply = await api.fetchApi(
      '/api/categories/mutations',
      method: 'POST',
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: pending.body,
    );
    _ensureOpen();
    _budget(reply);
    final value = wire.decodeProtoJson(
      wire.CategoryMutationResponse(),
      jsonDecode(reply.body),
      maxBytes: _responseLimit,
    );
    _version(value.schemaVersion);
    validateBusinessRevision(value.accountRevision);
    if (value.mutationId != pending.request.mutationId) {
      throw const FormatException(
        'Category mutation response identity mismatch',
      );
    }
    if (value.hasCategoryCatalog()) {
      _validateCatalog(true, value.categoryCatalog, value.accountRevision);
    }
    if (value.hasError()) {
      validateBusinessError(value.error);
      final failure = BusinessStateException(value.error);
      if (!value.error.retryable) pending.rejection = failure;
      throw failure;
    }
    _success(reply);
    _validateCatalog(
      value.hasCategoryCatalog(),
      value.categoryCatalog,
      value.accountRevision,
    );
    if (value.categoryCatalog.revision !=
        pending.request.expectedRevision + 1) {
      throw const FormatException(
        'Category mutation did not confirm a new revision',
      );
    }
    // Even a successful ACK can be an old idempotency record. Read back the
    // current catalog before accepting it; a deleted category stays deleted.
    await _readCategories();
    if (_catalog.revision != value.categoryCatalog.revision) {
      final failure = BusinessStateException(
        wire.BusinessStateError(
          code: wire
              .BusinessStateErrorCode
              .BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
          message: 'Categories changed after this mutation was applied',
        ),
      );
      _pendingCategory = pending;
      pending.rejection = failure;
      throw failure;
    }
    if (_catalog != value.categoryCatalog) {
      throw const FormatException(
        'Category ACK differs from confirmed catalog',
      );
    }
    _pendingCategory = null;
    return value;
  }

  /// Settings have independent global/manga CAS and never replay another scope.
  Stream<wire.SettingsResponse> watchSettings() => Stream.multi((sink) {
    final subscription = _settingsChanges.stream.listen(
      sink.add,
      onError: sink.addError,
      onDone: sink.close,
    );
    sink.onCancel = subscription.cancel;
    final confirmed = _settings.values.toList()
      ..sort((a, b) => a.accountRevision.compareTo(b.accountRevision));
    for (final value in confirmed) {
      sink.add(value);
    }
    if (_closed) sink.close();
  });

  ({wire.SettingsMutation request, bool retryable})? pendingSettings({
    String? mangaKey,
  }) {
    if (_closed) return null;
    final pending = _pendingSettings[_settingsScope(mangaKey)];
    return pending == null
        ? null
        : (request: pending.request, retryable: pending.rejection == null);
  }

  Future<wire.SettingsResponse> readSettings({String? mangaKey}) {
    if (mangaKey != null) validateBusinessMangaKey(mangaKey);
    return _serial(
      _settingsScope(mangaKey),
      () => _readSettings(mangaKey: mangaKey, clearRejected: true),
    );
  }

  Future<wire.SettingsResponse> _readSettings({
    String? mangaKey,
    bool clearRejected = false,
  }) async {
    final scope = _settingsScope(mangaKey);
    for (var attempt = 0; attempt < 3; attempt++) {
      final reply = await _get(
        mangaKey == null ? '/api/settings' : '/api/settings/manga/$mangaKey',
      );
      final value = wire.decodeProtoJson(
        wire.SettingsResponse(),
        jsonDecode(reply.body),
        maxBytes: _responseLimit,
      );
      validateBusinessSettingsResponse(value, mangaKey: mangaKey);
      if (value.hasError()) throw BusinessStateException(value.error);
      _success(reply);
      final previous = _settings[scope];
      final global = _latestGlobalSettings;
      if (value.accountRevision < _accountRevision ||
          (global != null && value.global.revision < global.revision) ||
          (mangaKey != null &&
              previous != null &&
              value.manga.revision < previous.manga.revision)) {
        continue;
      }
      if (global != null &&
          value.global.revision == global.revision &&
          !_globalSettingsMatch(value.global.values, global.values)) {
        throw const FormatException('Global settings changed without revision');
      }
      if (mangaKey != null &&
          previous != null &&
          value.manga.revision == previous.manga.revision &&
          (value.manga.mangaKey != previous.manga.mangaKey ||
              value.manga.overrides != previous.manga.overrides)) {
        throw const FormatException('Manga settings changed without revision');
      }
      _ensureOpen();
      final confirmed = value.deepCopy()..freeze();
      _settings[scope] = confirmed;
      _accountRevision = value.accountRevision;
      if (clearRejected && _pendingSettings[scope]?.rejection != null) {
        _pendingSettings.remove(scope);
      }
      _settingsChanges.add(confirmed);
      return confirmed;
    }
    throw StateError('Settings changed repeatedly; refresh again');
  }

  wire.GlobalSettings? get _latestGlobalSettings {
    wire.GlobalSettings? latest;
    for (final value in _settings.values) {
      if (latest == null || value.global.revision > latest.revision) {
        latest = value.global;
      }
    }
    return latest;
  }

  Future<wire.SettingsResponse> mutateSettings(
    wire.SettingsMutation operation,
  ) {
    final command = operation.deepCopy()
      ..schemaVersion = _schemaVersion
      ..clearMutationId();
    validateBusinessSettingsMutation(command);
    final mangaKey = command.hasSetManga() ? command.setManga.mangaKey : null;
    final scope = _settingsScope(mangaKey);
    final fingerprint = jsonEncode(wire.encodeProtoJson(command));
    return _serial(scope, () async {
      final previous = _pendingSettings[scope];
      if (previous != null) {
        if (previous.fingerprint != fingerprint) {
          throw StateError('请先重试原设置修改；已确认冲突请刷新后重新编辑。');
        }
        return _sendSettings(previous, mangaKey: mangaKey);
      }
      command.mutationId = _uuid.v4();
      command.freeze();
      final pending = _PendingSettingsMutation(
        fingerprint,
        command,
        jsonEncode(
          wire.encodeProtoJson(command, maxBytes: wire.controlRequestLimit),
        ),
      );
      _pendingSettings[scope] = pending;
      return _sendSettings(pending, mangaKey: mangaKey);
    });
  }

  Future<wire.SettingsResponse> _sendSettings(
    _PendingSettingsMutation pending, {
    String? mangaKey,
  }) async {
    _ensureOpen();
    if (pending.rejection != null) throw pending.rejection!;
    final reply = await api.fetchApi(
      '/api/settings/mutations',
      method: 'POST',
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: pending.body,
    );
    _ensureOpen();
    _budget(reply);
    final value = wire.decodeProtoJson(
      wire.SettingsMutationResponse(),
      jsonDecode(reply.body),
      maxBytes: _responseLimit,
    );
    if (value.mutationId != pending.request.mutationId &&
        (!value.hasError() || value.mutationId.isNotEmpty)) {
      throw const FormatException('Settings mutation identity mismatch');
    }
    final snapshot = wire.SettingsResponse(
      schemaVersion: value.schemaVersion,
      accountRevision: value.accountRevision,
      global: value.hasGlobal() ? value.global : null,
      manga: value.hasManga() ? value.manga : null,
      effectiveReader: value.hasEffectiveReader()
          ? value.effectiveReader
          : null,
      error: value.hasError() ? value.error : null,
    );
    validateBusinessSettingsResponse(snapshot, mangaKey: mangaKey);
    if (value.hasError()) {
      final failure = BusinessStateException(value.error);
      if (!value.error.retryable) pending.rejection = failure;
      throw failure;
    }
    _success(reply);
    final revision = mangaKey == null
        ? value.global.revision
        : value.manga.revision;
    if (revision != pending.request.expectedRevision + 1 ||
        !_settingsMatch(pending.request, snapshot)) {
      throw const FormatException(
        'Settings ACK does not confirm the requested values',
      );
    }
    // A persisted idempotency ACK may predate another device's write. Confirm
    // current values with GET before exposing them as saved.
    final current = await _readSettings(mangaKey: mangaKey);
    if (!_settingsMatch(pending.request, current)) {
      final failure = BusinessStateException(
        wire.BusinessStateError(
          code: wire
              .BusinessStateErrorCode
              .BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
          message: 'Settings changed after this mutation was applied',
        ),
      );
      pending.rejection = failure;
      throw failure;
    }
    _pendingSettings.remove(_settingsScope(mangaKey));
    return current;
  }

  ({wire.SourcePreferencesMutation request, bool retryable})?
  pendingSourcePreferences(
    String packageName,
    String sourceId, {
    required wire.CatalogReference catalog,
  }) {
    if (_closed) return null;
    final pending =
        _pendingSourcePreferences[_sourcePreferenceKey(
          catalog,
          packageName,
          sourceId,
        )];
    return pending == null
        ? null
        : (request: pending.request, retryable: pending.rejection == null);
  }

  bool hasPendingSourcePreferences(
    String packageName, {
    required wire.CatalogReference catalog,
  }) =>
      !_closed &&
      _pendingSourcePreferences.values.any(
        (pending) =>
            pending.request.packageName == packageName &&
            pending.request.catalog == catalog,
      );

  Future<wire.SourcePreferencesResponse> readSourcePreferences(
    String packageName, {
    required wire.CatalogReference catalog,
  }) {
    validateBusinessCatalogReference(catalog);
    validateSourcePreferencesIdentity(packageName);
    return _serial(
      'source-preferences:${_sourcePreferenceScope(catalog, packageName)}',
      () => _readSourcePreferences(
        packageName,
        catalog: catalog,
        clearRejected: true,
      ),
    );
  }

  Future<wire.SourcePreferencesResponse> _readSourcePreferences(
    String packageName, {
    required wire.CatalogReference catalog,
    bool clearRejected = false,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final reply = await _get(
        Uri(
          path:
              '/api/source-preferences/packages/${Uri.encodeComponent(packageName)}',
          queryParameters: {
            'catalogUrl': catalog.catalogUrl,
            'repoId': catalog.repoId,
          },
        ).toString(),
      );
      final value = wire.decodeProtoJson(
        wire.SourcePreferencesResponse(),
        jsonDecode(reply.body),
        maxBytes: 128 * 1024,
      );
      validateSourcePreferencesResponse(value, packageName, catalog: catalog);
      if (value.hasError()) throw BusinessStateException(value.error);
      _success(reply);
      final previous =
          _sourcePreferences[_sourcePreferenceScope(catalog, packageName)];
      if (value.accountRevision < _accountRevision) continue;
      var stale = false;
      for (final old in previous?.sources ?? <wire.SourcePreferences>[]) {
        final matching = value.sources.where(
          (source) => source.sourceId == old.sourceId,
        );
        if (matching.isEmpty || matching.single.revision < old.revision) {
          stale = true;
          break;
        }
        if (matching.single.revision == old.revision &&
            !samePreferenceEntries(matching.single.entries, old.entries)) {
          throw const FormatException(
            'Source settings changed without revision',
          );
        }
      }
      if (stale) continue;
      _ensureOpen();
      final confirmed = value.deepCopy()..freeze();
      _sourcePreferences[_sourcePreferenceScope(catalog, packageName)] =
          confirmed;
      _accountRevision = value.accountRevision;
      if (clearRejected) {
        _pendingSourcePreferences.removeWhere(
          (_, pending) =>
              pending.request.packageName == packageName &&
              pending.request.catalog == catalog &&
              pending.rejection != null,
        );
      }
      return confirmed;
    }
    throw StateError('Source settings changed repeatedly; refresh again');
  }

  Future<wire.SourcePreferencesResponse> mutateSourcePreferences(
    wire.SourcePreferencesMutation operation,
  ) {
    final command = operation.deepCopy()
      ..schemaVersion = _schemaVersion
      ..clearMutationId();
    validateBusinessCatalogReference(command.catalog);
    validateSourcePreferencesIdentity(command.packageName, command.sourceId);
    validateBusinessRevision(command.expectedRevision);
    final entries = canonicalPreferenceEntries(command.entries);
    wire.validatePreferenceEntries(entries);
    command.entries
      ..clear()
      ..addAll(entries);
    final fingerprint = jsonEncode(
      wire.encodeProtoJson(command, maxBytes: wire.controlRequestLimit),
    );
    final key = _sourcePreferenceKey(
      command.catalog,
      command.packageName,
      command.sourceId,
    );
    return _serial(
      'source-preferences:${_sourcePreferenceScope(command.catalog, command.packageName)}',
      () {
        final previous = _pendingSourcePreferences[key];
        if (previous != null) {
          if (previous.fingerprint != fingerprint) {
            throw StateError('请先处理这个漫画源未确认的原设置操作。');
          }
          return _sendSourcePreferences(previous);
        }
        command.mutationId = _uuid.v4();
        final body = jsonEncode(
          wire.encodeProtoJson(command, maxBytes: wire.controlRequestLimit),
        );
        command.freeze();
        final pending = _PendingSourcePreferencesMutation(
          fingerprint,
          command,
          body,
        );
        _pendingSourcePreferences[key] = pending;
        return _sendSourcePreferences(pending);
      },
    );
  }

  Future<wire.SourcePreferencesResponse> retrySourcePreferences(
    String packageName,
    String sourceId, {
    required wire.CatalogReference catalog,
  }) => _serial(
    'source-preferences:${_sourcePreferenceScope(catalog, packageName)}',
    () {
      final pending =
          _pendingSourcePreferences[_sourcePreferenceKey(
            catalog,
            packageName,
            sourceId,
          )];
      if (pending == null) throw StateError('没有待确认的原漫画源设置。');
      return _sendSourcePreferences(pending);
    },
  );

  Future<wire.SourcePreferencesResponse> discardSourcePreferences(
    String packageName,
    String sourceId, {
    required wire.CatalogReference catalog,
  }) => _serial(
    'source-preferences:${_sourcePreferenceScope(catalog, packageName)}',
    () async {
      final current = await _readSourcePreferences(
        packageName,
        catalog: catalog,
      );
      _pendingSourcePreferences.remove(
        _sourcePreferenceKey(catalog, packageName, sourceId),
      );
      return current;
    },
  );

  Future<wire.SourcePreferencesResponse> _sendSourcePreferences(
    _PendingSourcePreferencesMutation pending,
  ) async {
    _ensureOpen();
    if (pending.rejection != null) throw pending.rejection!;
    final reply = await api.fetchApi(
      '/api/source-preferences/mutations',
      method: 'POST',
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: pending.body,
    );
    _ensureOpen();
    _budget(reply);
    final value = wire.decodeProtoJson(
      wire.SourcePreferencesMutationResponse(),
      jsonDecode(reply.body),
      maxBytes: 128 * 1024,
    );
    _version(value.schemaVersion);
    if (!value.hasCatalog() || value.catalog != pending.request.catalog) {
      throw const FormatException('Source settings ACK repository mismatch');
    }
    validateBusinessRevision(value.accountRevision);
    wire.validatePreferenceSyncRules(value.syncRules);
    if (value.mutationId != pending.request.mutationId &&
        (!value.hasError() || value.mutationId.isNotEmpty)) {
      throw const FormatException('Source settings mutation identity mismatch');
    }
    if (value.hasError()) {
      final failure = BusinessStateException(value.error);
      if (!value.error.retryable) pending.rejection = failure;
      throw failure;
    }
    _success(reply);
    if (!value.hasPreferences()) {
      throw const FormatException(
        'Source settings ACK has no confirmed values',
      );
    }
    validateSourcePreferences(value.preferences, pending.request.packageName);
    if (value.preferences.sourceId != pending.request.sourceId ||
        value.preferences.revision != pending.request.expectedRevision + 1 ||
        !samePreferenceEntries(
          value.preferences.entries,
          pending.request.entries,
        )) {
      throw const FormatException(
        'Source settings ACK differs from submitted values',
      );
    }
    final current = await _readSourcePreferences(
      pending.request.packageName,
      catalog: pending.request.catalog,
    );
    final matches = current.sources.where(
      (source) => source.sourceId == pending.request.sourceId,
    );
    if (matches.isEmpty ||
        !samePreferenceEntries(
          matches.single.entries,
          pending.request.entries,
        )) {
      final failure = BusinessStateException(
        wire.BusinessStateError(
          code: wire
              .BusinessStateErrorCode
              .BUSINESS_STATE_ERROR_CODE_REVISION_CONFLICT,
          message: 'Source settings changed after this mutation was applied',
        ),
      );
      pending.rejection = failure;
      throw failure;
    }
    _pendingSourcePreferences.remove(
      _sourcePreferenceKey(
        pending.request.catalog,
        pending.request.packageName,
        pending.request.sourceId,
      ),
    );
    return current;
  }

  Future<ApiReply> _get(String path) async {
    _ensureOpen();
    final reply = await api.fetchApi(path, headers: _headers);
    _ensureOpen();
    _budget(reply);
    return reply;
  }

  void _accept(wire.MangaState value, {bool local = false}) {
    final previous = _manga[value.mangaKey]?.revision ?? 0;
    if (value.revision >= previous) {
      if (!local && value.revision > previous) {
        final remote = _remoteRevisions[value.mangaKey] ?? 0;
        _remoteRevisions[value.mangaKey] = value.revision > remote
            ? value.revision
            : remote;
      }
      _manga[value.mangaKey] = value.deepCopy()..freeze();
    }
  }

  void _validateCatalog(
    bool present,
    wire.CategoryCatalog catalog,
    int accountRevision,
  ) {
    if (!present) throw const FormatException('Missing category catalog');
    validateBusinessCategoryCatalog(catalog);
    if (catalog.revision > accountRevision) {
      throw const FormatException('Category revision exceeds account revision');
    }
  }

  void _acceptCatalog(wire.CategoryCatalog value) {
    if (value.revision < _catalog.revision) return;
    if (value.revision == _catalog.revision && value != _catalog) {
      throw const FormatException(
        'Category contents changed without a revision',
      );
    }
    _catalog = value.deepCopy()..freeze();
  }

  Future<void> _updateLibraryConfirmed(
    wire.MangaState value,
    wire.CategoryCatalog catalog,
  ) async {
    if (catalog != _libraryCatalog) {
      await refreshLibrary();
      return;
    }
    _updateLibrary(value);
  }

  void _updateLibrary(wire.MangaState value) {
    final next = _library
        .where((entry) => entry.mangaKey != value.mangaKey)
        .toList();
    if (value.favorite && value.hasMetadata()) {
      next.add(_manga[value.mangaKey]!);
    }
    next.sort(_compareShelf);
    _library = List.unmodifiable(next);
  }

  void _checkContinue(bool Function()? shouldContinue) {
    _ensureOpen();
    if (shouldContinue?.call() == false) throw StateError('迁移页面已关闭。');
  }

  Future<T> _serial<T>(String key, Future<T> Function() action) {
    final before = _queues[key] ?? Future<void>.value();
    final result = before.then((_) {
      _ensureOpen();
      return action();
    });
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _queues[key] = settled;
    settled.then((_) {
      if (identical(_queues[key], settled)) _queues.remove(key);
    });
    return result;
  }

  void _budget(ApiReply reply) {
    if (reply.redirected || utf8.encode(reply.body).length > _responseLimit) {
      throw const FormatException(
        'Business response redirect or size exceeds budget',
      );
    }
    if (!(reply.headers['content-type'] ?? reply.headers['Content-Type'] ?? '')
        .toLowerCase()
        .startsWith('application/json')) {
      throw BusinessStateTransportException(reply.status);
    }
  }

  void _success(ApiReply reply) {
    if (reply.status < 200 || reply.status >= 300) {
      throw BusinessStateTransportException(reply.status);
    }
  }

  void _version(int version) {
    if (version != _schemaVersion) {
      throw const FormatException('Unsupported business schema version');
    }
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Business session has ended');
  }

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _manga.clear();
    _remoteRevisions.clear();
    _pending.clear();
    _migrationClaims.clear();
    _library = const [];
    _pendingCategory = null;
    _pendingSourcePreferences.clear();
    _sourcePreferences.clear();
    _pendingSettings.clear();
    _settings.clear();
    await _settingsChanges.close();
    _catalog = wire.CategoryCatalog()..freeze();
    _libraryCatalog = _catalog;
    await _changes.close();
  }
}

String? _operationChapter(wire.StateMutation request) =>
    request.hasSaveProgress()
    ? request.saveProgress.snapshot.chapterKey
    : request.hasResetProgress()
    ? request.resetProgress.snapshot.chapterKey
    : request.hasSetChapterRead()
    ? request.setChapterRead.chapterKey
    : null;

String? _mutationChapter(wire.StateMutation request) => request.hasSetBookmark()
    ? request.setBookmark.chapterKey
    : _operationChapter(request);

int _compareShelf(wire.MangaState a, wire.MangaState b) {
  final byDate = b.addedAtSeconds.compareTo(a.addedAtSeconds);
  return byDate == 0 ? a.mangaKey.compareTo(b.mangaKey) : byDate;
}

String _settingsScope(String? mangaKey) =>
    mangaKey == null ? 'settings:global' : 'settings:manga:$mangaKey';

bool _settingsMatch(
  wire.SettingsMutation command,
  wire.SettingsResponse value,
) => command.hasSetGlobal()
    ? _globalSettingsMatch(value.global.values, command.setGlobal)
    : value.manga.overrides == command.setManga.overrides;

// Proto3 scalars without presence may be omitted by Protobuf-ES even when
// Dart stores an explicitly assigned default. Compare their generated getters;
// manga overrides keep protobuf equality because their optional presence matters.
final _readerSettingsEquality = EqualityBy(
  (wire.ReaderSettings value) => (
    value.mode,
    value.pageLayout,
    value.background,
    value.dimPercent,
    value.tapZones,
    value.keyboard,
    value.fit,
    value.cropBorders,
  ),
);
final _favoriteSourcesEquality = ListEquality(
  EqualityBy(
    (wire.FavoriteSource value) =>
        (value.packageName, value.sourceId, value.sourceName, value.sourceLang),
  ),
);
final _installedExtensionsEquality = ListEquality(
  EqualityBy(
    (wire.InstalledExtension value) => (
      value.catalogUrl,
      value.repoId,
      value.packageName,
      value.buildId,
      value.bundleSha256,
      value.enabled,
    ),
  ),
);
final _repositoriesEquality = ListEquality(
  EqualityBy(
    (wire.ExtensionRepository value) =>
        (value.catalogUrl, value.repoId, value.name),
  ),
);

bool _globalSettingsMatch(
  wire.GlobalSettingsValues a,
  wire.GlobalSettingsValues b,
) =>
    a.theme == b.theme &&
    _readerSettingsEquality.equals(a.reader, b.reader) &&
    _favoriteSourcesEquality.equals(a.favoriteSources, b.favoriteSources) &&
    _installedExtensionsEquality.equals(
      a.installedExtensions,
      b.installedExtensions,
    ) &&
    _repositoriesEquality.equals(a.repositories, b.repositories);

bool _coverMatches(wire.StateMutation request, wire.MangaState manga) =>
    !request.hasSetCustomCover() ||
    (request.setCustomCover.hasCover() == manga.hasCustomCover() &&
        (!manga.hasCustomCover() ||
            request.setCustomCover.cover == manga.customCover));

String _sourcePreferenceScope(
  wire.CatalogReference catalog,
  String packageName,
) => jsonEncode([catalog.catalogUrl, catalog.repoId, packageName]);

String _sourcePreferenceKey(
  wire.CatalogReference catalog,
  String packageName,
  String sourceId,
) => jsonEncode([catalog.catalogUrl, catalog.repoId, packageName, sourceId]);
