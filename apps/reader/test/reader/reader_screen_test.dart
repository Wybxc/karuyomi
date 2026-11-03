import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
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
      mimeType: 'image/png',
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
}) => MaterialApp(
  home: ReaderScreen(
    manifest: manifest,
    provider: provider,
    generation: 'runtime-1',
    initialPosition: position,
    initialMode: mode,
    onPositionChanged: onPosition,
    imageBuilder: fixtureImage,
  ),
);

void main() {
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
}
