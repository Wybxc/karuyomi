import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_fetch.dart';

const coverByteLimit = 1024 * 1024;
const _controlLimit = 2 * 1024 * 1024;
final _assetId = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _digest = RegExp(r'^[0-9a-f]{64}$');

abstract interface class CoverTransport {
  Future<ApiReply> uploadCover({
    required String mangaKey,
    required String mutation,
    required String subject,
    required Uint8List bytes,
    required String contentType,
  });

  Future<Uint8List> readCover({
    required String assetId,
    required String subject,
    required String sha256,
    required int byteLength,
  });

  void close();
}

final class CoverTransportException implements Exception {
  const CoverTransportException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Private cover bytes use HTTP directly. They never enter the Source host or
/// its small ProtoJSON control channel. Each request owns an abortable client.
final class HttpCoverTransport implements CoverTransport {
  HttpCoverTransport({
    required this.origin,
    required this.createClient,
    this.sessionHeaders,
    this.timeout = const Duration(seconds: 60),
  }) {
    if (origin.hasQuery ||
        origin.hasFragment ||
        origin.userInfo.isNotEmpty ||
        origin.host.isEmpty ||
        !['http', 'https'].contains(origin.scheme) ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw ArgumentError('Cover service must use one deployment origin');
    }
  }

  final Uri origin;
  final http.Client Function() createClient;
  final Future<Map<String, String>> Function(Uri)? sessionHeaders;
  final Duration timeout;
  final _active = <http.Client>{};
  bool _closed = false;

  @override
  Future<ApiReply> uploadCover({
    required String mangaKey,
    required String mutation,
    required String subject,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!_digest.hasMatch(mangaKey) ||
        !['image/jpeg', 'image/png'].contains(contentType) ||
        bytes.isEmpty ||
        bytes.length > coverByteLimit ||
        utf8.encode(mutation).length > 128 * 1024) {
      throw ArgumentError('Invalid cover upload');
    }
    final request =
        http.MultipartRequest('POST', origin.resolve('/api/covers/$mangaKey'))
          ..followRedirects = false
          ..fields['mutation'] = mutation
          ..files.add(
            http.MultipartFile.fromBytes(
              'image',
              bytes,
              filename: contentType == 'image/png' ? 'cover.png' : 'cover.jpg',
              contentType: MediaType.parse(contentType),
            ),
          );
    final result = await _send(request, subject, _controlLimit);
    return ApiReply(
      status: result.status,
      headers: result.headers,
      body: utf8.decode(result.bytes),
      redirected: result.status >= 300 && result.status < 400,
    );
  }

  @override
  Future<Uint8List> readCover({
    required String assetId,
    required String subject,
    required String sha256,
    required int byteLength,
  }) async {
    if (!_assetId.hasMatch(assetId) ||
        !_digest.hasMatch(sha256) ||
        byteLength < 1 ||
        byteLength > coverByteLimit) {
      throw ArgumentError('Invalid cover descriptor');
    }
    final request = http.Request('GET', origin.resolve('/api/covers/$assetId'))
      ..followRedirects = false;
    final result = await _send(request, subject, coverByteLimit);
    if (result.status != 200) {
      throw CoverTransportException(result.status, '封面读取失败，请重新连接后重试。');
    }
    final type = result.headers['content-type']?.split(';').first.trim();
    if (!['image/jpeg', 'image/png'].contains(type) ||
        result.bytes.length != byteLength ||
        sha256 != crypto.sha256.convert(result.bytes).toString()) {
      throw const CoverTransportException(502, '封面传输校验失败，请重试。');
    }
    return result.bytes.asUnmodifiableView();
  }

  Future<({int status, Map<String, String> headers, Uint8List bytes})> _send(
    http.BaseRequest request,
    String subject,
    int limit,
  ) async {
    if (_closed) throw StateError('封面连接已关闭。');
    if (subject.isEmpty || request.url.origin != origin.origin) {
      throw ArgumentError('Cover request must bind the deployment identity');
    }
    final client = createClient();
    _active.add(client);
    try {
      return await (() async {
        final credentials = await sessionHeaders?.call(request.url);
        if (_closed) throw StateError('封面连接已关闭。');
        request.headers.addAll({
          ...?credentials,
          'Origin': origin.origin,
          'X-App-Request': '1',
          'X-App-Subject': subject,
          'Accept': request.method == 'GET'
              ? 'image/jpeg, image/png'
              : 'application/json',
        });
        final response = await client.send(request);
        if (response.contentLength != null && response.contentLength! > limit) {
          throw const CoverTransportException(413, '封面响应超出大小限制。');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (_closed) throw StateError('封面连接已关闭。');
          if (bytes.length + chunk.length > limit) {
            throw const CoverTransportException(413, '封面响应超出大小限制。');
          }
          bytes.add(chunk);
        }
        if (_closed) throw StateError('封面连接已关闭。');
        return (
          status: response.statusCode,
          headers: Map<String, String>.unmodifiable(response.headers),
          bytes: bytes.takeBytes(),
        );
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
