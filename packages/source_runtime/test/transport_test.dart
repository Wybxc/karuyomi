import 'dart:async';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:test/test.dart';

const sourceId = '9223372036854775806';

final class FakeTransport implements RuntimeTransport {
  final calls = <wire.ControlRequest>[];
  Future<wire.ControlResponse> Function(wire.ControlRequest)? handler;
  Object? Function(wire.ControlRequest, Map<String, Object?>)? corrupt;

  wire.ControlResponse respond(wire.ControlRequest request) {
    final response = wire.ControlResponse(requestId: request.requestId);
    switch (request.whichCommand()) {
      case wire.ControlRequest_Command.ready:
        response.hello = wire.RuntimeHello(
          protocolVersion: protocolVersion,
          hostAbi: hostAbi,
          runtimeBaseline: runtimeBaseline,
        );
      case wire.ControlRequest_Command.open:
        response.session = wire.RuntimeSession(
          protocolVersion: protocolVersion,
          buildId: 'build-1',
          workerInstanceId: 'worker-1',
          generation: 'generation-1',
          sources: [wire.SourceInfo(id: sourceId, name: 'Source', lang: 'en')],
          capabilities: ['source-rpc'],
        );
      case wire.ControlRequest_Command.invoke:
        response.source = wire.SourceResult(
          requestId: request.invoke.requestId,
          generation: 'generation-1',
          buildId: 'build-1',
          mangaPage: wire.MangaPage(hasNextPage: false),
        );
      case wire.ControlRequest_Command.acquireImage:
        response.image = wire.ImageResource(
          resourceId: 'resource-1',
          generation: 'generation-1',
          mimeType: 'image/png',
          byteLength: 1234,
          width: 600,
          height: 900,
          url: 'blob:https://reader.example/image-1',
        );
      case wire.ControlRequest_Command.cancelImage ||
          wire.ControlRequest_Command.releaseImage:
        response.released = wire.Released(released: true);
      case wire.ControlRequest_Command.closePageSession:
        response.closed = wire.Closed(closed: true);
      default:
        response.completed = wire.Completed(completed: true);
    }
    return response;
  }

  @override
  Future<Object?> control(Map<String, Object?> json) async {
    final request = wire.decodeProtoJson(wire.ControlRequest(), json);
    calls.add(request.deepCopy()..freeze());
    final response = handler == null
        ? respond(request)
        : await handler!(request);
    final encoded = wire.encodeProtoJson(
      response,
      maxBytes: wire.controlJsonLimit,
    );
    return corrupt?.call(request, encoded) ?? encoded;
  }
}

final class ManagedTransport
    implements RuntimeTransport, ManagedImageTransport {
  ManagedTransport(this.delegate);
  final FakeTransport delegate;
  Uri? owned;
  @override
  Future<Object?> control(Map<String, Object?> request) =>
      delegate.control(request);
  @override
  bool ownsImageLocation(String resourceId, String generation, Uri location) =>
      resourceId == 'resource-1' &&
      generation == 'generation-1' &&
      location == owned;
}

BuildDescriptor build({String identity = 'owner', String? path}) =>
    BuildDescriptor(
      buildId: 'build-1',
      manifestUri: Uri.parse(
        path ?? '/extensions/builds/build-1/manifest.json',
      ),
      sha256: 'a' * 64,
      identity: identity,
      packageId: 'package-1',
    );
SourceRequest request({
  String generation = 'generation-1',
  String id = sourceId,
}) => SourceRequest(
  packageId: 'package-1',
  call: wire.SourceCall(
    requestId: 'request-1',
    generation: generation,
    sourceId: id,
    popular: wire.PageRequest(page: 2),
    timeoutMs: 30000,
  ),
);
TypeMatcher<RuntimeException> failure(RuntimeErrorCode code) =>
    isA<RuntimeException>().having((error) => error.code, 'code', code);
ImageAcquireRequest imageRequest({String generation = 'generation-1'}) =>
    ImageAcquireRequest(
      requestId: 'image-1',
      sourceId: sourceId,
      pageSessionId: 'pages-1',
      pageKey: 'p-0',
      generation: generation,
    );

