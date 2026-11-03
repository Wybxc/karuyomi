import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

/// File handoff for a single, already authenticated runtime container.
abstract interface class NativeImageFileStore {
  Future<Uri> copy(wire.AcquireImage request, wire.ImageResource resource);
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
  Future<Uri> copy(
    wire.AcquireImage request,
    wire.ImageResource resource,
  ) async {
    final value = await _channel.invokeMapMethod<String, Object?>('acquire', {
      'bindingId': _bindingId,
      'requestId': request.requestId,
      'resourceId': resource.resourceId,
      'generation': resource.generation,
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
      final location = await store.copy(request, image);
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
    await store.clear();
    await Future.wait(_tasks.values.toList().map((task) => task.done.future));
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
