import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:karuyomi/main.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'fakes.dart';

List<wire.Chapter> get _chapters => [
  wire.Chapter(
    url: '/duplicate',
    name: '同名章',
    scanlator: '甲组',
    sourceOrder: 16,
    memoJson: '{"edition":"a"}',
  ),
  wire.Chapter(
    url: '/fraction',
    name: '小数章节',
    chapterNumber: 0.5,
    scanlator: '特别组',
    sourceOrder: 2,
  ),
  wire.Chapter(
    url: '/duplicate',
    name: '同名章',
    chapterNumber: 7.25,
    scanlator: '乙组',
    sourceOrder: 8,
    memoJson: '{"edition":"b"}',
  ),
  wire.Chapter(url: '/tail', name: '尾章', chapterNumber: 0, sourceOrder: 1),
];

ChapterSequence get _sequence => ChapterSequence(
  packageName: 'eu.kanade.source.test',
  sourceId: sourceId,
  mangaUrl: testManga.url,
  chapters: _chapters,
);

TestPlatform _platform() =>
    TestPlatform()
      ..invokeHandler = (call) async => switch (call.whichRequest()) {
        wire.SourceCall_Request.details => wire.SourceResult(manga: testManga),
        wire.SourceCall_Request.chapters => wire.SourceResult(
          chapters: wire.ChapterList(chapters: _chapters),
        ),
        wire.SourceCall_Request.pages => wire.SourceResult(
          pageList: wire.PageList(
            pageSessionId: 'chapter-list-${call.requestId}',
            pages: [wire.Page(pageKey: 'page-one', url: '/page-one')],
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

Future<CatalogController> _details(
  WidgetTester tester,
  TestPlatform platform, {
  bool settleDetails = true,
}) async {
  tester.view.physicalSize = const Size(1100, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(KaruyomiApp(platform: platform));
  await tester.pumpAndSettle();
  await _tap(tester, find.text('去浏览'));
  await _tap(tester, find.text('eu.kanade.source.test · 1.0'));
  await _tap(tester, find.byKey(ValueKey(('catalog-source', sourceId))));
  if (settleDetails) {
    await _tap(tester, find.text('真实源 DTO 测试'));
  } else {
    await tester.runAsync(() async {
      await tester.tap(find.text('真实源 DTO 测试'));
      await Future<void>.delayed(Duration.zero);
    });
    // The intentionally pending business read keeps its progress indicator
    // animating, so advance only until the detail route itself is mounted.
    for (
      var attempt = 0;
      attempt < 10 && find.byType(MangaDetailsPage).evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(MangaDetailsPage), findsOneWidget);
  }
  return tester
      .widget<MangaDetailsPage>(find.byType(MangaDetailsPage))
      .controller;
}

Finder get _tiles => find.descendant(
  of: find.byType(MangaDetailsPage),
  matching: find.byType(ListTile),
);

Finder _row(int sourceIndex) =>
    find.byKey(ValueKey(_sequence.entries[sourceIndex].key));

List<Key?> _visibleKeys(WidgetTester tester) =>
    tester.widgetList<ListTile>(_tiles).map((tile) => tile.key).toList();

List<Key> _keys(Iterable<int> sourceIndices) => [
  for (final index in sourceIndices) ValueKey(_sequence.entries[index].key),
];

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(const ValueKey('chapter-search')), query);
  await tester.pumpAndSettle();
}

Future<void> _reverse(WidgetTester tester) async {
  await _tap(tester, find.byKey(const ValueKey('chapter-list-order')));
  await _tap(tester, find.text('反向来源顺序').last);
}

Future<void> _finish(WidgetTester tester, CatalogController catalog) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(catalog.closeReadingProgress);
}

Future<void> _leaveReader(
  WidgetTester tester,
  CatalogController catalog,
) async {
  final route = ModalRoute.of(tester.element(find.byType(ReaderScreen)))!;
  await tester.runAsync(catalog.flushReadingProgress);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.binding.handlePopRoute();
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await route.completed;
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
  expect(find.byType(MangaDetailsPage), findsOneWidget);
}

void main() {
  testWidgets(
    'chapter list preserves duplicate occurrences and Source order with absent and fractional numbers',
    (tester) async {
      final platform = _platform();
      final catalog = await _details(tester, platform);
      final calls = platform.invocations.length;
      expect(find.text('章节（4）'), findsOneWidget);
      expect(_visibleKeys(tester), _keys([0, 1, 2, 3]));
      expect(find.text('同名章'), findsNWidgets(2));
      for (final sourceIndex in [0, 2]) {
        expect(
          find.descendant(
            of: _row(sourceIndex),
            matching: find.textContaining('同名章节'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: _row(sourceIndex),
            matching: find.textContaining('重复链接'),
          ),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: _row(0), matching: find.textContaining('第 0 章')),
        findsNothing,
      );
      expect(
        find.descendant(of: _row(1), matching: find.textContaining('第 0.5 章')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _row(3), matching: find.textContaining('第 0 章')),
        findsOneWidget,
      );
      await _reverse(tester);
      expect(_visibleKeys(tester), _keys([3, 2, 1, 0]));
      expect(platform.invocations, hasLength(calls));
      await _finish(tester, catalog);
    },
  );

  testWidgets(
    'chapter search matches name scanlator and displayed number locally and can clear an empty result',
    (tester) async {
      final platform = _platform();
      final catalog = await _details(tester, platform);
      final calls = platform.invocations.length;
      await _search(tester, '同名');
      expect(_visibleKeys(tester), _keys([0, 2]));
      await _search(tester, '特别组');
      expect(_visibleKeys(tester), _keys([1]));
      await _search(tester, '0.5');
      expect(_visibleKeys(tester), _keys([1]));
      await _search(tester, '完全没有的章节');
      expect(_tiles, findsNothing);
      expect(find.text('没有匹配的章节'), findsOneWidget);
      expect(find.byTooltip('清空章节搜索'), findsOneWidget);
      await _tap(tester, find.byTooltip('清空章节搜索'));
      expect(_visibleKeys(tester), _keys([0, 1, 2, 3]));
      expect(find.text('没有匹配的章节'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('chapter-search')))
            .controller!
            .text,
        isEmpty,
      );
      await _search(tester, '   ');
      expect(_visibleKeys(tester), _keys([0, 1, 2, 3]));
      expect(platform.invocations, hasLength(calls));
      await _finish(tester, catalog);
    },
  );

  testWidgets(
    'reversed search and bookmarks open the exact duplicate Source occurrence',
    (tester) async {
      final platform = _platform();
      final catalog = await _details(tester, platform);
      final calls = platform.invocations.length;
      await _tap(
        tester,
        find.descendant(of: _row(2), matching: find.byTooltip('标记章节书签 同名章')),
      );
      expect(
        platform.businessServer.bookmarked(
          _sequence.mangaKey,
          _sequence.entries[2].key,
        ),
        true,
      );
      expect(
        platform.businessServer.bookmarked(
          _sequence.mangaKey,
          _sequence.entries[0].key,
        ),
        false,
      );
      await _search(tester, '同名章');
      await _reverse(tester);
      expect(_visibleKeys(tester), _keys([2, 0]));
      await _tap(tester, find.widgetWithText(FilterChip, '仅书签'));
      expect(_visibleKeys(tester), _keys([2]));
      expect(platform.invocations, hasLength(calls));
      await _tap(tester, _row(2));
      expect(find.byType(ReaderScreen), findsOneWidget);
      final readerRoute = tester.widget<ChapterReaderRoute>(
        find.byType(ChapterReaderRoute),
      );
      expect(readerRoute.initialChapter.sourceIndex, 2);
      expect(readerRoute.initialChapter.key, _sequence.entries[2].key);
      expect(readerRoute.initialOrder, ChapterOrder.reversed);
      final pages = platform.invocations.where(
        (call) => call.whichRequest() == wire.SourceCall_Request.pages,
      );
      expect(pages, hasLength(1));
      expect(pages.single.pages.chapter, _chapters[2]);
      expect(platform.invocations, hasLength(calls + 1));
      await _leaveReader(tester, catalog);
      expect(_visibleKeys(tester), _keys([2]));
      await _finish(tester, catalog);
    },
  );

  testWidgets(
    'opening before the detail state read finishes restores the saved reader order',
    (tester) async {
      final platform = _platform();
      final seed = BusinessStateClient(
        api: platform.businessServer,
        identity: ProgressIdentity(
          origin: platform.origin,
          subject: platform.bootstrapSubject,
        ),
      );
      final manifest = ChapterManifest(
        chapterKey: _sequence.entries[1].key,
        version: 'seed-manifest',
        pages: [ReaderPage(key: 'page-one')],
      );
      await tester.runAsync(() async {
        await ProgressRepository(seed).save(
          mangaKey: _sequence.mangaKey,
          manifest: manifest,
          progress: ChapterProgress(current: manifest.positionAt(0)),
          reversedOrder: true,
        );
        await seed.dispose();
      });
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      var delayed = false;
      platform.businessServer.beforeRequest = (request) async {
        if (!delayed &&
            request.method == 'GET' &&
            request.uri.path == '/api/state/manga/${_sequence.mangaKey}' &&
            request.uri.queryParameters.isEmpty) {
          delayed = true;
          await gate.future;
        }
        return null;
      };
      final catalog = await _details(tester, platform, settleDetails: false);
      expect(delayed, true);
      expect(find.text('继续阅读'), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(_row(1));
        await Future<void>.delayed(Duration.zero);
      });
      for (
        var attempt = 0;
        attempt < 10 && find.byType(ChapterReaderRoute).evaluate().isEmpty;
        attempt++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      }
      expect(find.byType(ChapterReaderRoute), findsOneWidget);
      expect(
        tester
            .widget<ChapterReaderRoute>(find.byType(ChapterReaderRoute))
            .initialOrder,
        isNull,
      );
      gate.complete();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButton<ChapterOrder>>(
              find.byType(DropdownButton<ChapterOrder>),
            )
            .value,
        ChapterOrder.reversed,
      );
      await _leaveReader(tester, catalog);
      expect(_visibleKeys(tester), _keys([3, 2, 1, 0]));
      await _finish(tester, catalog);
    },
  );
}
