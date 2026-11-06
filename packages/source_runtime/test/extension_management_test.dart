import 'dart:async';

import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';
import 'package:test/test.dart';

import 'support/fake_runtime_transport.dart';

wire.ExtensionBuildDescriptor descriptor() => wire.ExtensionBuildDescriptor(
  buildId: 'build-1',
  packageName: 'package-1',
  repoId: 'repo',
  version: '1',
  manifestPath: '/extensions/builds/build-1/manifest.json',
  sourceIds: [sourceId],
  sources: [wire.CatalogSource(id: sourceId, name: 'Source', lang: 'en')],
);

void main() {
  test('preparation rejects a reply for a different catalog origin', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    addTearDown(runtime.dispose);
    transport.handler = (request) async => request.hasPrepareBuild()
        ? wire.ControlResponse(
            requestId: request.requestId,
            preparedBuild: wire.PreparedBuild(
              build: request.prepareBuild.build,
              catalog: wire.CatalogReference(
                catalogUrl: 'https://other.example/extensions/index.json',
                repoId: 'repo',
              ),
              bundleSha256: 'a' * 64,
              byteLength: 12,
            ),
          )
        : transport.respond(request);
    await expectLater(
      runtime.prepareBuild(
        preparationId: 'prepare-1',
        catalog: catalog(),
        build: descriptor(),
      ),
      throwsFormatException,
    );
  });

  test(
    'open cache includes catalog identity and validates the returned session catalog',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      addTearDown(runtime.dispose);
      final original = build();
      await runtime.open(original);
      final external = BuildDescriptor(
        buildId: original.buildId,
        catalog: wire.CatalogReference(
          catalogUrl: 'https://other.example/extensions/index.json',
          repoId: original.catalog.repoId,
        ),
        manifestUri: original.manifestUri,
        sha256: original.sha256,
        identity: original.identity,
        packageId: original.packageId,
      );
      final opened = await runtime.open(external);
      expect(opened.catalog, external.catalog);
      expect(
        transport.calls.where((request) => request.hasOpen()),
        hasLength(2),
      );
      transport.handler = (request) async {
        final response = transport.respond(request);
        if (request.hasOpen()) response.session.catalog = external.catalog;
        return response;
      };
      await expectLater(
        runtime.open(original),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
    },
  );

  test(
    'prepare/cache are frozen independent controls and cannot open or invoke a Source',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      transport.handler = (request) async {
        if (request.hasPrepareBuild()) {
          return wire.ControlResponse(
            requestId: request.requestId,
            preparedBuild: wire.PreparedBuild(
              build: request.prepareBuild.build.deepCopy(),
              catalog: request.prepareBuild.catalog.deepCopy(),
              bundleSha256: 'a' * 64,
              byteLength: 12,
            ),
          );
        }
        if (request.hasExtensionCache()) {
          return wire.ControlResponse(
            requestId: request.requestId,
            extensionCache: wire.ExtensionCacheState(
              artifacts: [
                wire.CachedExtensionArtifact(
                  sha256: 'a' * 64,
                  byteLength: 12,
                  contentType: 'application/javascript',
                ),
              ],
              totalBytes: 12,
              maxBytes: 256 * 1024 * 1024,
              maxArtifacts: 128,
            ),
          );
        }
        return transport.respond(request);
      };
      final input = descriptor();
      final prepared = await runtime.prepareBuild(
        preparationId: 'prepare-1',
        catalog: catalog(),
        build: input,
      );
      input.sources.single.name = 'changed';
      expect(prepared.build.sources.single.name, 'Source');
      expect(() => prepared.build.sources.clear(), throwsUnsupportedError);
      expect((await runtime.extensionCache()).totalBytes, 12);
      await runtime.cancelPreparation('prepare-1');
      await runtime.forgetExtensionArtifact('a' * 64);
      expect(
        transport.calls.any((call) => call.hasOpen() || call.hasInvoke()),
        false,
      );
      await runtime.dispose();
    },
  );

  test(
    'management errors and false close ACK preserve an active Source, confirmed close fences later calls',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      final events = <RuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      await runtime.open(build());
      transport.handler = (call) async {
        if (call.hasPrepareBuild() || call.hasExtensionCache()) {
          return wire.ControlResponse(
            requestId: call.requestId,
            error: wire.RuntimeError(
              code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_RUNTIME_LOST,
              message: 'Asset unavailable',
            ),
          );
        }
        if (call.hasCloseBuild()) {
          return wire.ControlResponse(
            requestId: call.requestId,
            closed: wire.Closed(closed: false),
          );
        }
        return transport.respond(call);
      };
      await expectLater(
        runtime.prepareBuild(
          preparationId: 'p',
          catalog: catalog(),
          build: descriptor(),
        ),
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      await expectLater(
        runtime.extensionCache(),
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      await expectLater(
        runtime.closeBuild(buildId: 'build-1', generation: 'generation-1'),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      await runtime.invoke(request());
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      transport.handler = (call) async => call.hasCloseBuild()
          ? wire.ControlResponse(
              requestId: call.requestId,
              closed: wire.Closed(closed: true),
            )
          : transport.respond(call);
      await runtime.closeBuild(buildId: 'build-1', generation: 'generation-1');
      await expectLater(
        runtime.invoke(request()),
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      await subscription.cancel();
      await runtime.dispose();
    },
  );

  test(
    'API lost ACK preserves the active Source while Access failures still pause execution',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      final events = <RuntimeEvent>[];
      final subscription = runtime.events.listen(events.add);
      await runtime.open(build());
      transport.handler = (call) async {
        if (call.hasFetchApi()) {
          throw StateError('Lost API response');
        }
        return transport.respond(call);
      };
      await expectLater(
        runtime.fetchApi(
          wire.ApiFetchRequest(path: '/api/settings/mutations', method: 'POST'),
        ),
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      await runtime.invoke(request());
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      transport.handler = (call) async => call.hasFetchApi()
          ? wire.ControlResponse(
              requestId: call.requestId,
              error: wire.RuntimeError(
                code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_ACCESS_REQUIRED,
                message: 'Log in',
              ),
            )
          : transport.respond(call);
      await expectLater(
        runtime.fetchApi(wire.ApiFetchRequest(path: '/api/settings')),
        throwsA(failure(RuntimeErrorCode.accessRequired)),
      );
      await expectLater(
        runtime.invoke(request()),
        throwsA(failure(RuntimeErrorCode.accessRequired)),
      );
      await subscription.cancel();
      await runtime.dispose();
    },
  );

  test('a delayed old close cannot clear a new Source session', () async {
    final transport = FakeTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    final entered = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    transport.handler = (call) async {
      if (call.hasCloseBuild()) {
        entered.complete();
        await release.future;
        return wire.ControlResponse(
          requestId: call.requestId,
          closed: wire.Closed(closed: true),
        );
      }
      final response = transport.respond(call);
      if (call.hasOpen()) response.session.generation = 'generation-2';
      if (call.hasInvoke()) response.source.generation = 'generation-2';
      return response;
    };
    final closing = runtime.closeBuild(
      buildId: 'build-1',
      generation: 'generation-1',
    );
    final outcome = expectLater(
      closing,
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
    await entered.future.timeout(const Duration(seconds: 5));
    await runtime.open(build(identity: 'new-owner'));
    release.complete();
    await outcome;
    expect(
      (await runtime.invoke(request(generation: 'generation-2'))).generation,
      'generation-2',
    );
    await runtime.dispose();
  });
}
