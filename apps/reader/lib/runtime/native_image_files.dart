import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

/// File handoff for a single, already authenticated runtime container.
abstract interface class NativeImageFileStore {
  Future<Uri> copy({
    required String requestId,
    required String generation,
    required wire.ImageResource resource,
    bool tile = false,
  });
  Future<void> cancel(String requestId, String generation);
  Future<void> release(String resourceId, String generation);
  Future<void> clear();
}

final class IosImageFileStore implements NativeImageFileStore {
  IosImageFileStore._(this._channel, this._bindingId, this._directory);
  static const channelName = 'dev.karuyomi/native_image_files';
  final MethodChannel _channel;
  final String _bindingId;
  final Uri _directory;

  static Future<IosImageFileStore> bind({
    required String token,
    required Uri origin,
    MethodChannel channel = const MethodChannel(channelName),
  }) async {
    final value = await channel.invokeMapMethod<String, Object?>('bind', {
      'token': token,
      'origin': origin.origin,
    });
    final id = value?['bindingId'];
    final directory = Uri.tryParse(value?['directoryUrl']?.toString() ?? '');
    if (id is! String || id.isEmpty || !_localFile(directory)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Native image file binding is invalid',
      );
    }
    return IosImageFileStore._(channel, id, directory!);
  }

  static bool _localFile(Uri? uri) =>
      uri != null &&
      uri.scheme == 'file' &&
      uri.host.isEmpty &&
      uri.path.startsWith('/') &&
      !uri.hasQuery &&
      !uri.hasFragment;

  @override
  Future<Uri> copy({
    required String requestId,
    required String generation,
    required wire.ImageResource resource,
    bool tile = false,
  }) async {
    final value = await _channel.invokeMapMethod<String, Object?>('acquire', {
      'bindingId': _bindingId,
      'requestId': requestId,
      'resourceId': resource.resourceId,
      'generation': generation,
      'tile': tile,
      'url': resource.url,
      'byteLength': resource.byteLength,
      'mimeType': resource.mimeType,
      'width': resource.width,
      'height': resource.height,
    });
    final location = Uri.tryParse(value?['url']?.toString() ?? '');
    if (!_localFile(location) ||
        File.fromUri(location!).parent.uri != _directory ||
        location.pathSegments.last.isEmpty) {
      await release(resource.resourceId, resource.generation);
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Native image is outside its managed directory',
      );
    }
    return location;
  }

  Future<void> _ack(
    String method,
    Map<String, Object?> arguments,
    String field,
  ) async {
    final value = await _channel.invokeMapMethod<String, Object?>(method, {
      'bindingId': _bindingId,
      ...arguments,
    });
    if (value?[field] != true) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native image cleanup was not acknowledged',
      );
    }
  }

  @override
  Future<void> cancel(String requestId, String generation) => _ack('cancel', {
    'requestId': requestId,
    'generation': generation,
  }, 'released');
  @override
  Future<void> release(String resourceId, String generation) => _ack(
    'release',
    {'resourceId': resourceId, 'generation': generation},
    'released',
  );
  @override
  Future<void> clear() => _ack('clear', {}, 'cleared');
}

typedef NativeControlCall =
    Future<wire.ControlResponse> Function(wire.ControlRequest);

/// Keeps Source cancellation and file-copy cancellation in one ownership scope.
/// The Blob remains charged to the JS resource pool until the local file leaves
/// Flutter's image cache and its explicit release reaches both owners.
final class NativeImageControl {
  NativeImageControl({
    required this.store,
    required this.call,
    required this.origin,
  });
  final NativeImageFileStore store;
  final NativeControlCall call;
  final Uri origin;
  final _tasks = <String, _ImageTask>{};
  final _resources = <String, _ImageTask>{};
  bool _closed = false;
  int _bytes = 0;
  int _pixels = 0;
  int _sequence = 0;
  Future<void>? _closing;
  final _tileTasks = <String, _TileTask>{};
  final _tilePages = <String, _TilePage>{};
  final _tileObservations = <Set<String>>{};
  Future<void> _tileCopyQueue = Future<void>.value();
  int _tileBytes = 0;

