import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/runtime/native_image_files.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

final class Files implements NativeImageFileStore {
  Files(this.root);
  final Directory root;
  final files = <String, File>{};
  final copied = Completer<void>();
  Completer<void>? permitCopy;
  Completer<void>? permitCancel;
  int cancelled = 0;
  bool rejectCancel = false;
  bool rejectRelease = false;
  @override
  Future<Uri> copy({
    required String requestId,
    required String generation,
    required wire.ImageResource resource,
    bool tile = false,
  }) async {
    if (!copied.isCompleted) copied.complete();
    await permitCopy?.future;
    final file = File('${root.path}/${resource.resourceId}.image');
    await file.writeAsBytes(Uint8List(resource.byteLength));
    files[resource.resourceId] = file;
    return file.uri;
  }

  @override
  Future<void> cancel(String requestId, String generation) async {
    cancelled++;
    if (rejectCancel) throw StateError('cancel failed');
    await permitCancel?.future;
    if (permitCopy != null && !permitCopy!.isCompleted) permitCopy!.complete();
  }

  @override
  Future<void> release(String resourceId, String generation) async {
    if (rejectRelease) throw StateError('release failed');
    final file = files.remove(resourceId);
    if (file != null && await file.exists()) await file.delete();
  }

  @override
  Future<void> clear() async {
    if (permitCopy != null && !permitCopy!.isCompleted) permitCopy!.complete();
    if (await root.exists()) await root.delete(recursive: true);
    files.clear();
  }
}

wire.ControlRequest acquire(int index, {int timeout = 60000}) =>
    wire.ControlRequest(
      requestId: 'control-$index',
      acquireImage: wire.AcquireImage(
        requestId: 'request-$index',
        sourceId: '42',
        generation: 'g',
        pageSessionId: 'pages',
        pageKey: 'p-$index',
        timeoutMs: timeout,
      ),
    );
wire.ControlRequest release(String id, {String generation = 'g'}) =>
    wire.ControlRequest(
      requestId: 'release',
      releaseImage: wire.ReleaseImage(resourceId: id, generation: generation),
    );
