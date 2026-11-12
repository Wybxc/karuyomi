import '../test_app.dart';

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/data/business_state_client.dart';
import 'package:karuyomi/data/progress_repository.dart';
import 'package:karuyomi/data/reading_progress.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/reader/chapter_reader_route.dart';
import 'package:karuyomi/features/reader/chapter_sequence.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/runtime/runtime_platform_types.dart';
import 'package:reader_core/reader_core.dart';
import 'package:source_runtime/source_runtime.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'fakes.dart';

List<wire.Chapter> get _chapters => [
  wire.Chapter(url: '/duplicate', name: '第一版', memoJson: '{"edition":"a"}'),
  wire.Chapter(url: '/duplicate', name: '第二版', memoJson: '{"edition":"b"}'),
];

ChapterSequence get _sequence => ChapterSequence(
  packageName: 'eu.kanade.source.test',
  sourceId: sourceId,
  mangaUrl: testManga.url,
  chapters: _chapters,
);

ChapterManifest get _manifest => ChapterManifest(
  chapterKey: _sequence.entries[1].key,
  version: 'saved-manifest',
  pages: [
    ReaderPage(key: 'page-one'),
    ReaderPage(key: 'page-two'),
  ],
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
            pageSessionId: 'recovery-${call.requestId}',
            pages: [wire.Page(pageKey: 'page-one', url: '/page-one')],
          ),
        ),
        _ => wire.SourceResult(mangaPage: wire.MangaPage(mangas: [testManga])),
      };

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scrollable = find
        .descendant(
          of: find.byType(MangaDetailsPage),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    for (
      var attempt = 0;
      position.pixels > position.minScrollExtent && attempt < 30;
      attempt++
    ) {
      await tester.drag(scrollable, const Offset(0, 500));
      await tester.pumpAndSettle();
    }
    await tester.scrollUntilVisible(finder, 250, scrollable: scrollable);
  }
  await tester.ensureVisible(finder);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(Duration.zero);
  });
  await tester.pumpAndSettle();
}

