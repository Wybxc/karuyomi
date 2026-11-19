import '../../test_support/cupertino.dart';

import 'package:karuyomi/widgets/choice_field.dart';

import '../test_app.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
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
    position.jumpTo(position.minScrollExtent);
    await tester.pumpAndSettle();
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
    'refresh keeps the existing work and chapter list until the whole Source read succeeds',
    (tester) async {
      final platform = _platform();
      final catalog = await _details(tester, platform);
      final oldHandler = platform.invokeHandler!;
      final chaptersGate = Completer<wire.SourceResult>();
      addTearDown(() {
        if (!chaptersGate.isCompleted) {
          chaptersGate.complete(
            wire.SourceResult(chapters: wire.ChapterList(chapters: _chapters)),
          );
        }
      });
      var chapterReads = 0;
      platform.invokeHandler = (call) async {
        switch (call.whichRequest()) {
          case wire.SourceCall_Request.details:
            return wire.SourceResult(manga: testManga..author = '资料更新后的作者');
          case wire.SourceCall_Request.chapters:
            if (++chapterReads == 1) return chaptersGate.future;
            return wire.SourceResult(
              chapters: wire.ChapterList(
                chapters: [
                  ..._chapters,
                  wire.Chapter(url: '/new', name: '新章节'),
                ],
              ),
            );
          default:
            return oldHandler(call);
        }
      };
      final reload = find.byKey(const ValueKey('details-source-refresh'));
      expect(reload, findsOneWidget);
      await _reveal(tester, reload);
      final before = platform.businessServer.appliedMutations;
      await tester.runAsync(() async {
        await tester.tap(reload);
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pump();
      expect(chapterReads, 1);
      expect(find.text('正在刷新作品资料和章节'), findsOneWidget);
      expect(find.text('作者：作者'), findsOneWidget);
      expect(find.text('章节（2）'), findsOneWidget);
      expect(find.text('作者：资料更新后的作者'), findsNothing);
      expect(tester.widget<CupertinoButton>(reload).onPressed, isNull);

      await tester.runAsync(() async {
        chaptersGate.completeError(
          const RuntimeException(RuntimeErrorCode.sourceError, 'test failure'),
        );
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(find.text('作者：作者'), findsOneWidget);
      expect(find.text('章节（2）'), findsOneWidget);
      expect(find.textContaining('未能刷新作品资料和章节'), findsOneWidget);
      expect(find.text('这个漫画源没有返回章节'), findsNothing);
      expect(platform.businessServer.appliedMutations, before);

      await _tap(tester, find.text('重试刷新'));
      expect(chapterReads, 2);
      expect(find.text('作者：资料更新后的作者'), findsOneWidget);
      expect(find.text('章节（3）'), findsOneWidget);
      expect(find.textContaining('未能刷新作品资料和章节'), findsNothing);
      await _reveal(tester, find.text('新章节'));
      expect(find.text('新章节'), findsOneWidget);
      expect(platform.businessServer.appliedMutations, before);
      await _finish(tester, catalog);
    },
  );

  testWidgets(
    'a filtered list can be reset and a genuine empty chapter list can be refreshed',
    (tester) async {
      final platform = _platform();
      final catalog = await _details(tester, platform);
      tester.view.physicalSize = const Size(360, 800);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      final search = find.byKey(const ValueKey('chapter-search'));
      await _reveal(tester, search);
      await tester.enterText(search, '不存在的名称');
      await tester.pumpAndSettle();
      final clear = find.byKey(const ValueKey('clear-chapter-filters'));
      expect(find.text('没有匹配的章节'), findsOneWidget);
      expect(clear, findsOneWidget);
      expect(find.text('这个漫画源没有返回章节'), findsNothing);
      await _tap(tester, clear);
      expect(find.text('显示 2 / 2 章'), findsOneWidget);
      expect(clear, findsNothing);

      final oldHandler = platform.invokeHandler!;
      platform.invokeHandler = (call) async =>
          call.whichRequest() == wire.SourceCall_Request.chapters
          ? wire.SourceResult(chapters: wire.ChapterList())
          : oldHandler(call);
      final reload = find.byKey(const ValueKey('details-source-refresh'));
      await _tap(tester, reload);
      expect(find.text('章节（0）'), findsOneWidget);
      expect(find.text('这个漫画源没有返回章节'), findsOneWidget);
      expect(clear, findsNothing);
      expect(reload, findsOneWidget);

      platform.invokeHandler = oldHandler;
      FocusManager.instance.primaryFocus?.unfocus();
      final scrollable = find
          .descendant(
            of: find.byType(MangaDetailsPage),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.minScrollExtent);
      await tester.pumpAndSettle();
      final pull = await tester.startGesture(const Offset(26, 162));
      await pull.moveBy(const Offset(0, 380));
      await tester.pump();
      await pull.up();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      await _reveal(tester, find.text('章节（2）'));
      expect(find.text('章节（2）'), findsOneWidget);
      expect(find.text('这个漫画源没有返回章节'), findsNothing);
      await _finish(tester, catalog);
    },
  );

  testWidgets('leaving during a refresh discards a late Source reply', (
    tester,
  ) async {
    final platform = _platform();
    final catalog = await _details(tester, platform);
    final oldHandler = platform.invokeHandler!;
    final detailGate = Completer<wire.SourceResult>();
    addTearDown(() {
      if (!detailGate.isCompleted) {
        detailGate.complete(wire.SourceResult(manga: testManga));
      }
    });
    var detailReads = 0;
    var chapterReads = 0;
    platform.invokeHandler = (call) async {
      if (call.hasDetails() && ++detailReads == 1) return detailGate.future;
      if (call.hasChapters()) chapterReads++;
      return oldHandler(call);
    };
    final reload = find.byKey(const ValueKey('details-source-refresh'));
    await _reveal(tester, reload);
    await tester.runAsync(() async {
      await tester.tap(reload);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(detailReads, 1);
    expect(chapterReads, 0);
    final route = ModalRoute.of(tester.element(find.byType(MangaDetailsPage)))!;
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(route.isCurrent, isFalse);

    await tester.runAsync(() async {
      detailGate.complete(
        wire.SourceResult(manga: testManga..author = '已离开页面的回复'),
      );
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    expect(find.byType(MangaDetailsPage), findsNothing);
    expect(chapterReads, 0);
    expect(find.text('已离开页面的回复'), findsNothing);
    await _tap(tester, find.text('真实源 DTO 测试'));
    expect(chapterReads, 1);
    expect(find.text('作者：作者'), findsOneWidget);
    await _finish(tester, catalog);
  });

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
      expect(
        find.byKey(const ValueKey('chapter-open-failure')),
        findsOneWidget,
      );
      expect(find.text('未能打开「第二版」：漫画源请求失败，请重试'), findsOneWidget);
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
            .widget<ChoiceField<ChapterOrder>>(
              find.byType(ChoiceField<ChapterOrder>),
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
            .widget<CupertinoButton>(
              find.byKey(const ValueKey('retry-read-resume')),
            )
            .onPressed,
        isNotNull,
      );
      await _reveal(tester, find.byKey(ValueKey(_sequence.entries[1].key)));
      expect(
        tester
                .widget<CupertinoButton>(
                  buttonAbove(find.byKey(ValueKey(_sequence.entries[1].key))),
                )
                .onPressed !=
            null,
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
      await _reveal(tester, find.byType(ChoiceField<ChapterOrder>));
      expect(
        tester
            .widget<ChoiceField<ChapterOrder>>(
              find.byType(ChoiceField<ChapterOrder>),
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
      expect(tester.widget<CupertinoButton>(retry).onPressed, isNull);
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
