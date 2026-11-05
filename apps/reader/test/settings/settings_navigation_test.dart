import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/features/settings/settings_widgets.dart';
import 'package:karuyomi/main.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';

List<wire.Chapter> get _chapters => [
  wire.Chapter(url: '/one', name: '第一章'),
  wire.Chapter(url: '/two', name: '第二章'),
];

TestPlatform _platform() =>
    TestPlatform()
      ..invokeHandler = (call) async => switch (call.whichRequest()) {
        wire.SourceCall_Request.details => wire.SourceResult(manga: testManga),
        wire.SourceCall_Request.chapters => wire.SourceResult(
          chapters: wire.ChapterList(chapters: _chapters),
        ),
        wire.SourceCall_Request.pages => wire.SourceResult(
          pageList: wire.PageList(
            pageSessionId: 'settings-${call.pages.chapter.url}',
            pages: [
              wire.Page(
                pageKey: 'page-one',
                url: '${call.pages.chapter.url}/page-one',
              ),
            ],
          ),
        ),
        _ => wire.SourceResult(mangaPage: wire.MangaPage(mangas: [testManga])),
      };

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

Future<void> _choose<T>(WidgetTester tester, String label) async {
  await _tap(tester, find.byType(DropdownButtonFormField<T>));
  await _tap(tester, find.text(label).last);
}

