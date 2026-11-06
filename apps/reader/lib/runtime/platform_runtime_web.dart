import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/widgets.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:uuid/uuid.dart';
import 'package:web/web.dart' as web;
import 'package:http/browser_client.dart';
import 'cover_transport.dart';
import 'catalog_transport.dart';
import 'catalog_transport_web.dart';
import 'popup_authentication.dart';
import 'runtime_platform_types.dart';

@JS('globalThis.karuyomiRuntime')
external JSObject? get _runtimeHost;
@JS('globalThis.location.origin')
external JSString get _origin;

PlatformRuntime createPlatformRuntime({Uri? origin}) => WebPlatformRuntime();

final class WebPlatformRuntime extends PlatformRuntime {
  PopupAuthentication? _authentication;
  Map<String, Object?>? _pendingAuthentication;
  bool _disposed = false;
  @override
  late final CatalogTransport catalogTransport = WebCatalogTransport();
  @override
  late final CoverTransport coverTransport = HttpCoverTransport(
    origin: origin,
    createClient: BrowserClient.new,
  );

  @override
  Uri get origin => Uri.parse(_origin.toDart);

  @override
  Future<bool> authenticate(
    BuildContext context, {
    String returnTo = '/',
    Map<String, Object?> pending = const {},
  }) async {
    if (_disposed) throw StateError('服务已关闭，请重新连接。');
    if (_authentication != null) throw StateError('登录窗口已打开，请先完成或关闭。');
    authenticationPath(returnTo);
    final continuation = {'returnTo': returnTo, 'pending': pending};
    wire.checkJsonBudget(continuation, maxBytes: wire.controlRequestLimit);
    final attempt = const Uuid().v4();
    final path = Uri(
      path: '/api/auth/login',
      queryParameters: {'returnTo': '/auth/complete', 'attempt': attempt},
    ).toString();
    // Open synchronously before the first await, while the click still grants
    // popup activation. The current app and its unconfirmed drafts stay alive.
    final popup = web.window.open(
      path,
      'karuyomi-auth-$attempt',
      'popup,width=520,height=720',
    );
    if (popup == null) throw StateError('浏览器阻止了登录窗口，请允许弹出窗口后重试。');
    final authentication = PopupAuthentication();
    _authentication = authentication;
    _pendingAuthentication = continuation;
    try {
      return await authentication.wait(
        origin: origin,
        attempt: attempt,
        readLocation: () {
          try {
            return Uri.tryParse(popup.location.href);
          } catch (_) {
            return null; // Reading the Access page's origin is not permitted.
          }
        },
        isClosed: () => popup.closed,
        close: () => popup.close(),
      );
    } catch (_) {
      _pendingAuthentication = null;
      rethrow;
    } finally {
      _authentication = null;
    }
  }

  @override
  Map<String, Object?>? takePendingAuthentication() {
    final pending = _pendingAuthentication;
    _pendingAuthentication = null;
    return pending;
  }

  Future<JSObject> _host() async {
    for (var attempt = 0; attempt < 50; attempt++) {
      final host = _runtimeHost;
      if (host != null) return host;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const RuntimeException(
      RuntimeErrorCode.runtimeLost,
      'The same-origin runtime control module did not load',
    );
  }

  @override
  Future<Object?> control(Map<String, Object?> request) async {
    try {
      final host = await _host();
      final result = host.callMethod<JSPromise<JSAny?>>(
        'control'.toJS,
        request.jsify(),
      );
      return (await result.toDart)?.dartify();
    } catch (error) {
      if (error is RuntimeException) rethrow;
      throw const RuntimeException(
        RuntimeErrorCode.runtimeLost,
        'Web runtime control transport failed',
      );
    }
  }

  @override
  Future<void> rebuild() async {
    runtime.containerLost('Web runtime slot must be opened again');
    await runtime.rebuildHost();
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    coverTransport.close();
    catalogTransport.close();
    _authentication?.cancel();
    _pendingAuthentication = null;
    return runtime.dispose();
  }
}
