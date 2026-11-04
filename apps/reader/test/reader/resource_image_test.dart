import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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
}) => baseline == null
    ? imageContent(
        resource: resource,
        provider: provider,
        decoded: decoded,
        failures: failures,
      )
    : ReaderBaselineScope(
        recorder: baseline,
        child: imageContent(
          resource: resource,
          provider: provider,
          decoded: decoded,
          failures: failures,
        ),
      );

Widget imageContent({
  required ImageResource resource,
  required ImageProvider<Object> provider,
  required List<ReaderImageDecoded> decoded,
  required List<ReaderImageFailed> failures,
}) => Directionality(
  textDirection: TextDirection.ltr,
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

void main() {
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
      final decoded = <ReaderImageDecoded>[];
      final failures = <ReaderImageFailed>[];
      Widget pausedImage(bool enabled) => TickerMode(
        enabled: enabled,
        child: image(
          resource: encoded,
          provider: provider,
          decoded: decoded,
          failures: failures,
        ),
      );
      await tester.pumpWidget(pausedImage(false));
      await finishDecode(tester, provider);
      expect(decoded, hasLength(1));
      expect(provider.completer?.hasListeners, false);
      await tester.pumpWidget(pausedImage(true));
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
      await tester.pumpWidget(
        image(
          resource: resource('late'),
          provider: provider,
          decoded: decoded,
          failures: failures,
        ),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await finishDecode(tester, provider);
      expect(decoded, isEmpty);
      expect(failures, isEmpty);
      await provider.evict();
      expect(tester.takeException(), isNull);
    },
  );
}
