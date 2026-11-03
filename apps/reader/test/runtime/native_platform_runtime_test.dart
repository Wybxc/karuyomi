import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/runtime/native_runtime_assets.dart';
import 'package:karuyomi/runtime/platform_runtime_native.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

final class TestController extends PlatformInAppWebViewController {
  TestController()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'test-native'),
      );
  Object? readiness = false;
  Completer<Object?>? pendingReadiness;
  int probes = 0;
  int handshakes = 0;
  final probeSources = <String>[];

  @override
  Future<Object?> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    probes++;
    probeSources.add(source);
    return pendingReadiness?.future ?? readiness;
  }

  @override
  Future<CallAsyncJavaScriptResult?> callAsyncJavaScript({
    required String functionBody,
    Map<String, Object?> arguments = const {},
    ContentWorld? contentWorld,
  }) async {
    final request = wire.decodeProtoJson(
      wire.ControlRequest(),
      arguments['request'],
    );
    if (request.requestId.startsWith('native-handshake-')) handshakes++;
    return CallAsyncJavaScriptResult(
      value: jsonEncode(
        wire.encodeProtoJson(
          wire.ControlResponse(
            requestId: request.requestId,
            hello: request.hasReady()
                ? wire.RuntimeHello(
                    protocolVersion: protocolVersion,
                    hostAbi: hostAbi,
                    runtimeBaseline: runtimeBaseline,
                    generation: 'test-generation',
                  )
                : null,
            completed: request.hasDispose()
                ? wire.Completed(completed: true)
                : null,
          ),
        ),
      ),
    );
  }
}

final class TestHeadless extends PlatformHeadlessInAppWebView {
  TestHeadless(super.params) : super.implementation();
  final controller = TestController();
  bool disposed = false;
  @override
  Future<void> run() async {
    params.onWebViewCreated?.call(
      InAppWebViewController.fromPlatform(platform: controller),
    );
  }

  void loadStopped() {
    params.onLoadStop?.call(
      InAppWebViewController.fromPlatform(platform: controller),
      WebUri('https://reader.example/runtime/host'),
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class TestWebViewPlatform extends InAppWebViewPlatform {
  final created = Completer<TestHeadless>();
  @override
  PlatformHeadlessInAppWebView createPlatformHeadlessInAppWebView(
    PlatformHeadlessInAppWebViewCreationParams params,
  ) {
    final view = TestHeadless(params);
    created.complete(view);
    return view;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestWebViewPlatform platform;
  late NativePlatformRuntime runtime;
  setUp(() {
    platform = TestWebViewPlatform();
    InAppWebViewPlatform.instance = platform;
    runtime = NativePlatformRuntime(Uri.parse('https://reader.example'));
    final scripts = {
      'host': utf8.encode('host'),
      'worker': utf8.encode('worker'),
    };
    final files = <String, Uint8List>{};
    for (final entry in scripts.entries) {
      files['${NativeRuntimeAssets.assetDirectory}${entry.key}.js'] =
          Uint8List.fromList(entry.value);
    }
    files['${NativeRuntimeAssets.assetDirectory}manifest.json'] =
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'schemaVersion': 1,
              'protocolVersion': protocolVersion,
              'hostAbi': hostAbi,
              'runtimeBaseline': runtimeBaseline,
              'materialVersion': 'a' * 64,
              'files': {
                for (final entry in scripts.entries)
                  entry.key: {
                    'path': '${entry.key}.js',
                    'sha256': sha256.convert(entry.value).toString(),
                    'size': entry.value.length,
                  },
              },
            }),
          ),
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          final key = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          final bytes = files[key];
          return bytes == null ? null : ByteData.sublistView(bytes);
        });
  });
  tearDown(() async {
    await runtime.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    rootBundle.clear();
  });
  Future<Object?> ready() => runtime.control(
    wire.encodeProtoJson(
      wire.ControlRequest(requestId: 'product-ready', ready: wire.Empty()),
    ),
  );
  Future<void> flushCallbacks() => Future<void>.delayed(Duration.zero);

  test(
    'unready load does not suppress the subsequent ready document',
    () async {
      final response = ready();
      final view = await platform.created.future;
      expect(
        view.params.initialUrlRequest?.url.toString(),
        'https://reader.example/runtime/host',
      );
      view.loadStopped();
      await flushCallbacks();
      expect(view.controller.probes, 1);
      expect(view.controller.handshakes, 0);
      view.controller.readiness = true;
      view.loadStopped();
      final result = wire.decodeProtoJson(
        wire.ControlResponse(),
        await response,
      );
      expect(result.hasHello(), isTrue);
      expect(view.controller.handshakes, 1);
      expect(
        view.controller.probeSources.first,
        allOf(
          contains("document.readyState === 'interactive'"),
          contains("document.readyState === 'complete'"),
        ),
      );
      expect(
        view.controller.probeSources.first,
        contains(
          "typeof window.flutter_inappwebview?.callHandler === 'function'",
        ),
      );
    },
  );

  test('overlapping readiness callbacks only claim one handshake', () async {
    final response = ready();
    final view = await platform.created.future;
    final probe = Completer<Object?>();
    view.controller.pendingReadiness = probe;
    view.loadStopped();
    view.loadStopped();
    await flushCallbacks();
    expect(view.controller.probes, 2);
    probe.complete(true);
    await response;
    expect(view.controller.handshakes, 1);
  });

  test('late readiness cannot revive a rebuilt container', () async {
    final response = ready();
    final view = await platform.created.future;
    final stale = Completer<Object?>();
    view.controller.pendingReadiness = stale;
    view.loadStopped();
    await flushCallbacks();
    view.controller.pendingReadiness = null;
    view.controller.readiness = true;
    view.loadStopped();
    await response;
    await runtime.rebuild();
    stale.complete(true);
    await flushCallbacks();
    expect(view.controller.handshakes, 1);
    expect(view.disposed, isTrue);
  });

  test('plugin readiness requires the documented boolean result', () async {
    final response = ready();
    final rejected = expectLater(
      response,
      throwsA(
        isA<RuntimeException>().having(
          (e) => e.code,
          'code',
          RuntimeErrorCode.protocolError,
        ),
      ),
    );
    final view = await platform.created.future;
    view.controller.readiness = 'true';
    view.loadStopped();
    await rejected;
    expect(view.controller.handshakes, 0);
    expect(view.disposed, isTrue);
  });
}