void main() {
  test(
    'concurrent open shares generated session and decimal Source identity',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      final first = runtime.open(build());
      final second = runtime.open(build());
      final session = await first;
      expect((await second).generation, session.generation);
      expect(session.sources.single.id, sourceId);
      expect(session.sources.single.hasSupportsLatest(), false);
      expect(transport.calls.where((call) => call.hasOpen()), hasLength(1));
      expect(
        transport.calls
            .singleWhere((call) => call.hasOpen())
            .open
            .expectedBundleSha256,
        'a' * 64,
      );
      final result = await runtime.invoke(request());
      expect(result.whichPayload(), wire.SourceResult_Payload.mangaPage);
      expect(result.mangaPage.hasNextPage, false);
      expect(transport.calls.last.invoke.popular.page, 2);
      expect(
        transport.calls.map((call) => call.requestId).toSet().length,
        transport.calls.length,
      );
      await runtime.dispose();
    },
  );

  test(
    'unconfirmed identity and noncanonical static paths never reach transport',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await expectLater(
        runtime.open(build(identity: '')),
        throwsA(failure(RuntimeErrorCode.accessRequired)),
      );
      for (final path in [
        '/runtime/build.json',
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

  test('foreign generation and Source cannot invoke transport', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    await expectLater(
      runtime.invoke(request(generation: 'old')),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
    await expectLater(
      runtime.invoke(request(id: 'other')),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
    expect(transport.calls.where((call) => call.hasInvoke()), isEmpty);
    await runtime.dispose();
  });

  test('container replacement discards late generated Source result', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    final ready = Completer<void>();
    transport.handler = (call) async {
      if (call.hasInvoke()) await ready.future;
      return transport.respond(call);
    };
    final assertion = expectLater(
      runtime.invoke(request()),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
    runtime.containerLost('process recycled');
    ready.complete();
    await assertion;
    await runtime.dispose();
  });

  test(
    'expired hello cannot start a Source in replacement container',
    () async {
      final transport = FakeTransport();
      final ready = Completer<void>();
      transport.handler = (call) async {
        if (call.hasReady()) await ready.future;
        return transport.respond(call);
      };
      final runtime = TransportSourceRuntime(transport);
      final assertion = expectLater(
        runtime.open(build()),
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      runtime.containerLost('replaced during hello');
      ready.complete();
      await assertion;
      expect(transport.calls.where((call) => call.hasOpen()), isEmpty);
      await runtime.dispose();
    },
  );

  test('invalid generated session shape is a protocol error', () async {
    final transport = FakeTransport();
    transport.corrupt = (call, json) => call.hasOpen()
        ? {
            ...json,
            'session': {
              ...json['session'] as Map,
              'capabilities': [42],
            },
          }
        : json;
    final runtime = TransportSourceRuntime(transport);
    await expectLater(
      runtime.open(build()),
      throwsA(failure(RuntimeErrorCode.protocolError)),
    );
    await runtime.dispose();
  });

  test(
    'generated error preserves category, Java class, message and retryability',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      transport.handler = (call) async => call.hasInvoke()
          ? wire.ControlResponse(
              requestId: call.requestId,
              error: wire.RuntimeError(
                code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_SOURCE_ERROR,
                message: 'Explicit reference is required',
                javaClass: 'java.lang.IllegalArgumentException',
                retryable: true,
              ),
            )
          : transport.respond(call);
      await expectLater(
        runtime.invoke(request()),
        throwsA(
          failure(RuntimeErrorCode.sourceError)
              .having(
                (error) => error.javaClass,
                'javaClass',
                'java.lang.IllegalArgumentException',
              )
              .having((error) => error.retryable, 'retryable', true),
        ),
      );
      await runtime.dispose();
    },
  );

  test('image control uses opaque handles and matching cleanup ACKs', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    final image = await runtime.acquireImage(imageRequest());
    expect(image.width, 600);
    expect(image.location.scheme, 'blob');
    expect(transport.calls.last.acquireImage.pageSessionId, 'pages-1');
    expect(transport.calls.last.acquireImage.pageKey, 'p-0');
    expect(transport.calls.last.acquireImage.timeoutMs, 30000);
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
    expect(transport.calls.where((call) => call.hasCancel()), isEmpty);
    transport.handler = (call) async => call.hasReleaseImage()
        ? wire.ControlResponse(
            requestId: call.requestId,
            released: wire.Released(),
          )
        : transport.respond(call);
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
  });

  test(
    'file images require the Native transport ownership table, including identity and generation',
    () async {
      final delegate = FakeTransport();
      final managed = ManagedTransport(delegate);
      final location = Uri.parse('file:///private/tmp/managed/image');
      delegate.handler = (request) async {
        final response = delegate.respond(request);
        if (request.hasAcquireImage()) response.image.url = location.toString();
        return response;
      };
      final runtime = TransportSourceRuntime(managed);
      await runtime.open(build());
      await expectLater(
        runtime.acquireImage(imageRequest()),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      managed.owned = location;
      final resource = await runtime.acquireImage(imageRequest());
      expect(resource.location, location);
      managed.owned = Uri.parse('file:///private/tmp/managed/other');
      await expectLater(
        runtime.acquireImage(imageRequest()),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      await runtime.dispose();
    },
  );

  test(
    'invalid managed locations and dimensions release rejected resource',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      for (final change in <void Function(wire.ImageResource)>[
        (image) => image.url = 'https://source.example/raw.png',
        (image) => image.url = 'data:image/png;base64,AAAA',
        (image) => image.height = 0,
        (image) => image.byteLength = 64 * 1024 * 1024 + 1,
      ]) {
        transport.handler = (call) async {
          final response = transport.respond(call);
          if (call.hasAcquireImage()) change(response.image);
          return response;
        };
        await expectLater(
          runtime.acquireImage(imageRequest()),
          throwsA(failure(RuntimeErrorCode.protocolError)),
        );
        expect(transport.calls.last.hasReleaseImage(), true);
      }
      await runtime.dispose();
    },
  );

  test(
    'late image after replacement is released under original generation',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final ready = Completer<void>();
      transport.handler = (call) async {
        if (call.hasAcquireImage()) await ready.future;
        return transport.respond(call);
      };
      final assertion = expectLater(
        runtime.acquireImage(imageRequest()),
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      runtime.containerLost('replaced');
      ready.complete();
      await assertion;
      expect(transport.calls.last.releaseImage.generation, 'generation-1');
      await runtime.dispose();
    },
  );

  test(
    'response control ID, result case and Source payload must match request',
    () async {
      for (final change in <void Function(wire.ControlResponse)>[
        (response) => response.requestId = 'foreign',
        (response) => response.completed = wire.Completed(completed: true),
        (response) => response.source.chapters = wire.ChapterList(),
      ]) {
        final transport = FakeTransport();
        final runtime = TransportSourceRuntime(transport);
        await runtime.open(build());
        transport.handler = (call) async {
          final response = transport.respond(call);
          if (call.hasInvoke()) change(response);
          return response;
        };
        await expectLater(
          runtime.invoke(request()),
          throwsA(failure(RuntimeErrorCode.protocolError)),
        );
        await runtime.dispose();
      }
    },
  );

  test(
    'opaque memo numeric lexemes and false optional presence survive response',
    () async {
      const memo = '{"id":9223372036854775806,"nested":{"huge":1e1000}}';
      final transport = FakeTransport();
      transport.handler = (call) async {
        final response = transport.respond(call);
        if (call.hasOpen()) {
          response.session.sources.single.supportsLatest = false;
        }
        if (call.hasInvoke()) {
          response.source.mangaPage.mangas.add(
            wire.Manga(url: '/m', title: 'm', memoJson: memo),
          );
        }
        return response;
      };
      final runtime = TransportSourceRuntime(transport);
      final session = await runtime.open(build());
      expect(session.sources.single.hasSupportsLatest(), true);
      expect(session.sources.single.supportsLatest, false);
      expect(
        (await runtime.invoke(request())).mangaPage.mangas.single.memoJson,
        memo,
      );
      await runtime.dispose();
    },
  );

  test('image timeout is local; lost generation remains broadcast', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    final events = <RuntimeEvent>[];
    final subscription = runtime.events.listen(events.add);
    var code = wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_TIMEOUT;
    transport.handler = (call) async => call.hasAcquireImage()
        ? wire.ControlResponse(
            requestId: call.requestId,
            error: wire.RuntimeError(
              code: code,
              message: 'Image unwind outcome',
            ),
          )
        : transport.respond(call);
    await expectLater(
      runtime.acquireImage(imageRequest()),
      throwsA(failure(RuntimeErrorCode.timeout)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    code = wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_RUNTIME_LOST;
    await expectLater(
      runtime.acquireImage(imageRequest()),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(events.single.code, RuntimeErrorCode.runtimeLost);
    await subscription.cancel();
    await runtime.dispose();
  });

  test('dispose is acknowledged once and rejects later work', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    await runtime.dispose();
    await runtime.dispose();
    expect(transport.calls.where((call) => call.hasDispose()), hasLength(1));
    await expectLater(
      runtime.invoke(request()),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
  });
}
