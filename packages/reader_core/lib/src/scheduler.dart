import 'dart:async';
import 'layout.dart';
import 'resources.dart';

final class ImageBudgetExceeded implements Exception {
  const ImageBudgetExceeded(this.message);
  final String message;
  @override
  String toString() => message;
}

final class ImageSchedulerSnapshot {
  ImageSchedulerSnapshot({
    required Map<String, ImageResource> resources,
    required Map<String, Object> errors,
    required Iterable<String> loading,
    required this.residentBytes,
    required this.estimatedDecodedBytes,
    required this.cleanupError,
  }) : resources = Map.unmodifiable(resources),
       errors = Map.unmodifiable(errors),
       loading = Set.unmodifiable(loading);

  final Map<String, ImageResource> resources;
  final Map<String, Object> errors;
  final Set<String> loading;
  final int residentBytes;
  final int estimatedDecodedBytes;
  final Object? cleanupError;
}

final class _Acquisition {
  _Acquisition(this.ref, this.epoch);
  final PageRef ref;
  final int epoch;
  bool cancelled = false;
}

/// Owns all images inside a bounded window and releases late/stale results.
/// The compressed-byte limit is enforced after acquire and before presentation.
/// Decoded costs are estimates; providers must additionally bound processing
/// buffers, and platform adapters must enforce actual decode/resource budgets.
final class ImageScheduler {
  static int _instanceSequence = 0;
  ImageScheduler({
    required this.provider,
    this.maxConcurrent = 2,
    this.maxResidentPages = 6,
    this.maxResidentBytes = 64 * 1024 * 1024,
    this.maxEstimatedDecodedBytes = 128 * 1024 * 1024,
    this.unknownPageDecodedEstimate = 24 * 1024 * 1024,
    this.requestTimeout = const Duration(seconds: 30),
  }) {
    if (maxConcurrent <= 0 ||
        maxResidentPages <= 0 ||
        maxResidentBytes <= 0 ||
        maxEstimatedDecodedBytes <= 0 ||
        unknownPageDecodedEstimate <= 0 ||
        requestTimeout <= Duration.zero) {
      throw ArgumentError('Image limits must be positive');
    }
  }

  final PageProvider provider;
  final int maxConcurrent;
  final int maxResidentPages;
  final int maxResidentBytes;
  final int maxEstimatedDecodedBytes;
  final int unknownPageDecodedEstimate;
  final Duration requestTimeout;
  final _changes = StreamController<ImageSchedulerSnapshot>.broadcast(
    sync: true,
  );
  final _resources = <String, ImageResource>{};
  final _errors = <String, Object>{};
  final _active = <String, _Acquisition>{};
  final _wanted = <String, ReaderPage>{};
  final _pendingCleanup = <Future<void>>{};
  final int _instanceId = ++_instanceSequence;
  String _chapterKey = '';
  String _generation = '';
  int _epoch = 0;
  int _requestCounter = 0;
  bool _disposed = false;
  Object? _cleanupError;
  Completer<void>? _idle;

  Stream<ImageSchedulerSnapshot> get changes => _changes.stream;
  ImageSchedulerSnapshot get snapshot => ImageSchedulerSnapshot(
    resources: _resources,
    errors: _errors,
    loading: _active.values
        .where((job) => !job.cancelled && job.epoch == _epoch)
        .map((job) => job.ref.pageKey),
    residentBytes: _resources.values.fold(0, (sum, r) => sum + r.byteLength),
    estimatedDecodedBytes: _resources.values.fold(
      0,
      (sum, image) => sum + image.width * image.height * 4,
    ),
    cleanupError: _cleanupError,
  );

  Future<void> get settled {
    if (_active.isEmpty && _pendingCleanup.isEmpty) return Future.value();
    return (_idle ??= Completer<void>()).future;
  }

  int _estimatedCost(ReaderPage? page) {
    final image = _resources[page?.key];
    return image == null
        ? page?.estimatedDecodedBytes ?? unknownPageDecodedEstimate
        : image.width * image.height * 4;
  }

  /// [pages] is in priority order: visible, forward prefetch, backward reserve.
  /// A generation/chapter switch invalidates all results and prior ownership.
  void setWindow({
    required String chapterKey,
    required String generation,
    required Iterable<ReaderPage> pages,
  }) {
    if (_disposed) throw StateError('Image scheduler is disposed');
    if (chapterKey.isEmpty || generation.isEmpty) {
      throw ArgumentError('Image window requires a chapter and generation');
    }
    // Re-evaluate a previously reduced window when priorities/dimensions change.
    _errors.removeWhere((_, error) => error is ImageBudgetExceeded);
    if (_chapterKey != chapterKey || _generation != generation) {
      _epoch++;
      _errors.clear();
      _chapterKey = chapterKey;
      _generation = generation;
      for (final resource in _resources.values) {
        _cleanup(() => provider.release(resource.id));
      }
      _resources.clear();
    }
    _wanted.clear();
    var estimatedBytes = 0;
    for (final page in pages) {
      if (_wanted.containsKey(page.key)) continue;
      final cost = _estimatedCost(page);
      if (_wanted.isEmpty && cost > maxEstimatedDecodedBytes) {
        _wanted[page.key] = page;
        _errors[page.key] = const ImageBudgetExceeded(
          '图片尺寸超过当前解码预算，需要缩小图片或分片显示。',
        );
        break;
      }
      if (_wanted.length >= maxResidentPages ||
          estimatedBytes + cost > maxEstimatedDecodedBytes) {
        continue;
      }
      estimatedBytes += cost;
      _wanted[page.key] = page;
    }
    for (final key in _resources.keys.toList()) {
      if (!_wanted.containsKey(key) ||
          _estimatedCost(_wanted[key]) > maxEstimatedDecodedBytes) {
        final resource = _resources.remove(key)!;
        _cleanup(() => provider.release(resource.id));
      }
    }
    _errors.removeWhere((key, _) => !_wanted.containsKey(key));
    for (final job in _active.values) {
      if (job.epoch != _epoch ||
          !_wanted.containsKey(job.ref.pageKey) ||
          _estimatedCost(_wanted[job.ref.pageKey]) > maxEstimatedDecodedBytes) {
        _cancel(job);
      }
    }
    _pump();
  }

