import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'native_image_files.dart';

/// The private platform sink prefixes each binary block with its slot-local,
/// never-reused transfer identity and sequence. A stale task cannot ACK a new one.
Uint8List? decodeAndroidImageBlock(
  Uint8List bytes, {
  required int transfer,
  required int sequence,
}) {
  if (bytes.length < 9 || bytes.length > 65536) {
    throw const RuntimeException(
      RuntimeErrorCode.protocolError,
      'Invalid Native image block size',
    );
  }
  final header = ByteData.sublistView(bytes);
  if (header.getUint32(0) != transfer) return null;
  if (header.getUint32(4) != sequence) {
    throw const RuntimeException(
      RuntimeErrorCode.protocolError,
      'Invalid Native image block sequence',
    );
  }
  return Uint8List.sublistView(bytes, 8);
}

/// The locked Android plugin transports ArrayBuffers as Uint8List without a
/// JSON/Base64 conversion. Only one <=64 KiB block is acknowledged at a time.
final class AndroidImageFileStore implements NativeImageFileStore {
  AndroidImageFileStore._(this.controller, this.origin, this.directory);
  final InAppWebViewController controller;
  final Uri origin;
  final Directory directory;
  final _pending = <String, _AndroidImageTransfer>{};
  final _files = <String, File>{};
  final _slots = <_AndroidImageSlot>[];
  bool _closed = false;
  int _sequence = 0;

  static Future<bool> supported() async {
    for (final feature in [
      WebViewFeature.CREATE_WEB_MESSAGE_CHANNEL,
      WebViewFeature.POST_WEB_MESSAGE,
      WebViewFeature.WEB_MESSAGE_ARRAY_BUFFER,
      WebViewFeature.WEB_MESSAGE_PORT_POST_MESSAGE,
      WebViewFeature.WEB_MESSAGE_PORT_SET_MESSAGE_CALLBACK,
      WebViewFeature.WEB_MESSAGE_PORT_CLOSE,
    ]) {
      if (!await WebViewFeature.isFeatureSupported(feature)) return false;
    }
    return true;
  }

  static Future<AndroidImageFileStore> bind(
    InAppWebViewController controller,
    Uri origin,
  ) async => AndroidImageFileStore._(
    controller,
    origin,
    await Directory.systemTemp.createTemp('karuyomi-images-'),
  );

  String _key(String id, String generation) => '$generation\u0000$id';

  @override
  Future<Uri> copy(
    wire.AcquireImage request,
    wire.ImageResource resource,
  ) async {
    if (_closed) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native image store was closed',
      );
    }
    final key = _key(request.requestId, request.generation);
    if (_pending.containsKey(key)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Duplicate file transfer',
      );
    }
    final reusable = _slots.where((value) => !value.busy).firstOrNull;
    if (reusable == null && _slots.length >= 6) {
      throw const RuntimeException(
        RuntimeErrorCode.limitExceeded,
        'Native image channel limit reached',
      );
    }
    final slot =
        reusable ??
        _AndroidImageSlot(
          'slot-${Random.secure().nextInt(1 << 32)}-${++_sequence}',
        );
    if (!_slots.contains(slot)) _slots.add(slot);
    if (slot.sequence == 0xffffffff) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native image channel identity exhausted',
      );
    }
    slot.busy = true;
    final task = _AndroidImageTransfer(
      controller: controller,
      origin: origin,
      slot: slot,
      transfer: ++slot.sequence,
      file: File('${directory.path}/${++_sequence}.image'),
      resource: resource,
    );
    _pending[key] = task;
    try {
      final file = await task.start();
      _files[_key(resource.resourceId, resource.generation)] = file;
      return file.uri;
    } catch (error) {
      if (error is! RuntimeException ||
          error.code != RuntimeErrorCode.cancelled) {
        _closed = true;
      }
      rethrow;
    } finally {
      _pending.remove(key);
      slot.busy = false;
    }
  }

  @override
  Future<void> cancel(String requestId, String generation) async {
    await _pending[_key(requestId, generation)]?.cancel();
  }

  @override
  Future<void> release(String resourceId, String generation) async {
    final key = _key(resourceId, generation);
    final file = _files[key];
    if (file == null) return;
    await file.delete();
    _files.remove(key);
  }

  @override
  Future<void> clear() async {
    _closed = true;
    try {
      await Future.wait(_pending.values.toList().map((task) => task.cancel()));
    } finally {
      for (final slot in _slots) {
        await slot.channel?.port1.close();
        if (!slot.transferred) await slot.channel?.port2.close();
        slot.channel?.dispose();
      }
      if (await directory.exists()) await directory.delete(recursive: true);
      _files.clear();
    }
  }
}

