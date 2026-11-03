import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:source_runtime/source_runtime.dart';

final class ApiRuntime extends PlatformRuntime {
  Object? status = 200.0;
  bool redirected = false;
  @override
  Uri get origin => Uri.parse('https://reader.example.com');
  @override
  Future<Object?> call(
    String method, [
    Map<String, Object?> payload = const {},
  ]) async => {
    'status': status,
    'headers': {'content-type': 'application/json'},
    'body': '{}',
    'redirected': redirected,
  };
  @override
  Future<bool> authenticate(
    BuildContext context, {
    String returnTo = '/',
    Map<String, Object?> pending = const {},
  }) async => false;
  @override
  Map<String, Object?>? takePendingAuthentication() => null;
  @override
  Future<void> rebuild() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'integral WKWebView Number statuses retain their HTTP meaning',
    () async {
      final runtime = ApiRuntime();
      for (final status in [200, 200.0, 401.0, 503.0]) {
        runtime.status = status;
        final reply = await runtime.fetchApi('/api/bootstrap');
        expect(reply.status, status.toInt());
        expect(reply.headers['content-type'], 'application/json');
        expect(reply.body, '{}');
        expect(reply.redirected, isFalse);
      }
    },
  );

  test(
    'malformed statuses fail instead of rounding into a successful response',
    () async {
      final runtime = ApiRuntime();
      for (final value in [
        200.5,
        double.nan,
        double.infinity,
        -1,
        99,
        600,
        '200',
        null,
        0,
      ]) {
        runtime.status = value;
        await expectLater(
          runtime.fetchApi('/api/bootstrap'),
          throwsA(
            isA<RuntimeException>().having(
              (error) => error.code,
              'code',
              RuntimeErrorCode.protocolError,
            ),
          ),
        );
      }
    },
  );

  test(
    'opaque manual redirects preserve status zero and require authentication',
    () async {
      final runtime = ApiRuntime()
        ..status = 0.0
        ..redirected = true;
      final reply = await runtime.fetchApi('/api/bootstrap');
      expect(reply.status, 0);
      expect(reply.redirected, isTrue);
    },
  );
}
