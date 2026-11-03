import 'dart:async';
import 'package:source_runtime/source_runtime.dart';
import 'package:test/test.dart';

final class FakeTransport implements RuntimeTransport {
  final calls = <(String, Map<String, Object?>)>[];
  Future<Object?> Function(String, Map<String, Object?>)? handler;
  @override
  Future<Object?> call(
    String method, [
    Map<String, Object?> payload = const {},
  ]) async {
    calls.add((method, payload));
    if (handler != null) return handler!(method, payload);
    return switch (method) {
      'ready' => {
        'protocolVersion': protocolVersion,
        'hostAbi': hostAbi,
        'runtimeBaseline': runtimeBaseline,
      },
      'open' => {
        'protocolVersion': protocolVersion,
        'buildId': 'build-1',
        'workerInstanceId': 'worker-1',
        'generation': 'generation-1',
        'sources': [
          {'id': '9223372036854775806', 'name': 'Source', 'lang': 'en'},
        ],
        'capabilities': ['source-rpc'],
      },
      'invoke' => {
        'requestId': payload['requestId'],
        'generation': 'generation-1',
        'buildId': 'build-1',
        'data': {'mangas': <Object?>[], 'hasNextPage': false},
      },
      _ => null,
    };
  }
}

BuildDescriptor build({String identity = 'owner', String? path}) =>
    BuildDescriptor(
      buildId: 'build-1',
      manifestUri: Uri.parse(
        path ?? '/extensions/builds/build-1/manifest.json',
      ),
      sha256: 'hash',
      identity: identity,
      packageId: 'package-1',
    );
SourceRequest request({
  String generation = 'generation-1',
  String sourceId = '9223372036854775806',
}) => SourceRequest(
  requestId: 'request-1',
  generation: generation,
  packageId: 'package-1',
  sourceId: sourceId,
  operation: 'popular',
  arguments: {'page': 2},
);
TypeMatcher<RuntimeException> failure(RuntimeErrorCode code) =>
    isA<RuntimeException>().having((error) => error.code, 'code', code);

ImageAcquireRequest imageRequest({String generation = 'generation-1'}) =>
    ImageAcquireRequest(
      requestId: 'image-1',
      sourceId: '9223372036854775806',
      pageSessionId: 'pages-1',
      pageKey: 'p-0',
      generation: generation,
    );
Map<String, Object?> imageReply() => {
  'resourceId': 'resource-1',
  'generation': 'generation-1',
  'mimeType': 'image/png',
  'byteLength': 1234,
  'width': 600,
  'height': 900,
  'url': 'blob:https://reader.example/image-1',
};

