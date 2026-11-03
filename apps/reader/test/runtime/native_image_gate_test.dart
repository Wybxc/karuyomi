import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/runtime/platform_runtime_native.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

void main() {
  test(
    'Native image acquire is unsupported before creating any WebView',
    () async {
      final platform = NativePlatformRuntime(
        Uri.parse('https://reader.example'),
      );
      await expectLater(
        platform.control(
          wire.encodeProtoJson(
            wire.ControlRequest(
              requestId: 'image',
              acquireImage: wire.AcquireImage(
                requestId: 'i',
                generation: 'old',
                sourceId: '42',
                pageSessionId: 'p',
                pageKey: 'p-0',
              ),
            ),
          ),
        ),
        throwsA(
          isA<RuntimeException>().having(
            (error) => error.code,
            'code',
            RuntimeErrorCode.unsupportedCapability,
          ),
        ),
      );
      expect(
        wire
            .decodeProtoJson(
              wire.ControlResponse(),
              await platform.control(
                wire.encodeProtoJson(
                  wire.ControlRequest(
                    requestId: 'close',
                    closePageSession: wire.ClosePageSession(
                      pageSessionId: 'expired',
                      generation: 'old',
                    ),
                  ),
                ),
              ),
            )
            .closed
            .closed,
        true,
      );
      expect(
        wire
            .decodeProtoJson(
              wire.ControlResponse(),
              await platform.control(
                wire.encodeProtoJson(
                  wire.ControlRequest(
                    requestId: 'release',
                    releaseImage: wire.ReleaseImage(
                      resourceId: 'expired',
                      generation: 'old',
                    ),
                  ),
                ),
              ),
            )
            .released
            .released,
        true,
      );
      await platform.dispose();
    },
  );
}
