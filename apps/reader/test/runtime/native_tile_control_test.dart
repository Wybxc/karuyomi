import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/runtime/native_image_files.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

final class TileFiles implements NativeImageFileStore {
  TileFiles(this.root);
  final Directory root;
  final files = <String, File>{};
  final copied = Completer<void>();
  Completer<void>? permitCopy;
  Completer<void>? permitCancel;
  int copies = 0;
  int cancelled = 0;
  bool rejectRelease = false;
  void Function()? onCopy;

  @override
  Future<Uri> copy({
    required String requestId,
    required String generation,
    required wire.ImageResource resource,
    bool tile = false,
  }) async {
    expect(tile, true);
    expect(generation, resource.generation);
    copies++;
    onCopy?.call();
    if (!copied.isCompleted) copied.complete();
    await permitCopy?.future;
    final file = File('${root.path}/${resource.resourceId}.png');
    await file.writeAsBytes([1]);
    files[resource.resourceId] = file;
    return file.uri;
  }

  @override
  Future<void> cancel(String requestId, String generation) async {
    cancelled++;
    await permitCancel?.future;
    final permit = permitCopy;
    if (permit != null && !permit.isCompleted) permit.complete();
  }

  @override
  Future<void> release(String resourceId, String generation) async {
    if (rejectRelease) throw StateError('release failed');
    final file = files.remove(resourceId);
    if (file != null && await file.exists()) await file.delete();
  }

  @override
  Future<void> clear() async {
    final permit = permitCopy;
    if (permit != null && !permit.isCompleted) permit.complete();
    if (await root.exists()) await root.delete(recursive: true);
    files.clear();
  }
}

wire.ControlRequest window({String id = 'window', int end = 2048}) =>
    wire.ControlRequest(
      requestId: 'request-$id',
      requestImageWindow: wire.RequestImageWindow(
        pageId: 'page',
        generation: 'g',
        windowId: id,
        sourceY: 0,
        sourceEndY: end,
        denominator: 1,
      ),
    );
wire.ControlRequest releaseTile(String id, {String generation = 'g'}) =>
    wire.ControlRequest(
      requestId: 'release-$id',
      releaseImageTile: wire.ReleaseImageTile(
        leaseId: id,
        generation: generation,
      ),
    );
wire.ControlRequest closePage() => wire.ControlRequest(
  requestId: 'close',
  closeImagePage: wire.CloseImagePage(pageId: 'page', generation: 'g'),
);

wire.ControlResponse snapshot(
  wire.ControlRequest request, {
  int count = 8,
  int revision = 1,
  int firstIndex = 0,
  List<String> invalidated = const [],
  String? windowId,
}) => wire.ControlResponse(
  requestId: request.requestId,
  imageWindow: wire.ImageWindowSnapshot(
    pageId: 'page',
    generation: 'g',
    windowId: windowId ?? request.requestImageWindow.windowId,
    revision: revision,
    state: wire.ImageWindowState.IMAGE_WINDOW_STATE_PENDING,
    header: wire.ImageTileHeader(
      width: 100,
      height: 20000,
      sourceWidth: 100,
      sourceHeight: 20000,
      denominator: 1,
    ),
    tiles: List.generate(count, (i) {
      final index = firstIndex + i;
      return wire.ImageTile(
        leaseId: 'lease-$index',
        sessionId: 'codec',
        index: index,
        sourceRect: wire.ImageSourceRect(
          x: 0,
          y: index * 256,
          width: 100,
          height: 256,
        ),
        denominator: 1,
        provisional: true,
        resource: wire.ImageResource(
          resourceId: 'lease-$index',
          generation: 'g',
          url: 'blob:https://reader.example/tile-$index',
          mimeType: 'image/png',
          byteLength: 100,
          width: 100,
          height: 256,
        ),
      );
    }),
    invalidatedLeaseIds: invalidated,
  ),
);