void main() {
  test('shares concurrent open and keeps Long identities as strings', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    final a = runtime.open(build());
    final b = runtime.open(build());
    final session = await a;
    expect((await b).generation, session.generation);
    expect(session.sources.single.id, '9223372036854775806');
    expect(transport.calls.where((call) => call.$1 == 'open'), hasLength(1));
    final payload = transport.calls.firstWhere((call) => call.$1 == 'open').$2;
    expect(payload['expectedBuildId'], 'build-1');
    expect(payload['expectedBundleSha256'], 'hash');
    expect((await runtime.invoke(request())).data['hasNextPage'], false);
    await runtime.dispose();
  });

  test(
    'refuses unconfirmed identities and mismatched/cross-origin static manifests',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await expectLater(
        runtime.open(build(identity: '')),
        throwsA(failure(RuntimeErrorCode.accessRequired)),
      );
      for (final path in [
        '/runtime/build.json',
        '/api/extensions/builds/build-1/manifest',
        '/extensions/builds/other/manifest.json',
        '/extensions/builds/build-1/manifest.json?old=1',
        'https://another.example/extensions/builds/build-1/manifest.json',
      ]) {
        await expectLater(
          runtime.open(build(path: path)),
          throwsA(failure(RuntimeErrorCode.protocolError)),
        );
      }
      expect(transport.calls, isEmpty);
      await runtime.dispose();
    },
  );

  test('stale or foreign Source requests never enter the transport', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    await expectLater(
      runtime.invoke(request(generation: 'old')),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
    await expectLater(
      runtime.invoke(request(sourceId: 'other')),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
    expect(transport.calls.where((call) => call.$1 == 'invoke'), isEmpty);
    await runtime.dispose();
  });

  test('native process replacement discards late control results', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    final response = Completer<Object?>();
    transport.handler = (method, payload) async =>
        method == 'invoke' ? response.future : null;
    final invocation = runtime.invoke(request());
    final assertion = expectLater(
      invocation,
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
    runtime.containerLost('process recycled');
    response.complete({
      'requestId': 'request-1',
      'generation': 'generation-1',
      'buildId': 'build-1',
      'data': {'stale': true},
    });
    await assertion;
    await runtime.dispose();
  });

  test(
    'expired handshake never starts a Source in a replacement container',
    () async {
      final transport = FakeTransport();
      final ready = Completer<Object?>();
      transport.handler = (method, payload) async =>
          method == 'ready' ? ready.future : null;
      final runtime = TransportSourceRuntime(transport);
      final opening = runtime.open(build());
      final assertion = expectLater(
        opening,
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      runtime.containerLost('replaced during ready');
      ready.complete({
        'protocolVersion': protocolVersion,
        'hostAbi': hostAbi,
        'runtimeBaseline': runtimeBaseline,
      });
      await assertion;
      expect(transport.calls.where((call) => call.$1 == 'open'), isEmpty);
      await runtime.dispose();
    },
  );

  test(
    'malformed session capabilities are a structured protocol error',
    () async {
      final transport = FakeTransport();
      transport.handler = (method, payload) async => switch (method) {
        'ready' => {
          'protocolVersion': protocolVersion,
          'hostAbi': hostAbi,
          'runtimeBaseline': runtimeBaseline,
        },
        'open' => {
          'protocolVersion': protocolVersion,
          'buildId': 'build-1',
          'workerInstanceId': 'worker-1',
          'generation': 'generation-1',
          'sources': <Object?>[],
          'capabilities': <Object?>[42],
        },
        _ => null,
      };
      final runtime = TransportSourceRuntime(transport);
      await expectLater(
        runtime.open(build()),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      await runtime.dispose();
    },
  );

  test(
    'Java errors retain category, class and message across native JSON RPC',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      transport.handler = (method, payload) async {
        if (method == 'invoke') {
          throw {
            'code': 'source_error',
            'message': 'Explicit reference is required',
            'javaClass': 'java.lang.IllegalArgumentException',
          };
        }
        return null;
      };
      await expectLater(
        runtime.invoke(request()),
        throwsA(
          failure(RuntimeErrorCode.sourceError).having(
            (error) => error.javaClass,
            'javaClass',
            'java.lang.IllegalArgumentException',
          ),
        ),
      );
      await runtime.dispose();
    },
  );

  test(
    'image controls pass explicit handles and require release/cancel acknowledgements',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      transport.handler = (method, payload) async => switch (method) {
        'acquireImage' => imageReply(),
        'cancelImage' || 'releaseImage' => {'released': true},
        'closePageSession' => {'closed': true},
        _ => null,
      };
      final image = await runtime.acquireImage(imageRequest());
      expect(image.width, 600);
      expect(image.location.scheme, 'blob');
      expect(transport.calls.last.$2, {
        'requestId': 'image-1',
        'sourceId': '9223372036854775806',
        'pageSessionId': 'pages-1',
        'pageKey': 'p-0',
        'generation': 'generation-1',
        'timeoutMs': 30000,
      });
      await runtime.cancelImage(
        const ImageCancelRequest(
          requestId: 'image-1',
          generation: 'generation-1',
        ),
      );
      await runtime.releaseImage(
        const ImageReleaseRequest(
          resourceId: 'resource-1',
          generation: 'generation-1',
        ),
      );
      await runtime.closePageSession(
        const PageSessionRef(
          pageSessionId: 'pages-1',
          generation: 'generation-1',
        ),
      );
      expect(transport.calls.where((call) => call.$1 == 'cancel'), isEmpty);
      await runtime.dispose();
    },
  );

  test(
    'rejects Source URLs and invalid dimensions and releases rejected resources',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      for (final invalid in [
        {'url': 'https://source.example/raw.png'},
        {'url': 'data:image/png;base64,AAAA'},
        {'width': 1.5},
        {'height': 0},
        {'byteLength': 64 * 1024 * 1024 + 1},
      ]) {
        transport.handler = (method, payload) async => method == 'acquireImage'
            ? {...imageReply(), ...invalid}
            : {'released': true};
        await expectLater(
          runtime.acquireImage(imageRequest()),
          throwsA(failure(RuntimeErrorCode.protocolError)),
        );
        expect(transport.calls.last.$1, 'releaseImage');
      }
      await expectLater(
        runtime.acquireImage(imageRequest(generation: 'old')),
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      transport.handler = (_, payload) async => {'released': false};
      await expectLater(
        runtime.releaseImage(
          const ImageReleaseRequest(
            resourceId: 'resource-1',
            generation: 'generation-1',
          ),
        ),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      await runtime.dispose();
    },
  );

  test(
    'late image after container replacement is released under its original generation',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final result = Completer<Object?>();
      transport.handler = (method, payload) async =>
          method == 'acquireImage' ? result.future : {'released': true};
      final acquiring = runtime.acquireImage(imageRequest());
      final assertion = expectLater(
        acquiring,
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      runtime.containerLost('replaced');
      result.complete(imageReply());
      await assertion;
      expect(transport.calls.last.$1, 'releaseImage');
      expect(transport.calls.last.$2, {
        'resourceId': 'resource-1',
        'generation': 'generation-1',
      });
      await runtime.dispose();
    },
  );

  test('dispose is idempotent and prevents future runtime work', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    await runtime.dispose();
    await runtime.dispose();
    expect(transport.calls.where((call) => call.$1 == 'dispose'), hasLength(1));
    await expectLater(
      runtime.invoke(request()),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
  });

  test(
    'an image timeout stays local while a real container loss is broadcast',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final events = <RuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      transport.handler = (_, payload) async =>
          throw {'code': 'timeout', 'message': 'Image cancelled and unwound'};
      await expectLater(
        runtime.acquireImage(imageRequest()),
        throwsA(failure(RuntimeErrorCode.timeout)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      transport.handler = (_, payload) async => throw {
        'code': 'runtime_lost',
        'message': 'Cancellation needed Worker recycle',
      };
      await expectLater(
        runtime.acquireImage(imageRequest()),
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events.single.code, RuntimeErrorCode.runtimeLost);
      await subscription.cancel();
      transport.handler = null;
      await runtime.dispose();
    },
  );
}
