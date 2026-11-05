import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:karuyomi/runtime/cover_transport.dart';

const asset = '35b6103d-08f4-4604-b958-42fe15c50377';
const subject = 'confirmed-subject';
final origin = Uri.parse('https://reader.example');
final payload = Uint8List.fromList([0, 1, 2, 255]);
final digest = sha256.convert(payload).toString();
final manga = List.filled(64, 'a').join();

Future<Uint8List> read(HttpCoverTransport transport, {String? hash}) =>
    transport.readCover(
      assetId: asset,
      subject: subject,
      sha256: hash ?? digest,
      byteLength: payload.length,
    );

void main() {
  test(
    'multipart carries opaque bytes and binds the same deployment identity',
    () async {
      var cookiesRead = 0;
      final transport = HttpCoverTransport(
        origin: origin,
        sessionHeaders: (target) async {
          expect(target, origin.resolve('/api/covers/$manga'));
          cookiesRead++;
          return {'Cookie': 'CF_Authorization=session'};
        },
        createClient: () => MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.followRedirects, false);
          expect(request.headers['Origin'], origin.origin);
          expect(request.headers['X-App-Subject'], subject);
          expect(request.headers['X-App-Request'], '1');
          expect(request.headers['Cookie'], 'CF_Authorization=session');
          expect(
            request.headers['content-type'],
            startsWith('multipart/form-data; boundary='),
          );
          final body = latin1.decode(request.bodyBytes);
          expect(body, contains('name="mutation"'));
          expect(body, contains('{"schemaVersion":1}'));
          expect(body, contains('name="image"; filename="cover.png"'));
          expect(body, contains('content-type: image/png'));
          expect(body, contains(latin1.decode(payload)));
          return http.Response(
            '{"ok":true}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(transport.close);
      final response = await transport.uploadCover(
        mangaKey: manga,
        mutation: '{"schemaVersion":1}',
        subject: subject,
        bytes: payload,
        contentType: 'image/png',
      );
      expect(response.status, 200);
      expect(response.redirected, false);
      expect(response.body, '{"ok":true}');
      expect(cookiesRead, 1);
    },
  );

  test(
    'download verifies its descriptor at transfer and returns immutable bytes',
    () async {
      final transport = HttpCoverTransport(
        origin: origin,
        createClient: () => MockClient((request) async {
          expect(request.url, origin.resolve('/api/covers/$asset'));
          expect(request.followRedirects, false);
          expect(request.headers['X-App-Subject'], subject);
          return http.Response.bytes(
            payload,
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      addTearDown(transport.close);
      final result = await read(transport);
      expect(result, orderedEquals(payload));
      expect(() => result[0] = 5, throwsUnsupportedError);
    },
  );

  test(
    'wrong digest, MIME, size, login redirect and missing object are rejected',
    () async {
      final variants = [
        http.Response.bytes(
          payload,
          200,
          headers: {'content-type': 'text/html'},
        ),
        http.Response.bytes(
          [0, 1],
          200,
          headers: {'content-type': 'image/png'},
        ),
        http.Response.bytes(
          [4, 3, 2, 1],
          200,
          headers: {'content-type': 'image/png'},
        ),
        http.Response('', 302, headers: {'location': 'https://login.example'}),
        http.Response('', 404),
      ];
      for (final response in variants) {
        final transport = HttpCoverTransport(
          origin: origin,
          createClient: () => MockClient((_) async => response),
        );
        await expectLater(
          read(transport),
          throwsA(isA<CoverTransportException>()),
        );
        transport.close();
      }
    },
  );

  test('announced and streaming limits stop an oversized download', () async {
    for (final announced in [true, false]) {
      var cancelled = false;
      late StreamController<List<int>> controller;
      controller = StreamController<List<int>>(
        onListen: () {
          controller.add(Uint8List(coverByteLimit));
          controller.add([1]);
        },
        onCancel: () => cancelled = true,
      );
      final transport = HttpCoverTransport(
        origin: origin,
        createClient: () => MockClient.streaming((_, body) async {
          await body.drain<void>();
          return http.StreamedResponse(
            controller.stream,
            200,
            contentLength: announced ? coverByteLimit + 1 : null,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      await expectLater(
        read(transport),
        throwsA(
          isA<CoverTransportException>().having((e) => e.status, 'status', 413),
        ),
      );
      if (!announced) expect(cancelled, true);
      transport.close();
      unawaited(controller.close());
    }
  });

  test('close retires an upload waiting for native session cookies', () async {
    final credentials = Completer<Map<String, String>>();
    var requests = 0;
    final transport = HttpCoverTransport(
      origin: origin,
      sessionHeaders: (_) => credentials.future,
      createClient: () => MockClient((_) async {
        requests++;
        return http.Response('', 200);
      }),
    );
    final pending = transport.uploadCover(
      mangaKey: manga,
      mutation: '{}',
      subject: subject,
      bytes: payload,
      contentType: 'image/png',
    );
    final rejected = expectLater(pending, throwsStateError);
    transport.close();
    credentials.complete({'Cookie': 'CF_Authorization=session'});
    await rejected;
    expect(requests, 0);
    await expectLater(read(transport), throwsStateError);
  });

  test('timeout discards the late response', () async {
    final response = Completer<http.Response>();
    final transport = HttpCoverTransport(
      origin: origin,
      timeout: const Duration(milliseconds: 10),
      createClient: () => MockClient((_) => response.future),
    );
    addTearDown(transport.close);
    await expectLater(read(transport), throwsA(isA<TimeoutException>()));
    response.complete(
      http.Response.bytes(payload, 200, headers: {'content-type': 'image/png'}),
    );
    await Future<void>.delayed(Duration.zero);
  });

  test('invalid identities and oversized uploads never reach HTTP', () async {
    var clients = 0;
    final transport = HttpCoverTransport(
      origin: origin,
      createClient: () {
        clients++;
        return MockClient((_) async => http.Response('', 200));
      },
    );
    addTearDown(transport.close);
    await expectLater(
      transport.readCover(
        assetId: '../bootstrap',
        subject: subject,
        sha256: digest,
        byteLength: payload.length,
      ),
      throwsArgumentError,
    );
    await expectLater(
      transport.readCover(
        assetId: asset.toUpperCase(),
        subject: subject,
        sha256: digest,
        byteLength: payload.length,
      ),
      throwsArgumentError,
    );
    await expectLater(
      transport.uploadCover(
        mangaKey: manga,
        mutation: '{}',
        subject: subject,
        bytes: Uint8List(coverByteLimit + 1),
        contentType: 'image/png',
      ),
      throwsArgumentError,
    );
    await expectLater(
      transport.readCover(
        assetId: asset,
        subject: '',
        sha256: digest,
        byteLength: payload.length,
      ),
      throwsArgumentError,
    );
    expect(clients, 0);
  });
}
