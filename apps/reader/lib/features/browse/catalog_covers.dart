part of 'catalog_controller.dart';

Uri? sourceThumbnail(String value) {
  if (value.isEmpty || value.length > 4096) return null;
  final url = Uri.tryParse(value);
  return url != null &&
          (url.scheme == 'http' || url.scheme == 'https') &&
          url.host.isNotEmpty &&
          url.userInfo.isEmpty
      ? url
      : null;
}

extension CatalogCovers on CatalogController {
  SourceSearchTarget? libraryCoverTarget(LibraryEntry entry) {
    final installed = installedExtension(entry.packageName);
    if (installed == null || !installed.enabled) return null;
    for (final build in builds) {
      if (build.packageName != entry.packageName ||
          !_allowsBuild(build, sha256: installed.bundleSha256)) {
        continue;
      }
      for (final source in build.sources) {
        if (source.id == entry.sourceId) {
          return SourceSearchTarget(
            build: build,
            source: source,
            bundleSha256: installed.bundleSha256,
          );
        }
      }
    }
    return null;
  }

  Future<Uint8List?> readSourceCover({
    CatalogSourceRef? source,
    SourceSearchTarget? target,
    required Uri thumbnail,
    required String requestId,
    required bool Function() stillVisible,
  }) async {
    if (closed || accessPaused || !stillVisible()) return null;
    final epoch = _epoch;
    final request = _CoverRequest(requestId, thumbnail);
    _coverRequests[requestId] = request;
    bool current() =>
        !closed &&
        _epoch == epoch &&
        !accessPaused &&
        !request.cancelled.isCompleted &&
        stillVisible();
    try {
      if (source != null) {
        bool valid() =>
            current() && _searchOwner == null && isCurrentSource(source);
        if (!valid()) return null;
        return await (_coverPool ??= Pool(2)).withResource(() async {
          final loaded = session;
          if (!valid() || loaded == null) return null;
          return request.read(runtime, loaded, source.sourceId, valid);
        });
      }
      if (target == null) return null;
      bool valid() =>
          current() && _allowsBuild(target.build, sha256: target.bundleSha256);
      return await _readTargetCover(target, request, valid);
    } finally {
      _coverRequests.remove(requestId);
    }
  }

  bool get _coverSlotAvailable => !busy && _searchOwner == null;

  void _wakeCoverRequests() {
    final waiter = _coverAvailability;
    _coverAvailability = null;
    waiter?.complete();
  }

  Future<Uint8List?> _readTargetCover(
    SourceSearchTarget target,
    _CoverRequest request,
    bool Function() valid,
  ) async {
    final secondary = _secondaryRuntime;
    final slot = secondary == null || identical(secondary, runtime)
        ? null
        : _coverRuntime ??= _CoverRuntimeSlot(secondary);
    slot?.pending++;
    bool ready() => valid() && _coverSlotAvailable;
    try {
      while (valid()) {
        if (!_coverSlotAvailable) {
          await Future.any([
            (_coverAvailability ??= Completer<void>()).future,
            request.cancelled.future,
          ]);
          continue;
        }
        final bytes = await (_coverPool ??= Pool(2)).withResource(() async {
          if (!ready()) return null;
          final build = activeBuild;
          final loaded = session;
          if (loaded != null &&
              build?.packageName == target.build.packageName &&
              build?.catalog == target.build.catalog) {
            bool current() =>
                ready() &&
                session?.generation == loaded.generation &&
                activeBuild?.id == target.build.id &&
                _activeBundleSha256 == target.bundleSha256;
            return request.read(runtime, loaded, target.source.id, current);
          }
          return slot?.read(this, target, request, ready);
        });
        if (bytes != null || _coverSlotAvailable) return bytes;
      }
      return null;
    } finally {
      if (slot != null) {
        slot.pending--;
        await slot.releaseIfIdle();
      }
    }
  }

  Future<void> cancelSourceCover(String requestId) async {
    await _coverRequests[requestId]?.cancel();
  }
}

final class _CoverRequest {
  _CoverRequest(this.id, this.thumbnail);
  final String id;
  final Uri thumbnail;
  final cancelled = Completer<void>();
  ({SourceRuntime runtime, ImageCancelRequest request})? _transfer;
  int _attempts = 0;

