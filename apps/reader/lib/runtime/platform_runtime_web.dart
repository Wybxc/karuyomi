import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/widgets.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'runtime_platform_types.dart';

@JS('globalThis.karuyomiRuntime')
external JSObject? get _runtimeHost;
@JS('globalThis.location.origin')
external JSString get _origin;
@JS('globalThis.location')
external _Location get _location;
@JS('globalThis.sessionStorage')
external _Storage get _storage;

extension type _Location(JSObject _) implements JSObject {
  external void assign(JSString url);
}

extension type _Storage(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
  external void removeItem(JSString key);
}

PlatformRuntime createPlatformRuntime({Uri? origin}) => WebPlatformRuntime();

final class WebPlatformRuntime extends PlatformRuntime {
  static const _authenticationKey = 'karuyomi.authentication.v1';

  @override
  Uri get origin => Uri.parse(_origin.toDart);

  @override
  Future<bool> authenticate(
    BuildContext context, {
    String returnTo = '/',
    Map<String, Object?> pending = const {},
  }) async {
    final path = authenticationPath(returnTo);
    final continuation = {'returnTo': returnTo, 'pending': pending};
    wire.checkJsonBudget(continuation, maxBytes: wire.controlRequestLimit);
    final state = jsonEncode(continuation);
    _storage.setItem(_authenticationKey.toJS, state.toJS);
    _location.assign(path.toJS);
    return false;
  }

  @override
  Map<String, Object?>? takePendingAuthentication() {
    final value = _storage.getItem(_authenticationKey.toJS)?.toDart;
    _storage.removeItem(_authenticationKey.toJS);
    if (value == null) return null;
    try {
      final data = jsonDecode(value);
      return data is Map ? Map<String, Object?>.from(data) : null;
    } on FormatException {
      return null;
    }
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
  Future<void> dispose() => runtime.dispose();
}
