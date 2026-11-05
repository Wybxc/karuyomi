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
  Completer<CallAsyncJavaScriptResult?>? pendingHandshake;
  Completer<CallAsyncJavaScriptResult?>? pendingControl;
  Completer<void>? disposeAcknowledgement;
  int disposeRequests = 0;
  CallAsyncJavaScriptResult? handshakeResult;
  CallAsyncJavaScriptResult? controlResult;
  int probes = 0;
  int handshakes = 0;
  int controls = 0;
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
    if (request.hasDispose()) {
      disposeRequests++;
      await disposeAcknowledgement?.future;
    } else if (request.requestId.startsWith('native-handshake-')) {
      handshakes++;
      final pending = pendingHandshake;
      if (pending != null) return pending.future;
      if (handshakeResult != null) return handshakeResult;
    } else if (!request.hasDispose()) {
      controls++;
      final pending = pendingControl;
      if (pending != null) return pending.future;
      if (controlResult != null) return controlResult;
    }
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
  TestHeadless(super.params, {this.runAcknowledgement})
    : super.implementation();
  final Completer<void>? runAcknowledgement;
  final controller = TestController();
  bool runCompleted = false;
  int disposals = 0;
  bool get disposed => disposals > 0;
  @override
  Future<void> run() async {
    params.onWebViewCreated?.call(
      InAppWebViewController.fromPlatform(platform: controller),
    );
    await runAcknowledgement?.future;
    runCompleted = true;
  }

  void loadStopped() {
    params.onLoadStop?.call(
      InAppWebViewController.fromPlatform(platform: controller),
      WebUri('https://reader.example/runtime/host'),
    );
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}

