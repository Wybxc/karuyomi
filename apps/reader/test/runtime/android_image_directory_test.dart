import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/runtime/android_image_files.dart';
import 'package:source_runtime/source_runtime.dart';

final class _Controller extends PlatformInAppWebViewController {
  _Controller()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(
          id: 'directory-owner',
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'startup retries failed cleanup and only reclaims previous runs',
    () async {
      final cache = await Directory.systemTemp.createTemp(
        'karuyomi-image-dirs-',
      );
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(paths, (call) async {
        if (call.method == 'getTemporaryDirectory') return cache.path;
        throw MissingPluginException(call.method);
      });
      final stores = <AndroidImageFileStore>[];
      final controller = InAppWebViewController.fromPlatform(
        platform: _Controller(),
      );
      final origin = Uri.parse('https://reader.example');
      try {
        final invalidRoot = File('${cache.path}/karuyomi-images');
        await invalidRoot.writeAsString('keep invalid entry');
        await expectLater(
          AndroidImageFileStore.bind(controller, origin),
          throwsA(
            isA<RuntimeException>().having(
              (error) => error.code,
              'code',
              RuntimeErrorCode.runtimeLost,
            ),
          ),
        );
        expect(await invalidRoot.readAsString(), 'keep invalid entry');
        await invalidRoot.delete();

        final orphan = File('${invalidRoot.path}/dead-run/store/image');
        await orphan.parent.create(recursive: true);
        await orphan.writeAsBytes([1, 2, 3]);
        final unrelated = File('${cache.path}/unrelated-cache');
        await unrelated.writeAsString('unrelated');
        stores.addAll(
          await Future.wait([
            AndroidImageFileStore.bind(controller, origin),
            AndroidImageFileStore.bind(controller, origin),
          ]),
        );
        expect(await orphan.exists(), isFalse);
        expect(await unrelated.readAsString(), 'unrelated');
        expect(
          stores[0].directory.parent.path,
          stores[1].directory.parent.path,
        );
        expect(stores[0].directory.path, isNot(stores[1].directory.path));

        final active = File('${stores[1].directory.path}/active.image');
        await active.writeAsBytes([4, 5, 6]);
        await stores[0].clear();
        stores.add(await AndroidImageFileStore.bind(controller, origin));
        expect(await active.readAsBytes(), [4, 5, 6]);
        expect(
          stores[2].directory.parent.path,
          stores[1].directory.parent.path,
        );
      } finally {
        await Future.wait(stores.map((store) => store.clear()));
        messenger.setMockMethodCallHandler(paths, null);
        if (await cache.exists()) await cache.delete(recursive: true);
      }
    },
  );
}