Matcher code(RuntimeErrorCode value) =>
    isA<RuntimeException>().having((error) => error.code, 'code', value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late TileFiles files;
  late NativeImageControl images;
  late List<wire.ControlRequest> calls;
  late Future<wire.ControlResponse> Function(wire.ControlRequest) handler;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('native-tile-test-');
    files = TileFiles(directory);
    calls = [];
    handler = (request) async => request.hasRequestImageWindow()
        ? snapshot(request)
        : wire.ControlResponse(
            requestId: request.requestId,
            closed: request.hasCloseImagePage()
                ? wire.Closed(closed: true)
                : null,
            released: request.hasCloseImagePage()
                ? null
                : wire.Released(released: true),
          );
    images = NativeImageControl(
      store: files,
      origin: Uri.parse('https://reader.example'),
      call: (request) {
        calls.add(request);
        return handler(request);
      },
    );
  });
  tearDown(() async {
    await images.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'more than six tiles use stable files and invalidation waits for display release',
    () async {
      final first = await images.window(window());
      expect(first.imageWindow.tiles.length, 8);
      expect(files.copies, 8);
      final again = await images.window(window());
      expect(files.copies, 8);
      expect(
        again.imageWindow.tiles.map((t) => t.resource.url),
        first.imageWindow.tiles.map((t) => t.resource.url),
      );
      final image = first.imageWindow.tiles.first.resource;
      expect(images.owns(image.resourceId, 'g', Uri.parse(image.url)), true);
      handler = (request) async => request.hasRequestImageWindow()
          ? snapshot(request, count: 0, revision: 2, invalidated: ['lease-0'])
          : wire.ControlResponse(
              requestId: request.requestId,
              closed: request.hasCloseImagePage()
                  ? wire.Closed(closed: true)
                  : null,
              released: request.hasCloseImagePage()
                  ? null
                  : wire.Released(released: true),
            );
      final invalid = await images.window(window());
      expect(invalid.imageWindow.invalidatedLeaseIds, ['lease-0']);
      expect(await File.fromUri(Uri.parse(image.url)).exists(), true);
      await images.closeImagePage(closePage());
      expect(files.files.length, 8);
      await images.releaseTile(releaseTile('lease-0', generation: 'other'));
      expect(files.files.length, 8);
      await images.releaseTile(releaseTile('lease-0'));
      expect(files.files.length, 7);
      expect(images.owns(image.resourceId, 'g', Uri.parse(image.url)), false);
      await images.releaseTile(releaseTile('lease-0'));
    },
  );

  test('concurrent snapshots share pending tile copies', () async {
    files.permitCopy = Completer<void>();
    final one = images.window(window());
    await files.copied.future;
    final two = images.window(window());
    await Future<void>.delayed(Duration.zero);
    files.permitCopy!.complete();
    final responses = await Future.wait([one, two]);
    expect(files.copies, 8);
    expect(
      responses[0].imageWindow.tiles.first.resource.url,
      responses[1].imageWindow.tiles.first.resource.url,
    );
  });

  test(
    'close waits for actual file cancellation and reclaims unpublished leases',
    () async {
      files.permitCopy = Completer<void>();
      files.permitCancel = Completer<void>();
      final pending = images.window(window());
      final failed = expectLater(
        pending,
        throwsA(code(RuntimeErrorCode.cancelled)),
      );
      await files.copied.future;
      var acknowledged = false;
      final closing = images
          .closeImagePage(closePage())
          .then((_) => acknowledged = true);
      await Future<void>.delayed(Duration.zero);
      expect(acknowledged, false);
      files.permitCancel!.complete();
      await closing;
      await failed;
      expect(files.files, isEmpty);
      expect(
        calls
            .where((r) => r.hasReleaseImageTile())
            .map((r) => r.releaseImageTile.leaseId)
            .toSet()
            .length,
        8,
      );
      expect(
        calls.any((r) => r.hasAcquireImage() || r.hasAcquireEncodedImage()),
        false,
      );
    },
  );

  test(
    'window replacement discards late copies without releasing published tiles',
    () async {
      files.permitCopy = Completer<void>();
      final old = images.window(window());
      final rejected = expectLater(
        old,
        throwsA(code(RuntimeErrorCode.cancelled)),
      );
      await files.copied.future;
      handler = (request) async => request.hasRequestImageWindow()
          ? snapshot(request, count: 1, firstIndex: 8, revision: 2)
          : wire.ControlResponse(
              requestId: request.requestId,
              released: wire.Released(released: true),
            );
      final next = images.window(window(id: 'next', end: 2304));
      files.permitCopy!.complete();
      final result = await next;
      await rejected;
      expect(files.files.keys, ['lease-8']);
      expect(
        images.owns(
          'lease-8',
          'g',
          Uri.parse(result.imageWindow.tiles.single.resource.url),
        ),
        true,
      );
    },
  );

  test(
    'retained tile count is charged until release and rejected new pins are cleaned',
    () async {
      handler = (request) async => request.hasRequestImageWindow()
          ? snapshot(
              request,
              count: request.requestImageWindow.windowId == 'overflow' ? 1 : 64,
              firstIndex: request.requestImageWindow.windowId == 'overflow'
                  ? 64
                  : 0,
              revision: request.requestImageWindow.windowId == 'overflow'
                  ? 2
                  : 1,
            )
          : wire.ControlResponse(
              requestId: request.requestId,
              released: wire.Released(released: true),
            );
      await images.window(window(end: 16384));
      expect(files.files.length, 64);
      await expectLater(
        images.window(window(id: 'overflow', end: 16640)),
        throwsA(code(RuntimeErrorCode.limitExceeded)),
      );
      expect(files.files.length, 64);
      expect(
        calls.any(
          (r) =>
              r.hasReleaseImageTile() &&
              r.releaseImageTile.leaseId == 'lease-64',
        ),
        true,
      );
      await images.releaseTile(releaseTile('lease-0'));
      await images.window(window(id: 'overflow', end: 16640));
      expect(files.files.length, 64);
    },
  );

  test(
    'release during a later snapshot cannot republish a retired file',
    () async {
      await images.window(window());
      files.permitCopy = Completer<void>();
      final started = Completer<void>();
      files.onCopy = () {
        if (files.copies == 9) started.complete();
      };
      handler = (request) async => request.hasRequestImageWindow()
          ? snapshot(request, count: 9, revision: 2)
          : wire.ControlResponse(
              requestId: request.requestId,
              released: wire.Released(released: true),
            );
      final pending = images.window(window(id: 'later', end: 2304));
      final rejected = expectLater(
        pending,
        throwsA(code(RuntimeErrorCode.cancelled)),
      );
      await started.future;
      await images.releaseTile(releaseTile('lease-0'));
      files.permitCopy!.complete();
      await rejected;
      expect(files.files.keys, isNot(contains('lease-0')));
      expect(files.files.keys, isNot(contains('lease-8')));
      expect(files.files.length, 7);
    },
  );

  test(
    'a rejected new window preserves the accepted window for observation',
    () async {
      final before = await images.window(window());
      handler = (request) async {
        if (request.hasRequestImageWindow()) {
          return wire.ControlResponse(
            requestId: request.requestId,
            error: wire.RuntimeError(
              code: wire
                  .RuntimeErrorCode
                  .RUNTIME_ERROR_CODE_UNSUPPORTED_CAPABILITY,
              message: 'PNG scale 2 is not supported',
            ),
          );
        }
        return snapshot(request, revision: 2, windowId: 'window');
      };
      final refused = await images.window(window(id: 'rejected'));
      expect(refused.hasError(), true);
      final observed = await images.window(
        wire.ControlRequest(
          requestId: 'observe',
          waitImageWindow: wire.WaitImageWindow(
            pageId: 'page',
            generation: 'g',
            windowId: 'window',
            afterRevision: before.imageWindow.revision,
            timeoutMs: 5,
          ),
        ),
      );
      expect(observed.imageWindow.windowId, 'window');
      expect(files.copies, 8);
    },
  );

  test(
    'a wrong envelope reclaims only the newly returned page leases',
    () async {
      handler = (request) async => request.hasRequestImageWindow()
          ? (snapshot(request)..requestId = 'wrong-control')
          : wire.ControlResponse(
              requestId: request.requestId,
              released: wire.Released(released: true),
            );
      await expectLater(
        images.window(window()),
        throwsA(code(RuntimeErrorCode.protocolError)),
      );
      expect(files.copies, 0);
      expect(
        calls
            .where((r) => r.hasReleaseImageTile())
            .map((r) => r.releaseImageTile.leaseId)
            .toSet()
            .length,
        8,
      );
    },
  );

  test(
    'a host snapshot arriving after release ACK cannot recreate the retired file',
    () async {
      await images.window(window());
      final response = Completer<wire.ControlResponse>();
      wire.ControlRequest? pendingRequest;
      handler = (request) async {
        if (request.hasRequestImageWindow()) {
          pendingRequest = request;
          return response.future;
        }
        return wire.ControlResponse(
          requestId: request.requestId,
          released: wire.Released(released: true),
        );
      };
      final pending = images.window(window(id: 'delayed'));
      final rejected = expectLater(
        pending,
        throwsA(code(RuntimeErrorCode.cancelled)),
      );
      await images.releaseTile(releaseTile('lease-0'));
      response.complete(snapshot(pendingRequest!, revision: 2));
      await rejected;
      expect(files.copies, 8);
      expect(files.files.length, 7);
      expect(files.files.containsKey('lease-0'), false);
    },
  );

  test('refused file release retains ownership and can be retried', () async {
    final response = await images.window(window());
    final resource = response.imageWindow.tiles.first.resource;
    files.rejectRelease = true;
    await expectLater(
      images.releaseTile(releaseTile(resource.resourceId)),
      throwsStateError,
    );
    expect(
      images.owns(resource.resourceId, 'g', Uri.parse(resource.url)),
      true,
    );
    files.rejectRelease = false;
    await images.releaseTile(releaseTile(resource.resourceId));
    expect(
      images.owns(resource.resourceId, 'g', Uri.parse(resource.url)),
      false,
    );
  });
}
