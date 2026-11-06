import 'dart:async';

import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';
import 'package:test/test.dart';

import 'support/fake_runtime_transport.dart';

/// Models independent physical owners behind the one platform bridge.
final class SlotTransport implements RuntimeTransport {
  final calls = <wire.ControlRequest>[];
  final _generations = <wire.RuntimeSlot, int>{};
  final _sessions = <wire.RuntimeSlot, wire.RuntimeSession>{};

  @override
  Future<Object?> control(Map<String, Object?> json) async {
    final command = wire.decodeProtoJson(wire.ControlRequest(), json);
    expect(
      command.slotId,
      anyOf(
        wire.RuntimeSlot.RUNTIME_SLOT_FOREGROUND,
        wire.RuntimeSlot.RUNTIME_SLOT_SEARCH,
      ),
    );
    calls.add(command.deepCopy()..freeze());
    final response = wire.ControlResponse(
      requestId: command.requestId,
      slotId: command.slotId,
    );
    switch (command.whichCommand()) {
      case wire.ControlRequest_Command.ready:
        response.hello = wire.RuntimeHello(
          protocolVersion: protocolVersion,
          hostAbi: hostAbi,
          runtimeBaseline: runtimeBaseline,
        );
      case wire.ControlRequest_Command.open:
        final sequence = (_generations[command.slotId] ?? 0) + 1;
        _generations[command.slotId] = sequence;
        final generation = '${command.slotId.name}-$sequence';
        response.session = wire.RuntimeSession(
          protocolVersion: protocolVersion,
          workerInstanceId: 'worker-$generation',
          generation: generation,
          catalog: command.open.catalog.deepCopy(),
          buildId: command.open.expectedBuildId,
          sources: [wire.SourceInfo(id: sourceId, name: 'Source', lang: 'en')],
          capabilities: ['source-rpc'],
        );
        _sessions[command.slotId] = response.session.deepCopy()..freeze();
      case wire.ControlRequest_Command.invoke:
        final session = _sessions[command.slotId]!;
        expect(command.invoke.generation, session.generation);
        response.source = wire.SourceResult(
          requestId: command.invoke.requestId,
          generation: session.generation,
          buildId: session.buildId,
          mangaPage: wire.MangaPage(hasNextPage: false),
        );
      case wire.ControlRequest_Command.closeBuild:
        final session = _sessions[command.slotId];
        if (session?.generation == command.closeBuild.generation) {
          _sessions.remove(command.slotId);
        }
        response.closed = wire.Closed(closed: true);
      case wire.ControlRequest_Command.rebuild ||
          wire.ControlRequest_Command.dispose:
        _sessions.remove(command.slotId);
        response.completed = wire.Completed(completed: true);
      default:
        response.completed = wire.Completed(completed: true);
    }
    return wire.encodeProtoJson(response);
  }
}

BuildDescriptor searchBuild() => BuildDescriptor(
  buildId: 'build-search',
  catalog: catalog(),
  manifestUri: Uri.parse('/extensions/builds/build-search/manifest.json'),
  sha256: 'b' * 64,
  identity: 'owner',
  packageId: 'package-search',
);

SourceRequest searchRequest(String generation) => SourceRequest(
  packageId: 'package-search',
  call: wire.SourceCall(
    requestId: 'search-request',
    generation: generation,
    sourceId: sourceId,
    search: wire.SearchRequest(page: 1, query: 'example'),
    timeoutMs: 30000,
  ),
);