Future<CatalogController> _details(
  WidgetTester tester,
  TestPlatform platform,
) async {
  tester.view.physicalSize = const Size(480, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpApp(KaruyomiApp(platform: platform));
  await tester.pumpAndSettle();
  await _tap(tester, find.text('去浏览'));
  for (final target in [
    find.byKey(
      const ValueKey((
        'source-directory-row',
        'eu.kanade.source.test',
        sourceId,
      )),
    ),
    find.text('真实源 DTO 测试'),
  ]) {
    await tester.ensureVisible(target);
    await tester.runAsync(() async {
      await tester.tap(target);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }
  return tester
      .widget<MangaDetailsPage>(find.byType(MangaDetailsPage))
      .controller;
}

Future<void> _finish(WidgetTester tester, CatalogController catalog) async {
  expect(tester.takeException(), isNull);
  await tester.pumpApp(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(catalog.closeReadingProgress);
}

bool _resumeRequest(String path, String method) {
  final uri = Uri.parse(path);
  return method == 'GET' &&
      uri.path == '/api/state/manga/${_sequence.mangaKey}' &&
      uri.queryParameters.isEmpty;
}

const _unavailable = ApiReply(
  status: 503,
  headers: {'content-type': 'application/json'},
  body: '{}',
  redirected: false,
);

Future<void> _seed(TestPlatform platform, WidgetTester tester) async {
  final client = BusinessStateClient(
    api: platform.businessServer,
    identity: ProgressIdentity(
      origin: platform.origin,
      subject: platform.bootstrapSubject,
    ),
  );
  await tester.runAsync(() async {
    await ProgressRepository(client).save(
      mangaKey: _sequence.mangaKey,
      manifest: _manifest,
      progress: ChapterProgress(current: _manifest.positionAt(1)),
      reversedOrder: true,
    );
    await client.dispose();
  });
}

void main() {
  testWidgets(
    'a failed chapter opens only on explicit retry with the same occurrence DTO',
    (tester) async {
      final platform = _platform();
      final normal = platform.invokeHandler!;
      var pageCalls = 0;
      platform.invokeHandler = (call) async {
        if (call.hasPages() && ++pageCalls == 1) {
          throw const RuntimeException(
            RuntimeErrorCode.sourceError,
            'Injected Source failure',
          );
        }
        return normal(call);
      };
      final catalog = await _details(tester, platform);
      await _tap(tester, find.byKey(ValueKey(_sequence.entries[1].key)));
      expect(find.byType(ChapterReaderRoute), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('chapter-open-failure')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('chapter-open-failure')))
            .data,
        '未能打开「第二版」：漫画源请求失败，请重试',
      );
      await tester.pump(const Duration(seconds: 3));
      expect(pageCalls, 1);
      await _reveal(tester, find.byKey(const ValueKey('chapter-search')));
      await tester.enterText(
        find.byKey(const ValueKey('chapter-search')),
        '第一版',
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('retry-open-chapter')));
      expect(pageCalls, 2);
      final reader = tester.widget<ChapterReaderRoute>(
        find.byType(ChapterReaderRoute),
      );
      expect(reader.initialChapter.key, _sequence.entries[1].key);
      expect(reader.initialChapter.sourceIndex, 1);
      final pageCallsSent = platform.invocations
          .where((call) => call.hasPages())
          .toList();
      expect(pageCallsSent[0].pages.chapter, _chapters[1]);
      expect(pageCallsSent[1].pages.chapter, _chapters[1]);
      await _finish(tester, catalog);
    },
  );

  testWidgets(
    'resume retry reads the server without replaying Source calls or writes',
    (tester) async {
      final platform = _platform();
      await _seed(platform, tester);
      var unavailable = true;
      platform.businessServer.beforeRequest = (request) {
        return unavailable && _resumeRequest(request.path, request.method)
            ? _unavailable
            : null;
      };
      final catalog = await _details(tester, platform);
      expect(find.text('未能读取服务端阅读位置，仍可从章节列表打开。'), findsOneWidget);
      expect(find.text('继续阅读'), findsNothing);
      final calls = platform.invocations.length;
      final start = platform.businessServer.requests.length;
      unavailable = false;
      await _tap(tester, find.byKey(const ValueKey('retry-read-resume')));
      final requests = platform.businessServer.requests.skip(start).toList();
      expect(requests, isNotEmpty);
      expect(
        requests.every(
          (request) => _resumeRequest(request.path, request.method),
        ),
        true,
      );
      expect(platform.invocations, hasLength(calls));
      await _reveal(tester, find.text('继续阅读'));
      expect(find.text('继续阅读'), findsOneWidget);
      expect(find.byKey(const ValueKey('retry-read-resume')), findsNothing);
      expect(
        tester
            .widget<DropdownButton<ChapterOrder>>(
              find.byType(DropdownButton<ChapterOrder>),
            )
            .value,
        ChapterOrder.reversed,
      );
      await _finish(tester, catalog);
    },
  );

  testWidgets(
    'a failed resume retry remains explicit and leaves chapter navigation enabled',
    (tester) async {
      final platform = _platform();
      platform.businessServer.beforeRequest = (request) =>
          _resumeRequest(request.path, request.method) ? _unavailable : null;
      final catalog = await _details(tester, platform);
      final start = platform.businessServer.requests.length;
      await _tap(tester, find.byKey(const ValueKey('retry-read-resume')));
      expect(platform.businessServer.requests.skip(start), hasLength(1));
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('retry-read-resume')))
            .onPressed,
        isNotNull,
      );
      await _reveal(tester, find.byKey(ValueKey(_sequence.entries[1].key)));
      expect(
        tester
            .widget<ListTile>(find.byKey(ValueKey(_sequence.entries[1].key)))
            .enabled,
        true,
      );
      await tester.pump(const Duration(seconds: 3));
      expect(platform.businessServer.requests.skip(start), hasLength(1));
      await _finish(tester, catalog);
    },
  );

  testWidgets(
    'read-only resume retry preserves an unconfirmed progress mutation without resending it',
    (tester) async {
      final platform = _platform();
      var unavailable = true;
      platform.businessServer.beforeRequest = (request) =>
          unavailable && _resumeRequest(request.path, request.method)
          ? _unavailable
          : null;
      final catalog = await _details(tester, platform);
      final progress = catalog.createReadingProgress(_sequence.mangaKey)!;
      platform.businessServer.failWrites = true;
      await tester.runAsync(() async {
        await progress.restore(_manifest);
        progress.observe(
          manifest: _manifest,
          current: _manifest.positionAt(1),
          reversedOrder: true,
        );
        expect(await progress.flush(), false);
      });
      await tester.pumpAndSettle();
      expect(catalog.hasUnsavedReadingProgress, true);
      await _reveal(tester, find.text('重试保存进度'));
      expect(find.text('重试保存进度'), findsOneWidget);
      final start = platform.businessServer.requests.length;
      await _tap(tester, find.byKey(const ValueKey('retry-read-resume')));
      expect(catalog.hasUnsavedReadingProgress, true);
      await _reveal(tester, find.byType(DropdownButton<ChapterOrder>));
      expect(
        tester
            .widget<DropdownButton<ChapterOrder>>(
              find.byType(DropdownButton<ChapterOrder>),
            )
            .value,
        ChapterOrder.reversed,
      );
      unavailable = false;
      platform.businessServer.failWrites = false;
      await _tap(tester, find.byKey(const ValueKey('retry-read-resume')));
      final requests = platform.businessServer.requests.skip(start).toList();
      expect(requests, isNotEmpty);
      expect(
        requests.every(
          (request) => _resumeRequest(request.path, request.method),
        ),
        true,
      );
      expect(catalog.hasUnsavedReadingProgress, true);
      expect(progress.unsaved, true);
      expect(find.text('部分阅读进度尚未保存，当前会话仍保留记录。'), findsOneWidget);
      await _reveal(tester, find.text('继续阅读'));
      expect(find.text('继续阅读'), findsOneWidget);
      await _finish(tester, catalog);
    },
  );

  testWidgets(
    'a late resume retry cannot restore controls after the identity changes',
    (tester) async {
      final platform = _platform();
      await _seed(platform, tester);
      var unavailable = true;
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      var delaying = false;
      platform.businessServer.beforeRequest = (request) async {
        if (_resumeRequest(request.path, request.method)) {
          if (unavailable) return _unavailable;
          delaying = true;
          await gate.future;
        }
        return null;
      };
      final catalog = await _details(tester, platform);
      unavailable = false;
      final retry = find.byKey(const ValueKey('retry-read-resume'));
      await _reveal(tester, retry);
      await tester.runAsync(() async {
        await tester.tap(retry);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(delaying, true);
      expect(tester.widget<TextButton>(retry).onPressed, isNull);
      platform.bootstrapSubject = 'different-subject';
      await tester.runAsync(catalog.connect);
      await tester.pump();
      gate.complete();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(find.text('继续阅读'), findsNothing);
      expect(find.byKey(const ValueKey('retry-read-resume')), findsNothing);
      expect(find.text('漫画源会话已变化，请返回浏览重新打开详情。'), findsOneWidget);
      await _finish(tester, catalog);
    },
  );
}
