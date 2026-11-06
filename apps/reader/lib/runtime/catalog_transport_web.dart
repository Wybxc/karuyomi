import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'catalog_transport.dart';

/// Public repositories omit credentials even for the application origin.
final class WebCatalogTransport implements CatalogTransport {
  final _active = <web.AbortController>{};
  bool _closed = false;

  @override
  Future<Object?> read(
    Uri uri, {
    bool Function()? shouldContinue,
    Future<void>? cancelled,
  }) async {
    void current() {
      if (_closed || shouldContinue?.call() == false) {
        throw StateError('仓库读取已取消。');
      }
    }

    current();
    final abort = web.AbortController();
    _active.add(abort);
    unawaited(
      cancelled?.then((_) {
        if (_active.contains(abort)) abort.abort();
      }),
    );
    try {
      return await (() async {
        final response = await web.window
            .fetch(
              uri.toString().toJS,
              web.RequestInit(
                method: 'GET',
                mode: 'cors',
                credentials: 'omit',
                cache: 'no-cache',
                redirect: 'error',
                signal: abort.signal,
                headers: web.Headers()..set('Accept', 'application/json'),
              ),
            )
            .toDart;
        current();
        if (response.status != 200 ||
            (response.headers.get('content-type') ?? '')
                    .split(';')
                    .first
                    .trim()
                    .toLowerCase() !=
                'application/json') {
          throw const FormatException('仓库必须公开提供可跨域读取的 JSON，且不能重定向。');
        }
        final declared = int.tryParse(
          response.headers.get('content-length') ?? '',
        );
        if (declared != null && declared > HttpCatalogTransport.byteLimit) {
          throw const FormatException('仓库文档超过 2 MiB 限额。');
        }
        final body = BytesBuilder(copy: false);
        final stream = response.body;
        if (stream == null) throw const FormatException('仓库文档为空。');
        final reader = stream.getReader() as web.ReadableStreamDefaultReader;
        try {
          while (true) {
            final chunk = await reader.read().toDart;
            current();
            if (chunk.done) break;
            final value = chunk.value;
            if (value == null || !value.isA<JSUint8Array>()) {
              throw const FormatException('仓库响应不是字节流。');
            }
            final bytes = (value as JSUint8Array).toDart;
            if (body.length + bytes.length > HttpCatalogTransport.byteLimit) {
              throw const FormatException('仓库文档超过 2 MiB 限额。');
            }
            body.add(bytes);
          }
        } finally {
          reader.releaseLock();
        }
        current();
        return jsonDecode(utf8.decode(body.takeBytes()));
      })().timeout(const Duration(seconds: 30));
    } finally {
      abort.abort();
      _active.remove(abort);
    }
  }

  @override
  void close() {
    _closed = true;
    for (final abort in _active.toList()) {
      abort.abort();
    }
    _active.clear();
  }
}
