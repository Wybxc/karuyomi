import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:karuyomi/features/reader/resource_image.dart';
import 'package:karuyomi/diagnostics/reader_baseline.dart';
import 'package:reader_core/reader_core.dart';

final class CountingImageProvider extends ImageProvider<CountingImageProvider> {
  CountingImageProvider(this.bytes);
  final Uint8List bytes;
  final gate = Completer<void>();
  int loads = 0;
  int decodes = 0;
  ImageStreamCompleter? completer;

  @override
  Future<CountingImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    CountingImageProvider key,
    ImageDecoderCallback decode,
  ) {
    loads++;
    return completer = MultiFrameImageStreamCompleter(
      codec: _decode(decode),
      scale: 1,
    );
  }

  Future<ui.Codec> _decode(ImageDecoderCallback decode) async {
    await gate.future;
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    decodes++;
    return decode(buffer);
  }
}

ImageResource resource(String id) => ImageResource(
  id: id,
  generation: 'g',
  location: Uri.file('/unused/$id'),
  byteLength: 100,
);

Widget image({
  required ImageResource resource,
  required ImageProvider<Object> provider,
  required List<ReaderImageDecoded> decoded,
  required List<ReaderImageFailed> failures,
  ReaderBaselineRecorder? baseline,
  bool cropBorders = false,
  List<ReaderImageCrop>? crops,
  List<ReaderImageCropWork>? works,
}) => baseline == null
    ? imageContent(
        resource: resource,
        provider: provider,
        decoded: decoded,
        failures: failures,
        cropBorders: cropBorders,
        crops: crops,
        works: works,
      )
    : ReaderBaselineScope(
        recorder: baseline,
        child: imageContent(
          resource: resource,
          provider: provider,
          decoded: decoded,
          failures: failures,
          cropBorders: cropBorders,
          crops: crops,
          works: works,
        ),
      );