  void retry(String pageKey) {
    if (_disposed) throw StateError('Image scheduler is disposed');
    if (!_wanted.containsKey(pageKey)) return;
    if (_estimatedCost(_wanted[pageKey]) > maxEstimatedDecodedBytes) return;
    _errors.remove(pageKey);
    _pump();
  }

  void _cancel(_Acquisition job) {
    if (job.cancelled) return;
    job.cancelled = true;
    _cleanup(() => provider.cancel(job.ref.requestId));
  }

  void _pump() {
    if (_disposed) return;
    for (final page in _wanted.values) {
      // Stop new production until cancellation/release is acknowledged. This
      // also bounds pending resources when the user rapidly switches chapters.
      if (_pendingCleanup.isNotEmpty || _cleanupError != null) break;
      if (_active.length >= maxConcurrent) break;
      if (_resources.containsKey(page.key) ||
          _errors.containsKey(page.key) ||
          _active.values.any((job) => job.ref.pageKey == page.key)) {
        continue;
      }
      final job = _Acquisition(
        PageRef(
          requestId: 'reader-$_instanceId-$_epoch-${++_requestCounter}',
          chapterKey: _chapterKey,
          pageKey: page.key,
          generation: _generation,
        ),
        _epoch,
      );
      _active[job.ref.requestId] = job;
      unawaited(_acquire(job));
    }
    _emit();
    if (_active.isEmpty && _pendingCleanup.isEmpty && _idle != null) {
      _idle!.complete();
      _idle = null;
    }
  }

  bool _isCurrent(_Acquisition job) =>
      !_disposed &&
      !job.cancelled &&
      job.epoch == _epoch &&
      _wanted.containsKey(job.ref.pageKey);

  Future<void> _acquire(_Acquisition job) async {
    // Attach late-result cleanup to the original future. Future.timeout alone
    // would discard the eventual resource without releasing its ownership.
    Future<ImageResource>? original;
    var timedOut = false;
    try {
      original = provider.acquire(job.ref);
      unawaited(
        original.then((resource) {
          if (timedOut) _cleanup(() => provider.release(resource.id));
        }, onError: (Object _) {}),
      );
      final resource = await original.timeout(
        requestTimeout,
        onTimeout: () {
          timedOut = true;
          _cancel(job);
          throw TimeoutException('Image request timed out', requestTimeout);
        },
      );
      if (!_isCurrent(job) || resource.generation != _generation) {
        _cleanup(() => provider.release(resource.id));
        if (_isCurrent(job)) {
          _errors[job.ref.pageKey] = StateError('Image generation mismatch');
        }
        return;
      }
      if (resource.byteLength < 0) {
        _cleanup(() => provider.release(resource.id));
        throw StateError('Image byte length cannot be negative');
      }
      final ranks = _wanted.keys.toList();
      final incomingRank = ranks.indexOf(job.ref.pageKey);
      var residentBytes = snapshot.residentBytes;
      var decodedBytes = snapshot.estimatedDecodedBytes;
      final incomingDecodedBytes = resource.width * resource.height * 4;
      for (final key in ranks.reversed) {
        if (residentBytes + resource.byteLength <= maxResidentBytes &&
            decodedBytes + incomingDecodedBytes <= maxEstimatedDecodedBytes) {
          break;
        }
        if (ranks.indexOf(key) <= incomingRank) continue;
        final evicted = _resources.remove(key);
        if (evicted != null) {
          residentBytes -= evicted.byteLength;
          decodedBytes -= evicted.width * evicted.height * 4;
          _errors[key] = const ImageBudgetExceeded('预取窗口已缩小以保留当前图片。');
          _cleanup(() => provider.release(evicted.id));
        }
      }
      if (residentBytes + resource.byteLength > maxResidentBytes ||
          decodedBytes + incomingDecodedBytes > maxEstimatedDecodedBytes) {
        _cleanup(() => provider.release(resource.id));
        throw const ImageBudgetExceeded('图片资源超过当前内存预算。');
      }
      _resources[job.ref.pageKey] = resource;
    } catch (error) {
      if (_isCurrent(job) ||
          (timedOut &&
              job.epoch == _epoch &&
              !_disposed &&
              _wanted.containsKey(job.ref.pageKey))) {
        _errors[job.ref.pageKey] = error;
      }
    } finally {
      _active.remove(job.ref.requestId);
      _pump();
    }
  }

  void _cleanup(Future<void> Function() action) {
    late final Future<void> future;
    future = Future.sync(action)
        .catchError((Object error) {
          _cleanupError = error;
          _emit();
        })
        .whenComplete(() {
          _pendingCleanup.remove(future);
          _pump();
        });
    _pendingCleanup.add(future);
  }

  void _emit() {
    if (!_disposed) _changes.add(snapshot);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final job in _active.values) {
      _cancel(job);
    }
    for (final resource in _resources.values) {
      _cleanup(() => provider.release(resource.id));
    }
    _resources.clear();
    _wanted.clear();
    await Future.wait(_pendingCleanup.toList());
    if (_idle != null) {
      _idle!.complete();
      _idle = null;
    }
    await _changes.close();
  }
}