final class _AndroidImageSlot {
  _AndroidImageSlot(this.token);
  final String token;
  WebMessageChannel? channel;
  bool transferred = false;
  bool busy = false;
  int sequence = 0;
}

final class _AndroidImageTransfer {
  _AndroidImageTransfer({
    required this.controller,
    required this.origin,
    required this.slot,
    required this.transfer,
    required this.file,
    required this.resource,
  });
  final InAppWebViewController controller;
  final Uri origin;
  final _AndroidImageSlot slot;
  final int transfer;
  final File file;
  final wire.ImageResource resource;
  final _completion = Completer<void>();
  final _cancelled = Completer<void>();
  final _stopped = Completer<void>();
  WebMessageChannel? _channel;
  RandomAccessFile? _output;
  Future<void>? _cancelling;
  bool _cancelRequested = false;
  bool _transferred = false;
  bool _writing = false;
  Completer<void>? _writeStopped;
  int _bytes = 0;
  int _sequence = 0;

  void _check() {
    if (_cancelRequested) {
      throw const RuntimeException(
        RuntimeErrorCode.cancelled,
        'Image file transfer was cancelled',
      );
    }
  }

  Future<File> start() async {
    var success = false;
    try {
      _channel = slot.channel ??= await controller.createWebMessageChannel();
      if (_channel == null) {
        throw const RuntimeException(
          RuntimeErrorCode.unsupportedCapability,
          'Android ArrayBuffer channel is unavailable',
        );
      }
      _check();
      _output = await file.open(mode: FileMode.writeOnly);
      _check();
      await _channel!.port1.setWebMessageCallback((message) {
        unawaited(
          _receive(message).catchError((Object error) async {
            Object failure = error;
            try {
              await _signalCancel();
            } catch (_) {
              failure = const RuntimeException(
                RuntimeErrorCode.runtimeLost,
                'Android image cancellation could not be confirmed',
              );
            }
            if (!_completion.isCompleted) _completion.completeError(failure);
          }),
        );
      });
      final installed = await controller.callAsyncJavaScript(
        arguments: {
          'token': slot.token,
          'transfer': transfer,
          'origin': origin.origin,
          'url': resource.url,
        },
        functionBody: androidImageFileScript,
      );
      if (installed?.error != null || installed?.value != true) {
        throw const RuntimeException(
          RuntimeErrorCode.runtimeLost,
          'Android image channel installation failed',
        );
      }
      if (!slot.transferred) {
        await controller.postWebMessage(
          message: WebMessage(data: slot.token, ports: [_channel!.port2]),
          targetOrigin: WebUri(origin.origin),
        );
        slot.transferred = true;
      }
      _transferred = true;
      if (_cancelRequested) {
        _cancelling = null;
        await _signalCancel();
      }
      await _completion.future;
      _check();
      await _output!.flush();
      if (await file.length() != resource.byteLength) {
        throw const RuntimeException(
          RuntimeErrorCode.integrityError,
          'Native image file length changed',
        );
      }
      success = true;
      return file;
    } finally {
      try {
        try {
          if (!_transferred) {
            await controller.callAsyncJavaScript(
              arguments: {'token': slot.token},
              functionBody: '''
const listeners = window.__karuyomiImageFileListeners;
if (listeners?.[token]) {
  window.removeEventListener('message', listeners[token]);
  delete listeners[token];
}
''',
            );
          }
        } finally {
          await _writeStopped?.future;
          await _output?.close();
          if (!success && await file.exists()) await file.delete();
        }
      } finally {
        _stopped.complete();
      }
    }
  }

