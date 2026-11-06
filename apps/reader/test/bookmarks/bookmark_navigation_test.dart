import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/main.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';

List<wire.Chapter> get _chapters => [
  wire.Chapter(url: '/one', name: '第一章'),
  wire.Chapter(url: '/two', name: '第二章'),
];

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'details bookmark filtering and the reader current chapter share server state',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final platform = TestPlatform()
        ..invokeHandler = (call) async => switch (call.whichRequest()) {
          wire.SourceCall_Request.details => wire.SourceResult(
            manga: testManga,
          ),
          wire.SourceCall_Request.chapters => wire.SourceResult(
            chapters: wire.ChapterList(chapters: _chapters),
          ),
          wire.SourceCall_Request.pages => wire.SourceResult(
            pageList: wire.PageList(
              pageSessionId: 'bookmark-pages',
              pages: [
                wire.Page(
                  pageKey: 'page-one',
                  url: '${call.pages.chapter.url}/page-one',
                ),
              ],
            ),
          ),
          _ => wire.SourceResult(
            mangaPage: wire.MangaPage(mangas: [testManga]),
          ),
        };
      await tester.pumpWidget(KaruyomiApp(platform: platform));
      await tester.pumpAndSettle();
      await _tap(tester, find.text('去浏览'));
      await _tap(tester, find.text('eu.kanade.source.test · 1.0'));
      await _tap(tester, find.text('测试漫画源 · zh'));
      await _tap(tester, find.text('真实源 DTO 测试'));
      final catalog = tester
          .widget<MangaDetailsPage>(find.byType(MangaDetailsPage))
          .controller;
      final sequence = ChapterSequence(
        packageName: 'eu.kanade.source.test',
        sourceId: sourceId,
        mangaUrl: testManga.url,
        chapters: _chapters,
      );
      expect(find.text('已标记 0 章'), findsOneWidget);
      await _tap(tester, find.byTooltip('标记章节书签 第一章'));
      expect(
        platform.businessServer.bookmarked(
          sequence.mangaKey,
          sequence.entries.first.key,
        ),
        true,
      );
      expect(find.text('已标记 1 章'), findsOneWidget);
      await _tap(tester, find.widgetWithText(FilterChip, '仅书签'));
      expect(find.text('第一章'), findsOneWidget);
      expect(find.text('第二章'), findsNothing);
      await _tap(tester, find.text('第一章'));
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(find.text('本章已标记书签'), findsOneWidget);
      await _tap(tester, find.byTooltip('移除章节书签 第一章'));
      expect(find.text('本章未标记书签'), findsOneWidget);
      expect(
        platform.businessServer.bookmarked(
          sequence.mangaKey,
          sequence.entries.first.key,
        ),
        false,
      );
      final readerRoute = ModalRoute.of(
        tester.element(find.byType(ReaderScreen)),
      )!;
      await tester.runAsync(catalog.flushReadingProgress);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.binding.handlePopRoute();
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.byType(MangaDetailsPage), findsOneWidget);
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      // Route disposal closes the reader's resources before the detail page
      // performs its business reads. Drain both real supplier continuations
      // and the widget-test frame queue before inspecting the returned page.
      await tester.runAsync(() async {
        await readerRoute.completed;
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('已标记 0 章'), findsOneWidget);
      expect(find.text('当前章节列表中没有书签'), findsOneWidget);
      expect(find.text('第一章'), findsNothing);
      expect(find.text('第二章'), findsNothing);
      expect(platform.businessServer.manga(sequence.mangaKey)!.favorite, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(catalog.closeReadingProgress);
    },
  );
}
