import 'dart:async';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:test/test.dart';
import 'support/fake_runtime_transport.dart';

wire.EncodedImage encoded(
  String resourceId,
  String generation, {
  int width = 1080,
}) => wire.EncodedImage(
  resourceId: resourceId,
  generation: generation,
  mimeType: 'image/png',
  byteLength: 1234,
  rawWidth: width,
  rawHeight: 20000,
  orientation: 1,
);
wire.ImageTile tile(
  String id,
  String generation, {
  int index = 0,
  int width = 1080,
  bool provisional = true,
}) => wire.ImageTile(
  leaseId: id,
  sessionId: 'codec-session',
  index: index,
  denominator: 1,
  provisional: provisional,
  sourceRect: wire.ImageSourceRect(
    x: 0,
    y: index * 256,
    width: width,
    height: 256,
  ),
  resource: wire.ImageResource(
    resourceId: id,
    generation: generation,
    mimeType: 'image/png',
    byteLength: 1234,
    width: width,
    height: 256,
    url: 'blob:https://reader.example/$id',
  ),
);
wire.RequestImageWindow window(
  wire.ImagePage page, {
  String id = 'window-1',
  int y = 0,
  int end = 256,
}) => wire.RequestImageWindow(
  pageId: page.pageId,
  generation: page.generation,
  windowId: id,
  sourceY: y,
  sourceEndY: end,
  denominator: 1,
);

final class TileTransport implements RuntimeTransport {
  TileTransport() {
    delegate.handler = _respond;
  }
  final delegate = FakeTransport();
  final windows = <String, wire.RequestImageWindow>{};
  final pages = <String, wire.ImagePage>{};
  Future<void> Function(wire.ControlRequest, wire.ControlResponse)? modify;
  String generation = 'generation-1';
  int width = 1080;
  int sequence = 0;
  int revision = 0;
  bool committed = false;
  List<wire.ControlRequest> get calls => delegate.calls;
  Future<wire.ControlResponse> _respond(wire.ControlRequest request) async {
    final response = delegate.respond(request);
    if (request.hasOpen()) response.session.generation = generation;
    if (request.hasOpenImagePage()) {
      final input = request.openImagePage;
      final page = wire.ImagePage(
        pageId: 'page-${++sequence}',
        generation: input.generation,
        encoded: encoded(input.resourceId, input.generation, width: width),
      );
      pages[page.pageId] = page.deepCopy();
      response.imagePage = page;
    }
    wire.RequestImageWindow? demand;
    if (request.hasRequestImageWindow()) {
      demand = request.requestImageWindow;
      windows[demand.pageId] = demand.deepCopy();
    } else if (request.hasWaitImageWindow()) {
      demand = windows[request.waitImageWindow.pageId];
    }
    if (demand != null) {
      final page = pages[demand.pageId]!;
      final index = demand.sourceY ~/ 256;
      response.imageWindow = wire.ImageWindowSnapshot(
        pageId: demand.pageId,
        generation: demand.generation,
        windowId: demand.windowId,
        revision: ++revision,
        state: committed
            ? wire.ImageWindowState.IMAGE_WINDOW_STATE_COMPLETE
            : wire.ImageWindowState.IMAGE_WINDOW_STATE_PENDING,
        header: wire.ImageTileHeader(
          width: page.encoded.rawWidth,
          height: page.encoded.rawHeight,
          sourceWidth: page.encoded.rawWidth,
          sourceHeight: page.encoded.rawHeight,
          denominator: 1,
        ),
        tiles: [
          tile(
            'lease-${demand.pageId}-$index',
            demand.generation,
            index: index,
            width: page.encoded.rawWidth,
            provisional: !committed,
          ),
        ],
      );
    }
    if (request.hasReleaseImageTile()) {
      response.released = wire.Released(released: true);
    }
    if (request.hasCloseImagePage()) {
      response.closed = wire.Closed(closed: true);
    }
    await modify?.call(request, response);
    return response;
  }

  @override
  Future<Object?> control(Map<String, Object?> request) =>
      delegate.control(request);
}