  Future<void> _receive(WebMessage? message) async {
    final data = message?.data;
    if (data is String) {
      final identity = RegExp(
        r'^(?:cancelled|failed|end):(\d+)(?::|$)',
      ).firstMatch(data);
      if (identity != null && identity.group(1) != '$transfer') return;
    }
    if (data == 'cancelled:$transfer') {
      if (!_cancelled.isCompleted) _cancelled.complete();
      if (!_completion.isCompleted) {
        _completion.completeError(
          const RuntimeException(
            RuntimeErrorCode.cancelled,
            'Image file transfer was cancelled',
          ),
        );
      }
      return;
    }
    if (_cancelRequested &&
        data == 'end:$transfer:$_bytes:$_sequence' &&
        _bytes == resource.byteLength) {
      if (!_cancelled.isCompleted) _cancelled.complete();
      if (!_completion.isCompleted) {
        _completion.completeError(
          const RuntimeException(
            RuntimeErrorCode.cancelled,
            'Image file transfer was cancelled',
          ),
        );
      }
      return;
    }
    if (_completion.isCompleted || _cancelRequested) return;
    if (data is Uint8List && message?.type == WebMessageType.ARRAY_BUFFER) {
      final block = decodeAndroidImageBlock(
        data,
        transfer: transfer,
        sequence: _sequence + 1,
      );
      if (block == null) return;
      if (_writing || _bytes + block.length > resource.byteLength) {
        throw const RuntimeException(
          RuntimeErrorCode.protocolError,
          'Invalid Native image block',
        );
      }
      _writing = true;
      final stopped = Completer<void>();
      _writeStopped = stopped;
      try {
        await _output!.writeFrom(block);
        _bytes += block.length;
        _sequence++;
      } finally {
        _writing = false;
        stopped.complete();
      }
      _check();
      await _channel!.port1.postMessage(
        WebMessage(data: 'ack:$transfer:$_sequence'),
      );
    } else if (data == 'end:$transfer:$_bytes:$_sequence' &&
        !_writing &&
        _bytes == resource.byteLength) {
      _completion.complete();
    } else {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'Invalid Native image transfer terminal',
      );
    }
  }

  Future<void> _signalCancel() => _cancelling ??= () async {
    if (!_transferred || _completion.isCompleted) return;
    await _channel!.port1.postMessage(WebMessage(data: 'cancel:$transfer'));
    await _cancelled.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        throw const RuntimeException(
          RuntimeErrorCode.runtimeLost,
          'Android image cancellation was not acknowledged',
        );
      },
    );
  }();

  Future<void> cancel() async {
    _cancelRequested = true;
    try {
      await _signalCancel();
    } catch (_) {
      if (!_completion.isCompleted) {
        _completion.completeError(
          const RuntimeException(
            RuntimeErrorCode.runtimeLost,
            'Android image cancellation could not be confirmed',
          ),
        );
      }
      await _stopped.future;
      rethrow;
    }
    await _stopped.future;
  }
}

/// Installed once per bounded slot, then reused with a fresh transfer identity.
const androidImageFileScript = '''
if (window !== window.top || location.origin !== origin ||
    !['/runtime/host','/runtime/host.html'].includes(location.pathname)) return false;
const attach = port => {
  const abort = new AbortController();
  let pending, cancelled = false, reader, sequence = 0, bytes = 0, completed = false;
  port.onmessage = event => {
    if (event.data === 'cancel:' + transfer) {
      cancelled = true; abort.abort();
      if (pending) { pending.reject(Error('cancelled')); pending = undefined; }
    } else if (pending && event.data === 'ack:' + transfer + ':' + sequence) {
      pending.resolve(); pending = undefined;
    }
  };
  const send = data => new Promise((resolve,reject) => {
    if (cancelled) { reject(Error('cancelled')); return; }
    pending = {resolve,reject}; port.postMessage(data, [data]);
  });
  (async () => {
    try {
      const response = await fetch(url,{signal:abort.signal});
      if (!response.ok || !response.body) throw Error('blob unavailable');
      reader = response.body.getReader();
      for (;;) {
        const value = await reader.read(); if (value.done) break;
        for (let offset=0; offset<value.value.byteLength; offset+=65528) {
          const data = value.value.subarray(offset,offset+65528);
          bytes += data.byteLength; sequence++;
          const framed = new Uint8Array(data.byteLength + 8), header = new DataView(framed.buffer);
          header.setUint32(0,transfer); header.setUint32(4,sequence); framed.set(data,8);
          await send(framed.buffer);
        }
      }
      completed = true;
    } catch (_) {}
    finally {
      try { await reader?.cancel(); } catch (_) {}
      reader?.releaseLock();
      port.postMessage(cancelled ? 'cancelled:' + transfer : completed ? 'end:' + transfer + ':' + bytes + ':' + sequence : 'failed:' + transfer);
    }
  })();
};
window.__karuyomiImageFilePorts ??= Object.create(null);
if (window.__karuyomiImageFilePorts[token]) {
  attach(window.__karuyomiImageFilePorts[token]); return true;
}
const receive = event => {
  if (event.data !== token || event.ports.length !== 1) return;
  window.removeEventListener('message', receive);
  delete window.__karuyomiImageFileListeners[token];
  window.__karuyomiImageFilePorts[token] = event.ports[0];
  attach(event.ports[0]);
};
window.addEventListener('message', receive);
window.__karuyomiImageFileListeners ??= Object.create(null);
window.__karuyomiImageFileListeners[token] = receive;
return true;
''';
