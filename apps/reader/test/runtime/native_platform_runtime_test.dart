import 'package:karuyomi/widgets/app_page_route.dart';

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
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
  final disposeSlots = <wire.RuntimeSlot>[];
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
      disposeSlots.add(request.slotId);
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
            slotId: request.slotId,
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

final class TestAuthenticationWebView extends PlatformInAppWebViewWidget {
  TestAuthenticationWebView(super.params) : super.implementation();

  late final _controller = controllerFromPlatform<InAppWebViewController>(
    TestController(),
  );

  Uri get login => Uri.parse(params.initialUrlRequest!.url.toString());

  Future<NavigationActionPolicy?> decideNavigation(
    Uri target, {
    required bool isForMainFrame,
  }) async => params.shouldOverrideUrlLoading!(
    _controller,
    NavigationAction(
      request: URLRequest(url: WebUri(target.toString())),
      isForMainFrame: isForMainFrame,
    ),
  );

  void commitVisible(Uri target) =>
      params.onPageCommitVisible!(_controller, WebUri(target.toString()));

  void loadStopped(Uri target) =>
      params.onLoadStop!(_controller, WebUri(target.toString()));

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      params.controllerFromPlatform!(controller) as T;

  @override
  void dispose() {}
}

final class TestWebViewPlatform extends InAppWebViewPlatform {
  final created = Completer<TestHeadless>();
  final views = <TestHeadless>[];
  final authenticationViews = <TestAuthenticationWebView>[];
  Completer<void>? nextRunAcknowledgement;
  var _nextCreated = Completer<TestHeadless>();
  Future<TestHeadless> get nextCreated => _nextCreated.future;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    final view = TestAuthenticationWebView(params);
    authenticationViews.add(view);
    return view;
  }

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

const _readerRoute = ValueKey('test-reader-route');

final class TestAuthenticationNavigatorObserver extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
  }
}

