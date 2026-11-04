import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/diagnostics/reader_baseline.dart';
import 'package:karuyomi/features/reader/resource_image.dart';
import 'package:reader_core/reader_core.dart';

final class FixturePageProvider implements PageProvider {
  final acquired = <PageRef>[];
  final released = <String>[];
  final cancelled = <String>[];

  @override
  Future<ImageResource> acquire(PageRef ref) async {
    acquired.add(ref);
    return ImageResource(
      id: '${ref.generation}-${ref.pageKey}',
      generation: ref.generation,
      location: Uri.parse('https://processed-fixture.invalid/${ref.pageKey}'),
      byteLength: 100,
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

Widget screen({
  required FixturePageProvider provider,
  required ChapterManifest manifest,
  ReadingPosition? position,
  ReadingMode mode = ReadingMode.leftToRight,
  ValueChanged<ReadingPosition>? onPosition,
  ValueChanged<ReaderViewportState>? onViewport,
  ResourceImageBuilder imageBuilder = fixtureImage,
  bool? doublePage,
  Widget? chapterControls,
}) => MaterialApp(
  home: ReaderScreen(
    manifest: manifest,
    provider: provider,
    generation: 'runtime-1',
    initialPosition: position,
    initialMode: mode,
    doublePage: doublePage,
    chapterControls: chapterControls,
    onPositionChanged: onPosition,
    onViewportChanged: onViewport,
    imageBuilder: imageBuilder,
    imageEvictor: (_) async {},
  ),
);

void main() {
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
      expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, true);
      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).selected,
        false,
      );
      expect(find.text('51 / 51'), findsOneWidget);
      expect(find.byKey(const ValueKey('runtime-1-page-49')), findsNothing);

      // Completion/save controls may gain a row without changing page width.
      panelHeight.value = 72;
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).selected,
        false,
      );
      expect(find.byKey(const ValueKey('runtime-1-page-49')), findsNothing);

      await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNothing);
      await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).selected,
        false,
      );

      tester.view.physicalSize = const Size(800, 760);
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(1200, 760);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).selected,
        false,
      );
      expect(find.text('51 / 51'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('automatic double-page follows width until the user selects it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = FixturePageProvider();
    await tester.pumpWidget(
      screen(provider: provider, manifest: fixtureChapter()),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, false);
    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, true);
    tester.view.physicalSize = const Size(800, 900);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, false);
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(800, 760);
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, true);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

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
      expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, true);
      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).selected,
        false,
      );
      // Rebuilding an unchanged parent input must preserve the local choice.
      await tester.pumpWidget(
        screen(provider: provider, manifest: manifest, doublePage: true),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).selected,
        false,
      );
      await tester.pumpWidget(
        screen(provider: provider, manifest: manifest, doublePage: false),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        screen(provider: provider, manifest: manifest, doublePage: true),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, true);
      await tester.tap(find.byType(FilterChip));
      await tester.pumpAndSettle();
      await tester.pumpWidget(screen(provider: provider, manifest: manifest));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).selected,
        false,
      );
      tester.view.physicalSize = const Size(1200, 900);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, true);
      await tester.pumpWidget(
        screen(provider: provider, manifest: manifest, doublePage: false),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip)).selected,
        false,
      );
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
    await tester.tap(find.byType(FilterChip));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, false);
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
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, false);
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
    expect(tester.widget<FilterChip>(find.byType(FilterChip)).selected, true);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

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
    'zoom before decoding cannot mark a clipped final spread observed',
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
      expect(viewports.last.observed, isNull);
      expect(viewports.last.atEnd, false);
      expect(viewports.last.windowReady, false);
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
