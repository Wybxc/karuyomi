import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/runtime/platform_runtime_native.dart';
import 'package:source_runtime/source_runtime.dart';

void main() {
  test(
    'Native image acquire is unsupported before creating any WebView',
    () async {
      final platform = NativePlatformRuntime(
        Uri.parse('https://reader.example'),
      );
      await expectLater(
        platform.call('acquireImage', {
          'url': 'blob:https://reader.example/id',
        }),
        throwsA(
          isA<RuntimeException>().having(
            (error) => error.code,
            'code',
            RuntimeErrorCode.unsupportedCapability,
          ),
        ),
      );
      expect(
        await platform.call('closePageSession', {
          'pageSessionId': 'expired',
          'generation': 'old',
        }),
        {'closed': true},
      );
      expect(
        await platform.call('releaseImage', {
          'resourceId': 'expired',
          'generation': 'old',
        }),
        {'released': true},
      );
      await platform.dispose();
    },
  );
}
