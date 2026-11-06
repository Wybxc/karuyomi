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
  Completer<void>? permitRelease;
  Completer<void>? permitClear;
  final releaseStarted = Completer<void>();
  final clearStarted = Completer<void>();
  int releases = 0;
  int cancelled = 0;
  bool rejectCancel = false;
  bool rejectRelease = false;
  @override
  Future<Uri> copy({
    required String requestId,
    required String generation,
    required wire.ImageResource resource,
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
    releases++;
    if (!releaseStarted.isCompleted) releaseStarted.complete();
    if (rejectRelease) throw StateError('release failed');
    await permitRelease?.future;
    final file = files.remove(resourceId);
    if (file != null && await file.exists()) await file.delete();
  }

  @override
  Future<void> clear() async {
    if (!clearStarted.isCompleted) clearStarted.complete();
    await permitClear?.future;
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
  var byteLength = 1234;
  late Future<wire.ControlResponse> Function(wire.ControlRequest) handler;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('native-image-test-');
    files = Files(directory);
    calls = [];
    byteLength = 1234;
    handler = (request) async => request.hasAcquireImage()
        ? wire.ControlResponse(
            requestId: request.requestId,
            image: wire.ImageResource(
              resourceId: 'r-${request.acquireImage.requestId}',
              generation: 'g',
              url: 'blob:https://reader.example/image',
              byteLength: byteLength,
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
    'retained encoded files count against resource and byte budgets until release',
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
      byteLength = 32 * 1024 * 1024;
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

  for (final identity in ['matching', 'requestId', 'generation']) {
    for (final failure in ['none', 'host', 'file']) {
      test(
        'cancel waits for late Source identity and cleanup ($identity, $failure)',
        () async {
          final entered = Completer<void>();
          final source = Completer<wire.ControlResponse>();
          files.rejectRelease = failure == 'file';
          handler = (request) async {
            if (request.hasAcquireImage()) {
              entered.complete();
              return source.future;
            }
            if (request.hasReleaseImage() && failure == 'host') {
              return wire.ControlResponse(
                requestId: request.requestId,
                error: wire.RuntimeError(
                  code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_RUNTIME_LOST,
                  message: 'release rejected',
                ),
              );
            }
            return wire.ControlResponse(
              requestId: request.requestId,
              released: wire.Released(released: true),
            );
          };
          final confirmed = identity == 'matching' && failure == 'none';
          final acquisition = expectLater(
            images.acquire(acquire(1)),
            throwsA(
              code(
                confirmed
                    ? RuntimeErrorCode.cancelled
                    : RuntimeErrorCode.runtimeLost,
              ),
            ),
          );
          await entered.future;
          var ended = false;
          final cancelled = images
              .cancel(cancel(1))
              .whenComplete(() => ended = true);
          final cancellation = confirmed
              ? expectLater(
                  cancelled,
                  completion(
                    isA<wire.ControlResponse>().having(
                      (value) => value.released.released,
                      'released',
                      true,
                    ),
                  ),
                )
              : expectLater(
                  cancelled,
                  throwsA(code(RuntimeErrorCode.runtimeLost)),
                );
          await Future<void>.delayed(Duration.zero);
          expect(files.cancelled, 1);
          expect(ended, false);
          source.complete(
            wire.ControlResponse(
              requestId: identity == 'requestId'
                  ? 'foreign-control'
                  : 'control-1',
              image: wire.ImageResource(
                resourceId: 'late-resource',
                generation: identity == 'generation'
                    ? 'foreign-generation'
                    : 'g',
                byteLength: 1234,
                url: 'blob:https://reader.example/late-image',
              ),
            ),
          );
          await Future.wait([
            acquisition,
            cancellation,
          ]).timeout(const Duration(seconds: 2));
          final releases = calls
              .where((request) => request.hasReleaseImage())
              .toList();
          if (identity == 'generation') {
            expect(releases, isEmpty);
            expect(files.releases, 0);
          } else {
            expect(releases, hasLength(1));
            expect(files.releases, 1);
            expect(releases.single.releaseImage.resourceId, 'late-resource');
            expect(releases.single.releaseImage.generation, 'g');
          }
          expect(files.files, isEmpty);
        },
      );
    }
  }

  test(
    'close ends cancellation waiting for the original Source response',
    () async {
      final source = Completer<wire.ControlResponse>();
      final cancelled = Completer<void>();
      handler = (request) async {
        if (request.hasAcquireImage()) return source.future;
        if (request.hasCancelImage()) cancelled.complete();
        return wire.ControlResponse(
          requestId: request.requestId,
          released: wire.Released(released: true),
        );
      };
      final acquisition = expectLater(
        images.acquire(acquire(1)),
        throwsA(code(RuntimeErrorCode.cancelled)),
      );
      final cancellation = expectLater(
        images.cancel(cancel(1)),
        throwsA(code(RuntimeErrorCode.runtimeLost)),
      );
      await cancelled.future;
      await Future<void>.delayed(Duration.zero);
      await images.close().timeout(const Duration(seconds: 2));
      await Future.wait([
        acquisition,
        cancellation,
      ]).timeout(const Duration(seconds: 2));
      expect(await directory.exists(), false);
      expect(source.isCompleted, false);
    },
  );

  test(
    'close interrupts hanging Source cancel only after local clear ACK',
    () async {
      final source = Completer<wire.ControlResponse>();
      final entered = Completer<void>();
      final reply = Completer<wire.ControlResponse>();
      files.permitClear = Completer<void>();
      handler = (request) async {
        if (request.hasAcquireImage()) return source.future;
        if (request.hasCancelImage()) {
          entered.complete();
          return reply.future;
        }
        return wire.ControlResponse(
          requestId: request.requestId,
          released: wire.Released(released: true),
        );
      };
      final acquisition = expectLater(
        images.acquire(acquire(1)),
        throwsA(code(RuntimeErrorCode.runtimeLost)),
      );
      var ended = false;
      final cancellation = expectLater(
        images.cancel(cancel(1)).whenComplete(() => ended = true),
        throwsA(code(RuntimeErrorCode.runtimeLost)),
      );
      await entered.future;
      var closed = false;
      final closing = images.close().then((_) => closed = true);
      await files.clearStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(closed, false);
      expect(ended, false);
      expect(await directory.exists(), true);
      files.permitClear!.complete();
      await Future.wait([
        closing,
        acquisition,
        cancellation,
      ]).timeout(const Duration(seconds: 2));
      expect(reply.isCompleted, false);
      expect(await directory.exists(), false);
    },
  );

  test(
    'close interrupts hanging Blob release after local files clear',
    () async {
      final resource = (await images.acquire(acquire(1))).image;
      final location = Uri.parse(resource.url);
      final entered = Completer<void>();
      final reply = Completer<wire.ControlResponse>();
      files.permitRelease = Completer<void>();
      files.permitClear = Completer<void>();
      handler = (request) async {
        if (request.hasReleaseImage()) {
          entered.complete();
          return reply.future;
        }
        return wire.ControlResponse(
          requestId: request.requestId,
          released: wire.Released(released: true),
        );
      };
      var ended = false;
      final releasing = expectLater(
        images
            .release(release(resource.resourceId))
            .whenComplete(() => ended = true),
        throwsA(code(RuntimeErrorCode.runtimeLost)),
      );
      await entered.future;
      var closed = false;
      final closing = images.close().then((_) => closed = true);
      await files.clearStarted.future;
      await Future<void>.delayed(Duration.zero);
      expect(closed, false);
      expect(ended, false);
      expect(await File.fromUri(location).exists(), true);
      files.permitClear!.complete();
      await Future.wait([
        closing,
        releasing,
      ]).timeout(const Duration(seconds: 2));
      expect(await File.fromUri(location).exists(), false);
      expect(reply.isCompleted, false);
      files.permitRelease!.complete();
    },
  );

  for (final cancelling in [false, true]) {
    test(
      'close interrupts unowned cleanup control (cancel=$cancelling)',
      () async {
        final entered = Completer<void>();
        final reply = Completer<wire.ControlResponse>();
        files.permitClear = Completer<void>();
        handler = (request) {
          entered.complete();
          return reply.future;
        };
        var ended = false;
        final cleanup = cancelling
            ? images.cancel(cancel(99))
            : images.release(release('missing'));
        final rejected = expectLater(
          cleanup.whenComplete(() => ended = true),
          throwsA(code(RuntimeErrorCode.runtimeLost)),
        );
        await entered.future;
        final closing = images.close();
        await files.clearStarted.future;
        await Future<void>.delayed(Duration.zero);
        expect(ended, false);
        files.permitClear!.complete();
        await Future.wait([
          closing,
          rejected,
        ]).timeout(const Duration(seconds: 2));
        expect(reply.isCompleted, false);
      },
    );
  }

  for (final localFailure in [true, false]) {
    test(
      'transient ${localFailure ? 'local' : 'host'} release failure retries the same identity and holds capacity until ACK',
      () async {
        final first = (await images.acquire(acquire(1))).image;
        for (var i = 2; i <= 6; i++) {
          await images.acquire(acquire(i));
        }
        final original = handler;
        files.rejectRelease = localFailure;
        if (!localFailure) {
          handler = (request) async => request.hasReleaseImage()
              ? wire.ControlResponse(
                  requestId: request.requestId,
                  error: wire.RuntimeError(
                    code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_TIMEOUT,
                    message: 'Transient cleanup timeout',
                  ),
                )
              : original(request);
        }
        await expectLater(
          images.release(release(first.resourceId)),
          throwsA(anything),
        );
        expect(images.owns(first.resourceId, 'g', Uri.parse(first.url)), true);
        await expectLater(
          images.acquire(acquire(7)),
          throwsA(code(RuntimeErrorCode.limitExceeded)),
        );
        files.rejectRelease = false;
        handler = original;
        await images.release(release(first.resourceId));
        expect(images.owns(first.resourceId, 'g', Uri.parse(first.url)), false);
        expect(
          (await images.acquire(acquire(7))).image.resourceId,
          'r-request-7',
        );
        final releases = calls
            .where((request) => request.hasReleaseImage())
            .toList();
        expect(releases, hasLength(2));
        expect(releases[0].releaseImage, releases[1].releaseImage);
      },
    );
  }

  test('concurrent release shares one local deletion and host ACK', () async {
    final resource = (await images.acquire(acquire(1))).image;
    files.permitRelease = Completer<void>();
    final first = images.release(release(resource.resourceId));
    final second = images.release(release(resource.resourceId));
    await files.releaseStarted.future;
    expect(files.releases, 1);
    expect(calls.where((request) => request.hasReleaseImage()), hasLength(1));
    expect(await File.fromUri(Uri.parse(resource.url)).exists(), true);
    files.permitRelease!.complete();
    final responses = await Future.wait([first, second]);
    expect(responses.every((response) => response.released.released), true);
    expect(files.files, isEmpty);
  });

  test('closed image control never restarts JS cleanup', () async {
    await images.close();
    final before = calls.length;
    await expectLater(
      images.cancel(cancel(99)),
      throwsA(code(RuntimeErrorCode.runtimeLost)),
    );
    await expectLater(
      images.release(release('missing')),
      throwsA(code(RuntimeErrorCode.runtimeLost)),
    );
    expect(calls.length, before);
  });

  test(
    'duplicate image identity preserves the displayed managed file',
    () async {
      final resource = (await images.acquire(acquire(1))).image;
      handler = (request) async => wire.ControlResponse(
        requestId: request.requestId,
        image: resource.deepCopy()
          ..url = 'blob:https://reader.example/duplicate',
      );
      await expectLater(
        images.acquire(acquire(2)),
        throwsA(code(RuntimeErrorCode.protocolError)),
      );
      final location = Uri.parse(resource.url);
      expect(images.owns(resource.resourceId, 'g', location), true);
      expect(await File.fromUri(location).exists(), true);
      expect(files.releases, 0);
      expect(calls.where((request) => request.hasReleaseImage()), isEmpty);
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