  Future<Uint8List?> read(
    SourceRuntime runtime,
    RuntimeSession session,
    String sourceId,
    bool Function() current,
  ) async {
    if (!current() ||
        !session.capabilities.contains('cover-image-resources') ||
        !session.sources.any((source) => source.id == sourceId)) {
      return null;
    }
    final generation = session.generation;
    final requestId = '$id-${++_attempts}';
    _transfer = (
      runtime: runtime,
      request: ImageCancelRequest(requestId: requestId, generation: generation),
    );
    ImageResource? image;
    try {
      image = await runtime.acquireImage(
        ImageAcquireRequest(
          requestId: requestId,
          sourceId: sourceId,
          pageSessionId: '',
          pageKey: '',
          generation: generation,
          timeout: const Duration(seconds: 10),
          thumbnailUrl: thumbnail,
        ),
      );
      if (!current()) return null;
      if (image.generation != generation ||
          image.byteLength <= 0 ||
          image.byteLength > wire.coverByteLimit ||
          !{'blob', 'file'}.contains(image.location.scheme)) {
        throw const FormatException('Invalid managed Source cover resource');
      }
      final file = XFile(
        image.location.scheme == 'file'
            ? image.location.toFilePath()
            : image.location.toString(),
      );
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in file.openRead()) {
        if (!current()) return null;
        if (chunk.length > image.byteLength - bytes.length) {
          throw const FormatException(
            'Source cover exceeds its announced size',
          );
        }
        bytes.add(chunk);
      }
      if (bytes.length != image.byteLength) {
        throw const FormatException(
          'Source cover length does not match its resource',
        );
      }
      return current() ? bytes.takeBytes() : null;
    } finally {
      _transfer = null;
      if (image != null) {
        await runtime.releaseImage(
          ImageReleaseRequest(
            resourceId: image.id,
            generation: image.generation,
          ),
        );
      }
    }
  }

  Future<void> cancel() async {
    if (cancelled.isCompleted) return;
    cancelled.complete();
    await stopTransfer();
  }

  Future<void> stopTransfer() async {
    final transfer = _transfer;
    _transfer = null;
    if (transfer == null) return;
    try {
      await transfer.runtime.cancelImage(transfer.request);
    } catch (_) {
      // A retiring runtime settles or discards its pending image acquisition.
    }
  }
}

/// Uses the secondary runtime only while a visible batch needs it. Search
/// and foreground opens wait for its generation to close before taking over.
final class _CoverRuntimeSlot {
  _CoverRuntimeSlot(this.runtime);
  final SourceRuntime runtime;
  final _lease = Pool(1);
  int pending = 0;
  RuntimeSession? _session;
  SourceSearchTarget? _loaded;
  _CoverRequest? _active;
  Completer<void>? _interrupt;
  bool _opening = false;
  bool _needsReset = false;
  Future<void>? _release;

  Future<Uint8List?> read(
    CatalogController catalog,
    SourceSearchTarget target,
    _CoverRequest request,
    bool Function() valid,
  ) => _lease.withResource(() async {
    if (!valid()) return null;
    final interrupted = _interrupt = Completer<void>();
    _active = request;
    bool current() => !interrupted.isCompleted && valid();
    try {
      final build = target.build;
      final preferences = catalog.sourcePreferences;
      if (preferences == null ||
          preferences.hasPendingPackage(
            build.packageName,
            catalog: build.catalog,
          ) ||
          catalog._preferenceRecoveries.keys.any(
            (key) =>
                key.$1 == build.catalogUrl &&
                key.$2 == build.repoId &&
                key.$3 == build.packageName,
          )) {
        return null;
      }
      final previous = _loaded;
      if (_needsReset ||
          previous?.build.catalog != build.catalog ||
          previous?.build.id != build.id ||
          previous?.bundleSha256 != target.bundleSha256) {
        await _close();
      }
      if (!current()) return null;
      var session = _session;
      if (session == null) {
        final cancelled = Future.any([
          interrupted.future,
          request.cancelled.future,
        ]);
        final prepared = await Future.any([
          catalog._createSourceDescriptor(
            build,
            preferences,
            shouldContinue: current,
            cancelled: cancelled,
          ),
          cancelled.then((_) => null),
        ]);
        if (prepared == null ||
            !current() ||
            prepared.descriptor.sha256 != target.bundleSha256) {
          return null;
        }
        _opening = _needsReset = true;
        try {
          session = await runtime.open(prepared.descriptor);
          _session = session;
          _loaded = target;
          _needsReset = false;
        } finally {
          _opening = false;
        }
      }
      return await request.read(runtime, session, target.source.id, current);
    } catch (_) {
      if (!current()) return null;
      rethrow;
    } finally {
      _active = null;
      _interrupt = null;
    }
  });

  Future<void> releaseIfIdle() => pending == 0
      ? (_release ??
            _lease.withResource(() async {
              if (pending == 0) await _close();
            }))
      : Future.value();

  Future<void> release() => _release ??= _releaseSlot().whenComplete(() {
    _release = null;
  });

  Future<void> _releaseSlot() async {
    final interrupted = _interrupt;
    if (interrupted != null && !interrupted.isCompleted) interrupted.complete();
    if (_opening) {
      // A half-open runtime has no generation to close yet.
      await runtime.rebuildHost();
      _needsReset = false;
    } else {
      await _active?.stopTransfer();
    }
    await _lease.withResource(_close);
  }

  Future<void> _close() async {
    final loaded = _session;
    if (loaded != null && !_needsReset) {
      try {
        await runtime.closeBuild(
          buildId: loaded.buildId,
          generation: loaded.generation,
        );
      } catch (_) {
        _needsReset = true;
      }
    }
    if (_needsReset) await runtime.rebuildHost();
    _session = null;
    _loaded = null;
    _needsReset = false;
  }
}
