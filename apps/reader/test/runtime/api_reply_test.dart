import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

final class ApiRuntime extends PlatformRuntime {
  Object? status = 200;
  bool redirected = false;
  @override
  Uri get origin => Uri.parse('https://reader.example.com');
  @override
  Future<Object?> control(Map<String, Object?> json) async {
    final request = wire.decodeProtoJson(wire.ControlRequest(), json);
    return {
      'requestId': request.requestId,
      'slotId': request.slotId.name,
      'api': {
        'status': status,
        'headers': {'content-type': 'application/json'},
        'body': '{}',
        'redirected': redirected,
      },
    };
  }

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
  test('generated API reply retains HTTP status and headers', () async {
    final runtime = ApiRuntime();
    for (final status in [200, 401, 503]) {
      runtime.status = status;
      final reply = await runtime.fetchApi('/api/bootstrap');
      expect(reply.status, status.toInt());
      expect(reply.headers['content-type'], 'application/json');
      expect(reply.body, '{}');
      expect(reply.redirected, isFalse);
    }
  });

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
        'not-a-status',
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
        ..status = 0
        ..redirected = true;
      final reply = await runtime.fetchApi('/api/bootstrap');
      expect(reply.status, 0);
      expect(reply.redirected, isTrue);
    },
  );

  test('Native JSON text preserves integer tokens and rejects Number maps', () {
    final decoded = decodeNativeControlResult(
      '{"requestId":"c","slotId":"RUNTIME_SLOT_FOREGROUND","api":{"status":200,"body":"{}"}}',
    );
    expect(
      wire.decodeProtoJson(wire.ControlResponse(), decoded).api.status,
      200,
    );
    expect(
      () => decodeNativeControlResult({
        'api': {'status': 200.0},
      }),
      throwsA(isA<RuntimeException>()),
    );
  });
}