  String _key(String id, String generation) => '$generation\u0000$id';
  bool owns(String id, String generation, Uri location) =>
      !_closed &&
      ((_resources[_key(id, generation)]?.published == true &&
              _resources[_key(id, generation)]?.location == location) ||
          (_tileTasks[_key(id, generation)]?.published == true &&
              _tileTasks[_key(id, generation)]?.location == location));

  Future<wire.ControlResponse> acquire(wire.ControlRequest control) async {
    final request = control.acquireImage;
    final key = _key(request.requestId, request.generation);
    if (_closed) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native image container was replaced',
      );
    }
    if (_tasks.containsKey(key)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Duplicate image request',
      );
    }
    if (_tasks.length + _resources.length >= 6) {
      throw const RuntimeException(
        RuntimeErrorCode.limitExceeded,
        'Native image resource limit reached',
      );
    }
    final task = _ImageTask(request);
    _tasks[key] = task;
    final timer = Timer(
      Duration(
        milliseconds: request.hasTimeoutMs() ? request.timeoutMs : 60000,
      ),
      () {
        task.failure ??= const RuntimeException(
          RuntimeErrorCode.timeout,
          'Native image acquisition timed out',
        );
        unawaited(_abort(task).catchError((Object _) {}));
      },
    );
    var published = false;
    try {
      final response = await Future.any([
        call(control),
        task.interrupted.future.then<wire.ControlResponse>((_) {
          _check(task);
          throw const RuntimeException(
            RuntimeErrorCode.runtimeLost,
            'Native image operation was interrupted',
          );
        }),
      ]);
      if (response.requestId != control.requestId) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Image response identity mismatch',
        );
      }
      if (response.whichResult() == wire.ControlResponse_Result.error) {
        _check(task);
        return response;
      }
      if (response.whichResult() != wire.ControlResponse_Result.image) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Native image response is missing',
        );
      }
      final image = response.image;
      task.resource = image;
      final uri = Uri.tryParse(image.url);
      final inner = uri?.scheme == 'blob'
          ? Uri.tryParse(image.url.substring(5))
          : null;
      if (image.resourceId.isEmpty ||
          image.resourceId.length > 200 ||
          image.generation != request.generation ||
          inner?.scheme != 'https' ||
          inner?.host.isEmpty != false ||
          inner!.origin != origin.origin ||
          image.byteLength <= 0 ||
          image.byteLength > 64 * 1024 * 1024 ||
          image.width <= 0 ||
          image.height <= 0 ||
          image.width * image.height > 16 * 1024 * 1024 ||
          !RegExp(r'^image/[a-zA-Z0-9.+-]{1,80}$').hasMatch(image.mimeType)) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Invalid Native image descriptor',
        );
      }
      if (_bytes + image.byteLength > 64 * 1024 * 1024 ||
          _pixels + image.width * image.height > 32 * 1024 * 1024) {
        throw const RuntimeException(
          RuntimeErrorCode.limitExceeded,
          'Native image storage budget exceeded',
        );
      }
      task.reserved = true;
      _bytes += image.byteLength;
      _pixels += image.width * image.height;
      _check(task);
      final location = await store.copy(
        requestId: request.requestId,
        generation: request.generation,
        resource: image,
      );
      task.location = location;
      _check(task);
      if (location.scheme != 'file' ||
          location.host.isNotEmpty ||
          location.hasQuery ||
          location.hasFragment) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Native image handoff did not return a local file',
        );
      }
      final resourceKey = _key(image.resourceId, image.generation);
      if (_resources.containsKey(resourceKey)) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Duplicate Native image resource',
        );
      }
      _resources[resourceKey] = task;
      task.published = true;
      published = true;
      return response.deepCopy()..image.url = location.toString();
    } catch (_) {
      _check(task);
      rethrow;
    } finally {
      timer.cancel();
      try {
        if (!published) {
          try {
            await task.aborting;
            await _releaseTask(task);
          } catch (_) {
            final image = task.resource;
            if (image != null) {
              _resources[_key(image.resourceId, image.generation)] = task;
            }
            throw const RuntimeException(
              RuntimeErrorCode.runtimeLost,
              'Native image cleanup could not be confirmed',
            );
          }
        }
      } finally {
        _tasks.remove(key);
        task.done.complete();
      }
    }
  }

  /// Convert only bounded display tiles; the Source encoded page stays in JS.
  Future<wire.ControlResponse> window(wire.ControlRequest control) async {
    if (_tileObservations.length >= 32) {
      throw const RuntimeException(
        RuntimeErrorCode.limitExceeded,
        'Too many Native image window observations',
      );
    }
    final retired = _tileTasks.entries
        .where((entry) => entry.value.retiring)
        .map((entry) => entry.key)
        .toSet();
    _tileObservations.add(retired);
    try {
      return await _window(control, retired);
    } finally {
      _tileObservations.remove(retired);
    }
  }

  Future<wire.ControlResponse> _window(
    wire.ControlRequest control,
    Set<String> retired,
  ) async {
    final requesting = control.hasRequestImageWindow();
    final pageId = requesting
        ? control.requestImageWindow.pageId
        : control.waitImageWindow.pageId;
    final generation = requesting
        ? control.requestImageWindow.generation
        : control.waitImageWindow.generation;
    final windowId = requesting
        ? control.requestImageWindow.windowId
        : control.waitImageWindow.windowId;
    final pageKey = _key(pageId, generation);
    final page = _tilePages.putIfAbsent(pageKey, _TilePage.new);
    if (requesting && !page.closed) {
      page.windowId = windowId;
    } else if (page.windowId == null && !page.closed) {
      page.windowId = windowId;
    }
    final attempt = requesting ? ++page.attempt : page.attempt;
    void restoreRejectedWindow() {
      if (requesting && page.attempt == attempt && page.windowId == windowId) {
        page.windowId = page.acceptedWindowId;
      }
    }

    _checkTileWindow(page, windowId);
    final response = await call(control).catchError((Object error) {
      restoreRejectedWindow();
      throw error;
    });
    if (response.hasError()) {
      restoreRejectedWindow();
      if (response.requestId != control.requestId) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Tile control response identity mismatch',
        );
      }
      return response;
    }
    if (!response.hasImageWindow()) {
      restoreRejectedWindow();
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Tile window response is missing',
      );
    }
    final snapshot = response.imageWindow;
    if (snapshot.pageId != pageId || snapshot.generation != generation) {
      restoreRejectedWindow();
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Tile response belongs to another page',
      );
    }
    final used = <_TileTask>[];
    var published = false;
    var accepted = false;
    try {
      if (response.requestId != control.requestId) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Tile control response identity mismatch',
        );
      }
      wire.checkImageWindow(snapshot);
      if (snapshot.windowId != windowId ||
          (!requesting &&
              snapshot.revision < control.waitImageWindow.afterRevision)) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Tile response window or revision mismatch',
        );
      }
      _checkTileWindow(page, windowId);
      if (snapshot.revision < page.revision) {
        throw const RuntimeException(
          RuntimeErrorCode.cancelled,
          'A newer tile window response has already arrived',
        );
      }
      page.revision = snapshot.revision;
      page.acceptedWindowId = windowId;
      accepted = true;
      for (final tile in snapshot.tiles) {
        final image = tile.resource;
        final uri = Uri.tryParse(image.url.substring(5));
        if (uri?.scheme != 'https' || uri?.origin != origin.origin) {
          throw const RuntimeException(
            RuntimeErrorCode.protocolError,
            'Tile Blob is outside the managed origin',
          );
        }
        final key = _key(tile.leaseId, generation);
        if (retired.contains(key)) {
          throw const RuntimeException(
            RuntimeErrorCode.cancelled,
            'Tile was released while this observation was in flight',
          );
        }
        var task = _tileTasks[key];
        if (task != null) {
          if (task.pageId != pageId || !_sameTile(task.tile, tile)) {
            throw const RuntimeException(
              RuntimeErrorCode.protocolError,
              'Tile lease metadata changed',
            );
          }
        } else {
          if (_tileTasks.length >= 64 ||
              _tileBytes + image.byteLength > 16 * 1024 * 1024 ||
              _bytes + image.byteLength > 64 * 1024 * 1024 ||
              _pixels + image.width * image.height > 32 * 1024 * 1024) {
            throw const RuntimeException(
              RuntimeErrorCode.limitExceeded,
              'Native tile display budget exceeded',
            );
          }
          task = _TileTask(
            pageId: pageId,
            requestId: 'native-tile-${++_sequence}',
            tile: tile.deepCopy()..freeze(),
          );
          _tileTasks[key] = task;
          _tileBytes += image.byteLength;
          _bytes += image.byteLength;
          _pixels += image.width * image.height;
          final pending = task;
          task.copy = _tileCopyQueue.then((_) => _copyTile(pending));
          _tileCopyQueue = task.copy.then<void>((_) {}, onError: (Object _) {});
          task.timer = Timer(const Duration(seconds: 60), () {
            pending.failure ??= const RuntimeException(
              RuntimeErrorCode.timeout,
              'Native tile copy timed out',
            );
            unawaited(_stopTile(pending).catchError((Object _) {}));
          });
        }
        task.users++;
        used.add(task);
      }
      final result = response.deepCopy();
      for (var index = 0; index < used.length; index++) {
        final location = await used[index].copy;
        _checkTileWindow(page, windowId);
        if (page.revision != snapshot.revision) {
          throw const RuntimeException(
            RuntimeErrorCode.cancelled,
            'A newer tile snapshot superseded this file copy',
          );
        }
        result.imageWindow.tiles[index].resource.url = location.toString();
      }
      for (final task in used) {
        _checkTile(task);
      }
      for (final task in used) {
        task.published = true;
      }
      published = true;
      return result;
    } finally {
      if (!accepted) restoreRejectedWindow();
      for (final task in used) {
        task.users--;
      }
      if (!published) {
        // A refused snapshot can own new host leases even before file copying
        // starts. Existing published leases still belong to the display owner.
        final newIds = snapshot.tiles
            .where((tile) => tile.leaseId.isNotEmpty)
            .map((tile) => tile.leaseId)
            .toSet();
        for (final id in newIds) {
          final task = _tileTasks[_key(id, generation)];
          if (task != null) {
            if (task.pageId == pageId && !task.published && task.users == 0) {
              await _releaseTileTask(task);
            }
          } else if (!_closed) {
            await _cleanup(
              wire.ControlRequest(
                requestId: 'native-tile-discard-${++_sequence}',
                releaseImageTile: wire.ReleaseImageTile(
                  leaseId: id,
                  generation: generation,
                ),
              ),
            );
          }
        }
      }
    }
  }

  bool _sameTile(wire.ImageTile a, wire.ImageTile b) =>
      a.sessionId == b.sessionId &&
      a.index == b.index &&
      a.denominator == b.denominator &&
      a.sourceRect == b.sourceRect &&
      _sameTileResource(a.resource, b.resource);

  bool _sameTileResource(wire.ImageResource a, wire.ImageResource b) =>
      a.resourceId == b.resourceId &&
      a.generation == b.generation &&
      a.url == b.url &&
      a.mimeType == b.mimeType &&
      a.byteLength == b.byteLength &&
      a.width == b.width &&
      a.height == b.height;

  void _checkTileWindow(_TilePage page, String windowId) {
    if (_closed || page.closed || page.windowId != windowId) {
      throw const RuntimeException(
        RuntimeErrorCode.cancelled,
        'Tile window was replaced or closed',
      );
    }
  }

  void _checkTile(_TileTask task) {
    if (_closed) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native image container was replaced',
      );
    }
    if (task.retiring) {
      throw const RuntimeException(
        RuntimeErrorCode.cancelled,
        'Native tile display lease is being released',
      );
    }
    final failure = task.failure;
    if (failure != null) throw failure;
  }

  Future<Uri> _copyTile(_TileTask task) async {
    try {
      _checkTile(task);
      final location = await store.copy(
        requestId: task.requestId,
        generation: task.resource.generation,
        resource: task.resource,
        tile: true,
      );
      task.location = location;
      _checkTile(task);
      if (location.scheme != 'file' ||
          location.host.isNotEmpty ||
          location.hasQuery ||
          location.hasFragment) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Native tile handoff requires a managed file',
        );
      }
      return location;
    } catch (_) {
      _checkTile(task);
      rethrow;
    } finally {
      task.timer?.cancel();
    }
  }

  Future<void> _stopTile(_TileTask task) async {
    task.failure ??= const RuntimeException(
      RuntimeErrorCode.cancelled,
      'Native tile copy was cancelled',
    );
    await store.cancel(task.requestId, task.resource.generation);
    try {
      await task.copy;
    } catch (_) {
      // The actual copy future must reach terminal before its file is released.
    }
  }

  Future<void> _releaseTileTask(_TileTask task) => task.releasing ??= () async {
    try {
      task.retiring = true;
      final retiringKey = _key(
        task.resource.resourceId,
        task.resource.generation,
      );
      for (final observation in _tileObservations) {
        observation.add(retiringKey);
      }
      if (!task.published) await _stopTile(task);
      await store.release(task.resource.resourceId, task.resource.generation);
      if (!_closed) {
        await _cleanup(
          wire.ControlRequest(
            requestId: 'native-tile-release-${++_sequence}',
            releaseImageTile: wire.ReleaseImageTile(
              leaseId: task.resource.resourceId,
              generation: task.resource.generation,
            ),
          ),
        );
      }
      _tileTasks.remove(
        _key(task.resource.resourceId, task.resource.generation),
      );
      _pruneTilePage(task.pageId, task.resource.generation);
      _tileBytes -= task.resource.byteLength;
      _bytes -= task.resource.byteLength;
      _pixels -= task.resource.width * task.resource.height;
    } catch (_) {
      task.releasing = null;
      rethrow;
    }
  }();

  Future<wire.ControlResponse> releaseTile(wire.ControlRequest control) async {
    final request = control.releaseImageTile;
    final task = _tileTasks[_key(request.leaseId, request.generation)];
    if (task == null) return call(control);
    await _releaseTileTask(task);
    return wire.ControlResponse(
      requestId: control.requestId,
      released: wire.Released(released: true),
    );
  }

  Future<wire.ControlResponse> closeImagePage(
    wire.ControlRequest control,
  ) async {
    final request = control.closeImagePage;
    final page = _tilePages.putIfAbsent(
      _key(request.pageId, request.generation),
      _TilePage.new,
    );
    page.closed = true;
    final response = await call(control);
    if (response.requestId != control.requestId ||
        (!response.hasError() &&
            (!response.hasClosed() || !response.closed.closed))) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Image page close was not acknowledged',
      );
    }
    for (final task in _tileTasks.values.toList()) {
      if (task.pageId == request.pageId &&
          task.resource.generation == request.generation &&
          !task.published) {
        await _releaseTileTask(task);
      }
    }
    _pruneTilePage(request.pageId, request.generation);
    return response;
  }

  void _pruneTilePage(String pageId, String generation) {
    final key = _key(pageId, generation);
    if (_tilePages[key]?.closed == true &&
        !_tileTasks.values.any(
          (task) =>
              task.pageId == pageId && task.resource.generation == generation,
        )) {
      _tilePages.remove(key);
    }
  }

  void _check(_ImageTask task) {
    if (_closed) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native image container was replaced',
      );
    }
    final failure = task.failure;
    if (failure != null) throw failure;
  }

  Future<void> _cleanup(wire.ControlRequest request) async {
    final response = await call(request);
    if (response.whichResult() == wire.ControlResponse_Result.error) {
      throw RuntimeException.fromProto(response.error);
    }
    if (response.requestId != request.requestId ||
        response.whichResult() != wire.ControlResponse_Result.released ||
        !response.released.released) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Image cleanup was not acknowledged',
      );
    }
  }

  Future<void> _abort(_ImageTask task) => task.aborting ??= () async {
    try {
      await Future.wait([
        _cleanup(
          wire.ControlRequest(
            requestId: 'native-cancel-${++_sequence}',
            cancelImage: wire.CancelImage(
              requestId: task.request.requestId,
              generation: task.request.generation,
            ),
          ),
        ),
        store.cancel(task.request.requestId, task.request.generation),
      ]);
    } catch (_) {
      task.failure = const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native image cancellation could not be confirmed',
      );
      rethrow;
    } finally {
      if (!task.interrupted.isCompleted) task.interrupted.complete();
    }
  }();

  Future<wire.ControlResponse> cancel(wire.ControlRequest control) async {
    final request = control.cancelImage;
    final task = _tasks[_key(request.requestId, request.generation)];
    if (task == null) return call(control);
    task.failure ??= const RuntimeException(
      RuntimeErrorCode.cancelled,
      'Native image acquisition was cancelled',
    );
    await _abort(task);
    await task.done.future;
    return wire.ControlResponse(
      requestId: control.requestId,
      released: wire.Released(released: true),
    );
  }

  Future<void> _releaseTask(_ImageTask task) async {
    final image = task.resource;
    if (image == null) return;
    await Future.wait([
      store.release(image.resourceId, image.generation),
      if (!_closed)
        _cleanup(
          wire.ControlRequest(
            requestId: 'native-release-${++_sequence}',
            releaseImage: wire.ReleaseImage(
              resourceId: image.resourceId,
              generation: image.generation,
            ),
          ),
        ),
    ]);
    if (task.reserved) {
      task.reserved = false;
      _bytes -= image.byteLength;
      _pixels -= image.width * image.height;
    }
  }

  Future<wire.ControlResponse> release(wire.ControlRequest control) async {
    final request = control.releaseImage;
    final key = _key(request.resourceId, request.generation);
    final task = _resources[key];
    if (task == null) return call(control);
    await _releaseTask(task);
    _resources.remove(key);
    return wire.ControlResponse(
      requestId: control.requestId,
      released: wire.Released(released: true),
    );
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    for (final task in _tasks.values) {
      task.failure = const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native image container was replaced',
      );
      if (!task.interrupted.isCompleted) task.interrupted.complete();
    }
    for (final page in _tilePages.values) {
      page.closed = true;
    }
    for (final task in _tileTasks.values) {
      task.failure = const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native image container was replaced',
      );
    }
    await store.clear();
    await _tileCopyQueue;
    await Future.wait(_tasks.values.toList().map((task) => task.done.future));
    for (final task in _tileTasks.values) {
      task.timer?.cancel();
    }
    _tileTasks.clear();
    _tilePages.clear();
    _resources.clear();
  }
}

final class _ImageTask {
  _ImageTask(this.request);
  final wire.AcquireImage request;
  final done = Completer<void>();
  final interrupted = Completer<void>();
  wire.ImageResource? resource;
  Uri? location;
  RuntimeException? failure;
  Future<void>? aborting;
  bool reserved = false;
  bool published = false;
}

final class _TilePage {
  String? windowId;
  String? acceptedWindowId;
  int attempt = 0;
  int revision = 0;
  bool closed = false;
}

final class _TileTask {
  _TileTask({
    required this.pageId,
    required this.requestId,
    required this.tile,
  });
  final String pageId;
  final String requestId;
  final wire.ImageTile tile;
  wire.ImageResource get resource => tile.resource;
  late final Future<Uri> copy;
  Uri? location;
  RuntimeException? failure;
  Timer? timer;
  Future<void>? releasing;
  int users = 0;
  bool published = false;
  bool retiring = false;
}
