import 'dart:async';
import 'package:source_runtime/source_runtime.dart';
import 'package:reader_core/reader_core.dart';
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
      manifestUri: Uri.parse(path ?? '/api/extensions/builds/build-1/manifest'),
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
    'refuses unconfirmed identities and public/cross-origin manifests',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await expectLater(
        runtime.open(build(identity: '')),
        throwsA(failure(RuntimeErrorCode.accessRequired)),
      );
      for (final path in [
        '/runtime/build.json',
        'https://another.example/api/extensions/builds/build-1/manifest',
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
    'images remain an explicit unsupported resource gate without a string body fallback',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await expectLater(
        runtime.acquire(
          const PageRef(
            requestId: 'image',
            chapterKey: 'chapter',
            pageKey: 'page',
            generation: 'generation',
          ),
        ),
        throwsA(failure(RuntimeErrorCode.unsupportedCapability)),
      );
      expect(transport.calls, isEmpty);
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
}