Future<wire.ImagePage> openPage(
  TransportSourceRuntime runtime, {
  String id = 'encoded-1',
  String generation = 'generation-1',
}) => runtime.openImagePage(
  wire.OpenImagePage(resourceId: id, generation: generation),
);

void main() {
  test(
    'page and window replies are frozen and a committed lease keeps its identity',
    () async {
      final transport = TileTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final page = await openPage(runtime);
      expect(page.isFrozen, true);
      expect(page.encoded.isFrozen, true);
      final snapshot = await runtime.requestImageWindow(window(page));
      expect(snapshot.isFrozen, true);
      expect(snapshot.tiles.single.resource.isFrozen, true);
      transport.committed = true;
      final terminal = await runtime.waitImageWindow(
        wire.WaitImageWindow(
          pageId: page.pageId,
          generation: page.generation,
          windowId: 'window-1',
          afterRevision: snapshot.revision,
          timeoutMs: 25000,
        ),
      );
      expect(terminal.state, wire.ImageWindowState.IMAGE_WINDOW_STATE_COMPLETE);
      expect(terminal.tiles.single.resource, snapshot.tiles.single.resource);
      expect(terminal.tiles.single.provisional, false);
      await runtime.closeImagePage(
        wire.CloseImagePage(pageId: page.pageId, generation: page.generation),
      );
      expect(
        transport.calls.where((call) => call.hasReleaseImageTile()),
        isEmpty,
      );
      await runtime.releaseImageTile(
        wire.ReleaseImageTile(
          leaseId: terminal.tiles.single.leaseId,
          generation: page.generation,
        ),
      );
      await runtime.dispose();
    },
  );

  test(
    'opening the same encoded page is idempotent and keeps the frozen owner',
    () async {
      final transport = TileTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final page = await openPage(runtime);
      transport.modify = (request, response) async {
        if (request.hasOpenImagePage()) {
          response.imagePage = page.deepCopy();
        }
      };
      final duplicate = await openPage(runtime);
      expect(identical(page, duplicate), true);
      expect(
        transport.calls.where((call) => call.hasCloseImagePage()),
        isEmpty,
      );
      await runtime.dispose();
    },
  );

  test(
    'a host-rejected new window preserves the previously accepted window',
    () async {
      final transport = TileTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final page = await openPage(runtime);
      final priorInput = window(page);
      final snapshot = await runtime.requestImageWindow(priorInput);
      transport.modify = (request, response) async {
        if (request.hasRequestImageWindow() &&
            request.requestImageWindow.windowId == 'rejected') {
          transport.windows[page.pageId] = priorInput.deepCopy();
          response.error = wire.RuntimeError(
            code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_LIMIT_EXCEEDED,
            message: 'window exceeds retained budget',
          );
        }
      };
      await expectLater(
        runtime.requestImageWindow(
          window(page, id: 'rejected', y: 256, end: 512),
        ),
        throwsA(failure(RuntimeErrorCode.limitExceeded)),
      );
      transport.modify = null;
      final current = await runtime.waitImageWindow(
        wire.WaitImageWindow(
          pageId: page.pageId,
          generation: page.generation,
          windowId: snapshot.windowId,
          afterRevision: snapshot.revision,
        ),
      );
      expect(current.windowId, snapshot.windowId);
      expect(current.tiles.single.resource, snapshot.tiles.single.resource);
      // An identity the host rejected can be submitted again after capacity changes.
      expect(
        (await runtime.requestImageWindow(
          window(page, id: 'rejected', y: 256, end: 512),
        )).windowId,
        'rejected',
      );
      await runtime.dispose();
    },
  );

  test(
    'tile budgets, identities, geometry and native file ownership are independently checked',
    () {
      final snapshot = wire.ImageWindowSnapshot(
        pageId: 'page',
        generation: 'g',
        windowId: 'w',
        revision: 1,
        state: wire.ImageWindowState.IMAGE_WINDOW_STATE_PENDING,
        header: wire.ImageTileHeader(
          width: 1080,
          height: 20000,
          sourceWidth: 1080,
          sourceHeight: 20000,
          denominator: 1,
        ),
        tiles: [tile('lease', 'g')],
      );
      expect(() => wire.checkImageWindow(snapshot), returnsNormally);
      final changes = <void Function(wire.ImageWindowSnapshot)>[
        (s) => s.pageId = '',
        (s) => s.generation = '',
        (s) => s.windowId = '',
        (s) => s.state = wire.ImageWindowState.IMAGE_WINDOW_STATE_UNSPECIFIED,
        (s) => s.clearHeader(),
        (s) => s.state = wire.ImageWindowState.IMAGE_WINDOW_STATE_FAILED,
        (s) => s.state = wire.ImageWindowState.IMAGE_WINDOW_STATE_COMPLETE,
        (s) => s.error = wire.RuntimeError(
          code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_SOURCE_ERROR,
          message: 'unexpected',
        ),
        (s) => s.header.width += 1,
        (s) => s.header.denominator = 3,
        (s) => s.tiles.single.leaseId = '',
        (s) => s.tiles.single.sessionId = '',
        (s) => s.tiles.single.resource.resourceId = 'other',
        (s) => s.tiles.single.resource.generation = 'other',
        (s) => s.tiles.single.resource.url = 'https://source.example/raw.png',
        (s) => s.tiles.single.resource.mimeType = 'image/jpeg',
        (s) => s.tiles.single.resource.byteLength = wire.imageTileByteLimit + 1,
        (s) => s.tiles.single.resource.height = 257,
        (s) => s.tiles.single.sourceRect.y = 1,
        (s) => s.tiles.single.sourceRect.width = 1000,
        (s) => s.tiles.single.sourceRect.height = 255,
        (s) => s.tiles.add(s.tiles.single.deepCopy()),
        (s) => s.invalidatedLeaseIds.add('lease'),
        (s) => s.invalidatedLeaseIds.addAll(
          List.generate(64, (i) => 'invalid-$i'),
        ),
      ];
      for (final change in changes) {
        final invalid = snapshot.deepCopy();
        change(invalid);
        expect(() => wire.checkImageWindow(invalid), throwsFormatException);
      }
      final native = snapshot.deepCopy();
      native.tiles.single.resource.url = 'file:///private/tmp/tile';
      expect(() => wire.checkImageWindow(native), throwsFormatException);
      expect(
        () => wire.checkImageWindow(
          native,
          isManagedFile: (resource) => resource.resourceId == 'lease',
        ),
        returnsNormally,
      );
      expect(
        () => wire.checkImageWindow(native, isManagedFile: (_) => false),
        throwsFormatException,
      );
    },
  );

  test('invalid page and window inputs fail before transport work', () async {
    final transport = TileTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    await expectLater(
      openPage(runtime, id: ''),
      throwsA(failure(RuntimeErrorCode.protocolError)),
    );
    await expectLater(
      openPage(runtime, generation: 'foreign'),
      throwsA(failure(RuntimeErrorCode.runtimeLost)),
    );
    final page = await openPage(runtime);
    final before = transport.calls.length;
    final changes = <void Function(wire.RequestImageWindow)>[
      (w) => w.windowId = '',
      (w) => w.sourceEndY = 0,
      (w) => w.sourceEndY = 20001,
      (w) => w.denominator = 3,
    ];
    for (final change in changes) {
      final input = window(page);
      change(input);
      await expectLater(
        runtime.requestImageWindow(input),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
    }
    final scaledPng = window(page)..denominator = 2;
    await expectLater(
      runtime.requestImageWindow(scaledPng),
      throwsA(failure(RuntimeErrorCode.unsupportedCapability)),
    );
    expect(transport.calls, hasLength(before));
    final snapshot = await runtime.requestImageWindow(window(page));
    final afterRequest = transport.calls.length;
    for (final (id, revision, timeout) in [
      ('foreign', snapshot.revision, 1),
      ('window-1', snapshot.revision + 1, 1),
      ('window-1', snapshot.revision, 0),
      ('window-1', snapshot.revision, 25001),
    ]) {
      await expectLater(
        runtime.waitImageWindow(
          wire.WaitImageWindow(
            pageId: page.pageId,
            generation: page.generation,
            windowId: id,
            afterRevision: revision,
            timeoutMs: timeout,
          ),
        ),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
    }
    final changed = window(page, y: 256, end: 512);
    await expectLater(
      runtime.requestImageWindow(changed),
      throwsA(failure(RuntimeErrorCode.protocolError)),
    );
    expect(transport.calls, hasLength(afterRequest));
    await runtime.dispose();
  });

  test(
    'bad returned page identities close only new page owners under the original generation',
    () async {
      final transport = TileTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final current = await openPage(runtime);
      transport.modify = (request, response) async {
        if (request.hasOpenImagePage()) {
          response.imagePage.generation = 'foreign';
        }
      };
      await expectLater(
        openPage(runtime, id: 'encoded-2'),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      final cleanup = transport.calls.last.closeImagePage;
      expect(cleanup.pageId, 'page-2');
      expect(cleanup.generation, 'generation-1');
      transport.modify = (request, response) async {
        if (request.hasOpenImagePage()) {
          response.imagePage.pageId = current.pageId;
        }
      };
      final closedBefore = transport.calls
          .where((call) => call.hasCloseImagePage())
          .length;
      await expectLater(
        openPage(runtime, id: 'encoded-3'),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(
        transport.calls.where((call) => call.hasCloseImagePage()),
        hasLength(closedBefore),
      );
      await runtime.dispose();
    },
  );

  test(
    'malformed new tiles release only their original generation and accepted leases remain displayed',
    () async {
      final transport = TileTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final page = await openPage(runtime);
      transport.modify = (request, response) async {
        if (request.hasRequestImageWindow()) {
          response.imageWindow.tiles.single.resource.generation = 'foreign';
        }
      };
      await expectLater(
        runtime.requestImageWindow(window(page)),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(transport.calls.last.releaseImageTile.generation, 'generation-1');
      transport.modify = null;
      final snapshot = await runtime.requestImageWindow(window(page));
      final releasesBefore = transport.calls
          .where((call) => call.hasReleaseImageTile())
          .length;
      transport.modify = (request, response) async {
        if (request.hasWaitImageWindow()) {
          response.imageWindow.tiles.single.resource.url += '-changed';
        }
      };
      await expectLater(
        runtime.waitImageWindow(
          wire.WaitImageWindow(
            pageId: page.pageId,
            generation: page.generation,
            windowId: snapshot.windowId,
            afterRevision: snapshot.revision,
          ),
        ),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(
        transport.calls.where((call) => call.hasReleaseImageTile()),
        hasLength(releasesBefore),
      );
      transport.modify = (request, response) async {
        if (request.hasRequestImageWindow()) {
          response.imageWindow.pageId = 'some-other-page';
        }
      };
      await expectLater(
        runtime.requestImageWindow(window(page, id: 'other', y: 256, end: 512)),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(
        transport.calls.where((call) => call.hasReleaseImageTile()),
        hasLength(releasesBefore),
      );
      await runtime.dispose();
    },
  );

  test(
    'rejected response envelopes clean new owners without releasing accepted tiles',
    () async {
      final transport = TileTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      transport.modify = (request, response) async {
        if (request.hasOpenImagePage()) response.requestId = 'foreign';
      };
      await expectLater(
        openPage(runtime),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(transport.calls.last.hasCloseImagePage(), true);
      transport.modify = null;
      final page = await openPage(runtime);
      transport.modify = (request, response) async {
        if (request.hasRequestImageWindow()) response.requestId = 'foreign';
      };
      await expectLater(
        runtime.requestImageWindow(window(page)),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(transport.calls.last.hasReleaseImageTile(), true);
      await runtime.dispose();
    },
  );

  test(
    'a replaced window rejects its late tiles and preserves the current Source',
    () async {
      final transport = TileTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final page = await openPage(runtime);
      final entered = Completer<void>();
      final ready = Completer<void>();
      transport.modify = (request, response) async {
        if (request.hasRequestImageWindow() &&
            request.requestImageWindow.windowId == 'old') {
          entered.complete();
          await ready.future;
        }
      };
      final old = expectLater(
        runtime.requestImageWindow(window(page, id: 'old')),
        throwsA(failure(RuntimeErrorCode.cancelled)),
      );
      await entered.future;
      final current = await runtime.requestImageWindow(
        window(page, id: 'new', y: 256, end: 512),
      );
      ready.complete();
      await old;
      expect(current.windowId, 'new');
      expect(
        transport.calls.last.releaseImageTile.leaseId,
        'lease-${page.pageId}-0',
      );
      await expectLater(
        runtime.requestImageWindow(window(page, id: 'old')),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      await expectLater(
        runtime.waitImageWindow(
          wire.WaitImageWindow(
            pageId: page.pageId,
            generation: page.generation,
            windowId: 'old',
            afterRevision: 0,
          ),
        ),
        throwsA(failure(RuntimeErrorCode.cancelled)),
      );
      await runtime.cancel('still-active');
      expect(transport.calls.last.cancel.generation, page.generation);
      await runtime.dispose();
    },
  );

  test(
    'late pages and windows are cleaned under their old generation after replacement',
    () async {
      for (final pageOpening in [true, false]) {
        final transport = TileTransport();
        final runtime = TransportSourceRuntime(transport);
        await runtime.open(build());
        final page = pageOpening ? null : await openPage(runtime);
        final entered = Completer<void>();
        final ready = Completer<void>();
        transport.modify = (request, response) async {
          if ((pageOpening && request.hasOpenImagePage()) ||
              (!pageOpening && request.hasRequestImageWindow())) {
            entered.complete();
            await ready.future;
          }
        };
        final old = expectLater(
          pageOpening
              ? openPage(runtime)
              : runtime.requestImageWindow(window(page!)),
          throwsA(failure(RuntimeErrorCode.runtimeLost)),
        );
        await entered.future;
        runtime.containerLost('replaced');
        transport.generation = 'generation-2';
        await runtime.open(build());
        ready.complete();
        await old;
        final cleanup = transport.calls.last;
        expect(
          pageOpening
              ? cleanup.closeImagePage.generation
              : cleanup.releaseImageTile.generation,
          'generation-1',
        );
        await runtime.cancel('new-request');
        expect(transport.calls.last.cancel.generation, 'generation-2');
        await runtime.dispose();
      }
    },
  );

  test(
    'a window cannot change content at the same revision or invalidate another page lease',
    () async {
      final transport = TileTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final page = await openPage(runtime);
      final snapshot = await runtime.requestImageWindow(window(page));
      transport.committed = true;
      transport.modify = (request, response) async {
        if (request.hasWaitImageWindow()) {
          response.imageWindow.revision = snapshot.revision;
        }
      };
      await expectLater(
        runtime.waitImageWindow(
          wire.WaitImageWindow(
            pageId: page.pageId,
            generation: page.generation,
            windowId: snapshot.windowId,
            afterRevision: snapshot.revision,
          ),
        ),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(
        transport.calls.where((call) => call.hasReleaseImageTile()),
        isEmpty,
      );
      transport.modify = null;
      final other = await openPage(runtime, id: 'other-encoded');
      final otherSnapshot = await runtime.requestImageWindow(window(other));
      transport.modify = (request, response) async {
        if (request.hasWaitImageWindow()) {
          response.imageWindow.invalidatedLeaseIds.add(
            snapshot.tiles.single.leaseId,
          );
        }
      };
      await expectLater(
        runtime.waitImageWindow(
          wire.WaitImageWindow(
            pageId: other.pageId,
            generation: other.generation,
            windowId: otherSnapshot.windowId,
            afterRevision: otherSnapshot.revision,
          ),
        ),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(
        transport.calls.where((call) => call.hasReleaseImageTile()),
        isEmpty,
      );
      await runtime.dispose();
    },
  );

  test(
    'an invalidated lease cannot reappear before its display release ACK',
    () async {
      final transport = TileTransport();
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final page = await openPage(runtime);
      final snapshot = await runtime.requestImageWindow(window(page));
      transport.modify = (request, response) async {
        if (request.hasWaitImageWindow()) {
          response.imageWindow.tiles.clear();
          response.imageWindow.invalidatedLeaseIds.add(
            snapshot.tiles.single.leaseId,
          );
        }
      };
      final invalidated = await runtime.waitImageWindow(
        wire.WaitImageWindow(
          pageId: page.pageId,
          generation: page.generation,
          windowId: snapshot.windowId,
          afterRevision: snapshot.revision,
        ),
      );
      transport.modify = null;
      await expectLater(
        runtime.waitImageWindow(
          wire.WaitImageWindow(
            pageId: page.pageId,
            generation: page.generation,
            windowId: snapshot.windowId,
            afterRevision: invalidated.revision,
          ),
        ),
        throwsA(failure(RuntimeErrorCode.protocolError)),
      );
      expect(
        transport.calls.where((call) => call.hasReleaseImageTile()),
        isEmpty,
      );
      await runtime.dispose();
    },
  );

  test(
    'release retirement rejects snapshots before and after ACK without crossing generations',
    () async {
      for (final replaceGeneration in [false, true]) {
        final transport = TileTransport();
        final runtime = TransportSourceRuntime(transport);
        await runtime.open(build());
        final page = await openPage(runtime);
        final snapshot = await runtime.requestImageWindow(window(page));
        final leaseId = snapshot.tiles.single.leaseId;
        final waitEntered = [Completer<void>(), Completer<void>()];
        final waitReady = [Completer<void>(), Completer<void>()];
        final releaseEntered = Completer<void>();
        final releaseAck = Completer<void>();
        var waiting = 0;
        var releasing = 0;
        transport.modify = (request, response) async {
          if (request.hasWaitImageWindow() &&
              request.waitImageWindow.generation == page.generation) {
            final index = waiting++;
            waitEntered[index].complete();
            await waitReady[index].future;
          }
          if (request.hasReleaseImageTile() &&
              request.releaseImageTile.generation == page.generation &&
              releasing++ == 0) {
            releaseEntered.complete();
            await releaseAck.future;
          }
          if (request.hasRequestImageWindow() &&
              request.requestImageWindow.generation == 'generation-2') {
            final resource = response.imageWindow.tiles.single.resource;
            response.imageWindow.tiles.single.leaseId = leaseId;
            resource.resourceId = leaseId;
            resource.url = snapshot.tiles.single.resource.url;
          }
        };
        wire.WaitImageWindow waitInput() => wire.WaitImageWindow(
          pageId: page.pageId,
          generation: page.generation,
          windowId: snapshot.windowId,
          afterRevision: snapshot.revision,
        );
        final first = expectLater(
          runtime.waitImageWindow(waitInput()),
          throwsA(failure(RuntimeErrorCode.cancelled)),
        );
        await waitEntered[0].future;
        final release = runtime.releaseImageTile(
          wire.ReleaseImageTile(leaseId: leaseId, generation: page.generation),
        );
        await releaseEntered.future;
        final second = expectLater(
          runtime.waitImageWindow(waitInput()),
          throwsA(
            failure(
              replaceGeneration
                  ? RuntimeErrorCode.runtimeLost
                  : RuntimeErrorCode.cancelled,
            ),
          ),
        );
        await waitEntered[1].future;
        waitReady[0].complete();
        await first;
        releaseAck.complete();
        await release;
        wire.ImagePage? next;
        if (replaceGeneration) {
          runtime.containerLost('replace while old window is still in flight');
          transport.generation = 'generation-2';
          await runtime.open(build());
          next = await openPage(
            runtime,
            id: 'encoded-next',
            generation: 'generation-2',
          );
          expect(
            (await runtime.requestImageWindow(
              window(next),
            )).tiles.single.leaseId,
            leaseId,
          );
        }
        waitReady[1].complete();
        await second;
        final releases = transport.calls
            .where((call) => call.hasReleaseImageTile())
            .map((call) => call.releaseImageTile);
        expect(releases, hasLength(2));
        expect(
          releases.every((request) => request.generation == page.generation),
          true,
        );
        if (next != null) {
          expect(
            (await runtime.requestImageWindow(
              window(next),
            )).tiles.single.resource.generation,
            'generation-2',
          );
        }
        await runtime.dispose();
      }
    },
  );

  test('wait timeout is local and retains the Source session', () async {
    final transport = TileTransport();
    final runtime = TransportSourceRuntime(transport);
    await runtime.open(build());
    final page = await openPage(runtime);
    final snapshot = await runtime.requestImageWindow(window(page));
    final events = <RuntimeEvent>[];
    final subscription = runtime.events.listen(events.add);
    transport.modify = (request, response) async {
      if (request.hasWaitImageWindow()) {
        response.error = wire.RuntimeError(
          code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_TIMEOUT,
          message: 'local wait',
        );
      }
    };
    final input = wire.WaitImageWindow(
      pageId: page.pageId,
      generation: page.generation,
      windowId: snapshot.windowId,
      afterRevision: snapshot.revision,
    );
    await expectLater(
      runtime.waitImageWindow(input),
      throwsA(failure(RuntimeErrorCode.timeout)),
    );
    await Future<void>.delayed(Duration.zero);
    expect(events, isEmpty);
    transport.modify = null;
    expect((await runtime.waitImageWindow(input)).pageId, page.pageId);
    await subscription.cancel();
    await runtime.dispose();
  });

  test(
    'closed and invalidated display leases remain charged until release ACK',
    () async {
      final transport = TileTransport()..width = 2048;
      final runtime = TransportSourceRuntime(transport);
      await runtime.open(build());
      final page = await openPage(runtime);
      transport.modify = (request, response) async {
        if (request.hasRequestImageWindow() &&
            request.requestImageWindow.pageId == page.pageId) {
          response.imageWindow.tiles.clear();
          response.imageWindow.tiles.addAll(
            List.generate(
              64,
              (index) => tile(
                'old-$index',
                page.generation,
                index: index,
                width: 2048,
              ),
            ),
          );
        }
        if (request.hasWaitImageWindow()) {
          response.imageWindow.tiles.clear();
          response.imageWindow.invalidatedLeaseIds.addAll(
            List.generate(64, (index) => 'old-$index'),
          );
          response.imageWindow.state =
              wire.ImageWindowState.IMAGE_WINDOW_STATE_FAILED;
          response.imageWindow.error = wire.RuntimeError(
            code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_SOURCE_ERROR,
            message: 'bad tail',
          );
        }
      };
      final full = await runtime.requestImageWindow(window(page, end: 16384));
      await runtime.waitImageWindow(
        wire.WaitImageWindow(
          pageId: page.pageId,
          generation: page.generation,
          windowId: full.windowId,
          afterRevision: full.revision,
        ),
      );
      await runtime.closeImagePage(
        wire.CloseImagePage(pageId: page.pageId, generation: page.generation),
      );
      runtime.containerLost('replace Source while old tiles retire');
      transport.generation = 'generation-2';
      await runtime.open(build());
      final next = await openPage(
        runtime,
        id: 'encoded-next',
        generation: 'generation-2',
      );
      transport.modify = null;
      await expectLater(
        runtime.requestImageWindow(window(next)),
        throwsA(failure(RuntimeErrorCode.limitExceeded)),
      );
      final entered = Completer<void>();
      final ack = Completer<void>();
      transport.modify = (request, response) async {
        if (request.hasReleaseImageTile() &&
            request.releaseImageTile.leaseId == 'old-0') {
          entered.complete();
          await ack.future;
        }
      };
      final releasing = runtime.releaseImageTile(
        wire.ReleaseImageTile(leaseId: 'old-0', generation: page.generation),
      );
      await entered.future;
      await expectLater(
        runtime.requestImageWindow(window(next)),
        throwsA(failure(RuntimeErrorCode.limitExceeded)),
      );
      ack.complete();
      await releasing;
      expect(
        (await runtime.requestImageWindow(
          window(next),
        )).tiles.single.resource.width,
        2048,
      );
      await runtime.dispose();
    },
  );
}