Future<void> _start(WidgetTester tester, TestPlatform platform) async {
  tester.view.physicalSize = const Size(1100, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(KaruyomiApp(platform: platform));
  await tester.pumpAndSettle();
}

Future<void> _globalDefaults(WidgetTester tester, {bool dark = false}) async {
  await _tap(
    tester,
    find.descendant(of: find.byType(NavigationRail), matching: find.text('设置')),
  );
  if (dark) await _choose<wire.AppTheme>(tester, '深色');
  await _choose<wire.ReaderMode>(tester, '从右到左');
  await _choose<wire.ReaderPageLayout>(tester, '双页');
}

Future<CatalogController> _details(WidgetTester tester) async {
  await _tap(
    tester,
    find.descendant(of: find.byType(NavigationRail), matching: find.text('浏览')),
  );
  await _tap(tester, find.text('source.test · 1.0'));
  await _tap(tester, find.text('测试漫画源 · zh'));
  await _tap(tester, find.text('真实源 DTO 测试'));
  return tester
      .widget<MangaDetailsPage>(find.byType(MangaDetailsPage))
      .controller;
}

String get _mangaKey => ChapterSequence(
  packageName: 'source.test',
  sourceId: sourceId,
  mangaUrl: testManga.url,
  chapters: _chapters,
).mangaKey;

ReaderScreen _reader(WidgetTester tester) =>
    tester.widget<ReaderScreen>(find.byType(ReaderScreen));

Future<void> _closeModal(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.binding.handlePopRoute();
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

Future<void> _leaveReader(
  WidgetTester tester,
  CatalogController catalog,
) async {
  final route = ModalRoute.of(tester.element(find.byType(ReaderScreen)))!;
  await tester.runAsync(catalog.flushReadingProgress);
  await tester.pumpAndSettle();
  await _closeModal(tester);
  await tester.runAsync(() async {
    await route.completed;
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
  expect(find.byType(MangaDetailsPage), findsOneWidget);
}

Future<void> _finish(WidgetTester tester, CatalogController catalog) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(catalog.closeReadingProgress);
}

void main() {
  testWidgets(
    'global settings save confirms the app theme and reader defaults are inherited by a manga',
    (tester) async {
      final platform = _platform();
      await _start(tester, platform);
      await _globalDefaults(tester, dark: true);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );
      expect(
        platform.businessServer.requests.where(
          (request) => request.uri.path == '/api/settings/mutations',
        ),
        isEmpty,
      );
      await _tap(tester, find.text('保存全局设置'));
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      final catalog = await _details(tester);
      final inherited = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(inherited!.global.theme, wire.AppTheme.APP_THEME_DARK);
      expect(inherited.overrides!.hasMode(), false);
      expect(inherited.overrides!.hasPageLayout(), false);
      expect(
        inherited.effectiveReader.mode,
        wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
      );
      expect(
        inherited.effectiveReader.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
      );
      await _tap(tester, find.text('第一章'));
      expect(_reader(tester).initialMode, ReadingMode.rightToLeft);
      expect(_reader(tester).doublePage, true);
      expect(
        tester
            .widget<DropdownButton<ReadingMode>>(
              find.byType(DropdownButton<ReadingMode>),
            )
            .value,
        ReadingMode.rightToLeft,
      );
      expect(
        tester
            .widget<SegmentedButton<bool?>>(find.byType(SegmentedButton<bool?>))
            .selected,
        {true},
      );
      await _leaveReader(tester, catalog);
      await _finish(tester, catalog);
    },
  );

  testWidgets(
    'reader choices save manga overrides, modal inheritance is per field, and AUTO survives chapter replacement and reopening',
    (tester) async {
      final platform = _platform();
      await _start(tester, platform);
      await _globalDefaults(tester);
      await _tap(tester, find.text('保存全局设置'));
      final catalog = await _details(tester);
      await _tap(tester, find.text('第一章'));
      await _tap(tester, find.byType(DropdownButton<ReadingMode>));
      await _tap(tester, find.text('从左到右').last);
      await _tap(
        tester,
        find.descendant(
          of: find.byType(SegmentedButton<bool?>),
          matching: find.text('单页'),
        ),
      );
      var snapshot = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(
        snapshot!.overrides!.mode,
        wire.ReaderMode.READER_MODE_LEFT_TO_RIGHT,
      );
      expect(
        snapshot.overrides!.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_SINGLE,
      );
      expect(
        snapshot.global.reader.mode,
        wire.ReaderMode.READER_MODE_RIGHT_TO_LEFT,
      );
      expect(
        snapshot.global.reader.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_DOUBLE,
      );
      await _tap(tester, find.text('阅读设置'));
      expect(find.byType(MangaSettingsEditor), findsOneWidget);
      await _choose<wire.ReaderMode>(tester, '跟随全局');
      await _tap(tester, find.text('保存本漫画设置'));
      snapshot = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(snapshot!.overrides!.hasMode(), false);
      expect(
        snapshot.overrides!.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_SINGLE,
      );
      await _closeModal(tester);
      expect(_reader(tester).initialMode, ReadingMode.rightToLeft);
      expect(_reader(tester).doublePage, false);
      await _tap(tester, find.text('阅读设置'));
      await _choose<wire.ReaderPageLayout>(tester, '跟随全局');
      await _tap(tester, find.text('保存本漫画设置'));
      snapshot = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(snapshot!.overrides!.hasMode(), false);
      expect(snapshot.overrides!.hasPageLayout(), false);
      await _closeModal(tester);
      expect(_reader(tester).doublePage, true);
      await _tap(
        tester,
        find.descendant(
          of: find.byType(SegmentedButton<bool?>),
          matching: find.text('自动'),
        ),
      );
      snapshot = await tester.runAsync(
        () => catalog.settings!.loadManga(_mangaKey),
      );
      expect(snapshot!.overrides!.hasPageLayout(), true);
      expect(
        snapshot.overrides!.pageLayout,
        wire.ReaderPageLayout.READER_PAGE_LAYOUT_AUTO,
      );
      expect(_reader(tester).doublePage, isNull);
      expect(
        tester
            .widget<SegmentedButton<bool?>>(find.byType(SegmentedButton<bool?>))
            .selected,
        {null},
      );
      final writes = platform.businessServer.requests
          .where((request) => request.uri.path == '/api/settings/mutations')
          .length;
      final firstLeaf = _reader(tester).key;
      await tester.ensureVisible(find.text('下一章'));
      await tester.runAsync(() async {
        await tester.tap(find.text('下一章'));
        await Future<void>.delayed(Duration.zero);
      });
      // Replacing the leaf first disposes its resources in a frame, then
      // restores the next chapter through the real supplier continuation.
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(_reader(tester).key, isNot(firstLeaf));
      expect(_reader(tester).initialMode, ReadingMode.rightToLeft);
      expect(_reader(tester).doublePage, isNull);
      expect(
        tester
            .widget<SegmentedButton<bool?>>(find.byType(SegmentedButton<bool?>))
            .selected,
        {null},
      );
      await _leaveReader(tester, catalog);
      await _tap(tester, find.text('第一章'));
      expect(_reader(tester).doublePage, isNull);
      expect(
        tester
            .widget<SegmentedButton<bool?>>(find.byType(SegmentedButton<bool?>))
            .selected,
        {null},
      );
      expect(
        platform.businessServer.requests.where(
          (request) => request.uri.path == '/api/settings/mutations',
        ),
        hasLength(writes),
      );
      await _leaveReader(tester, catalog);
      await _finish(tester, catalog);
    },
  );
}
