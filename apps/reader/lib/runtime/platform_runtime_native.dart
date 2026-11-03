import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'runtime_platform_types.dart';
import 'native_runtime_assets.dart';

PlatformRuntime createPlatformRuntime({Uri? origin}) {
  if (origin == null) {
    throw ArgumentError('Native runtime requires the deployment HTTPS origin');
  }
  return NativePlatformRuntime(origin);
}

final class NativePlatformRuntime extends PlatformRuntime {
  NativePlatformRuntime(this.origin) {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw ArgumentError(
        'Native runtime must use a single deployment HTTPS origin',
      );
    }
  }

  @override
  final Uri origin;
  HeadlessInAppWebView? _view;
  InAppWebViewController? _controller;
  Future<void>? _opening;
  int _generation = 0;
  bool _disposed = false;
  Map<String, Object?>? _authenticationContinuation;

  @override
  Future<bool> authenticate(
    BuildContext context, {
    String returnTo = '/',
    Map<String, Object?> pending = const {},
  }) async {
    authenticationPath(returnTo);
    _authenticationContinuation = {'returnTo': returnTo, 'pending': pending};
    final authenticated = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _AuthenticationPage(origin: origin),
      ),
    );
    if (authenticated == true) await rebuild();
    return authenticated == true;
  }

  @override
  Map<String, Object?>? takePendingAuthentication() {
    final value = _authenticationContinuation;
    _authenticationContinuation = null;
    return value;
  }

  Future<void> _ensureHost() {
    if (_disposed) {
      return Future.error(
        const RuntimeException(
          RuntimeErrorCode.runtimeLost,
          'Native runtime container was disposed',
        ),
      );
    }
    final current = _opening;
    if (current != null) return current;
    final opening = _startHost();
    _opening = opening;
    unawaited(
      opening.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          if (identical(_opening, opening)) _opening = null;
        },
      ),
    );
    return opening;
  }

  Future<void> _startHost() async {
    final generation = ++_generation;
    final assets = await NativeRuntimeAssets.load();
    if (Platform.isAndroid &&
        !await WebViewFeature.isFeatureSupported(
          WebViewFeature.DOCUMENT_START_SCRIPT,
        )) {
      throw const RuntimeException(
        RuntimeErrorCode.unsupportedCapability,
        'This Android WebView cannot install the bundled runtime before page scripts',
      );
    }
    if (_disposed || generation != _generation) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native runtime container was replaced while loading app assets',
      );
    }
    final loaded = Completer<void>();
    _view = HeadlessInAppWebView(
      initialUserScripts: UnmodifiableListView([
        UserScript(
          groupName: 'karuyomi-native-runtime',
          source: assets.documentStartScript(origin),
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          contentWorld: ContentWorld.PAGE,
          forMainFrameOnly: true,
          allowedOriginRules: {origin.origin},
        ),
      ]),
      initialUrlRequest: URLRequest(
        url: WebUri(origin.resolve('/runtime/host.html').toString()),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        sharedCookiesEnabled: true,
        useShouldOverrideUrlLoading: true,
        useOnRenderProcessGone: true,
      ),
      onWebViewCreated: (controller) {
        if (generation == _generation) _controller = controller;
      },
      shouldOverrideUrlLoading: (controller, action) async {
        final target = action.request.url;
        // Interactive Access/IdP login uses a separate visible flow; the hidden
        // runtime never silently follows a cross-origin login document.
        if (target != null &&
            Uri.parse(target.toString()).origin != origin.origin) {
          if (generation == _generation && !loaded.isCompleted) {
            loaded.completeError(
              const RuntimeException(
                RuntimeErrorCode.accessRequired,
                'Access login requires a visible authentication flow',
              ),
            );
          }
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onLoadStop: (controller, url) async {
        if (generation != _generation || loaded.isCompleted) return;
        if (url == null || Uri.parse(url.toString()).origin != origin.origin) {
          loaded.completeError(
            const RuntimeException(
              RuntimeErrorCode.accessRequired,
              'Access login requires a visible authentication flow',
            ),
          );
          return;
        }
        try {
          final result = await controller.callAsyncJavaScript(
            functionBody: '''
              const installed = window.__karuyomiNativeRuntimeInstalled;
              if (!installed || installed.materialVersion !== materialVersion ||
                  installed.runtime !== window.karuyomiRuntime) {
                throw new Error('Bundled Native runtime is missing or was replaced');
              }
              return JSON.stringify(await window.karuyomiRuntime.control(request));
            ''',
            arguments: {
              'materialVersion': assets.materialVersion,
              'request': wire.encodeProtoJson(
                wire.ControlRequest(
                  requestId: 'native-handshake-$generation',
                  ready: wire.Empty(),
                ),
              ),
            },
          );
          if (result?.error != null || result?.value is! String) {
            throw const RuntimeException(
              RuntimeErrorCode.runtimeLost,
              'Native runtime control handshake failed',
            );
          }
          final response = wire.decodeProtoJson(
            wire.ControlResponse(),
            decodeNativeControlResult(result!.value),
          );
          if (response.whichResult() == wire.ControlResponse_Result.error) {
            throw RuntimeException.fromProto(response.error);
          }
          if (response.requestId != 'native-handshake-$generation' ||
              response.whichResult() != wire.ControlResponse_Result.hello ||
              !isCompatibleHost(response.hello) ||
              response.hello.runtimeBaseline != runtimeBaseline) {
            throw const RuntimeException(
              RuntimeErrorCode.protocolError,
              'Incompatible bundled Native runtime',
            );
          }
          if (!loaded.isCompleted) loaded.complete();
        } catch (error) {
          if (!loaded.isCompleted) loaded.completeError(error);
        }
      },
      onReceivedError: (controller, request, error) {
        if (generation == _generation &&
            request.isForMainFrame == true &&
            !loaded.isCompleted) {
          loaded.completeError(
            RuntimeException(RuntimeErrorCode.runtimeLost, error.description),
          );
        }
      },
      onWebContentProcessDidTerminate: (controller) => unawaited(rebuild()),
      onRenderProcessGone: (controller, detail) => rebuild(),
    );
    final view = _view!;
    try {
      await view.run();
      await loaded.future.timeout(const Duration(seconds: 20));
    } catch (_) {
      if (generation == _generation) {
        ++_generation;
        _view = null;
        _controller = null;
      }
      await view.dispose();
      rethrow;
    }
    if (generation != _generation) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native runtime container was replaced',
      );
    }
  }

  @override
  Future<Object?> control(Map<String, Object?> request) async {
    final message = wire.decodeProtoJson(
      wire.ControlRequest(),
      request,
      maxBytes: wire.controlRequestLimit,
    );
    final command = message.whichCommand();
    if (command == wire.ControlRequest_Command.acquireImage) {
      throw const RuntimeException(
        RuntimeErrorCode.unsupportedCapability,
        'Native processed-image files are not implemented on this platform',
      );
    }
    if (_view == null &&
        {
          wire.ControlRequest_Command.cancelImage,
          wire.ControlRequest_Command.releaseImage,
          wire.ControlRequest_Command.closePageSession,
        }.contains(command)) {
      // Cleanup of an expired handle must not create a replacement WebView.
      return wire.encodeProtoJson(
        wire.ControlResponse(
          requestId: message.requestId,
          closed: command == wire.ControlRequest_Command.closePageSession
              ? wire.Closed(closed: true)
              : null,
          released: command == wire.ControlRequest_Command.closePageSession
              ? null
              : wire.Released(released: true),
        ),
      );
    }
    if (command == wire.ControlRequest_Command.dispose && _view == null) {
      return wire.encodeProtoJson(
        wire.ControlResponse(
          requestId: message.requestId,
          completed: wire.Completed(completed: true),
        ),
      );
    }
    await _ensureHost();
    final generation = _generation;
    final result = await _controller!.callAsyncJavaScript(
      functionBody: '''
        const host = window.karuyomiRuntime;
        if (!host) throw new Error('Runtime control module was lost');
        return JSON.stringify(await host.control(request));
      ''',
      arguments: {'request': request},
    );
    if (generation != _generation ||
        result?.error != null ||
        result?.value is! String) {
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Native runtime call belongs to an expired or failed container',
      );
    }
    return decodeNativeControlResult(result!.value);
  }

  @override
  Future<void> rebuild() async {
    runtime.containerLost('Native runtime container was rebuilt');
    ++_generation;
    await _view?.dispose();
    _view = null;
    _controller = null;
    _opening = null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    try {
      await runtime.dispose();
    } finally {
      _disposed = true;
      ++_generation;
      await _view?.dispose();
      _view = null;
      _controller = null;
      _opening = null;
    }
  }
}

