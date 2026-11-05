import 'dart:async';
import 'dart:convert';

import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:uuid/uuid.dart';

import '../runtime/runtime_platform_types.dart';
import 'business_state_validation.dart';
import 'reading_progress.dart';

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
  );
  final String fingerprint;
  final wire.StateMutation request;
  final String body;
  final int accountRevision;
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

final class _PendingCategoryMutation {
  _PendingCategoryMutation(this.fingerprint, this.request, this.body);
  final String fingerprint;
  final wire.CategoryMutation request;
  final String body;
  BusinessStateException? rejection;
}

/// A session cache bound to one confirmed origin and Access subject. All
/// repositories share it so their writes use one revision per manga.
final class BusinessStateClient {
  BusinessStateClient({
    required ApiFetch api,
    required ProgressIdentity identity,
  }) : this._(api, identity);

  BusinessStateClient._(this._api, this.identity);

  ApiFetch _api;
  ApiFetch get api => _api;
  final ProgressIdentity identity;
  final _changes = StreamController<void>.broadcast(sync: true);
  final _manga = <String, wire.MangaState>{};
  final _remoteRevisions = <String, int>{};
  final _pending = <String, _PendingMutation>{};
  final _queues = <String, Future<void>>{};
  final _uuid = const Uuid();
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

  void rebindApi(ApiFetch api, {required ProgressIdentity verifiedIdentity}) {
    _ensureOpen();
    if (verifiedIdentity.key != identity.key) {
      throw ArgumentError('A business session cannot change identity');
    }
    _api = api;
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
            pending.rejected && _mutationChapter(pending.request) == null,
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
    String key,
  ) => _serial(key, () async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final state = await _readManga(key);
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
        final reply = await _get(path);
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
      if (rejected != null &&
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

  Future<wire.MangaStateResponse> readManga(String key, {String? chapterKey}) =>
      _serial(key, () => _readManga(key, chapterKey: chapterKey));

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
    int? knownLocalRevision,
  }) async {
    if (chapterKey != null) validateBusinessChapterKey(chapterKey);
    final path = Uri(
      path: '/api/state/manga/$key',
      queryParameters: {'chapterKey': ?chapterKey},
    ).toString();
    final reply = await _get(path);
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
    if (!accept) return value;
    if (value.categoryCatalog.revision < _catalog.revision) {
      throw StateError('Business category response predates this session');
    }
    _acceptCatalog(value.categoryCatalog);
    _accept(value.manga, local: value.manga.revision == knownLocalRevision);
    _accountRevision = value.accountRevision > _accountRevision
        ? value.accountRevision
        : _accountRevision;
    await _updateLibraryConfirmed(value.manga, value.categoryCatalog);
    _ensureOpen();
    final rejected = _pending[key];
    if (rejected != null && rejected.rejected) {
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

  /// Operation objects contain no transport identity or revision. A failed
  /// attempt retains its exact request and UUID, including after a lost reply.
  Future<wire.StateMutationResponse> mutate(
    wire.StateMutation operation, {
    int? basedOnRevision,
  }) {
    final command = operation.deepCopy();
    if (command.mangaKey.isEmpty) throw ArgumentError('Missing manga key');
    command.clearMutationId();
    command.clearExpectedRevision();
    command.schemaVersion = _schemaVersion;
    if (command.hasSetBookmark()) {
      validateBusinessChapterKey(command.setBookmark.chapterKey);
      if (basedOnRevision == null) {
        throw ArgumentError('Bookmark requires its confirmed revision');
      }
      validateBusinessRevision(basedOnRevision);
    }
    final fingerprint = jsonEncode(wire.encodeProtoJson(command));
    return _serial(command.mangaKey, () async {
      final previous = _pending[command.mangaKey];
      if (previous != null) {
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
          (command.hasSetCategories()
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
      );
      _pending[command.mangaKey] = pending;
      return _send(pending);
    });
  }

  Future<wire.StateMutationResponse> _send(_PendingMutation pending) async {
    _ensureOpen();
    if (pending.rejected && pending.failure != null) throw pending.failure!;
    final retry = pending.sent;
    pending.sent = true;
    final reply = await api.fetchApi(
      '/api/state/mutations',
      method: 'POST',
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: pending.body,
    );
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
        value.manga.revision <= pending.request.expectedRevision ||
        value.accountRevision < value.manga.revision ||
        value.accountRevision < pending.accountRevision) {
      throw const FormatException('Mutation did not confirm a new revision');
    }
    validateBusinessManga(value.manga);
    _validateCatalog(
      value.hasCategoryCatalog(),
      value.categoryCatalog,
      value.accountRevision,
    );
    validateBusinessMangaCategories(value.manga, value.categoryCatalog);
    final expectedChapter = _operationChapter(pending.request);
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
            !value.progress.hasCurrent() ||
            value.progress.current.chapterKey != expectedChapter ||
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
    if (bookmarkChanged ||
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
    _pending.remove(pending.request.mangaKey);
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
    final command = operation.deepCopy();
    command.clearMutationId();
    command.schemaVersion = _schemaVersion;
    validateBusinessCategoryMutation(command);
    final fingerprint = jsonEncode(wire.encodeProtoJson(command));
    return _serial('categories', () async {
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
    _library = const [];
    _pendingCategory = null;
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
    : null;

String? _mutationChapter(wire.StateMutation request) => request.hasSetBookmark()
    ? request.setBookmark.chapterKey
    : _operationChapter(request);

int _compareShelf(wire.MangaState a, wire.MangaState b) {
  final byDate = b.addedAtSeconds.compareTo(a.addedAtSeconds);
  return byDate == 0 ? a.mangaKey.compareTo(b.mangaKey) : byDate;
}