Future<TestAuthenticationNavigatorObserver> _openReader(
  WidgetTester tester,
) async {
  final navigator = GlobalKey<NavigatorState>();
  final observer = TestAuthenticationNavigatorObserver();
  await tester.pumpWidget(
    CupertinoApp(
      navigatorKey: navigator,
      navigatorObservers: [observer],
      home: const CupertinoPageScaffold(child: Text('书架')),
    ),
  );
  unawaited(
    navigator.currentState!.push<void>(
      AppPageRoute<void>(
        builder: (_) =>
            const CupertinoPageScaffold(key: _readerRoute, child: Text('阅读')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return observer;
}

Uri _callbackFor(TestAuthenticationWebView view) {
  final attempt = view.login.queryParameters['attempt'];
  expect(
    attempt,
    matches(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ),
    ),
  );
  expect(view.login.origin, 'https://reader.example');
  expect(view.login.path, '/api/auth/login');
  expect(view.login.queryParameters, {
    'returnTo': '/auth/complete',
    'attempt': attempt,
  });
  return Uri.https('reader.example', '/auth/complete', {'attempt': attempt});
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
      wire.ControlRequest(
        slotId: wire.RuntimeSlot.RUNTIME_SLOT_FOREGROUND,
        requestId: 'product-ready',
        ready: wire.Empty(),
      ),
    ),
  );
  Future<void> flushCallbacks() => Future<void>.delayed(Duration.zero);

  testWidgets(
    'only the current authentication callback can pop the login route',
    (tester) async {
      final observer = await _openReader(tester);
      final context = tester.element(find.byKey(_readerRoute));
      final results = <bool>[];

      unawaited(
        runtime.authenticate(context, pending: {'tab': 0}).then(results.add),
      );
      await tester.pumpAndSettle();
      final first = platform.authenticationViews.single;
      final previousCallback = _callbackFor(first);
      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(runtime.takePendingAuthentication(), isNull);
      expect(find.byKey(_readerRoute), findsOneWidget);
      expect(observer.pops, 1);

      const returnTo = '/reader?resume=1';
      const pending = {
        'tab': 1,
        'reader': {'chapter': 'test-chapter'},
      };
      unawaited(
        runtime
            .authenticate(context, returnTo: returnTo, pending: pending)
            .then(results.add),
      );
      await tester.pumpAndSettle();
      expect(platform.authenticationViews, hasLength(2));
      final current = platform.authenticationViews.last;
      final callback = _callbackFor(current);
      expect(callback, isNot(previousCallback));

      // The exact URL in a navigation decision is not yet a committed document.
      for (final isForMainFrame in [false, true]) {
        expect(
          await current.decideNavigation(
            callback,
            isForMainFrame: isForMainFrame,
          ),
          NavigationActionPolicy.ALLOW,
        );
      }
      first.loadStopped(previousCallback);
      for (final unrelated in [
        current.login,
        callback.replace(host: 'idp.example'),
        previousCallback,
        Uri.https('reader.example', '/auth/complete'),
        callback.replace(
          queryParameters: {...callback.queryParameters, 'extra': '1'},
        ),
      ]) {
        current.commitVisible(unrelated);
        current.loadStopped(unrelated);
        await tester.pump();
        expect(results, [false], reason: unrelated.toString());
        expect(find.text('登录'), findsOneWidget);
        expect(observer.pops, 1);
      }
      expect(runtime.takePendingAuthentication(), isNull);

      current.commitVisible(callback);
      current.loadStopped(callback);
      await tester.pumpAndSettle();
      expect(results, [false, true]);
      expect(find.text('登录'), findsNothing);
      expect(find.byKey(_readerRoute), findsOneWidget);
      expect(observer.pops, 2);
      expect(runtime.takePendingAuthentication(), {
        'returnTo': returnTo,
        'pending': pending,
      });
      expect(runtime.takePendingAuthentication(), isNull);

      current.loadStopped(callback);
      current.commitVisible(callback);
      await tester.pumpAndSettle();
      expect(find.byKey(_readerRoute), findsOneWidget);
      expect(observer.pops, 2);
      expect(runtime.takePendingAuthentication(), isNull);
      expect(platform.views, isEmpty);
    },
  );

  testWidgets('the current load stop also completes authentication', (
    tester,
  ) async {
    final observer = await _openReader(tester);
    final context = tester.element(find.byKey(_readerRoute));
    final results = <bool>[];
    unawaited(runtime.authenticate(context).then(results.add));
    await tester.pumpAndSettle();

    final view = platform.authenticationViews.single;
    view.loadStopped(_callbackFor(view));
    await tester.pumpAndSettle();
    expect(results, [true]);
    expect(observer.pops, 1);
    expect(find.byKey(_readerRoute), findsOneWidget);
    expect(runtime.takePendingAuthentication(), {
      'returnTo': '/',
      'pending': {},
    });
    expect(runtime.takePendingAuthentication(), isNull);
  });

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
    'rebuild retires an unacknowledged view and disposes it only after its ACK',
    () async {
      final acknowledgement = Completer<void>();
      platform.nextRunAcknowledgement = acknowledgement;
      addTearDown(() {
        if (!acknowledgement.isCompleted) acknowledgement.complete();
      });
      final response = ready();
      final rejected = expectLater(response, throwsA(runtimeLost));
      final old = await platform.created.future;
      await runtime.rebuild().timeout(const Duration(seconds: 2));
      await rejected.timeout(const Duration(seconds: 2));
      expect(old.runCompleted, isFalse);
      expect(old.disposals, 0);
      expect(runtime.runtimeRestartBlocked, isTrue);
      await expectLater(ready(), throwsA(runtimeLost));
      expect(platform.views, hasLength(1));
      acknowledgement.complete();
      await flushCallbacks();
      expect(old.runCompleted, isTrue);
      expect(old.disposals, 1);
      expect(runtime.runtimeRestartBlocked, isFalse);

      final created = platform.nextCreated;
      final nextResponse = ready();
      final next = await created;
      next.controller.readiness = true;
      next.loadStopped();
      await nextResponse;
      expect(next.disposals, 0);
    },
  );

  test('a missing run ACK ends startup and explicit reconnect does not pile up views', () async {
    await runtime.dispose();
    runtime = NativePlatformRuntime.withStartupTimeout(
      Uri.parse('https://reader.example'),
      const Duration(milliseconds: 100),
    );
    final acknowledgement = Completer<void>();
    platform.nextRunAcknowledgement = acknowledgement;
    addTearDown(() {
      if (!acknowledgement.isCompleted) acknowledgement.complete();
    });
    final catalog = CatalogController(
      api: runtime,
      runtime: runtime.runtime,
      rebuildRuntime: runtime.rebuild,
    );
    try {
      final connecting = catalog.connect();
      final old = await platform.created.future;
      expect(catalog.busy, isTrue);
      await connecting.timeout(const Duration(seconds: 2));
      expect(catalog.status, ServiceStatus.failed);
      expect(catalog.busy, isFalse);
      expect(catalog.error, contains('重启应用'));
      expect(old.disposals, 0);
      expect(runtime.runtimeRestartBlocked, isTrue);

      await catalog.connect().timeout(const Duration(seconds: 2));
      expect(catalog.status, ServiceStatus.failed);
      expect(catalog.error, contains('暂时无法重新连接'));
      expect(platform.views, hasLength(1));
      old.controller.readiness = true;
      old.loadStopped();
      old.params.onRenderProcessGone?.call(
        InAppWebViewController.fromPlatform(platform: old.controller),
        RenderProcessGoneDetail(didCrash: false),
      );
      await flushCallbacks();
      expect(old.controller.handshakes, 0);
      expect(old.disposals, 0);

      acknowledgement.complete();
      await flushCallbacks();
      expect(old.disposals, 1);
      expect(runtime.runtimeRestartBlocked, isFalse);
      final created = platform.nextCreated;
      final nextResponse = ready();
      final next = await created;
      expect(next, isNot(same(old)));
      next.controller.readiness = true;
      next.loadStopped();
      await nextResponse;
      expect(old.disposals, 1);
      expect(next.disposals, 0);
    } finally {
      catalog.dispose();
    }
  });

  for (final succeeds in [true, false]) {
    test(
      'component close retires startup once when its late run ACK ${succeeds ? 'succeeds' : 'fails'}',
      () async {
        final acknowledgement = Completer<void>();
        platform.nextRunAcknowledgement = acknowledgement;
        addTearDown(() {
          if (!acknowledgement.isCompleted) acknowledgement.complete();
        });
        final rejected = expectLater(ready(), throwsA(runtimeLost));
        final old = await platform.created.future;
        final closing = runtime.dispose();
        expect(runtime.dispose(), same(closing));
        await closing.timeout(const Duration(seconds: 2));
        await rejected.timeout(const Duration(seconds: 2));
        expect(old.disposals, 0);
        expect(old.controller.disposeRequests, 0);

        if (succeeds) {
          acknowledgement.complete();
        } else {
          acknowledgement.completeError(StateError('late run failure'));
        }
        await flushCallbacks();
        old.controller.readiness = true;
        old.loadStopped();
        await flushCallbacks();
        expect(old.disposals, succeeds ? 1 : 0);
        expect(old.controller.handshakes, 0);
        expect(runtime.runtimeRestartBlocked, isFalse);
        await expectLater(ready(), throwsA(runtimeLost));
        expect(platform.views, hasLength(1));
        expect(old.disposals, succeeds ? 1 : 0);
      },
    );
  }

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

  test('a search slot runtime error response does not replace the foreground WebView', () async {
    final first = ready();
    final view = await platform.created.future;
    view.controller.readiness = true;
    view.loadStopped();
    await first;
    view.controller.controlResult = CallAsyncJavaScriptResult(
      value: jsonEncode(
        wire.encodeProtoJson(
          wire.ControlResponse(
            requestId: 'search-ready',
            slotId: wire.RuntimeSlot.RUNTIME_SLOT_SEARCH,
            error: wire.RuntimeError(
              code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_RUNTIME_LOST,
              message: 'Search worker ended',
            ),
          ),
        ),
      ),
    );
    final response = wire.decodeProtoJson(
      wire.ControlResponse(),
      await runtime.control(
        wire.encodeProtoJson(
          wire.ControlRequest(
            requestId: 'search-ready',
            slotId: wire.RuntimeSlot.RUNTIME_SLOT_SEARCH,
            ready: wire.Empty(),
          ),
        ),
      ),
    );
    expect(response.slotId, wire.RuntimeSlot.RUNTIME_SLOT_SEARCH);
    expect(
      response.error.code,
      wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_RUNTIME_LOST,
    );
    await flushCallbacks();
    expect(view.disposals, 0);
    view.controller.controlResult = null;
    await ready();
    expect(platform.views, hasLength(1));
    expect(view.disposals, 0);
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
      expect(view.controller.disposeRequests, 2);
      expect(
        view.controller.disposeSlots,
        unorderedEquals([
          wire.RuntimeSlot.RUNTIME_SLOT_FOREGROUND,
          wire.RuntimeSlot.RUNTIME_SLOT_SEARCH,
        ]),
      );
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
      expect(view.controller.disposeRequests, 2);
      expect(
        view.controller.disposeSlots,
        unorderedEquals([
          wire.RuntimeSlot.RUNTIME_SLOT_FOREGROUND,
          wire.RuntimeSlot.RUNTIME_SLOT_SEARCH,
        ]),
      );
    },
  );
}
