import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/runtime/android_image_files.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

final class _Port extends PlatformWebMessagePort {
  _Port(int index)
    : super.implementation(PlatformWebMessagePortCreationParams(index: index));
  WebMessageCallback? receive;
  void Function(WebMessage)? posted;
  int closes = 0;
  Completer<void>? closeGate;
  Object? closeFailure;

  @override
  Map<String, Object?> toMap({EnumMethod? enumMethod}) => {
    'index': params.index,
  };

  @override
  Map<String, Object?> toJson() => toMap();

  @override
  Future<void> setWebMessageCallback(WebMessageCallback? onMessage) async {
    receive = onMessage;
  }

  @override
  Future<void> postMessage(WebMessage message) async => posted?.call(message);

  @override
  Future<void> close() async {
    closes++;
    await closeGate?.future;
    if (closeFailure case final failure?) throw failure;
  }
}

final class _Channel extends PlatformWebMessageChannel {
  _Channel(this.local, this.remote)
    : super.implementation(
        PlatformWebMessageChannelCreationParams(
          id: 'controller-owned-image-channel',
          port1: local,
          port2: remote,
        ),
      );
  final _Port local;
  final _Port remote;
  int disposes = 0;

  @override
  void dispose() {
    if (disposes != 0) throw StateError('controller channel disposed twice');
    disposes++;
  }
}

final class _Controller extends PlatformInAppWebViewController {
  _Controller()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'image-owner'),
      );
  final imageChannel = _Channel(_Port(0), _Port(1));
  bool rejectTransfer = false;
  int transfer = 0;

  @override
  Future<PlatformWebMessageChannel?> createWebMessageChannel() async =>
      imageChannel;

  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, Object?> arguments = const {},
    ContentWorld? contentWorld,
  }) async {
    if (arguments['transfer'] case final int value) transfer = value;
    return CallAsyncJavaScriptResult(value: true);
  }

  @override
  Future<void> postWebMessage({
    required WebMessage message,
    WebUri? targetOrigin,
  }) async {
    if (rejectTransfer) throw StateError('platform transfer rejected');
    final identity = transfer;
    imageChannel.local.posted = (message) {
      if (message.data == 'ack:$identity:1') {
        imageChannel.local.receive?.call(WebMessage(data: 'end:$identity:4:1'));
      }
    };
    final bytes = Uint8List(12);
    ByteData.sublistView(bytes)
      ..setUint32(0, identity)
      ..setUint32(4, 1);
    bytes.setRange(8, 12, [0, 255, 12, 34]);
    scheduleMicrotask(
      () => imageChannel.local.receive?.call(
        WebMessage(data: bytes, type: WebMessageType.ARRAY_BUFFER),
      ),
    );
  }

  // The locked plugin retains each created channel in its controller registry,
  // then disposes it when its Headless WebView is destroyed.
  void destroyWebView() => imageChannel.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final request = wire.AcquireImage(
    requestId: 'copy',
    generation: 'generation',
  );
  final resource = wire.ImageResource(
    resourceId: 'image',
    generation: 'generation',
    url: 'blob:https://reader.example/image',
    byteLength: 4,
  );

  test(
    'clear closes owned ports once; WebView alone disposes its channel',
    () async {
      final controller = _Controller();
      final store = await AndroidImageFileStore.bind(
        InAppWebViewController.fromPlatform(platform: controller),
        Uri.parse('https://reader.example'),
      );
      final location = await store.copy(
        requestId: request.requestId,
        generation: request.generation,
        resource: resource,
      );
      expect(await File.fromUri(location).readAsBytes(), [0, 255, 12, 34]);
      await store.clear();
      expect(controller.imageChannel.remote.closes, 0);
      expect(await store.directory.exists(), isFalse);
      expect(controller.imageChannel.disposes, 0);
      controller.destroyWebView();
      expect(controller.imageChannel.disposes, 1);
      await store.clear();
      expect(controller.imageChannel.local.closes, 1);
      await expectLater(
        store.copy(
          requestId: request.requestId,
          generation: request.generation,
          resource: resource,
        ),
        throwsA(isA<RuntimeException>()),
      );
    },
  );

  test('concurrent clear waits for the same actual port cleanup', () async {
    final controller = _Controller();
    final store = await AndroidImageFileStore.bind(
      InAppWebViewController.fromPlatform(platform: controller),
      Uri.parse('https://reader.example'),
    );
    await store.copy(
      requestId: request.requestId,
      generation: request.generation,
      resource: resource,
    );
    final gate = Completer<void>();
    controller.imageChannel.local.closeGate = gate;
    final first = store.clear();
    final concurrent = store.clear();
    try {
      expect(identical(first, concurrent), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(controller.imageChannel.local.closes, 1);
      expect(await store.directory.exists(), isTrue);
    } finally {
      gate.complete();
      await Future.wait([first, concurrent]);
    }
    expect(await store.directory.exists(), isFalse);
    expect(controller.imageChannel.disposes, 0);
    controller.destroyWebView();
  });

  test(
    'clear preserves failure after attempting other ports and files',
    () async {
      final controller = _Controller()..rejectTransfer = true;
      final store = await AndroidImageFileStore.bind(
        InAppWebViewController.fromPlatform(platform: controller),
        Uri.parse('https://reader.example'),
      );
      await expectLater(
        store.copy(
          requestId: request.requestId,
          generation: request.generation,
          resource: resource,
        ),
        throwsStateError,
      );
      await File('${store.directory.path}/leftover.image').writeAsBytes([1]);
      final failure = StateError('local port close rejected');
      controller.imageChannel.local.closeFailure = failure;
      await expectLater(store.clear(), throwsA(same(failure)));
      expect(controller.imageChannel.remote.closes, 1);
      expect(await store.directory.exists(), isFalse);
      expect(controller.imageChannel.disposes, 0);
      await expectLater(store.clear(), throwsA(same(failure)));
      expect(controller.imageChannel.local.closes, 1);
      expect(controller.imageChannel.remote.closes, 1);
      controller.destroyWebView();
      expect(controller.imageChannel.disposes, 1);
    },
  );
}
