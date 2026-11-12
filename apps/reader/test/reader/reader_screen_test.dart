import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/features/reader/reader_preferences.dart';
import 'package:karuyomi/diagnostics/reader_baseline.dart';
import 'package:karuyomi/features/reader/resource_image.dart';
import 'package:reader_core/reader_core.dart';

final class FixturePageProvider implements PageProvider {
  FixturePageProvider({this.location, this.byteLength = 100});
  final Uri? location;
  final int byteLength;
  final acquired = <PageRef>[];
  final released = <String>[];
  final cancelled = <String>[];

  @override
  Future<ImageResource> acquire(PageRef ref) async {
    acquired.add(ref);
    return ImageResource(
      id: '${ref.generation}-${ref.pageKey}',
      generation: ref.generation,
      location:
          location ??
          Uri.parse('https://processed-fixture.invalid/${ref.pageKey}'),
      byteLength: byteLength,
    );
  }

  @override
  Future<void> cancel(String requestId) async => cancelled.add(requestId);
  @override
  Future<void> release(String resourceId) async => released.add(resourceId);
}

ChapterManifest fixtureChapter() => ChapterManifest(
  chapterKey: 'chapter',
  version: '1',
  pages: List.generate(
    20,
    (index) => ReaderPage(key: 'page-$index', width: 600, height: 900),
  ),
);

Widget fixtureImage(BuildContext context, ImageResource resource, BoxFit fit) =>
    ColoredBox(
      key: ValueKey(resource.id),
      color: Colors.indigo,
      child: Center(child: Text(resource.id)),
    );

ResourceImageBuilder decodedImage({int width = 600, int height = 900}) =>
    (context, resource, fit) {
      ReaderImageDecoded(
        resource.id,
        width: width,
        height: height,
      ).dispatch(context);
      return fixtureImage(context, resource, fit);
    };

void expectRenderedAnchor(
  WidgetTester tester,
  ReadingPosition anchor,
  Finder viewport,
) {
  final image = tester.getRect(
    find.byKey(ValueKey('image-rect-${anchor.pageKey}')),
  );
  final bounds = tester.getRect(viewport);
  expect(
    image.left + image.width * anchor.normalizedX,
    closeTo(bounds.left + bounds.width * anchor.viewportX, 1),
  );
  expect(
    image.top + image.height * anchor.normalizedOffset,
    closeTo(bounds.top + bounds.height * anchor.viewportY, 1),
  );
}

Widget screen({
  required FixturePageProvider provider,
  required ChapterManifest manifest,
  ReadingPosition? position,
  bool preserveInitialPlacement = false,
  ReadingMode mode = ReadingMode.leftToRight,
  ValueChanged<ReadingPosition>? onPosition,
  ValueChanged<ReaderViewportState>? onViewport,
  ValueChanged<ReadingMode>? onMode,
  ValueChanged<bool?>? onDoublePage,
  ResourceImageBuilder imageBuilder = fixtureImage,
  bool? doublePage,
  Widget? chapterControls,
  bool layoutSettingsEnabled = true,
  ReaderFit fit = ReaderFit.contain,
  bool cropBorders = false,
  String generation = 'runtime-1',
  ValueListenable<ReadingPosition?>? positionRequest,
  ReaderBackground background = ReaderBackground.black,
  int dimPercent = 0,
  ReaderInputPreset tapZones = ReaderInputPreset.standard,
  ReaderInputPreset keyboard = ReaderInputPreset.standard,
}) => MaterialApp(
  home: ReaderScreen(
    manifest: manifest,
    provider: provider,
    generation: generation,
    initialPosition: position,
    preserveInitialPlacement: preserveInitialPlacement,
    initialMode: mode,
    doublePage: doublePage,
    chapterControls: chapterControls,
    layoutSettingsEnabled: layoutSettingsEnabled,
    fit: fit,
    cropBorders: cropBorders,
    positionRequest: positionRequest,
    background: background,
    dimPercent: dimPercent,
    tapZones: tapZones,
    keyboard: keyboard,
    onPositionChanged: onPosition,
    onViewportChanged: onViewport,
    onModeChanged: onMode,
    onDoublePageChanged: onDoublePage,
    imageBuilder: imageBuilder,
    imageEvictor: (_) async {},
  ),
);

void expectOriginalImageAnchor(
  WidgetTester tester,
  ReadingPosition anchor,
  Finder viewport, {
  String generation = 'runtime-1',
}) {
  final original = tester.getRect(
    find.byKey(ValueKey('$generation-${anchor.pageKey}')),
  );
  final bounds = tester.getRect(viewport);
  expect(
    original.left + original.width * anchor.normalizedX,
    closeTo(bounds.left + bounds.width * anchor.viewportX, 1),
  );
  expect(
    original.top + original.height * anchor.normalizedOffset,
    closeTo(bounds.top + bounds.height * anchor.viewportY, 1),
  );
}

bool? pageLayoutPreference(WidgetTester tester) => tester
    .widget<SegmentedButton<bool?>>(
      find.byKey(const ValueKey('reader-page-layout')),
    )
    .selected
    .single;