void main() {
  test('a transport cannot be constructed for an unspecified slot', () {
    expect(
      () => TransportSourceRuntime(
        FakeTransport(),
        slotId: wire.RuntimeSlot.RUNTIME_SLOT_UNSPECIFIED,
      ),
      throwsArgumentError,
    );
  });

  test(
    'search close and rebuild are addressed to its slot and preserve foreground ownership',
    () async {
      final transport = SlotTransport();
      final foreground = TransportSourceRuntime(transport);
      final search = TransportSourceRuntime(
        transport,
        slotId: wire.RuntimeSlot.RUNTIME_SLOT_SEARCH,
      );
      addTearDown(foreground.dispose);
      addTearDown(search.dispose);
      final events = <RuntimeEvent>[];
      final subscription = foreground.events.listen(events.add);
      addTearDown(subscription.cancel);
      final reading = await foreground.open(build());
      final initial = await search.open(searchBuild());
      expect(initial.generation, isNot(reading.generation));
      expect(
        (await search.invoke(searchRequest(initial.generation))).generation,
        initial.generation,
      );
      await search.cancel('search-request');
      await search.closeBuild(
        buildId: initial.buildId,
        generation: initial.generation,
      );
      final replacement = await search.open(searchBuild());
      expect(replacement.generation, isNot(initial.generation));
      await search.rebuildHost();
      expect(
        (await foreground.invoke(
          request(generation: reading.generation),
        )).generation,
        reading.generation,
      );
      expect(events, isEmpty);
      expect(
        transport.calls
            .where(
              (value) =>
                  value.hasCancel() ||
                  value.hasCloseBuild() ||
                  value.hasRebuild(),
            )
            .every(
              (value) => value.slotId == wire.RuntimeSlot.RUNTIME_SLOT_SEARCH,
            ),
        true,
      );
    },
  );

  for (final replacement in [
    null,
    'RUNTIME_SLOT_SEARCH',
    'RUNTIME_SLOT_UNSPECIFIED',
  ]) {
    test(
      'a foreground response with $replacement slot is rejected despite matching request identity',
      () async {
        final transport = FakeTransport();
        final runtime = TransportSourceRuntime(transport);
        addTearDown(runtime.dispose);
        await runtime.open(build());
        transport.corrupt = (request, response) => request.hasInvoke()
            ? (Map<String, Object?>.of(response)..remove('slotId'))
            : response;
        if (replacement != null) {
          transport.corrupt = (request, response) => request.hasInvoke()
              ? {...response, 'slotId': replacement}
              : response;
        }
        await expectLater(
          runtime.invoke(request()),
          throwsA(failure(RuntimeErrorCode.protocolError)),
        );
        transport.corrupt = null;
      },
    );
  }

  for (final method in ['GET', 'POST']) {
    for (final reset in [false, true]) {
      test(
        '${reset ? 'resetting' : 'opening'} this slot does not expire the in-flight $method account ACK',
        () async {
          final transport = FakeTransport();
          final runtime = TransportSourceRuntime(transport);
          addTearDown(runtime.dispose);
          final entered = Completer<void>();
          final release = Completer<void>();
          addTearDown(() {
            if (!release.isCompleted) release.complete();
          });
          transport.handler = (request) async {
            if (!request.hasFetchApi()) return transport.respond(request);
            entered.complete();
            await release.future;
            return wire.ControlResponse(
              requestId: request.requestId,
              slotId: request.slotId,
              api: wire.ApiFetchResponse(
                status: 200,
                headers: {'content-type': 'application/json'}.entries,
                body: '{"confirmed":true}',
              ),
            );
          };
          final acknowledgement = runtime.fetchApi(
            wire.ApiFetchRequest(
              path: '/api/state/mutations',
              method: method,
              headers: {'X-App-Subject': 'owner', 'X-App-Request': '1'}.entries,
              body: method == 'POST' ? '{}' : null,
            ),
          );
          await entered.future;
          if (reset) {
            await runtime.rebuildHost();
          } else {
            await runtime.open(build());
          }
          release.complete();
          final reply = await acknowledgement;
          expect(reply.status, 200);
          expect(reply.body, '{"confirmed":true}');
        },
      );
    }
  }

  test(
    'container invalidation still retires an in-flight account ACK',
    () async {
      final transport = FakeTransport();
      final runtime = TransportSourceRuntime(transport);
      addTearDown(runtime.dispose);
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      transport.handler = (request) async {
        if (!request.hasFetchApi()) return transport.respond(request);
        entered.complete();
        await release.future;
        return wire.ControlResponse(
          requestId: request.requestId,
          slotId: request.slotId,
          api: wire.ApiFetchResponse(status: 200, body: '{}'),
        );
      };
      final acknowledgement = runtime.fetchApi(
        wire.ApiFetchRequest(path: '/api/bootstrap', method: 'GET'),
      );
      final rejected = expectLater(
        acknowledgement,
        throwsA(failure(RuntimeErrorCode.runtimeLost)),
      );
      await entered.future;
      runtime.containerLost('The platform container was replaced');
      release.complete();
      await rejected;
    },
  );
}
