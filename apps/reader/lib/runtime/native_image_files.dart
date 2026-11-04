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
  }) async {
    final value = await _channel.invokeMapMethod<String, Object?>('acquire', {
      'bindingId': _bindingId,
      'requestId': requestId,
      'resourceId': resource.resourceId,
      'generation': generation,
      'url': resource.url,
      'byteLength': resource.byteLength,
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
  }) {
    // A failed clear must wake every waiter without creating an unobserved
    // Completer error when this container has no active image operations.
    unawaited(_filesCleared.future.catchError((Object _) {}));
  }
  final NativeImageFileStore store;
  final NativeControlCall call;
  final Uri origin;
  final _tasks = <String, _ImageTask>{};
  final _resources = <String, _ImageTask>{};
  bool _closed = false;
  int _bytes = 0;
  int _sequence = 0;
  Future<void>? _closing;
  final _closedSignal = Completer<void>();
  final _filesCleared = Completer<void>();

  String _key(String id, String generation) => '$generation\u0000$id';
  bool owns(String id, String generation, Uri location) =>
      !_closed &&
      _resources[_key(id, generation)]?.published == true &&
      _resources[_key(id, generation)]?.location == location;

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
    Future<wire.ControlResponse>? original;
    try {
      original = call(control).then((response) {
        // Identity is checked on the original completion path too: cancellation
        // may already be awaiting this late terminal response in finally.
        final image = response.hasImage() ? response.image : null;
        if (image != null &&
            image.generation == request.generation &&
            image.resourceId.isNotEmpty &&
            image.resourceId.length <= 200 &&
            !_resources.containsKey(_key(image.resourceId, image.generation))) {
          task.resource = image;
        }
        if (response.requestId != control.requestId ||
            (response.hasImage() &&
                response.image.generation != request.generation)) {
          const failure = RuntimeException(
            RuntimeErrorCode.runtimeLost,
            'Native image response identity mismatch',
          );
          task.cleanupFailure = failure;
          throw failure;
        }
        return response;
      });
      final response = await Future.any([
        original,
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
          image.url.length > 4096) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Invalid Native image descriptor',
        );
      }
      if (_bytes + image.byteLength > 64 * 1024 * 1024) {
        throw const RuntimeException(
          RuntimeErrorCode.limitExceeded,
          'Native image storage budget exceeded',
        );
      }
      final resourceKey = _key(image.resourceId, image.generation);
      if (_resources.containsKey(resourceKey)) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Duplicate Native image resource',
        );
      }
      task.reserved = true;
      _bytes += image.byteLength;
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
          if (!_closed && original != null) {
            await Future.any([
              original.then<void>((_) {}, onError: (Object _) {}),
              _closedSignal.future,
            ]);
          }
          try {
            await task.aborting;
            await _releaseTask(task);
            final failure = task.cleanupFailure;
            if (failure != null) throw failure;
          } catch (_) {
            final image = task.resource;
            if (image != null) {
              _resources[_key(image.resourceId, image.generation)] = task;
            }
            const failure = RuntimeException(
              RuntimeErrorCode.runtimeLost,
              'Native image cleanup could not be confirmed',
            );
            task.cleanupFailure = failure;
            throw failure;
          }
        }
      } finally {
        _tasks.remove(key);
        task.done.complete();
      }
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

  Future<T> _whileOpen<T>(Future<T> operation) => Future.any([
    operation,
    _closedSignal.future.then<T>((_) async {
      await _filesCleared.future;
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native image container was reset',
      );
    }),
  ]);

  Future<void> _cleanup(wire.ControlRequest request) async {
    if (_closed) {
      await _filesCleared.future;
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native image container was reset',
      );
    }
    final response = await _whileOpen(call(request));
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
      await Future.any([
        Future.wait([
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
        ]).then<void>((_) {}),
        _filesCleared.future,
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
    if (task == null) {
      await _cleanup(control);
      return wire.ControlResponse(
        requestId: control.requestId,
        released: wire.Released(released: true),
      );
    }
    task.failure ??= const RuntimeException(
      RuntimeErrorCode.cancelled,
      'Native image acquisition was cancelled',
    );
    await _abort(task);
    await task.done.future;
    if (_closed) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native image container was replaced',
      );
    }
    final failure = task.cleanupFailure;
    if (failure != null) throw failure;
    return wire.ControlResponse(
      requestId: control.requestId,
      released: wire.Released(released: true),
    );
  }

  Future<void> _releaseTask(_ImageTask task) => task.releasing ??= () async {
    final image = task.resource;
    if (image == null) return;
    if (_closed) {
      // clear() owns every local file once teardown starts. Its ACK also
      // covers a local release Future whose platform callback never returns.
      await _filesCleared.future;
    } else {
      await _whileOpen(
        Future.wait([
          store.release(image.resourceId, image.generation),
          _cleanup(
            wire.ControlRequest(
              requestId: 'native-release-${++_sequence}',
              releaseImage: wire.ReleaseImage(
                resourceId: image.resourceId,
                generation: image.generation,
              ),
            ),
          ),
        ]).then<void>((_) {}),
      );
    }
    if (task.reserved) {
      task.reserved = false;
      _bytes -= image.byteLength;
    }
  }();

  Future<wire.ControlResponse> release(wire.ControlRequest control) async {
    final request = control.releaseImage;
    final key = _key(request.resourceId, request.generation);
    final task = _resources[key];
    if (task == null) {
      await _cleanup(control);
    } else {
      await _releaseTask(task);
    }
    _resources.remove(key);
    return wire.ControlResponse(
      requestId: control.requestId,
      released: wire.Released(released: true),
    );
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    _closedSignal.complete();
    for (final task in _tasks.values) {
      task.failure = const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native image container was replaced',
      );
      if (!task.interrupted.isCompleted) task.interrupted.complete();
    }
    try {
      await store.clear();
      _filesCleared.complete();
    } catch (error, stack) {
      _filesCleared.completeError(error, stack);
      await Future.wait(_tasks.values.toList().map((task) => task.done.future));
      rethrow;
    }
    await Future.wait(_tasks.values.toList().map((task) => task.done.future));
    _resources.clear();
    _bytes = 0;
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
  RuntimeException? cleanupFailure;
  Future<void>? aborting;
  Future<void>? releasing;
  bool reserved = false;
  bool published = false;
}
