part of '../source_runtime.dart';

/// Binds logical reader pages to the original Page instances in one Source.
/// Closing waits for cancellation and late-resource cleanup before dropping
/// the Java page session. It never cancels the metadata execution slot.
final class ChapterPageProvider implements PageProvider {
  ChapterPageProvider({
    required this.runtime,
    required this.sourceId,
    required this.pageSessionId,
    required this.generation,
    required this.chapterKey,
    required Map<String, String> pageKeys,
    this.timeout = const Duration(seconds: 30),
  }) : pageKeys = Map.unmodifiable(pageKeys) {
    if ([
          sourceId,
          pageSessionId,
          generation,
          chapterKey,
        ].any((value) => value.isEmpty) ||
        pageKeys.entries.any(
          (entry) => entry.key.isEmpty || entry.value.isEmpty,
        ) ||
        pageKeys.values.toSet().length != pageKeys.length) {
      throw ArgumentError(
        'Chapter images require unique explicit page references',
      );
    }
  }

  final SourceRuntime runtime;
  final String sourceId;
  final String pageSessionId;
  final String generation;
  final String chapterKey;
  final Map<String, String> pageKeys;
  final Duration timeout;
  final _pending = <String, Future<void>>{};
  final _cancellations = <String, Future<void>>{};
  final _resources = <String>{};
  final _releases = <String, Future<void>>{};
  final _requestIds = <String>{};
  bool _closed = false;
  Future<void>? _closing;

  @override
  Future<ImageResource> acquire(PageRef page) {
    if (_closed ||
        page.generation != generation ||
        page.chapterKey != chapterKey) {
      return Future.error(
        const RuntimeException(
          RuntimeErrorCode.runtimeLost,
          'Chapter image session has expired',
        ),
      );
    }
    final key = pageKeys[page.pageKey];
    if (key == null ||
        page.requestId.isEmpty ||
        !_requestIds.add(page.requestId)) {
      return Future.error(
        const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Unknown page or reused image request',
        ),
      );
    }
    final result = _acquire(page, key);
    final settled = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _pending[page.requestId] = settled;
    unawaited(
      settled.then((_) {
        _pending.remove(page.requestId);
        _cancellations.remove(page.requestId);
      }),
    );
    return result;
  }

  Future<ImageResource> _acquire(PageRef page, String key) async {
    final image = await runtime.acquireImage(
      ImageAcquireRequest(
        requestId: page.requestId,
        sourceId: sourceId,
        pageSessionId: pageSessionId,
        pageKey: key,
        generation: generation,
        timeout: timeout,
      ),
    );
    if (_resources.contains(image.id) || _releases.containsKey(image.id)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Runtime reused an image resource identity',
      );
    }
    _resources.add(image.id);
    if (_closed ||
        _cancellations.containsKey(page.requestId) ||
        image.generation != generation) {
      await release(image.id);
      throw const RuntimeException(
        RuntimeErrorCode.cancelled,
        'Discarded a cancelled chapter image',
      );
    }
    return image;
  }

  @override
  Future<void> cancel(String requestId) {
    if (!_pending.containsKey(requestId)) return Future.value();
    return _cancellations.putIfAbsent(
      requestId,
      () => runtime.cancelImage(
        ImageCancelRequest(requestId: requestId, generation: generation),
      ),
    );
  }

  @override
  Future<void> release(String resourceId) {
    if (!_resources.contains(resourceId)) {
      return _releases[resourceId] ?? Future.value();
    }
    final release = _releases.putIfAbsent(resourceId, () async {
      await runtime.releaseImage(
        ImageReleaseRequest(resourceId: resourceId, generation: generation),
      );
      _resources.remove(resourceId);
    });
    // Successful cleanup needs no tombstone. Keep failed futures so a later
    // close cannot claim successful cleanup without the platform's ACK.
    unawaited(
      release.then((_) {
        _releases.remove(resourceId);
      }, onError: (Object error, StackTrace stack) {}),
    );
    return release;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    // Capture before awaiting: pending results can finish during cancellation.
    final pending = _pending.values.toList();
    await Future.wait(_pending.keys.toList().map(cancel));
    await Future.wait(pending);
    await Future.wait(_resources.toList().map(release));
    await runtime.closePageSession(
      PageSessionRef(pageSessionId: pageSessionId, generation: generation),
    );
  }
}