wire.ControlRequest cancel(int index) => wire.ControlRequest(
  requestId: 'cancel',
  cancelImage: wire.CancelImage(requestId: 'request-$index', generation: 'g'),
);
Matcher code(RuntimeErrorCode value) =>
    isA<RuntimeException>().having((error) => error.code, 'code', value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Files files;
  late NativeImageControl images;
  late List<wire.ControlRequest> calls;
  var pixels = 100;
  late Future<wire.ControlResponse> Function(wire.ControlRequest) handler;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('native-image-test-');
    files = Files(directory);
    calls = [];
    pixels = 100;
    handler = (request) async => request.hasAcquireImage()
        ? wire.ControlResponse(
            requestId: request.requestId,
            image: wire.ImageResource(
              resourceId: 'r-${request.acquireImage.requestId}',
              generation: 'g',
              url: 'blob:https://reader.example/image',
              mimeType: 'image/png',
              byteLength: 1234,
              width: pixels,
              height: pixels,
            ),
          )
        : wire.ControlResponse(
            requestId: request.requestId,
            released: wire.Released(released: true),
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
    'only a completed managed file is owned; stale release and late cancel preserve it',
    () async {
      final response = await images.acquire(acquire(1));
      final image = response.image;
      final location = Uri.parse(image.url);
      expect(location.scheme, 'file');
      expect(await File.fromUri(location).length(), 1234);
      expect(images.owns(image.resourceId, 'g', location), true);
      expect(images.owns(image.resourceId, 'other', location), false);
      await images.release(release(image.resourceId, generation: 'other'));
      await images.cancel(cancel(1));
      expect(await File.fromUri(location).exists(), true);
      await images.release(release(image.resourceId));
      await images.release(release(image.resourceId));
      expect(await File.fromUri(location).exists(), false);
      expect(images.owns(image.resourceId, 'g', location), false);
    },
  );

  test(
    'cancel waits for real file cancellation and discards a late copy before acknowledging',
    () async {
      files.permitCopy = Completer<void>();
      files.permitCancel = Completer<void>();
      final pending = images.acquire(acquire(1));
      final failure = expectLater(
        pending,
        throwsA(code(RuntimeErrorCode.cancelled)),
      );
      await files.copied.future;
      var acknowledged = false;
      final cancellation = images.cancel(cancel(1)).then((value) {
        acknowledged = value.released.released;
      });
      await Future<void>.delayed(Duration.zero);
      expect(acknowledged, false);
      files.permitCancel!.complete();
      await cancellation;
      await failure;
      expect(files.cancelled, 1);
      expect(acknowledged, true);
      expect(files.files, isEmpty);
      expect(calls.any((request) => request.hasReleaseImage()), true);
    },
  );

  test(
    'local deadline remains timeout when Source cancellation returns a cancelled envelope',
    () async {
      final source = Completer<wire.ControlResponse>();
      handler = (request) async {
        if (request.hasAcquireImage()) return source.future;
        source.complete(
          wire.ControlResponse(
            requestId: 'control-1',
            error: wire.RuntimeError(
              code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_CANCELLED,
              message: 'cancelled',
            ),
          ),
        );
        return wire.ControlResponse(
          requestId: request.requestId,
          released: wire.Released(released: true),
        );
      };
      await expectLater(
        images.acquire(acquire(1, timeout: 10)),
        throwsA(code(RuntimeErrorCode.timeout)),
      );
      expect(files.files, isEmpty);
    },
  );

  test(
    'retained files count against resource and raster budgets until release',
    () async {
      final retained = <wire.ImageResource>[];
      for (var index = 0; index < 6; index++) {
        retained.add((await images.acquire(acquire(index))).image);
      }
      final before = calls.length;
      await expectLater(
        images.acquire(acquire(7)),
        throwsA(code(RuntimeErrorCode.limitExceeded)),
      );
      expect(calls.length, before);
      for (final image in retained) {
        await images.release(release(image.resourceId));
      }
      pixels = 4096;
      final one = (await images.acquire(acquire(8))).image;
      final two = (await images.acquire(acquire(9))).image;
      await expectLater(
        images.acquire(acquire(10)),
        throwsA(code(RuntimeErrorCode.limitExceeded)),
      );
      expect(files.files.length, 2);
      await images.release(release(one.resourceId));
      await images.release(release(two.resourceId));
    },
  );

  test(
    'release cannot claim acknowledgement when the Blob owner rejects cleanup',
    () async {
      final resource = (await images.acquire(acquire(1))).image;
      handler = (request) async => wire.ControlResponse(
        requestId: request.requestId,
        error: wire.RuntimeError(
          code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_RUNTIME_LOST,
          message: 'lost',
        ),
      );
      await expectLater(
        images.release(release(resource.resourceId)),
        throwsA(code(RuntimeErrorCode.runtimeLost)),
      );
    },
  );

  test(
    'failed cancellation invalidates the operation instead of acknowledging cleanup',
    () async {
      files.permitCopy = Completer<void>();
      files.rejectCancel = true;
      final pending = images.acquire(acquire(1));
      final rejected = expectLater(
        pending,
        throwsA(code(RuntimeErrorCode.runtimeLost)),
      );
      await files.copied.future;
      await expectLater(images.cancel(cancel(1)), throwsA(anything));
      files.permitCopy!.complete();
      await rejected;
    },
  );

  test(
    'close interrupts an outstanding Source call and waits for local cleanup',
    () async {
      handler = (request) => Completer<wire.ControlResponse>().future;
      final pending = images.acquire(acquire(1));
      final rejected = expectLater(
        pending,
        throwsA(code(RuntimeErrorCode.runtimeLost)),
      );
      await images.close();
      await rejected;
      expect(await directory.exists(), false);
    },
  );

  test(
    'iOS only accepts a file directly inside the bound managed root',
    () async {
      const channel = MethodChannel(IosImageFileStore.channelName);
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            methods.add(call.method);
            return switch (call.method) {
              'bind' => {
                'bindingId': 'binding',
                'directoryUrl': directory.uri.toString(),
              },
              'acquire' => {
                'url': File(
                  '${directory.parent.path}/outside.image',
                ).uri.toString(),
              },
              'release' || 'cancel' => {'released': true},
              'clear' => {'cleared': true},
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final store = await IosImageFileStore.bind(
        token: 'token',
        origin: Uri.parse('https://reader.example'),
      );
      await expectLater(
        store.copy(
          requestId: 'request-1',
          generation: 'g',
          resource: wire.ImageResource(resourceId: 'r', generation: 'g'),
        ),
        throwsA(code(RuntimeErrorCode.protocolError)),
      );
      expect(methods, ['bind', 'acquire', 'release']);
      await store.clear();
    },
  );
}