final class TestWebViewPlatform extends InAppWebViewPlatform {
  final created = Completer<TestHeadless>();
  final views = <TestHeadless>[];
  Completer<void>? nextRunAcknowledgement;
  var _nextCreated = Completer<TestHeadless>();
  Future<TestHeadless> get nextCreated => _nextCreated.future;
  @override
  PlatformHeadlessInAppWebView createPlatformHeadlessInAppWebView(
    PlatformHeadlessInAppWebViewCreationParams params,
  ) {
    final view = TestHeadless(
      params,
      runAcknowledgement: nextRunAcknowledgement,
    );
    nextRunAcknowledgement = null;
    views.add(view);
    if (!created.isCompleted) created.complete(view);
    _nextCreated.complete(view);
    _nextCreated = Completer<TestHeadless>();
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

  final runtimeLost = isA<RuntimeException>().having(
    (error) => error.code,
    'code',
    RuntimeErrorCode.runtimeLost,
  );

  test(
    'rebuild immediately ends initialization before any load stop',
    () async {
      final response = ready();
      final rejected = expectLater(response, throwsA(runtimeLost));
      final old = await platform.created.future;
      await runtime.rebuild().timeout(const Duration(seconds: 2));
      await rejected.timeout(const Duration(seconds: 2));
      await flushCallbacks();
      expect(old.disposals, 1);
      expect(old.controller.probes, 0);
      expect(old.controller.handshakes, 0);

      final created = platform.nextCreated;
      final nextResponse = ready();
      final next = await created;
      next.controller.readiness = true;
      next.loadStopped();
      await nextResponse;
      expect(platform.views, hasLength(2));
      expect(next.disposed, isFalse);
    },
  );

  test('retired process callbacks cannot rebuild the current view', () async {
    final firstResponse = ready();
    final old = await platform.created.future;
    old.controller.readiness = true;
    old.loadStopped();
    await firstResponse;
    await runtime.rebuild();

    final created = platform.nextCreated;
    final nextResponse = ready();
    final next = await created;
    next.controller.readiness = true;
    next.loadStopped();
    await nextResponse;
    final oldController = InAppWebViewController.fromPlatform(
      platform: old.controller,
    );
    old.params.onRenderProcessGone?.call(
      oldController,
      RenderProcessGoneDetail(didCrash: true),
    );
    old.params.onWebContentProcessDidTerminate?.call(oldController);
    await flushCallbacks();
    await ready();
    expect(platform.views, hasLength(2));
    expect(old.disposals, 1);
    expect(next.disposals, 0);
  });

  test(
    'rebuild waits for the run acknowledgement before disposing once',
    () async {
      final acknowledgement = Completer<void>();
      platform.nextRunAcknowledgement = acknowledgement;
      addTearDown(() {
        if (!acknowledgement.isCompleted) acknowledgement.complete();
      });
      final response = ready();
      final rejected = expectLater(response, throwsA(runtimeLost));
      final old = await platform.created.future;
      var resetCompleted = false;
      final resetting = runtime.rebuild().then((_) => resetCompleted = true);
      await flushCallbacks();
      expect(old.runCompleted, isFalse);
      expect(old.disposals, 0);
      expect(resetCompleted, isFalse);
      acknowledgement.complete();
      await resetting.timeout(const Duration(seconds: 2));
      await rejected.timeout(const Duration(seconds: 2));
      await flushCallbacks();
      expect(old.runCompleted, isTrue);
      expect(old.disposals, 1);

      final created = platform.nextCreated;
      final nextResponse = ready();
      final next = await created;
      next.controller.readiness = true;
      next.loadStopped();
      await nextResponse;
      expect(next.disposals, 0);
    },
  );

  test('a late failed handshake cannot retire a newer generation', () async {
    final response = ready();
    final rejected = expectLater(response, throwsA(runtimeLost));
    final old = await platform.created.future;
    final handshake = Completer<CallAsyncJavaScriptResult?>();
    old.controller.pendingHandshake = handshake;
    old.controller.readiness = true;
    old.loadStopped();
    await flushCallbacks();
    expect(old.controller.handshakes, 1);
    await runtime.rebuild();
    await rejected.timeout(const Duration(seconds: 2));

    final created = platform.nextCreated;
    final nextResponse = ready();
    final next = await created;
    next.controller.readiness = true;
    next.loadStopped();
    await nextResponse;
    handshake.complete(
      CallAsyncJavaScriptResult(error: 'Error: expired-handshake'),
    );
    await flushCallbacks();
    await ready();
    expect(platform.views, hasLength(2));
    expect(old.disposals, 1);
    expect(next.disposals, 0);
  });

  test('a late failed control call cannot retire a newer generation', () async {
    final firstResponse = ready();
    final old = await platform.created.future;
    old.controller.readiness = true;
    old.loadStopped();
    await firstResponse;
    final call = Completer<CallAsyncJavaScriptResult?>();
    old.controller.pendingControl = call;
    final response = ready();
    final rejected = expectLater(response, throwsA(runtimeLost));
    await flushCallbacks();
    expect(old.controller.controls, 2);
    await runtime.rebuild();
    await rejected.timeout(const Duration(seconds: 2));

    final created = platform.nextCreated;
    final nextResponse = ready();
    final next = await created;
    next.controller.readiness = true;
    next.loadStopped();
    await nextResponse;
    call.completeError(
      PlatformException(code: 'javascript', message: 'expired-control'),
    );
    await flushCallbacks();
    await ready();
    expect(platform.views, hasLength(2));
    expect(old.disposals, 1);
    expect(next.disposals, 0);
  });

  test('handshake JavaScript errors retain their transport detail', () async {
    final response = ready();
    final rejected = expectLater(
      response,
      throwsA(
        runtimeLost.having(
          (error) => error.message,
          'message',
          contains('handshake-sentinel'),
        ),
      ),
    );
    final view = await platform.created.future;
    view.controller.readiness = true;
    view.controller.handshakeResult = CallAsyncJavaScriptResult(
      error: 'Error: handshake-sentinel',
    );
    view.loadStopped();
    await rejected;
    expect(view.disposals, 1);
  });

  test('control JavaScript errors retain their transport detail', () async {
    final firstResponse = ready();
    final view = await platform.created.future;
    view.controller.readiness = true;
    view.loadStopped();
    await firstResponse;
    view.controller.controlResult = CallAsyncJavaScriptResult(
      error: 'Error: control-sentinel',
    );
    await expectLater(
      ready(),
      throwsA(
        runtimeLost.having(
          (error) => error.message,
          'message',
          contains('control-sentinel'),
        ),
      ),
    );
    await flushCallbacks();
    expect(view.disposals, 1);
  });

  test(
    'dispose ends unfinished initialization without reviving late callbacks',
    () async {
      final response = ready();
      final rejected = expectLater(response, throwsA(runtimeLost));
      final view = await platform.created.future;
      await runtime.dispose().timeout(const Duration(seconds: 2));
      await rejected.timeout(const Duration(seconds: 2));
      await flushCallbacks();
      expect(view.disposals, 1);
      expect(view.controller.disposeRequests, 0);
      final oldController = InAppWebViewController.fromPlatform(
        platform: view.controller,
      );
      view.params.onWebViewCreated?.call(oldController);
      view.controller.readiness = true;
      view.loadStopped();
      view.params.onRenderProcessGone?.call(
        oldController,
        RenderProcessGoneDetail(didCrash: true),
      );
      view.params.onWebContentProcessDidTerminate?.call(oldController);
      await runtime.rebuild();
      await flushCallbacks();
      await expectLater(ready(), throwsA(runtimeLost));
      expect(platform.views, hasLength(1));
      expect(view.disposals, 1);
      expect(view.controller.handshakes, 0);
    },
  );

  test(
    'dispose awaits the ready host acknowledgement and never revives it',
    () async {
      final response = ready();
      final view = await platform.created.future;
      view.controller.readiness = true;
      view.loadStopped();
      await response;
      final acknowledgement = Completer<void>();
      view.controller.disposeAcknowledgement = acknowledgement;
      addTearDown(() {
        if (!acknowledgement.isCompleted) acknowledgement.complete();
      });
      var disposed = false;
      final closing = runtime.dispose().then((_) => disposed = true);
      await flushCallbacks();
      expect(view.controller.disposeRequests, 1);
      expect(view.disposals, 0);
      expect(disposed, isFalse);
      await expectLater(ready(), throwsA(runtimeLost));
      acknowledgement.complete();
      await closing.timeout(const Duration(seconds: 2));
      expect(disposed, isTrue);
      expect(view.disposals, 1);
      final oldController = InAppWebViewController.fromPlatform(
        platform: view.controller,
      );
      view.params.onWebViewCreated?.call(oldController);
      view.loadStopped();
      view.params.onRenderProcessGone?.call(
        oldController,
        RenderProcessGoneDetail(didCrash: true),
      );
      view.params.onWebContentProcessDidTerminate?.call(oldController);
      await runtime.rebuild();
      await flushCallbacks();
      await expectLater(ready(), throwsA(runtimeLost));
      expect(platform.views, hasLength(1));
      expect(view.disposals, 1);
      expect(view.controller.disposeRequests, 1);
    },
  );
}
