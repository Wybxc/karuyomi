import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:uuid/uuid.dart';

import 'api_fetch.dart';
import 'cover_transport.dart';
import 'catalog_transport.dart';
export 'api_fetch.dart';

/// Native returns JSON.stringify output so JS integer tokens survive the
/// WebView's otherwise all-double JavaScript Number conversion.
Object? decodeNativeControlResult(Object? value) {
  if (value is! String) {
    throw const RuntimeException(
      RuntimeErrorCode.protocolError,
      'Native control did not return ProtoJSON text',
    );
  }
  return jsonDecode(value);
}

abstract class PlatformRuntime implements RuntimeTransport, ApiFetch {
  late final TransportSourceRuntime runtime = TransportSourceRuntime(this);
  late final TransportSourceRuntime searchRuntime = TransportSourceRuntime(
    this,
    slotId: wire.RuntimeSlot.RUNTIME_SLOT_SEARCH,
  );
  Uri get origin;
  bool get runtimeRestartBlocked => false;
  CatalogTransport? _catalogTransport;
  CatalogTransport get catalogTransport =>
      _catalogTransport ??= HttpCatalogTransport();

  CoverTransport? get coverTransport => null;

  /// Waits for the first-party Access return. The caller then bootstraps to
  /// confirm the session and its identity before continuing.
  Future<bool> authenticate(
    BuildContext context, {
    String returnTo = '/',
    Map<String, Object?> pending = const {},
  });

  /// One-shot continuation saved before the visible authentication flow.
  Map<String, Object?>? takePendingAuthentication();

  @override
  Future<ApiReply> fetchApi(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final value = await runtime.fetchApi(
      wire.ApiFetchRequest(
        path: path,
        method: method,
        headers: headers.entries,
        body: body,
      ),
    );
    return ApiReply(
      status: value.status,
      headers: Map.unmodifiable(value.headers),
      body: value.body,
      redirected: value.redirected,
    );
  }

  Future<void> rebuild();
  Future<void> dispose();
}

({String id, Uri login, Uri callback}) authenticationAttempt(
  Uri origin,
  String returnTo,
) {
  final uri = Uri.tryParse(returnTo);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !returnTo.startsWith('/') ||
      returnTo.startsWith('//') ||
      returnTo.contains('\\')) {
    throw ArgumentError('Authentication return path must be same-origin');
  }
  const callbackPath = '/auth/complete';
  final id = const Uuid().v4();
  return (
    id: id,
    login: origin
        .resolve('/api/auth/login')
        .replace(queryParameters: {'returnTo': callbackPath, 'attempt': id}),
    callback: origin
        .resolve(callbackPath)
        .replace(queryParameters: {'attempt': id}),
  );
}
