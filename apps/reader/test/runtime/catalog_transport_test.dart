import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/runtime/catalog_transport.dart';

void main() {
  late HttpServer server;
  late HttpCatalogTransport transport;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    transport = HttpCatalogTransport(timeout: const Duration(seconds: 2));
  });
  tearDown(() async {
    transport.close();
    await server.close(force: true);
  });
  Uri location(String path) =>
      Uri.parse('http://127.0.0.1:${server.port}$path');

  test(
    'public reads send only anonymous JSON requests and accept case-insensitive exact JSON MIME',
    () async {
      final received = Completer<HttpRequest>();
      server.listen((request) async {
        received.complete(request);
        request.response.headers.set(
          'content-type',
          'Application/JSON; charset=utf-8',
        );
        request.response.write('{"repo":"community"}');
        await request.response.close();
      });
      expect(await transport.read(location('/extensions/index.json')), {
        'repo': 'community',
      });
      final request = await received.future;
      expect(request.headers.value('cookie'), isNull);
      expect(request.headers.value('authorization'), isNull);
      expect(request.headers.value('accept'), 'application/json');
    },
  );

  test(
    'redirects are rejected without requesting the redirected destination',
    () async {
      final paths = <String>[];
      server.listen((request) async {
        paths.add(request.uri.path);
        request.response.statusCode = 302;
        request.response.headers.set('location', '/secret');
        await request.response.close();
      });
      await expectLater(
        transport.read(location('/extensions/index.json')),
        throwsFormatException,
      );
      expect(paths, ['/extensions/index.json']);
    },
  );

  test(
    'deceptive JSON MIME and declared oversized documents are rejected',
    () async {
      server.listen((request) async {
        if (request.uri.path == '/bad-mime') {
          request.response.headers.set('content-type', 'not-application/json');
          request.response.write('{}');
        } else {
          request.response.headers.set('content-type', 'application/json');
          request.response.contentLength = HttpCatalogTransport.byteLimit + 1;
          request.response.add([32]);
          await request.response.flush();
          return;
        }
        try {
          await request.response.close();
        } on HttpException {
          /* Deliberately incomplete oversized response. */
        }
      });
      await expectLater(
        transport.read(location('/bad-mime')),
        throwsFormatException,
      );
      await expectLater(
        transport.read(location('/oversized')),
        throwsFormatException,
      );
    },
  );

  test(
    'chunked documents are bounded independently of Content-Length',
    () async {
      server.listen((request) async {
        request.response.headers.set('content-type', 'application/json');
        try {
          for (var i = 0; i < 33; i++) {
            request.response.add(utf8.encode(' ' * 65536));
            await request.response.flush();
          }
          await request.response.close();
        } on SocketException {
          /* The bounded client closes the connection. */
        }
      });
      await expectLater(
        transport.read(location('/extensions/index.json')),
        throwsFormatException,
      );
    },
  );

  test('caller cancellation immediately closes a held request', () async {
    final started = Completer<void>();
    server.listen((request) {
      started.complete();
      // Leave headers unsent to exercise cancellation while fetch is pending.
    });
    final cancelled = Completer<void>();
    final reading = transport.read(
      location('/extensions/index.json'),
      cancelled: cancelled.future,
    );
    final outcome = expectLater(reading, throwsA(isA<Exception>()));
    await started.future;
    cancelled.complete();
    await outcome.timeout(const Duration(seconds: 1));
  });
}