Widget imageContent({
  required ImageResource resource,
  required ImageProvider<Object> provider,
  required List<ReaderImageDecoded> decoded,
  required List<ReaderImageFailed> failures,
  bool cropBorders = false,
  List<ReaderImageCrop>? crops,
  List<ReaderImageCropWork>? works,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: NotificationListener<ReaderImageCropWork>(
    onNotification: (work) {
      works?.add(work);
      return true;
    },
    child: NotificationListener<ReaderImageCrop>(
      onNotification: (crop) {
        crops?.add(crop);
        return true;
      },
      child: NotificationListener<ReaderImageDecoded>(
        onNotification: (notification) {
          decoded.add(notification);
          return true;
        },
        child: NotificationListener<ReaderImageFailed>(
          onNotification: (notification) {
            failures.add(notification);
            return true;
          },
          child: ResourceImage(
            resource: resource,
            fit: BoxFit.contain,
            imageProvider: provider,
            cropBorders: cropBorders,
          ),
        ),
      ),
    ),
  ),
);

Future<void> finishDecode(
  WidgetTester tester,
  CountingImageProvider provider,
) async {
  final ready = Completer<void>();
  final listener = ImageStreamListener(
    (info, synchronousCall) {
      info.dispose();
      if (!ready.isCompleted) ready.complete();
    },
    onError: (Object error, StackTrace? stack) {
      if (!ready.isCompleted) ready.complete();
    },
    reportErrors: false,
  );
  final completer = provider.completer!;
  completer.addListener(listener);
  try {
    await tester.runAsync(() async {
      provider.gate.complete();
    });
    final timeout = Stopwatch()..start();
    while (!ready.isCompleted && timeout.elapsed < const Duration(seconds: 5)) {
      // MultiFrameImageStreamCompleter emits via the test scheduler. Drive
      // frames while allowing the real engine codec's asynchronous work.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(
      ready.isCompleted,
      true,
      reason: 'The actual provider must finish a frame or report an error',
    );
  } finally {
    completer.removeListener(listener);
  }
  await tester.pumpAndSettle();
}

Future<void> finishCrop(
  WidgetTester tester,
  List<ReaderImageCrop> crops,
  int count,
) async {
  final timeout = Stopwatch()..start();
  while (crops.length < count && timeout.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(
    crops,
    hasLength(count),
    reason: 'The actual UI pixel readback must finish',
  );
  await tester.pumpAndSettle();
}

Uint8List borderedPng({
  int white = 255,
  bool content = true,
  bool darkBorder = false,
  bool transparent = false,
}) {
  final bitmap = img.Image(width: 80, height: 100, numChannels: 4);
  img.fill(
    bitmap,
    color: img.ColorRgba8(
      darkBorder ? 20 : white,
      darkBorder ? 30 : white,
      darkBorder ? 40 : white,
      transparent ? 0 : 255,
    ),
  );
  if (content) {
    img.fillRect(
      bitmap,
      x1: 20,
      y1: 25,
      x2: 59,
      y2: 74,
      color: img.ColorRgba8(20, 40, 80, 255),
    );
  }
  return img.encodePng(bitmap);
}

void main() {
  testWidgets(
    'white border detection reuses the displayed codec and toggles cached geometry',
    (tester) async {
      final provider = CountingImageProvider(borderedPng());
      final encoded = resource('crop');
      final decoded = <ReaderImageDecoded>[];
      final failures = <ReaderImageFailed>[];
      final crops = <ReaderImageCrop>[];
      final works = <ReaderImageCropWork>[];
      Widget page(bool enabled) => image(
        resource: encoded,
        provider: provider,
        decoded: decoded,
        failures: failures,
        cropBorders: enabled,
        crops: crops,
        works: works,
      );
      await tester.pumpWidget(page(false));
      await finishDecode(tester, provider);
      expect(crops, isEmpty);
      expect(works, isEmpty);
      await tester.pumpWidget(page(true));
      await finishCrop(tester, crops, 1);
      expect(crops.single.bounds, const ui.Rect.fromLTRB(.225, .23, .775, .77));
      expect(crops.single.width, 80);
      expect(crops.single.height, 100);
      expect(crops.single.resourceId, 'crop');
      expect(provider.loads, 1);
      expect(provider.decodes, 1);
      expect(works, hasLength(1));
      await tester.pumpWidget(page(false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(page(true));
      await finishCrop(tester, crops, 2);
      expect(crops.last.bounds, crops.first.bounds);
      expect(works, hasLength(1));
      expect(provider.loads, 1);
      expect(provider.decodes, 1);
      expect(failures, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await provider.evict();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'near white margins trim while blank and colored edges retain the complete image',
    (tester) async {
      for (final variant in [0, 1, 2, 3]) {
        final provider = CountingImageProvider(
          borderedPng(
            white: 250,
            content: variant != 1,
            darkBorder: variant == 2,
            transparent: variant == 3,
          ),
        );
        final decoded = <ReaderImageDecoded>[];
        final failures = <ReaderImageFailed>[];
        final crops = <ReaderImageCrop>[];
        await tester.pumpWidget(
          image(
            resource: resource('variant-$variant'),
            provider: provider,
            decoded: decoded,
            failures: failures,
            cropBorders: true,
            crops: crops,
          ),
        );
        await finishDecode(tester, provider);
        await finishCrop(tester, crops, 1);
        expect(
          crops.single.bounds,
          variant == 0
              ? const ui.Rect.fromLTRB(.225, .23, .775, .77)
              : const ui.Rect.fromLTWH(0, 0, 1, 1),
        );
        expect(provider.loads, 1);
        expect(provider.decodes, 1);
        expect(failures, isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await provider.evict();
      }
      expect(tester.takeException(), isNull);
    },
  );

  // Real, encoded 3x2 PNG. Only CountingImageProvider's decoder reads these bytes.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAYAAACddGYaAAAAEUlEQVR4nGOoV3D4D8MMyBwAjN4LNZqBoewAAAAASUVORK5CYII=',
  );

  testWidgets(
    'metadata observer and displayed Image share one actual decode and report after a frame',
    (tester) async {
      final baseline = ReaderBaselineRecorder(
        flushDuration: const Duration(milliseconds: 10),
      )..start();
      addTearDown(baseline.dispose);
      final provider = CountingImageProvider(png);
      final decoded = <ReaderImageDecoded>[];
      final failures = <ReaderImageFailed>[];
      await tester.pumpWidget(
        image(
          resource: resource('a'),
          baseline: baseline,
          provider: provider,
          decoded: decoded,
          failures: failures,
        ),
      );
      expect(provider.loads, 1);
      expect(provider.decodes, 0);
      expect(decoded, isEmpty);
      await finishDecode(tester, provider);
      expect(provider.loads, 1);
      expect(provider.decodes, 1);
      expect(decoded, hasLength(1));
      expect(decoded.single.resourceId, 'a');
      expect(decoded.single.width, 3);
      expect(decoded.single.height, 2);
      expect(failures, isEmpty);
      final raw = tester.widget<RawImage>(find.byType(RawImage));
      expect(raw.image?.width, decoded.single.width);
      expect(raw.image?.height, decoded.single.height);

      // Cached synchronous frame and another logical owner use the same completer.
      await tester.pumpWidget(
        image(
          resource: resource('b'),
          baseline: baseline,
          provider: provider,
          decoded: decoded,
          failures: failures,
        ),
      );
      await tester.pumpAndSettle();
      expect(provider.loads, 1);
      expect(provider.decodes, 1);
      expect(decoded.map((event) => event.resourceId), ['a', 'b']);
      final stopped = baseline.stop();
      await tester.pump(const Duration(milliseconds: 10));
      await stopped;
      final captured = (jsonDecode(baseline.exportJson())['events'] as List)
          .cast<Map<String, dynamic>>();
      final infos = captured.where((e) => e['type'] == 'image_info').toList();
      expect(infos, hasLength(2));
      expect(infos.first['data'], containsPair('synchronousCall', false));
      expect(infos.last['data'], containsPair('synchronousCall', true));
      expect(infos.last['data'], containsPair('width', 3));
      expect(infos.last['data'], containsPair('height', 2));
      final frames = captured.where((e) => e['type'] == 'image_frame').toList();
      expect(frames.map((e) => e['data']['resourceId']), ['a', 'b']);
      expect(
        frames.every(
          (e) =>
              e['data']['imageFrame'] == 0 && e['data']['frameNumber'] is int,
        ),
        true,
      );
      expect(
        captured.where((e) => e['type'] == 'image_post_frame'),
        hasLength(2),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await provider.evict();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual provider decode error emits failure and never a decoded frame',
    (tester) async {
      final baseline = ReaderBaselineRecorder(
        flushDuration: const Duration(milliseconds: 10),
      )..start();
      addTearDown(baseline.dispose);
      final provider = CountingImageProvider(Uint8List.fromList([1, 2, 3]));
      final decoded = <ReaderImageDecoded>[];
      final failures = <ReaderImageFailed>[];
      await tester.pumpWidget(
        image(
          resource: resource('bad'),
          baseline: baseline,
          provider: provider,
          decoded: decoded,
          failures: failures,
        ),
      );
      await finishDecode(tester, provider);
      expect(provider.loads, 1);
      expect(provider.decodes, 1);
      expect(decoded, isEmpty);
      expect(failures, hasLength(1));
      expect(failures.single.resourceId, 'bad');
      final stopped = baseline.stop();
      await tester.pump(const Duration(milliseconds: 10));
      await stopped;
      final captured = (jsonDecode(baseline.exportJson())['events'] as List)
          .cast<Map<String, dynamic>>();
      expect(captured.where((e) => e['type'] == 'image_error'), hasLength(1));
      expect(
        captured.where(
          (e) =>
              e['type'] == 'image_info' ||
              e['type'] == 'image_frame' ||
              e['type'] == 'image_post_frame',
        ),
        isEmpty,
      );

      expect(find.text('无法显示这张图片'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await provider.evict();
    },
  );

  testWidgets(
    'metadata listener follows Image pause without keeping background animation active',
    (tester) async {
      final provider = CountingImageProvider(png);
      final encoded = resource('paused');
      final crops = <ReaderImageCrop>[];
      final decoded = <ReaderImageDecoded>[];
      final failures = <ReaderImageFailed>[];
      Widget pausedImage(bool enabled, {bool crop = false}) => TickerMode(
        enabled: enabled,
        child: image(
          resource: encoded,
          provider: provider,
          decoded: decoded,
          failures: failures,
          cropBorders: crop,
          crops: crops,
        ),
      );
      await tester.pumpWidget(pausedImage(false));
      await finishDecode(tester, provider);
      expect(decoded, hasLength(1));
      expect(provider.completer?.hasListeners, false);
      await tester.pumpWidget(pausedImage(false, crop: true));
      // Pixel readback is still pending; enabling crop must not restart the
      // paused completer while waiting for it.
      expect(crops, isEmpty);
      expect(provider.completer?.hasListeners, false);
      await finishCrop(tester, crops, 1);
      expect(provider.completer?.hasListeners, false);
      await tester.pumpWidget(pausedImage(true, crop: true));
      await tester.pumpAndSettle();
      expect(provider.completer?.hasListeners, true);
      expect(provider.loads, 1);
      expect(provider.decodes, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await provider.evict();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late provider completion after unmount does not publish dimensions',
    (tester) async {
      final provider = CountingImageProvider(png);
      final decoded = <ReaderImageDecoded>[];
      final failures = <ReaderImageFailed>[];
      final crops = <ReaderImageCrop>[];
      await tester.pumpWidget(
        image(
          resource: resource('late'),
          cropBorders: true,
          crops: crops,
          provider: provider,
          decoded: decoded,
          failures: failures,
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await finishDecode(tester, provider);
      expect(decoded, isEmpty);
      expect(failures, isEmpty);
      expect(crops, isEmpty);
      await provider.evict();
      expect(tester.takeException(), isNull);
    },
  );
}
