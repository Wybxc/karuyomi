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
    this.conflictedChapterKey,
  });
  final wire.BusinessStateError error;
  final wire.MangaState? manga;
  final wire.ChapterProgressState? progress;
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
  final _pending = <String, _PendingMutation>{};
  final _queues = <String, Future<void>>{};
  final _uuid = const Uuid();
  List<wire.MangaState> _library = const [];
  int _accountRevision = 0;
  bool _closed = false;
  Future<void>? _refreshing;

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

  Stream<List<wire.MangaState>> watchLibrary() => Stream.multi((sink) {
    final subscription = _changes.stream.listen(
      (_) => sink.add(_library),
      onError: sink.addError,
      onDone: sink.close,
    );
    sink.onCancel = subscription.cancel;
    refreshLibrary().then(
      (_) {
        if (!_closed) sink.add(_library);
      },
      onError: (Object error, StackTrace stack) => sink.addError(error, stack),
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
            pending.rejected && _operationChapter(pending.request) == null,
      );
      _changes.add(null);
      return;
    }
    throw StateError('Library changed repeatedly; refresh again');
  }

  Future<wire.MangaStateResponse> readManga(String key, {String? chapterKey}) =>
      _serial(key, () => _readManga(key, chapterKey: chapterKey));

  Future<wire.MangaStateResponse> _readManga(
    String key, {
    String? chapterKey,
  }) async {
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
        (value.hasProgress() && value.progress.chapterKey != chapterKey)) {
      throw const FormatException('Business state response identity mismatch');
    }
    validateBusinessManga(value.manga);
    if (value.hasProgress()) {
      validateBusinessProgress(value.progress, chapterKey: chapterKey);
    }
    if (value.manga.revision < (_manga[key]?.revision ?? 0) ||
        value.accountRevision < _accountRevision ||
        value.accountRevision < value.manga.revision) {
      throw StateError('Business state response predates this session');
    }
    _accept(value.manga);
    _updateLibrary(value.manga);
    _accountRevision = value.accountRevision > _accountRevision
        ? value.accountRevision
        : _accountRevision;
    final rejected = _pending[key];
    if (rejected != null && rejected.rejected) {
      final rejectedChapter = _operationChapter(rejected.request);
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
  Future<wire.StateMutationResponse> mutate(wire.StateMutation operation) {
    final command = operation.deepCopy();
    if (command.mangaKey.isEmpty) throw ArgumentError('Missing manga key');
    command.clearMutationId();
    command.clearExpectedRevision();
    command.schemaVersion = _schemaVersion;
    final fingerprint = jsonEncode(wire.encodeProtoJson(command));
    return _serial(command.mangaKey, () async {
      final previous = _pending[command.mangaKey];
      if (previous != null) {
        final result = await _send(previous);
        if (previous.fingerprint == fingerprint) return result;
      }
      if (!_manga.containsKey(command.mangaKey)) {
        await _readManga(command.mangaKey);
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
    if (value.hasError()) {
      validateBusinessError(value.error);
      if (value.hasManga()) validateBusinessManga(value.manga);
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
        conflictedChapterKey: _operationChapter(pending.request),
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
    final expectedChapter = _operationChapter(pending.request);
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
    final current = retry || value.accountRevision < _accountRevision
        ? await _readManga(
            pending.request.mangaKey,
            chapterKey: expectedChapter,
          )
        : null;
    if (value.manga.revision < (_manga[value.manga.mangaKey]?.revision ?? 0)) {
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
        conflictedChapterKey: expectedChapter,
      );
      pending.rejected = true;
      pending.failure = failure;
      throw failure;
    }
    _pending.remove(pending.request.mangaKey);
    _accept(value.manga);
    _accountRevision = value.accountRevision > _accountRevision
        ? value.accountRevision
        : _accountRevision;
    _updateLibrary(_manga[value.manga.mangaKey]!);
    _changes.add(null);
    return value;
  }

  Future<ApiReply> _get(String path) async {
    _ensureOpen();
    final reply = await api.fetchApi(path, headers: _headers);
    _ensureOpen();
    _budget(reply);
    return reply;
  }

  void _accept(wire.MangaState value) {
    if (value.revision >= (_manga[value.mangaKey]?.revision ?? 0)) {
      _manga[value.mangaKey] = value.deepCopy()..freeze();
    }
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
    _pending.clear();
    _library = const [];
    await _changes.close();
  }
}

String? _operationChapter(wire.StateMutation request) =>
    request.hasSaveProgress()
    ? request.saveProgress.snapshot.chapterKey
    : request.hasResetProgress()
    ? request.resetProgress.snapshot.chapterKey
    : null;

int _compareShelf(wire.MangaState a, wire.MangaState b) {
  final byDate = b.addedAtSeconds.compareTo(a.addedAtSeconds);
  return byDate == 0 ? a.mangaKey.compareTo(b.mangaKey) : byDate;
}
