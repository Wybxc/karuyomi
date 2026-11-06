import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Public repository documents have no application authentication headers.
abstract interface class CatalogTransport {
  Future<Object?> read(
    Uri uri, {
    bool Function()? shouldContinue,
    Future<void>? cancelled,
  });
  void close();
}

final class HttpCatalogTransport implements CatalogTransport {
  HttpCatalogTransport({
    http.Client Function()? createClient,
    this.timeout = const Duration(seconds: 30),
  }) : createClient = createClient ?? http.Client.new;
  final http.Client Function() createClient;
  final Duration timeout;
  final _active = <http.Client>{};
  bool _closed = false;
  static const byteLimit = 2 * 1024 * 1024;

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
    final client = createClient();
    _active.add(client);
    unawaited(
      cancelled?.then((_) {
        if (_active.contains(client)) client.close();
      }),
    );
    try {
      return await (() async {
        final response = await client.send(
          http.Request('GET', uri)
            ..followRedirects = false
            ..headers['Accept'] = 'application/json',
        );
        current();
        if (response.statusCode != 200 ||
            (response.headers['content-type'] ?? '')
                    .split(';')
                    .first
                    .trim()
                    .toLowerCase() !=
                'application/json') {
          throw const FormatException('仓库必须公开提供可跨域读取的 JSON，且不能重定向。');
        }
        if (response.contentLength != null &&
            response.contentLength! > byteLimit) {
          throw const FormatException('仓库文档超过 2 MiB 限额。');
        }
        final body = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          current();
          if (body.length + chunk.length > byteLimit) {
            throw const FormatException('仓库文档超过 2 MiB 限额。');
          }
          body.add(chunk);
        }
        current();
        return jsonDecode(utf8.decode(body.takeBytes()));
      })().timeout(timeout);
    } finally {
      _active.remove(client);
      client.close();
    }
  }

  @override
  void close() {
    _closed = true;
    for (final client in _active.toList()) {
      client.close();
    }
    _active.clear();
  }
}