/// Access and the IdP stay inside the app, sharing the runtime's cookie store.
final class _AuthenticationPage extends StatefulWidget {
  const _AuthenticationPage({required this.origin});
  final Uri origin;

  @override
  State<_AuthenticationPage> createState() => _AuthenticationPageState();
}

final class _AuthenticationPageState extends State<_AuthenticationPage> {
  String? _error;
  bool _checking = false;
  bool _completed = false;
  InAppWebViewController? _controller;

  Future<void> _check(InAppWebViewController controller, WebUri? url) async {
    if (_checking || _completed || url == null || !mounted) return;
    if (Uri.parse(url.toString()).origin != widget.origin.origin) return;
    _checking = true;
    try {
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
          const response = await fetch('/api/bootstrap', {
            credentials:'same-origin', redirect:'manual', cache:'no-store',
            headers:{Accept:'application/json'}
          });
          if (response.status !== 200 || !(response.headers.get('content-type') ?? '').includes('application/json')) return false;
          const bootstrap = await response.json();
          return typeof bootstrap.identity?.subject === 'string' && typeof bootstrap.identity?.email === 'string';
        ''',
      );
      if (mounted && result?.value == true) {
        _completed = true;
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '登录后未能确认身份，请重试。');
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('登录')),
    body: Column(
      children: [
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(
                onPressed: () => _controller?.reload(),
                child: const Text('重试'),
              ),
            ],
          ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri(
                widget.origin
                    .resolve(authenticationPath('/runtime/host.html'))
                    .toString(),
              ),
            ),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              sharedCookiesEnabled: true,
              useShouldOverrideUrlLoading: true,
            ),
            onWebViewCreated: (controller) => _controller = controller,
            shouldOverrideUrlLoading: (controller, action) async {
              final target = action.request.url;
              return target == null || target.scheme == 'https'
                  ? NavigationActionPolicy.ALLOW
                  : NavigationActionPolicy.CANCEL;
            },
            onLoadStop: _check,
            onReceivedError: (controller, request, error) {
              if (request.isForMainFrame == true && mounted) {
                setState(() => _error = error.description);
              }
            },
          ),
        ),
      ],
    ),
  );
}