void main() {
  testWidgets(
    'default reader image pipeline trims actual file pixels and preserves original anchors',
    (tester) async {
      final bitmap = img.Image(width: 80, height: 100, numChannels: 4);
      img.fill(bitmap, color: img.ColorRgba8(255, 255, 255, 255));
      img.fillRect(
        bitmap,
        x1: 20,
        y1: 25,
        x2: 59,
        y2: 74,
        color: img.ColorRgba8(20, 40, 80, 255),
      );
      final bytes = img.encodePng(bitmap);
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('karuyomi-reader-crop-'),
      ))!;
      final file = File('${directory.path}/page.png');
      final manifest = ChapterManifest(
        chapterKey: 'actual-crop',
        version: '1',
        pages: [ReaderPage(key: 'page')],
      );
      final provider = FixturePageProvider(
        location: file.uri,
        byteLength: bytes.length,
      );
      final viewports = <ReaderViewportState>[];
      try {
        await tester.runAsync(() => file.writeAsBytes(bytes));
        await tester.pumpWidget(
          screen(
            provider: provider,
            manifest: manifest,
            cropBorders: true,
            imageBuilder: buildResourceImage,
            onViewport: viewports.add,
          ),
        );
        final timeout = Stopwatch()..start();
        while ((viewports.isEmpty || !viewports.last.windowReady) &&
            timeout.elapsed < const Duration(seconds: 5)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(viewports.last.windowReady, true);
        expect(viewports.last.atEnd, true);
        expect(viewports.last.observed!.normalizedOffset, closeTo(.77, .001));
        expect(viewports.last.observed!.normalizedX, closeTo(.775, .001));
        final anchor = viewports.last.current;
        expect(anchor.normalizedOffset, closeTo(.23, .001));
        expect(anchor.normalizedX, closeTo(.225, .001));
        expect(provider.acquired, hasLength(1));
        await tester.pumpWidget(
          screen(
            provider: provider,
            manifest: manifest,
            cropBorders: false,
            imageBuilder: buildResourceImage,
            onViewport: viewports.add,
          ),
        );
        await tester.pumpAndSettle();
        expect(viewports.last.windowReady, true);
        expect(viewports.last.observed!.normalizedOffset, 1);
        expect(viewports.last.observed!.normalizedX, 1);
        expect(
          viewports.last.current.normalizedOffset,
          closeTo(anchor.normalizedOffset, .001),
        );
        expect(
          viewports.last.current.normalizedX,
          closeTo(anchor.normalizedX, .001),
        );
        expect(provider.acquired, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await FileImage(file).evict();
        await tester.runAsync(() => directory.delete(recursive: true));
      }
      expect(provider.released, hasLength(1));
    },
  );

  testWidgets(
    'late crop bounds gate observation, preserve original anchors and finish at content end',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: '1',
        pages: [ReaderPage(key: 'long', width: 600, height: 3600)],
      );
      final viewports = <ReaderViewportState>[];
      BuildContext? imageContext;
      Widget configured(bool crop) => screen(
        provider: provider,
        manifest: manifest,
        cropBorders: crop,
        fit: ReaderFit.width,
        onViewport: viewports.add,
        imageBuilder: (context, resource, fit) {
          imageContext = context;
          ReaderImageDecoded(
            resource.id,
            width: 600,
            height: 3600,
          ).dispatch(context);
          return fixtureImage(context, resource, fit);
        },
      );
      await tester.pumpWidget(configured(true));
      await tester.pumpAndSettle();
      expect(viewports.last.observed, isNull);
      expect(viewports.last.windowReady, false);
      expect(viewports.last.atEnd, false);
      ReaderImageCrop(
        'runtime-1-long',
        bounds: const Rect.fromLTRB(.1, .25, .9, .75),
        width: 600,
        height: 3600,
      ).dispatch(imageContext!);
      await tester.pumpAndSettle();
      expect(viewports.last.observed, isNotNull);
      expect(viewports.last.windowReady, true);
      expect(viewports.last.current.normalizedX, closeTo(.1, .001));
      expect(viewports.last.current.normalizedOffset, closeTo(.25, .001));
      expect(viewports.last.atEnd, false);
      final viewer = find.byType(InteractiveViewer);
      expectOriginalImageAnchor(tester, viewports.last.current, viewer);
      await tester.drag(viewer, const Offset(0, -150));
      await tester.pumpAndSettle();
      expectOriginalImageAnchor(tester, viewports.last.current, viewer);
      final image = tester.getRect(
        find.byKey(const ValueKey('image-rect-long')),
      );
      final bounds = tester.getRect(viewer);
      final controller = tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!;
      final matrix = controller.value.clone();
      matrix.setEntry(1, 3, matrix.entry(1, 3) + bounds.bottom - image.bottom);
      controller.value = matrix;
      await tester.pumpAndSettle();
      expect(viewports.last.atEnd, true);
      expect(viewports.last.observed!.normalizedOffset, closeTo(.75, .001));
      final current = viewports.last.current;
      await tester.pumpWidget(configured(false));
      await tester.pumpAndSettle();
      expect(
        viewports.last.current.normalizedX,
        closeTo(current.normalizedX, .001),
      );
      expect(
        viewports.last.current.normalizedOffset,
        closeTo(current.normalizedOffset, .001),
      );
      expectOriginalImageAnchor(tester, viewports.last.current, viewer);
      expect(viewports.last.atEnd, false);
      expect(provider.acquired.length, 1);
      expect(provider.released, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(provider.released, ['runtime-1-long']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'crop aspect ratio regroups RTL pages without changing original decode dimensions',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: '1',
        pages: [
          for (var index = 0; index < 3; index++)
            ReaderPage(key: 'page-$index', width: 1200, height: 600),
        ],
      );
      final viewports = <ReaderViewportState>[];
      Widget configured(bool crop) => screen(
        provider: provider,
        manifest: manifest,
        cropBorders: crop,
        fit: ReaderFit.height,
        mode: ReadingMode.rightToLeft,
        doublePage: true,
        onViewport: viewports.add,
        imageBuilder: (context, resource, fit) {
          ReaderImageDecoded(
            resource.id,
            width: 1200,
            height: 600,
          ).dispatch(context);
          ReaderImageCrop(
            resource.id,
            bounds: const Rect.fromLTRB(.3, 0, .7, 1),
            width: 1200,
            height: 600,
          ).dispatch(context);
          return fixtureImage(context, resource, fit);
        },
      );
      await tester.pumpWidget(configured(true));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('spread-page-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('image-rect-page-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('image-rect-page-2')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('image-rect-page-1'))).left,
        greaterThan(
          tester.getRect(find.byKey(const ValueKey('image-rect-page-2'))).left,
        ),
      );
      final viewer = find.byType(InteractiveViewer);
      expectOriginalImageAnchor(tester, viewports.last.current, viewer);
      tester.widget<InteractiveViewer>(viewer).transformationController!.value =
          Matrix4.identity();
      await tester.pumpAndSettle();
      expect(viewports.last.atEnd, true);
      expect(viewports.last.observed!.normalizedX, closeTo(.3, .001));
      expect(viewports.last.observed!.pageKey, 'page-2');
      final activeAcquires = provider.acquired
          .where((page) => page.pageKey != 'page-0')
          .length;
      await tester.pumpWidget(configured(false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('spread-page-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('image-rect-page-1')), findsNothing);
      expect(viewports.last.observed, isNotNull);
      // Regrouping changes whether the cover belongs to the adjacent prefetch
      // window; the two displayed resources themselves must not be reacquired.
      expect(
        provider.acquired.where((page) => page.pageKey != 'page-0').length,
        activeAcquires,
      );
      expect(provider.acquired.map((page) => page.pageKey).toSet(), {
        'page-0',
        'page-1',
        'page-2',
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(provider.released.toSet().length, 3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'crop in continuous and zoom keeps original 2D points across live settings and resize',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      var activeProvider = provider;
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: '1',
        pages: [ReaderPage(key: 'page-0')],
      );
      final anchor = manifest.positionAt(
        0,
        offset: .6,
        normalizedX: .7,
        viewportX: .3,
        viewportY: .4,
      );
      final viewports = <ReaderViewportState>[];
      Widget configured(bool crop, ReadingMode mode, ReaderFit fit) => screen(
        provider: activeProvider,
        manifest: manifest,
        position: anchor,
        cropBorders: crop,
        mode: mode,
        fit: fit,
        onViewport: viewports.add,
        imageBuilder: (context, resource, fit) {
          ReaderImageDecoded(
            resource.id,
            width: 900,
            height: 1200,
          ).dispatch(context);
          ReaderImageCrop(
            resource.id,
            bounds: const Rect.fromLTRB(.1, .2, .9, .8),
            width: 900,
            height: 1200,
          ).dispatch(context);
          return fixtureImage(context, resource, fit);
        },
      );
      await tester.pumpWidget(
        configured(true, ReadingMode.continuous, ReaderFit.height),
      );
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('continuous-reader'));
      expect(viewports.last.current.normalizedX, closeTo(.7, .001));
      expect(viewports.last.current.normalizedOffset, closeTo(.6, .001));
      expectOriginalImageAnchor(tester, viewports.last.current, list);
      await tester.pumpWidget(
        configured(true, ReadingMode.webtoon, ReaderFit.width),
      );
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(700, 500);
      await tester.pumpAndSettle();
      expect(viewports.last.current.normalizedX, closeTo(.7, .001));
      expect(viewports.last.current.normalizedOffset, closeTo(.6, .001));
      expectOriginalImageAnchor(tester, viewports.last.current, list);
      await tester.tap(find.byTooltip('放大当前图片'));
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog);
      final original = find.descendant(
        of: dialog,
        matching: find.byKey(const ValueKey('runtime-1-page-0')),
      );
      final croppedWidth = tester.getRect(original).width;
      final acquired = provider.acquired.length;
      await tester.pumpWidget(
        configured(false, ReadingMode.webtoon, ReaderFit.width),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(original).width, lessThan(croppedWidth));
      await tester.pumpWidget(
        configured(true, ReadingMode.webtoon, ReaderFit.width),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(original).width, closeTo(croppedWidth, 1));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(viewports.last.current.normalizedX, closeTo(.7, .001));
      expect(viewports.last.current.normalizedOffset, closeTo(.6, .001));
      expectOriginalImageAnchor(tester, viewports.last.current, list);
      expect(provider.acquired.length, acquired);
      expect(provider.released, isEmpty);
      await tester.tap(find.byTooltip('放大当前图片'));
      await tester.pumpAndSettle();
      final oldImageContext = tester.element(original);
      final replacement = FixturePageProvider();
      activeProvider = replacement;
      await tester.pumpWidget(
        configured(true, ReadingMode.webtoon, ReaderFit.width),
      );
      await tester.pumpAndSettle();
      final contentSize = tester.getSize(
        find.byKey(const ValueKey('image-rect-page-0')),
      );
      ReaderImageCrop(
        'runtime-1-page-0',
        bounds: const Rect.fromLTRB(.2, .3, .8, .7),
        width: 900,
        height: 1200,
      ).dispatch(oldImageContext);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const ValueKey('image-rect-page-0'))),
        contentSize,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(provider.released, ['runtime-1-page-0']);
      expect(replacement.acquired.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(provider.released.length, 1);
      expect(replacement.released, ['runtime-1-page-0']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid, stale-size and old-generation crops never make pending images observable',
    (tester) async {
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: '1',
        pages: [ReaderPage(key: 'page-0', width: 600, height: 900)],
      );
      final viewports = <ReaderViewportState>[];
      BuildContext? imageContext;
      Widget configured(String generation) => screen(
        provider: provider,
        manifest: manifest,
        generation: generation,
        cropBorders: true,
        onViewport: viewports.add,
        imageBuilder: (context, resource, fit) {
          imageContext = context;
          ReaderImageDecoded(
            resource.id,
            width: 600,
            height: 900,
          ).dispatch(context);
          return fixtureImage(context, resource, fit);
        },
      );
      await tester.pumpWidget(configured('runtime-1'));
      await tester.pumpAndSettle();
      for (final bounds in [
        const Rect.fromLTRB(-.1, 0, 1, 1),
        const Rect.fromLTRB(0, 0, 0, 1),
        Rect.fromLTRB(double.nan, 0, 1, 1),
      ]) {
        ReaderImageCrop(
          'runtime-1-page-0',
          bounds: bounds,
          width: 600,
          height: 900,
        ).dispatch(imageContext!);
      }
      ReaderImageCrop(
        'runtime-1-page-0',
        bounds: const Rect.fromLTRB(.1, .1, .9, .9),
        width: 300,
        height: 900,
      ).dispatch(imageContext!);
      await tester.pumpAndSettle();
      expect(viewports.last.observed, isNull);
      expect(viewports.last.windowReady, false);
      ReaderImageCrop(
        'runtime-1-page-0',
        bounds: const Rect.fromLTRB(0, 0, 1, 1),
        width: 600,
        height: 900,
      ).dispatch(imageContext!);
      await tester.pumpAndSettle();
      expect(viewports.last.atEnd, true);
      await tester.pumpWidget(configured('runtime-2'));
      await tester.pumpAndSettle();
      ReaderImageCrop(
        'runtime-1-page-0',
        bounds: const Rect.fromLTRB(.1, .1, .9, .9),
        width: 600,
        height: 900,
      ).dispatch(imageContext!);
      await tester.pumpAndSettle();
      expect(viewports.last.observed, isNull);
      expect(viewports.last.atEnd, false);
      ReaderImageCrop(
        'runtime-2-page-0',
        bounds: const Rect.fromLTRB(0, 0, 1, 1),
        width: 600,
        height: 900,
      ).dispatch(imageContext!);
      await tester.pumpAndSettle();
      expect(viewports.last.windowReady, true);
      expect(viewports.last.atEnd, true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(provider.released.toSet(), {
        'runtime-1-page-0',
        'runtime-2-page-0',
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'width reaches the true long-image end and same-effective layout edits keep observing',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: '1',
        pages: [ReaderPage(key: 'long', width: 600, height: 3600)],
      );
      final viewports = <ReaderViewportState>[];
      await tester.pumpWidget(
        screen(
          provider: provider,
          manifest: manifest,
          fit: ReaderFit.width,
          onViewport: viewports.add,
          imageBuilder: decodedImage(width: 600, height: 3600),
        ),
      );
      await tester.pumpAndSettle();
      expect(viewports.last.observed?.pageKey, 'long');
      expect(viewports.last.atEnd, false);
      await tester.tap(find.text('单页'));
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), false);
      expect(viewports.last.observed, isNotNull);
      expect(viewports.last.atEnd, false);
      final viewer = find.byType(InteractiveViewer);
      await tester.drag(viewer, const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(find.text('1 / 1'), findsOneWidget);
      expect(viewports.last.current.normalizedOffset, greaterThan(0));
      final image = tester.getRect(
        find.byKey(const ValueKey('image-rect-long')),
      );
      final bounds = tester.getRect(viewer);
      final controller = tester
          .widget<InteractiveViewer>(viewer)
          .transformationController!;
      final matrix = controller.value.clone();
      matrix.setEntry(1, 3, matrix.entry(1, 3) + bounds.bottom - image.bottom);
      controller.value = matrix;
      await tester.pumpAndSettle();
      expect(viewports.last.atEnd, true);
      expect(viewports.last.observed!.normalizedOffset, 1);
      expect(provider.acquired.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(provider.released, ['runtime-1-long']);
    },
  );

  testWidgets(
    'height pans wide images and RTL double spreads to the reading end',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final mode in [ReadingMode.leftToRight, ReadingMode.rightToLeft]) {
        final provider = FixturePageProvider();
        final manifest = ChapterManifest(
          chapterKey: 'chapter',
          version: '1',
          pages: [ReaderPage(key: 'wide', width: 2400, height: 600)],
        );
        final viewports = <ReaderViewportState>[];
        await tester.pumpWidget(
          screen(
            provider: provider,
            manifest: manifest,
            mode: mode,
            fit: ReaderFit.height,
            doublePage: false,
            onViewport: viewports.add,
            imageBuilder: decodedImage(width: 2400, height: 600),
          ),
        );
        await tester.pumpAndSettle();
        expect(viewports.last.atEnd, false);
        final viewer = find.byType(InteractiveViewer);
        await tester.drag(
          viewer,
          Offset(mode == ReadingMode.rightToLeft ? 160 : -160, 0),
        );
        await tester.pumpAndSettle();
        expect(find.text('1 / 1'), findsOneWidget);
        final image = tester.getRect(
          find.byKey(const ValueKey('image-rect-wide')),
        );
        final bounds = tester.getRect(viewer);
        final controller = tester
            .widget<InteractiveViewer>(viewer)
            .transformationController!;
        final matrix = controller.value.clone();
        final adjustment = mode == ReadingMode.rightToLeft
            ? bounds.left - image.left
            : bounds.right - image.right;
        matrix.setEntry(0, 3, matrix.entry(0, 3) + adjustment);
        controller.value = matrix;
        await tester.pumpAndSettle();
        expect(viewports.last.atEnd, true);
        expect(
          viewports.last.observed!.normalizedX,
          mode == ReadingMode.rightToLeft ? 0 : 1,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(provider.released, ['runtime-1-wide']);
      }
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: '1',
        pages: [
          for (var i = 0; i < 3; i++)
            ReaderPage(key: 'page-$i', width: 900, height: 1000),
        ],
      );
      final viewports = <ReaderViewportState>[];
      await tester.pumpWidget(
        screen(
          provider: provider,
          manifest: manifest,
          mode: ReadingMode.rightToLeft,
          fit: ReaderFit.height,
          doublePage: true,
          onViewport: viewports.add,
          imageBuilder: decodedImage(width: 900, height: 1000),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(viewports.last.current.pageKey, 'page-1');
      expect(viewports.last.current.normalizedX, 1);
      expect(viewports.last.atEnd, false);
      final viewer = find.byType(InteractiveViewer);
      expect(
        tester.getRect(find.byKey(const ValueKey('image-rect-page-1'))).left,
        greaterThan(
          tester.getRect(find.byKey(const ValueKey('image-rect-page-2'))).left,
        ),
      );
      await tester.drag(viewer, const Offset(140, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('spread-page-1')), findsOneWidget);
      tester.widget<InteractiveViewer>(viewer).transformationController!.value =
          Matrix4.identity();
      await tester.pumpAndSettle();
      expect(viewports.last.atEnd, true);
      expect(viewports.last.observed!.pageKey, 'page-2');
      await tester.tap(find.byTooltip('上一页'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'continuous height is horizontally reachable and contain applies to Webtoon',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: '1',
        pages: [ReaderPage(key: 'wide', width: 2400, height: 600)],
      );
      final viewports = <ReaderViewportState>[];
      Widget configured(ReadingMode mode, ReaderFit fit) => screen(
        provider: provider,
        manifest: manifest,
        mode: mode,
        fit: fit,
        onViewport: viewports.add,
        imageBuilder: decodedImage(width: 2400, height: 600),
      );
      await tester.pumpWidget(
        configured(ReadingMode.continuous, ReaderFit.height),
      );
      await tester.pumpAndSettle();
      expect(viewports.last.atEnd, false);
      final horizontal = find.byKey(const ValueKey('horizontal-wide'));
      await tester.drag(horizontal, const Offset(-160, 0));
      await tester.pumpAndSettle();
      final anchor = viewports.last.current;
      expect(anchor.normalizedX, greaterThan(0));
      final scroll = tester
          .widget<SingleChildScrollView>(horizontal)
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(viewports.last.atEnd, true);
      final last = viewports.last.current;
      await tester.pumpWidget(
        configured(ReadingMode.webtoon, ReaderFit.height),
      );
      await tester.pumpAndSettle();
      expect(
        viewports.last.current.normalizedX,
        closeTo(last.normalizedX, .001),
      );
      await tester.pumpWidget(
        configured(ReadingMode.webtoon, ReaderFit.contain),
      );
      await tester.pumpAndSettle();
      final image = tester.getSize(
        find.byKey(const ValueKey('image-rect-wide')),
      );
      final viewport = tester.getSize(
        find.byKey(const ValueKey('continuous-reader')),
      );
      expect(image.width, lessThanOrEqualTo(viewport.width));
      expect(image.height, lessThanOrEqualTo(viewport.height));
      expect(viewports.last.atEnd, true);
      expect(provider.acquired.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(provider.released, ['runtime-1-wide']);
    },
  );

  testWidgets(
    'a late matching decoded frame confirms the actual 2D viewport only once',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: '1',
        pages: [ReaderPage(key: 'page-0', width: 600, height: 900)],
      );
      final requested = manifest.positionAt(
        0,
        offset: .65,
        normalizedX: .7,
        viewportX: .1,
        viewportY: .05,
      );
      final viewports = <ReaderViewportState>[];
      final positions = <ReadingPosition>[];
      Widget configured({required bool decode}) => screen(
        provider: provider,
        manifest: manifest,
        position: requested,
        onViewport: viewports.add,
        onPosition: positions.add,
        imageBuilder: decode ? decodedImage() : fixtureImage,
      );
      await tester.pumpWidget(configured(decode: false));
      await tester.pumpAndSettle();
      expect(viewports.last.observed, isNull);
      expect(viewports.last.current.viewportX, .1);
      expect(viewports.last.current.viewportY, .05);
      await tester.pumpWidget(configured(decode: true));
      await tester.pumpAndSettle();
      expect(viewports.last.observed, isNotNull);
      expect(viewports.last.current.normalizedX, .7);
      expect(viewports.last.current.normalizedOffset, .65);
      expectRenderedAnchor(
        tester,
        viewports.last.current,
        find.byType(InteractiveViewer),
      );
      final count = positions.length;
      await tester.pumpWidget(configured(decode: true));
      await tester.pumpAndSettle();
      expect(positions.length, count);
      expect(tester.binding.hasScheduledFrame, false);
      expect(provider.acquired.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'chapter controls reflow retains the preferred image anchor through restore',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: '1',
        pages: [ReaderPage(key: 'page')],
      );
      final viewports = <ReaderViewportState>[];
      Widget configured(double controlsHeight) => screen(
        provider: provider,
        manifest: manifest,
        chapterControls: SizedBox(height: controlsHeight),
        imageBuilder: decodedImage(width: 400, height: 200),
        onViewport: viewports.add,
      );
      final viewport = find.byType(InteractiveViewer);
      await tester.pumpWidget(configured(40));
      await tester.pumpAndSettle();
      final initial = viewports.last.current;
      final initialBounds = tester.getRect(viewport);
      expectRenderedAnchor(tester, initial, viewport);
      for (final height in [160.0, 40.0, 100.0]) {
        await tester.pumpWidget(configured(height));
        await tester.pumpAndSettle();
        final current = viewports.last.current;
        expect(current.pageKey, initial.pageKey);
        expect(current.normalizedX, initial.normalizedX);
        expect(current.normalizedOffset, initial.normalizedOffset);
        expect(current.viewportX, initial.viewportX);
        expect(current.viewportY, initial.viewportY);
      }
      expect(tester.getRect(viewport).height, lessThan(initialBounds.height));
      expect(viewports.last.observed, isNotNull);
      tester.view.physicalSize = const Size(700, 500);
      await tester.pumpAndSettle();
      expectRenderedAnchor(tester, viewports.last.current, viewport);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'replacing position commands detaches the old input without resetting the chapter',
    (tester) async {
      final provider = FixturePageProvider();
      final manifest = fixtureChapter();
      final oldCommands = ValueNotifier<ReadingPosition?>(null);
      final commands = ValueNotifier<ReadingPosition?>(null);
      addTearDown(oldCommands.dispose);
      addTearDown(commands.dispose);
      final positions = <ReadingPosition>[];
      Widget configured(ValueListenable<ReadingPosition?> input) => screen(
        provider: provider,
        manifest: manifest,
        positionRequest: input,
        onPosition: positions.add,
        doublePage: false,
      );

      await tester.pumpWidget(configured(oldCommands));
      await tester.pumpAndSettle();
      oldCommands.value = manifest.positionAt(3);
      await tester.pumpAndSettle();
      expect(positions.last.pageKey, 'page-3');

      await tester.pumpWidget(configured(commands));
      await tester.pumpAndSettle();
      expect(positions.last.pageKey, 'page-3');
      oldCommands.value = manifest.positionAt(8);
      await tester.pumpAndSettle();
      expect(positions.last.pageKey, 'page-3');
      commands.value = manifest.positionAt(5);
      await tester.pumpAndSettle();
      expect(positions.last.pageKey, 'page-5');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      commands.value = manifest.positionAt(9);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late decode and removing controls preserve placement until an explicit jump',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: '1',
        pages: [ReaderPage(key: 'page')],
      );
      final saved = manifest.positionAt(
        0,
        offset: .1,
        normalizedX: .5,
        viewportX: .5,
        viewportY: .2,
      );
      final requests = ValueNotifier<ReadingPosition?>(null);
      addTearDown(requests.dispose);
      final viewports = <ReaderViewportState>[];
      Widget restored(ResourceImageBuilder builder, {double controls = 48}) =>
          screen(
            provider: provider,
            manifest: manifest,
            position: saved,
            preserveInitialPlacement: true,
            positionRequest: requests,
            onViewport: viewports.add,
            imageBuilder: builder,
            chapterControls: SizedBox(height: controls),
          );

      await tester.pumpWidget(restored(fixtureImage));
      await tester.pumpAndSettle();
      expect(viewports.last.observed, isNull);
      await tester.pumpWidget(restored(decodedImage(width: 400, height: 200)));
      await tester.pumpAndSettle();
      expect(viewports.last.observed?.normalizedOffset, 1);
      expect(viewports.last.current.normalizedOffset, saved.normalizedOffset);
      expect(viewports.last.current.viewportY, saved.viewportY);

      final viewport = find.byType(InteractiveViewer);
      final bounds = tester.getRect(viewport);
      final image = tester.getRect(
        find.byKey(const ValueKey('image-rect-page')),
      );
      final renderedY =
          (image.top + image.height * saved.normalizedOffset - bounds.top) /
          bounds.height;
      expect(renderedY, inExclusiveRange(0, 1));
      expect((renderedY - saved.viewportY).abs(), greaterThan(.01));

      await tester.pumpWidget(
        restored(decodedImage(width: 400, height: 200), controls: 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(viewport).height, greaterThan(bounds.height));
      expect(viewports.last.current.normalizedOffset, saved.normalizedOffset);
      expect(viewports.last.current.viewportY, saved.viewportY);

      requests.value = manifest.positionAt(
        0,
        offset: .8,
        normalizedX: .5,
        viewportX: .5,
        viewportY: .2,
      );
      await tester.pumpAndSettle();
      final moved = viewports.last.current;
      expect(moved.normalizedOffset, closeTo(.8, .001));
      expectRenderedAnchor(tester, moved, viewport);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a backward page turn keeps its placement while the destination decodes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: '1',
        pages: [
          ReaderPage(key: 'portrait'),
          ReaderPage(key: 'landscape'),
        ],
      );
      final viewports = <ReaderViewportState>[];
      Widget configured({required bool decodeDestination}) => screen(
        provider: provider,
        manifest: manifest,
        position: manifest.positionAt(1),
        preserveInitialPlacement: true,
        onViewport: viewports.add,
        imageBuilder: (context, resource, fit) {
          if (resource.id.endsWith('landscape')) {
            return decodedImage(width: 1600, height: 600)(
              context,
              resource,
              fit,
            );
          }
          return decodeDestination
              ? decodedImage(width: 600, height: 1800)(context, resource, fit)
              : fixtureImage(context, resource, fit);
        },
      );
      await tester.pumpWidget(configured(decodeDestination: false));
      await tester.pumpAndSettle();
      expect(viewports.last.observed?.pageKey, 'landscape');
      await tester.tap(find.byTooltip('上一页'));
      await tester.pumpAndSettle();
      final navigation = viewports.last.current;
      expect(navigation.pageKey, 'portrait');
      expect(viewports.last.observed, isNull);

      await tester.pumpWidget(configured(decodeDestination: true));
      await tester.pumpAndSettle();
      expect(viewports.last.observed?.pageKey, 'portrait');
      expect(viewports.last.current.normalizedX, navigation.normalizedX);
      expect(
        viewports.last.current.normalizedOffset,
        navigation.normalizedOffset,
      );
      expect(viewports.last.current.viewportX, navigation.viewportX);
      expect(viewports.last.current.viewportY, navigation.viewportY);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    '2D request survives unknown dimensions, fit, layout, resize, zoom and reopening',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: '1',
        pages: [ReaderPage(key: 'wide')],
      );
      final requested = manifest.positionAt(
        0,
        offset: .4,
        normalizedX: .7,
        viewportX: .25,
        viewportY: .3,
      );
      final requests = ValueNotifier<ReadingPosition?>(requested);
      addTearDown(requests.dispose);
      final viewports = <ReaderViewportState>[];
      final positions = <ReadingPosition>[];
      var decode = false;
      Widget configured(
        ReadingMode mode,
        ReaderFit fit, {
        ReadingPosition? initial,
      }) => screen(
        provider: provider,
        manifest: manifest,
        mode: mode,
        fit: fit,
        position: initial ?? requested,
        positionRequest: requests,
        onViewport: viewports.add,
        onPosition: positions.add,
        imageBuilder: decode
            ? decodedImage(width: 2400, height: 600)
            : fixtureImage,
      );
      await tester.pumpWidget(
        configured(ReadingMode.leftToRight, ReaderFit.height),
      );
      await tester.pumpAndSettle();
      expect(viewports.last.observed, isNull);
      expect(viewports.last.current.viewportX, .25);
      expect(viewports.last.current.viewportY, .3);
      decode = true;
      await tester.pumpWidget(
        configured(ReadingMode.leftToRight, ReaderFit.height),
      );
      await tester.pumpAndSettle();
      void expectOriginalPoint(Finder viewport) {
        final current = viewports.last.current;
        expect(current.normalizedX, closeTo(.7, .001));
        expect(current.normalizedOffset, closeTo(.4, .001));
        expectRenderedAnchor(tester, current, viewport);
      }

      expectOriginalPoint(find.byType(InteractiveViewer));
      await tester.pumpWidget(
        configured(ReadingMode.leftToRight, ReaderFit.contain),
      );
      await tester.pumpAndSettle();
      expectOriginalPoint(find.byType(InteractiveViewer));
      await tester.pumpWidget(
        configured(ReadingMode.continuous, ReaderFit.height),
      );
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('continuous-reader'));
      expectOriginalPoint(list);
      tester.view.physicalSize = const Size(700, 500);
      await tester.pumpAndSettle();
      expectOriginalPoint(list);
      final saved = viewports.last.current;
      await tester.tap(find.byTooltip('放大当前图片'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        configured(ReadingMode.continuous, ReaderFit.width),
      );
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog);
      final dialogViewport = find.descendant(
        of: dialog,
        matching: find.byType(InteractiveViewer),
      );
      final dialogImage = find.descendant(
        of: dialog,
        matching: find.byKey(const ValueKey('runtime-1-wide')),
      );
      expect(
        tester.getRect(dialogImage).width,
        closeTo(tester.getRect(dialogViewport).width, 1),
      );
      await tester.pumpWidget(
        configured(ReadingMode.continuous, ReaderFit.height),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(dialogImage).height,
        closeTo(tester.getRect(dialogViewport).height, 1),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(viewports.last.observed, isNotNull);
      final count = positions.length;
      await tester.pump(const Duration(seconds: 1));
      expect(positions.length, count);
      expect(provider.acquired.length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        configured(ReadingMode.continuous, ReaderFit.height, initial: saved),
      );
      await tester.pumpAndSettle();
      expectOriginalPoint(find.byKey(const ValueKey('continuous-reader')));
      requests.value = manifest.positionAt(
        0,
        offset: .2,
        normalizedX: .3,
        viewportX: .1,
        viewportY: .2,
      );
      await tester.pumpAndSettle();
      expect(viewports.last.current.normalizedX, closeTo(.3, .001));
      expect(viewports.last.current.normalizedOffset, closeTo(.2, .001));
      expectRenderedAnchor(
        tester,
        viewports.last.current,
        find.byKey(const ValueKey('continuous-reader')),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'tap presets respect reading direction while disabled keeps toolbar and swipes usable',
    (tester) async {
      final provider = FixturePageProvider();
      final manifest = fixtureChapter();
      Widget configured(ReadingMode mode, ReaderInputPreset tapZones) => screen(
        provider: provider,
        manifest: manifest,
        position: manifest.positionAt(5),
        mode: mode,
        doublePage: false,
        tapZones: tapZones,
        dimPercent: 80,
      );
      Future<void> tapFraction(double fraction) async {
        final rect = tester.getRect(find.byType(InteractiveViewer));
        await tester.tapAt(
          Offset(rect.left + rect.width * fraction, rect.center.dy),
        );
        await tester.pump(kDoubleTapTimeout);
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        configured(ReadingMode.leftToRight, ReaderInputPreset.standard),
      );
      await tester.pumpAndSettle();
      expect(find.text('6 / 20'), findsOneWidget);
      await tapFraction(.9);
      expect(find.text('7 / 20'), findsOneWidget);
      await tester.pumpWidget(
        configured(ReadingMode.leftToRight, ReaderInputPreset.reversed),
      );
      await tester.pumpAndSettle();
      await tapFraction(.9);
      expect(find.text('6 / 20'), findsOneWidget);
      await tester.pumpWidget(
        configured(ReadingMode.rightToLeft, ReaderInputPreset.standard),
      );
      await tester.pumpAndSettle();
      await tapFraction(.1);
      expect(find.text('7 / 20'), findsOneWidget);
      await tester.pumpWidget(
        configured(ReadingMode.rightToLeft, ReaderInputPreset.reversed),
      );
      await tester.pumpAndSettle();
      await tapFraction(.1);
      expect(find.text('6 / 20'), findsOneWidget);
      await tester.pumpWidget(
        configured(ReadingMode.rightToLeft, ReaderInputPreset.disabled),
      );
      await tester.pumpAndSettle();
      await tapFraction(.1);
      await tapFraction(.9);
      expect(find.text('6 / 20'), findsOneWidget);
      await tapFraction(.5);
      expect(find.byType(AppBar), findsNothing);
      await tapFraction(.5);
      expect(find.byType(AppBar), findsOneWidget);
      await tester.drag(find.byType(InteractiveViewer), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(find.text('7 / 20'), findsOneWidget);
      await tester.tap(find.byTooltip('上一页'));
      await tester.pumpAndSettle();
      expect(find.text('6 / 20'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'keyboard presets reverse relative keys, retain absolute keys and consume disabled navigation',
    (tester) async {
      final provider = FixturePageProvider();
      final manifest = fixtureChapter();
      Widget configured(ReadingMode mode, ReaderInputPreset keyboard) => screen(
        provider: provider,
        manifest: manifest,
        position: manifest.positionAt(5),
        mode: mode,
        doublePage: false,
        keyboard: keyboard,
      );
      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(
        configured(ReadingMode.leftToRight, ReaderInputPreset.standard),
      );
      await tester.pumpAndSettle();
      await press(LogicalKeyboardKey.arrowRight);
      expect(find.text('7 / 20'), findsOneWidget);
      await tester.pumpWidget(
        configured(ReadingMode.leftToRight, ReaderInputPreset.reversed),
      );
      await tester.pumpAndSettle();
      await press(LogicalKeyboardKey.arrowRight);
      expect(find.text('6 / 20'), findsOneWidget);
      await press(LogicalKeyboardKey.pageDown);
      expect(find.text('5 / 20'), findsOneWidget);
      await press(LogicalKeyboardKey.pageUp);
      expect(find.text('6 / 20'), findsOneWidget);
      await press(LogicalKeyboardKey.space);
      expect(find.text('5 / 20'), findsOneWidget);
      await tester.pumpWidget(
        configured(ReadingMode.rightToLeft, ReaderInputPreset.reversed),
      );
      await tester.pumpAndSettle();
      await press(LogicalKeyboardKey.arrowRight);
      expect(find.text('6 / 20'), findsOneWidget);
      await press(LogicalKeyboardKey.arrowLeft);
      expect(find.text('5 / 20'), findsOneWidget);
      await press(LogicalKeyboardKey.home);
      expect(find.text('1 / 20'), findsOneWidget);
      await press(LogicalKeyboardKey.end);
      expect(find.text('20 / 20'), findsOneWidget);
      await tester.pumpWidget(
        configured(ReadingMode.rightToLeft, ReaderInputPreset.disabled),
      );
      await tester.pumpAndSettle();
      for (final key in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.home,
        LogicalKeyboardKey.end,
      ]) {
        await press(key);
      }
      expect(find.text('20 / 20'), findsOneWidget);
      await tester.tap(find.byTooltip('上一页'));
      await tester.pumpAndSettle();
      expect(find.text('19 / 20'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'content appearance updates preserve anchor and resource residency without fabricating observation',
    (tester) async {
      final provider = FixturePageProvider();
      final manifest = fixtureChapter();
      final viewports = <ReaderViewportState>[];
      Color? textColor;
      Widget configured(ReaderBackground background, int dimPercent) => screen(
        provider: provider,
        manifest: manifest,
        position: manifest.positionAt(5, offset: .35),
        doublePage: false,
        background: background,
        dimPercent: dimPercent,
        onViewport: viewports.add,
        imageBuilder: (context, resource, fit) {
          textColor = DefaultTextStyle.of(context).style.color;
          return fixtureImage(context, resource, fit);
        },
      );
      await tester.pumpWidget(configured(ReaderBackground.black, 0));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.black,
      );
      expect(textColor, Colors.white);
      final acquired = provider.acquired.map((page) => page.pageKey).toList();
      final released = provider.released.toList();
      final anchor = viewports.last.current;
      expect(viewports.last.observed, isNull);
      await tester.pumpWidget(configured(ReaderBackground.white, 80));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Colors.white,
      );
      expect(textColor, Colors.black);
      final dimmer = find.byKey(const ValueKey('reader-content-dimming'));
      expect(tester.widget<ColoredBox>(dimmer).color.a, closeTo(.8, .001));
      expect(
        tester.getRect(dimmer),
        tester.getRect(find.byType(InteractiveViewer)),
      );
      expect(
        tester.getRect(dimmer).overlaps(tester.getRect(find.byTooltip('下一页'))),
        false,
      );
      expect(viewports.last.current.pageKey, anchor.pageKey);
      expect(
        viewports.last.current.normalizedOffset,
        closeTo(anchor.normalizedOffset, .001),
      );
      expect(viewports.last.observed, isNull);
      expect(viewports.last.atEnd, false);
      expect(provider.acquired.map((page) => page.pageKey), acquired);
      expect(provider.released, released);
      await tester.pumpWidget(configured(ReaderBackground.theme, 0));
      await tester.pumpAndSettle();
      final readerContext = tester.element(find.byType(ReaderScreen));
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Theme.of(readerContext).scaffoldBackgroundColor,
      );
      expect(textColor, Theme.of(readerContext).colorScheme.onSurface);
      expect(dimmer, findsNothing);
      expect(provider.acquired.map((page) => page.pageKey), acquired);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'continuous zoom follows live content appearance while controls and scrolling remain usable',
    (tester) async {
      final provider = FixturePageProvider();
      final manifest = fixtureChapter();
      final positions = <ReadingPosition>[];
      Widget configured(ReaderBackground background, int dimPercent) => screen(
        provider: provider,
        manifest: manifest,
        position: manifest.positionAt(4, offset: .3),
        mode: ReadingMode.continuous,
        imageBuilder: decodedImage(),
        background: background,
        dimPercent: dimPercent,
        keyboard: ReaderInputPreset.disabled,
        onPosition: positions.add,
      );
      await tester.pumpWidget(configured(ReaderBackground.black, 20));
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('continuous-reader'));
      await tester.drag(list, const Offset(0, -150));
      await tester.pumpAndSettle();
      final anchor = positions.last;
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)).first,
      );
      final scrollOffset = scrollable.position.pixels;
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, scrollOffset);
      await tester.tap(find.byTooltip('放大当前图片'));
      await tester.pumpAndSettle();
      expect(find.text('查看图片'), findsOneWidget);
      final acquired = provider.acquired.map((page) => page.pageKey).toList();
      final released = provider.released.toList();
      await tester.pumpWidget(configured(ReaderBackground.white, 80));
      await tester.pumpAndSettle();
      final dialog = find.byType(Dialog);
      expect(
        tester
            .widget<Scaffold>(
              find.descendant(of: dialog, matching: find.byType(Scaffold)),
            )
            .backgroundColor,
        Colors.white,
      );
      final dimmer = find.descendant(
        of: dialog,
        matching: find.byKey(const ValueKey('reader-content-dimming')),
      );
      expect(tester.widget<ColoredBox>(dimmer).color.a, closeTo(.8, .001));
      expect(
        tester.getRect(dimmer).overlaps(tester.getRect(find.byTooltip('放大'))),
        false,
      );
      await tester.tap(find.byTooltip('放大'));
      await tester.pumpAndSettle();
      final zoom = tester.widget<InteractiveViewer>(
        find.descendant(of: dialog, matching: find.byType(InteractiveViewer)),
      );
      expect(zoom.transformationController!.value.getMaxScaleOnAxis(), 2);
      expect(provider.acquired.map((page) => page.pageKey), acquired);
      expect(provider.released, released);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(positions.last.pageKey, anchor.pageKey);
      expect(
        positions.last.normalizedOffset,
        closeTo(anchor.normalizedOffset, .001),
      );
      await tester.drag(list, const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(scrollOffset));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(provider.released.length, provider.released.toSet().length);
      expect(
        provider.released.toSet(),
        provider.acquired.map((page) => 'runtime-1-${page.pageKey}').toSet(),
      );
    },
  );

  testWidgets(
    'baseline keeps visible pages distinct from prefetch and fences late reader exit',
    (tester) async {
      final baseline = ReaderBaselineRecorder(
        flushDuration: const Duration(milliseconds: 10),
      )..start();
      addTearDown(baseline.dispose);
      final provider = FixturePageProvider();
      final closeGate = Completer<void>();
      Future<void>? closing;
      await tester.pumpWidget(
        ReaderBaselineScope(
          recorder: baseline,
          child: MaterialApp(
            home: ReaderScreen(
              manifest: fixtureChapter(),
              provider: provider,
              generation: 'runtime-1',
              doublePage: false,
              imageBuilder: fixtureImage,
              imageEvictor: (_) async {},
              onClosed: () => closeGate.future,
              onClosing: (value) => closing = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        provider.acquired.map((e) => e.pageKey),
        containsAll(['page-0', 'page-1']),
      );
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final stopped = baseline.stop();
      await tester.pump(const Duration(milliseconds: 10));
      await stopped;
      final captured = (baseline.export()['events'] as List)
          .cast<Map<String, Object?>>();
      final viewports = captured
          .where((e) => e['type'] == 'viewport')
          .map((e) => e['data'] as Map<String, Object?>)
          .toList();
      expect(viewports, isNotEmpty);
      final first = viewports.first;
      expect((first['visible'] as List).map((e) => e['pageKey']), ['page-0']);
      expect(
        (first['visible'] as List).every((e) => e['decoded'] == false),
        true,
      );
      final afterAdvance = viewports.last;
      expect(afterAdvance['currentPageKey'], 'page-1');
      expect(afterAdvance['navigationEpoch'], 1);
      expect(afterAdvance['manifestVersion'], '1');
      expect(
        (afterAdvance['visible'] as List).single['resourceId'],
        'runtime-1-page-1',
      );
      final navigation =
          captured.singleWhere((e) => e['type'] == 'navigation')['data']
              as Map<String, Object?>;
      expect(navigation['targetPageKey'], 'page-1');
      expect(captured.map((e) => e['type']), contains('reader_exit_requested'));
      expect(
        captured.map((e) => e['type']),
        isNot(contains('reader_exit_ack')),
      );
      baseline.start();
      closeGate.complete();
      expect(closing, isNotNull);
      await closing!;
      final next = baseline.stop();
      await tester.pump(const Duration(milliseconds: 10));
      await next;
      expect(
        (baseline.export()['events'] as List).map((e) => e['type']),
        isNot(contains('reader_exit_ack')),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual single-page preference survives progress panel and viewport changes',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: '1',
        pages: List.generate(
          51,
          (index) => ReaderPage(key: 'page-$index', width: 600, height: 900),
        ),
      );
      final panelHeight = ValueNotifier(0.0);
      addTearDown(panelHeight.dispose);
      await tester.pumpWidget(
        ValueListenableBuilder<double>(
          valueListenable: panelHeight,
          builder: (context, height, child) => screen(
            provider: provider,
            manifest: manifest,
            position: manifest.positionAt(50),
            chapterControls: SizedBox(height: height),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), isNull);
      await tester.tap(find.text('单页'));
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), false);
      expect(find.text('51 / 51'), findsOneWidget);
      expect(find.byKey(const ValueKey('runtime-1-page-49')), findsNothing);

      // Completion/save controls may gain a row without changing page width.
      panelHeight.value = 72;
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), false);
      expect(find.byKey(const ValueKey('runtime-1-page-49')), findsNothing);

      await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('reader-page-layout')), findsNothing);
      await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), false);

      tester.view.physicalSize = const Size(800, 760);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1200, 760);
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), false);
      expect(find.text('51 / 51'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'automatic, single and double page selections preserve their policy',
    (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = fixtureChapter();
      final selections = <bool?>[];
      await tester.pumpWidget(
        screen(
          provider: provider,
          manifest: manifest,
          position: manifest.positionAt(1),
          onDoublePage: selections.add,
        ),
      );
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), isNull);
      expect(find.byKey(const ValueKey('runtime-1-page-2')), findsNothing);
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), isNull);
      expect(find.byKey(const ValueKey('runtime-1-page-2')), findsOneWidget);
      expect(selections, isEmpty);
      await tester.tap(find.text('单页'));
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), false);
      expect(find.byKey(const ValueKey('runtime-1-page-2')), findsNothing);
      tester.view.physicalSize = const Size(800, 900);
      await tester.pumpAndSettle();
      await tester.tap(find.text('双页'));
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), true);
      expect(find.byKey(const ValueKey('runtime-1-page-2')), findsOneWidget);
      await tester.tap(find.text('自动'));
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), isNull);
      expect(find.byKey(const ValueKey('runtime-1-page-2')), findsNothing);
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('runtime-1-page-2')), findsOneWidget);
      expect(selections, [false, true, null]);
      expect(find.text('2 / 20'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'changed doublePage input resets manual choice and null resumes automatic',
    (tester) async {
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = fixtureChapter();
      await tester.pumpWidget(
        screen(provider: provider, manifest: manifest, doublePage: true),
      );
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), true);
      await tester.tap(find.text('单页'));
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), false);
      // Rebuilding an unchanged parent input must preserve the local choice.
      await tester.pumpWidget(
        screen(provider: provider, manifest: manifest, doublePage: true),
      );
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), false);
      await tester.pumpWidget(
        screen(provider: provider, manifest: manifest, doublePage: false),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        screen(provider: provider, manifest: manifest, doublePage: true),
      );
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), true);
      await tester.tap(find.text('单页'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(screen(provider: provider, manifest: manifest));
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), isNull);
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), isNull);
      await tester.pumpWidget(
        screen(provider: provider, manifest: manifest, doublePage: false),
      );
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), false);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('manual layout persists for a chapter and resets for the next', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = FixturePageProvider();
    final manifest = fixtureChapter();
    await tester.pumpWidget(screen(provider: provider, manifest: manifest));
    await tester.pumpAndSettle();
    await tester.tap(find.text('单页'));
    await tester.pumpAndSettle();
    expect(pageLayoutPreference(tester), false);
    await tester.pumpWidget(
      screen(
        provider: provider,
        manifest: ChapterManifest(
          chapterKey: manifest.chapterKey,
          version: '2',
          pages: manifest.pages,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(pageLayoutPreference(tester), false);
    await tester.pumpWidget(
      screen(
        provider: provider,
        manifest: ChapterManifest(
          chapterKey: 'next-chapter',
          version: '1',
          pages: List.generate(
            20,
            (index) =>
                ReaderPage(key: 'next-page-$index', width: 600, height: 900),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(pageLayoutPreference(tester), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'asynchronous parent layout applies at the same logical anchor without save callbacks',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = fixtureChapter();
      final modes = <ReadingMode>[];
      final pagePolicies = <bool?>[];
      final viewports = <ReaderViewportState>[];
      Widget configured(ReadingMode mode, bool? doublePage) => screen(
        provider: provider,
        manifest: manifest,
        position: manifest.positionAt(5, offset: .35),
        mode: mode,
        doublePage: doublePage,
        onMode: modes.add,
        onDoublePage: pagePolicies.add,
        onViewport: viewports.add,
      );
      await tester.pumpWidget(configured(ReadingMode.leftToRight, false));
      await tester.pumpAndSettle();
      final leaf = tester.state(find.byType(ReaderScreen));
      await tester.pumpWidget(configured(ReadingMode.continuous, true));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ReaderScreen)), same(leaf));
      expect(find.byKey(const ValueKey('continuous-reader')), findsOneWidget);
      expect(viewports.last.current.pageKey, 'page-5');
      expect(viewports.last.current.normalizedOffset, closeTo(.35, .001));
      expect(viewports.last.doublePage, true);
      await tester.pumpWidget(configured(ReadingMode.webtoon, null));
      await tester.pumpAndSettle();
      expect(viewports.last.mode, ReadingMode.webtoon);
      expect(viewports.last.current.pageKey, 'page-5');
      expect(viewports.last.current.normalizedOffset, closeTo(.35, .001));
      expect(viewports.last.doublePage, isNull);
      expect(modes, isEmpty);
      expect(pagePolicies, isEmpty);
      await tester.tap(find.byType(DropdownButton<ReadingMode>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从右到左').last);
      await tester.pumpAndSettle();
      expect(modes, [ReadingMode.rightToLeft]);
      expect(viewports.last.current.pageKey, 'page-5');
      expect(viewports.last.current.normalizedOffset, closeTo(.35, .001));
      // A parent rebuild with its unchanged value cannot roll back a selection
      // while the asynchronous settings acknowledgement is outstanding.
      await tester.pumpWidget(configured(ReadingMode.webtoon, null));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<ReadingMode>>(
              find.byType(DropdownButton<ReadingMode>),
            )
            .value,
        ReadingMode.rightToLeft,
      );
      await tester.pumpWidget(configured(ReadingMode.rightToLeft, true));
      await tester.pumpAndSettle();
      expect(pageLayoutPreference(tester), true);
      expect(modes, [ReadingMode.rightToLeft]);
      expect(pagePolicies, isEmpty);
      tester.view.physicalSize = const Size(600, 900);
      await tester.pumpAndSettle();
      expect(modes, [ReadingMode.rightToLeft]);
      expect(pagePolicies, isEmpty);
      expect(viewports.last.current.pageKey, 'page-5');
      expect(viewports.last.current.normalizedOffset, closeTo(.35, .001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'pending settings disable layout edits while page navigation remains available',
    (tester) async {
      final provider = FixturePageProvider();
      final manifest = fixtureChapter();
      final modes = <ReadingMode>[];
      final pagePolicies = <bool?>[];
      await tester.pumpWidget(
        screen(
          provider: provider,
          manifest: manifest,
          doublePage: false,
          layoutSettingsEnabled: false,
          onMode: modes.add,
          onDoublePage: pagePolicies.add,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<ReadingMode>>(
              find.byType(DropdownButton<ReadingMode>),
            )
            .onChanged,
        isNull,
      );
      expect(
        tester
            .widget<SegmentedButton<bool?>>(
              find.byKey(const ValueKey('reader-page-layout')),
            )
            .onSelectionChanged,
        isNull,
      );
      await tester.tap(find.byTooltip('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 20'), findsOneWidget);
      await tester.pumpWidget(
        screen(
          provider: provider,
          manifest: manifest,
          mode: ReadingMode.continuous,
          doublePage: true,
          layoutSettingsEnabled: false,
          onMode: modes.add,
          onDoublePage: pagePolicies.add,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('continuous-reader')), findsOneWidget);
      expect(find.text('2 / 20'), findsOneWidget);
      expect(modes, isEmpty);
      expect(pagePolicies, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'decoded notification after a frame schedules its viewport observation',
    (tester) async {
      final provider = FixturePageProvider();
      final manifest = fixtureChapter();
      final viewports = <ReaderViewportState>[];
      BuildContext? imageContext;
      await tester.pumpWidget(
        screen(
          provider: provider,
          manifest: manifest,
          onViewport: viewports.add,
          imageBuilder: (context, resource, fit) {
            if (resource.id == 'runtime-1-page-0') imageContext = context;
            return fixtureImage(context, resource, fit);
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(imageContext, isNotNull);
      expect(viewports.last.observed, isNull);
      expect(tester.binding.hasScheduledFrame, false);

      tester.binding.addPostFrameCallback((_) {
        ReaderImageDecoded(
          'runtime-1-page-0',
          width: 600,
          height: 900,
        ).dispatch(imageContext!);
      });
      tester.binding.ensureVisualUpdate();
      await tester.pump();

      // pumpAndSettle would force the missing viewport frame and hide the bug.
      expect(tester.binding.hasScheduledFrame, true);
      await tester.pump();
      expect(viewports.last.observed?.pageKey, 'page-0');
      expect(tester.binding.hasScheduledFrame, false);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'decoder error clears observed progress and rejects a queued late frame',
    (tester) async {
      final provider = FixturePageProvider();
      final viewports = <ReaderViewportState>[];
      BuildContext? imageContext;
      await tester.pumpWidget(
        screen(
          provider: provider,
          manifest: fixtureChapter(),
          onViewport: viewports.add,
          imageBuilder: (context, resource, fit) {
            if (resource.id == 'runtime-1-page-0') imageContext = context;
            return fixtureImage(context, resource, fit);
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(viewports.last.observed, isNull);
      ReaderImageDecoded(
        'runtime-1-page-0',
        width: 600,
        height: 900,
      ).dispatch(imageContext!);
      await tester.pumpAndSettle();
      expect(viewports.last.observed?.pageKey, 'page-0');
      ReaderImageFailed(
        'runtime-1-page-0',
        StateError('failed frame'),
      ).dispatch(imageContext!);
      ReaderImageDecoded(
        'runtime-1-page-0',
        width: 600,
        height: 900,
      ).dispatch(imageContext!);
      await tester.pumpAndSettle();
      expect(viewports.last.observed, isNull);
      expect(viewports.last.windowReady, false);
      expect(viewports.last.atEnd, false);
      expect(find.text('图片未能加载'), findsOneWidget);
      expect(provider.released, contains('runtime-1-page-0'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'zoom observes decoded intersections without completing a clipped final spread',
    (tester) async {
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: 'v1',
        pages: List.generate(
          21,
          (index) => ReaderPage(key: 'page-$index', width: 600, height: 900),
        ),
      );
      final viewports = <ReaderViewportState>[];
      await tester.pumpWidget(
        screen(
          provider: provider,
          manifest: manifest,
          doublePage: true,
          position: manifest.positionAt(19),
          onViewport: viewports.add,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('放大'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        screen(
          provider: provider,
          manifest: manifest,
          doublePage: true,
          position: manifest.positionAt(19),
          onViewport: viewports.add,
          imageBuilder: (context, resource, fit) {
            ReaderImageDecoded(
              resource.id,
              width: 600,
              height: 900,
            ).dispatch(context);
            return fixtureImage(context, resource, fit);
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(viewports.last.observed, isNotNull);
      expect(viewports.last.atEnd, false);
      expect(viewports.last.windowReady, true);
      await tester.tap(find.byTooltip('重置缩放'));
      await tester.pumpAndSettle();
      expect(viewports.last.observed!.pageKey, 'page-20');
      expect(viewports.last.atEnd, true);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('resident images do not report reading before a Flutter frame', (
    tester,
  ) async {
    final provider = FixturePageProvider();
    final manifest = fixtureChapter();
    final viewports = <ReaderViewportState>[];
    await tester.pumpWidget(
      screen(
        provider: provider,
        manifest: manifest,
        position: manifest.positionAt(19),
        onViewport: viewports.add,
      ),
    );
    await tester.pumpAndSettle();
    expect(provider.acquired, isNotEmpty);
    expect(viewports.last.observed, isNull);
    expect(viewports.last.atEnd, false);
    expect(viewports.last.windowReady, false);
    await tester.pumpWidget(
      screen(
        provider: provider,
        manifest: manifest,
        position: manifest.positionAt(19),
        onViewport: viewports.add,
        imageBuilder: (context, resource, fit) {
          ReaderImageDecoded(
            resource.id,
            width: 600,
            height: 900,
          ).dispatch(context);
          return fixtureImage(context, resource, fit);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(viewports.last.observed!.pageKey, 'page-19');
    expect(viewports.last.observed!.normalizedOffset, 1);
    expect(viewports.last.atEnd, true);
    expect(viewports.last.windowReady, true);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('paged controls, zoom and pan do not race page turning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = FixturePageProvider();
    await tester.pumpWidget(
      screen(provider: provider, manifest: fixtureChapter()),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 / 20'), findsOneWidget);
    expect(provider.acquired.length, lessThanOrEqualTo(3));
    await tester.tap(find.byTooltip('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 20'), findsOneWidget);
    await tester.tap(find.byTooltip('放大'));
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 2);
    await tester.drag(find.byType(InteractiveViewer), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 20'), findsOneWidget);
    await tester.tap(find.byTooltip('重置缩放'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(InteractiveViewer), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(find.text('3 / 20'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(provider.released, isNotEmpty);
  });

  testWidgets('landscape keeps the image visible with tall chapter controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final manifest = fixtureChapter();
    final viewports = <ReaderViewportState>[];
    var nextChapter = false;
    await tester.pumpWidget(
      screen(
        provider: FixturePageProvider(),
        manifest: manifest,
        position: manifest.positionAt(1, offset: .28),
        mode: ReadingMode.continuous,
        imageBuilder: decodedImage(),
        onViewport: viewports.add,
        chapterControls: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final label in [
              '阅读设置',
              '刷新进度',
              '重新阅读本章',
              '读完本章',
              '标记书签',
              '刷新书签',
            ])
              TextButton(onPressed: () {}, child: Text(label)),
            TextButton(
              onPressed: () => nextChapter = true,
              child: const Text('下一章'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final before = viewports.last.current;
    expect(before.pageKey, manifest.pages[1].key);

    tester.view.physicalSize = const Size(915, 411);
    await tester.pumpAndSettle();
    final imageViewport = find.byKey(const ValueKey('continuous-reader'));
    expect(imageViewport.hitTestable(), findsOneWidget);
    expect(viewports.last.observed, isNotNull);
    final rotated = viewports.last.current;
    expect(rotated.pageKey, before.pageKey);
    expect(rotated.normalizedOffset, before.normalizedOffset);

    final next = find.text('下一章');
    expect(next.hitTestable(), findsNothing);
    await tester.ensureVisible(next);
    await tester.pumpAndSettle();
    await tester.tap(next);
    expect(nextChapter, isTrue);
    expect(imageViewport.hitTestable(), findsOneWidget);
    expect(viewports.last.current, rotated);
  });

  testWidgets('continuous position survives resize and Webtoon layout switch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = FixturePageProvider();
    final manifest = fixtureChapter();
    final positions = <ReadingPosition>[];
    await tester.pumpWidget(
      screen(
        provider: provider,
        manifest: manifest,
        position: manifest.positionAt(4, offset: 0.3),
        mode: ReadingMode.continuous,
        fit: ReaderFit.width,
        imageBuilder: decodedImage(),
        onPosition: positions.add,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('5 / 20'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('continuous-reader')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final before = positions.last;
    await tester.tap(find.byTooltip('放大当前图片'));
    await tester.pumpAndSettle();
    expect(find.text('查看图片'), findsOneWidget);
    await tester.tap(find.byTooltip('放大'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('查看图片'), findsNothing);
    tester.view.physicalSize = const Size(700, 500);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<ReadingMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('条漫').last);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('continuous-reader')),
      Offset.zero,
    );
    await tester.pumpAndSettle();
    expect(positions.last.pageKey, before.pageKey);
    expect(
      positions.last.normalizedOffset,
      closeTo(before.normalizedOffset, 0.01),
    );
    expect(provider.acquired.length, lessThan(20));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('missing stable page gets an explicit recovery notice', (
    tester,
  ) async {
    final provider = FixturePageProvider();
    await tester.pumpWidget(
      screen(
        provider: provider,
        manifest: fixtureChapter(),
        position: ReadingPosition(
          chapterKey: 'chapter',
          pageKey: 'removed-page',
          manifestVersion: 'old',
          pageIndexHint: 2,
          normalizedOffset: 0.2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('页面清单发生变化，已定位到最接近的页码。'), findsOneWidget);
    expect(find.text('3 / 20'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'learned image dimensions preserve page, offset and content version',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = FixturePageProvider();
      final manifest = ChapterManifest(
        chapterKey: 'chapter',
        version: 'content-v1',
        pages: List.generate(12, (index) => ReaderPage(key: 'page-$index')),
      );
      final positions = <ReadingPosition>[];
      await tester.pumpWidget(
        screen(
          provider: provider,
          manifest: manifest,
          position: manifest.positionAt(4, offset: 0.3),
          mode: ReadingMode.continuous,
          onPosition: positions.add,
          imageBuilder: (context, resource, fit) {
            ReaderImageDecoded(
              resource.id,
              width: 1200,
              height: 600,
            ).dispatch(context);
            return fixtureImage(context, resource, fit);
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(positions.last.pageKey, 'page-4');
      expect(positions.last.manifestVersion, 'content-v1');
      expect(positions.last.normalizedOffset, closeTo(0.3, 0.01));
      // Learned 2:1 images have a much smaller logical height than the 2:3 fallback.
      expect(
        tester.getSize(find.byKey(const ValueKey('runtime-1-page-4'))).height,
        closeTo(360 / 2, 1),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
