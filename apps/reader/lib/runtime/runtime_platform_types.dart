import 'package:flutter/widgets.dart';
import 'package:source_runtime/source_runtime.dart';

final class ApiReply {
  const ApiReply({
    required this.status,
    required this.headers,
    required this.body,
    required this.redirected,
  });
  final int status;
  final Map<String, String> headers;
  final String body;
  final bool redirected;
}

abstract interface class ApiFetch {
  Future<ApiReply> fetchApi(
    String path, {
    String method = 'GET',
    Map<String, String> headers = const {},
    String? body,
  });
}

abstract class PlatformRuntime implements RuntimeTransport, ApiFetch {
  late final TransportSourceRuntime runtime = TransportSourceRuntime(this);
  Uri get origin;

  /// Web leaves this page; native returns after bootstrap confirms the cookie.
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
    final value = await call('fetchApi', {
      'path': path,
      'method': method,
      'headers': headers,
      'body': ?body,
    });
    if (value is! Map) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'API transport did not return a response',
      );
    }
    // WKWebView maps JavaScript Numbers to doubles, including HTTP status codes.
    final status = value['status'];
    if (status is! num ||
        !status.isFinite ||
        status != status.truncateToDouble() ||
        (status != 0 && (status < 100 || status > 599)) ||
        (status == 0 && value['redirected'] != true)) {
      throw const RuntimeException(
        RuntimeErrorCode.protocolError,
        'API transport returned an invalid HTTP status',
      );
    }
    return ApiReply(
      status: status.toInt(),
      headers: Map<String, String>.from(value['headers'] as Map),
      body: value['body'] as String,
      redirected: value['redirected'] == true,
    );
  }

  Future<void> rebuild();
  Future<void> dispose();
}

String authenticationPath(String returnTo) {
  final uri = Uri.tryParse(returnTo);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !returnTo.startsWith('/') ||
      returnTo.startsWith('//') ||
      returnTo.contains('\\')) {
    throw ArgumentError('Authentication return path must be same-origin');
  }
  return Uri(
    path: '/api/auth/login',
    queryParameters: {'returnTo': returnTo},
  ).toString();
}
