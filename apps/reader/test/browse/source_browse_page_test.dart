import 'package:karuyomi/widgets/app_routes.dart';

import '../test_app.dart';

import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/browse/source_browse_page.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

import 'fakes.dart';

void main() {
  late TestPlatform platform;
  late CatalogController catalog;
  setUp(() async {
    platform = TestPlatform();
    catalog = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
  });
  tearDown(() async {
    catalog.dispose();
    await catalog.closeReadingProgress();
    await platform.dispose();
  });
  Future<void> show(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpApp(
      CupertinoApp(
        theme: readerAppTheme(brightness),
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: CupertinoButton(
              onPressed: () => Navigator.of(context).push<void>(
                AppPageRoute(
                  builder: (_) => SourceBrowsePage(
                    catalog: catalog,
                    build: catalog.builds.single,
                    source: catalog.builds.single.sources.single,
                  ),
                ),
              ),
              child: const Text('打开源'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开源'));
    await tester.pumpAndSettle();
  }

  Future<void> hide(WidgetTester tester) async {
    await tester.pumpApp(const SizedBox());
    await tester.pumpAndSettle();
  }

  wire.SourceResult page(String title, {bool more = true}) => wire.SourceResult(
    mangaPage: wire.MangaPage(
      mangas: [wire.Manga(title: title, url: '/$title')],
      hasNextPage: more,
    ),
  );
  Future<void> tap(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  for (final brightness in Brightness.values) {
    testWidgets('compact source covers follow the toolbar in $brightness', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      platform.invokeHandler = (_) async => wire.SourceResult(
        mangaPage: wire.MangaPage(
          mangas: [
            for (final title in ['作品一', '作品二', '作品三'])
              wire.Manga(title: title, url: '/$title'),
          ],
        ),
      );
      await show(tester, brightness: brightness);
      final first = tester.getRect(
        find.byKey(const ValueKey(('source-manga', '/作品一'))),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey(('source-manga', '/作品二'))),
      );
      final third = tester.getRect(
        find.byKey(const ValueKey(('source-manga', '/作品三'))),
      );
      final bar = tester.getRect(find.byType(CupertinoNavigationBar));
      expect(first.top - bar.center.dy, closeTo(93, 2));
      expect(first, Rect.fromLTWH(12, first.top, 162, 243));
      expect(second.left, 186);
      expect(third.top - first.top, 255);
      expect(find.byKey(const ValueKey('source-manga-search')), findsNothing);
      await hide(tester);
    });

    testWidgets(
      'source search preserves the displayed query on a short screen in $brightness',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 480);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        platform.invokeHandler = (_) async => page('原热门');
        await show(tester, brightness: brightness);

        final toggle = find.byKey(const ValueKey('source-search-toggle'));
        final field = find.byKey(const ValueKey('source-manga-search'));
        final submit = find.byKey(const ValueKey('source-search-submit'));
        final beforeSearch = platform.invocations.length;
        await tap(tester, 'source-search-toggle');
        expect(
          tester.widget<CupertinoTextField>(field).focusNode!.hasFocus,
          isTrue,
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        await tester.pumpAndSettle();
        expect(tester.getBottomRight(field).dy, lessThan(260));
        expect(tester.getBottomRight(submit).dy, lessThan(260));
        expect(tester.getSize(submit).width, greaterThanOrEqualTo(44));
        await tester.enterText(field, '只输入的草稿');
        expect(platform.invocations, hasLength(beforeSearch));
        await tap(tester, 'source-search-toggle');
        expect(field, findsNothing);
        expect(
          tester.widget<CupertinoButton>(toggle).focusNode!.hasFocus,
          isTrue,
        );
        expect(catalog.mangas.single.title, '原热门');
        expect(platform.invocations, hasLength(beforeSearch));

        await tap(tester, 'source-search-toggle');
        expect(
          tester.widget<CupertinoTextField>(field).controller!.text,
          isEmpty,
        );
        await tester.enterText(field, '已提交的关键词');
        platform.invokeHandler = (call) async {
          expect(call.search.query, '已提交的关键词');
          throw const RuntimeException(RuntimeErrorCode.sourceError, 'failed');
        };
        await tester.tap(submit);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(find.text('当前列表：热门'), findsOneWidget);
        expect(catalog.mangas.single.title, '原热门');
        await tester.enterText(field, '重试前输入的文字');
        platform.invokeHandler = (call) async {
          expect(call.search.query, '已提交的关键词');
          return page('搜索结果', more: false);
        };
        final retry = find.text('重试');
        await tester.ensureVisible(retry);
        await tester.pumpAndSettle();
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(catalog.mangas.single.title, '搜索结果');
        expect(catalog.query, '已提交的关键词');
        await tap(tester, 'source-search-toggle');
        expect(field, findsNothing);
        expect(find.text('当前查询：已提交的关键词'), findsOneWidget);
        expect(platform.invocations, hasLength(beforeSearch + 2));
        expect(tester.takeException(), isNull);
        await hide(tester);
      },
    );
  }

  testWidgets(
    'opening prepares the confirmed build without an account write and hides unsupported latest',
    (tester) async {
      platform.sourceInventory = [
        wire.SourceInfo(
          id: sourceId,
          name: '测试漫画源',
          lang: 'zh',
          supportsLatest: false,
        ),
      ];
      await show(tester);
      expect(platform.preparations, hasLength(1));
      expect(platform.openedBuilds, ['build-1']);
      expect(find.text(testManga.title), findsOneWidget);
      expect(find.widgetWithText(CupertinoButton, '最新'), findsNothing);
      expect(
        platform.businessServer.requests.where(
          (request) => request.method == 'POST',
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  for (final reduced in [false, true]) {
    testWidgets('details navigation bar follows reduced motion: $reduced', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(reduceMotion: reduced);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await show(tester);
      final title = find.text(testManga.title);
      final navigationBar = find.descendant(
        of: find.byType(MangaDetailsPage),
        matching: find.byType(CupertinoNavigationBar),
      );
      final navigationTitle = find.descendant(
        of: navigationBar,
        matching: title,
      );
      List<Rect> titleBoundsInHeader() {
        final header = tester.getRect(navigationBar);
        return title
            .evaluate()
            .map((element) {
              return tester.getRect(
                find.byElementPredicate((other) => identical(element, other)),
              );
            })
            .where((bounds) {
              return bounds.top >= header.top && bounds.bottom <= header.bottom;
            })
            .toList();
      }

      await tester.tap(title);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      final entering = titleBoundsInHeader();
      await tester.pumpAndSettle();
      final settled = tester.getRect(navigationTitle);
      expect(entering, reduced ? [settled] : hasLength(2));

      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(titleBoundsInHeader(), reduced ? [settled] : hasLength(2));
      await tester.pumpAndSettle();
      expect(find.byType(MangaDetailsPage), findsNothing);
      expect(find.byType(SourceBrowsePage), findsOneWidget);
      expect(platform.businessServer.appliedMutations, 0);
      expect(tester.takeException(), isNull);
      await hide(tester);
    });
  }

  testWidgets(
    'an occupied Source has a separate retry action that activates with Enter',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        platform.preparationFailure = wire.RuntimeError(
          code: wire.RuntimeErrorCode.RUNTIME_ERROR_CODE_STORAGE_BUSY,
          message: 'Source storage namespace is already in use',
        );
        await show(tester);
        expect(find.text('这个漫画源已在其他标签页或窗口运行，请先关闭后再连接'), findsOneWidget);
        final retry = find.text('重试');
        final action = tester.getSemantics(retry).getSemanticsData();
        expect(action.label, '重试');
        expect(action.hasAction(SemanticsAction.tap), isTrue);
        final section = find.ancestor(
          of: retry,
          matching: find.byType(CupertinoListSection),
        );
        expect(
          tester.widget<CupertinoListSection>(section).clipBehavior,
          Clip.none,
          reason:
              'The Cupertino action paints its focus outline outside the row.',
        );

        platform.preparationFailure = null;
        final focus = Focus.of(tester.element(retry));
        focus.requestFocus();
        await tester.pumpAndSettle();
        expect(focus.hasPrimaryFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(platform.preparations, hasLength(2));
        expect(platform.openedBuilds, ['build-1']);
        expect(find.text(testManga.title), findsOneWidget);
        expect(retry, findsNothing);
        expect(tester.takeException(), isNull);
        await hide(tester);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'typing does not search and failed new queries retain the previous labeled results',
    (tester) async {
      platform.invokeHandler = (_) async => page('原热门');
      await show(tester);
      final before = platform.invocations.length;
      await tap(tester, 'source-search-toggle');
      await tester.enterText(
        find.byKey(const ValueKey('source-manga-search')),
        '新关键词',
      );
      await tester.pumpAndSettle();
      expect(platform.invocations, hasLength(before));
      platform.invokeHandler = (_) async =>
          throw const RuntimeException(RuntimeErrorCode.sourceError, 'failed');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('原热门'), findsOneWidget);
      expect(find.text('新查询失败，仍显示原列表'), findsOneWidget);
      expect(catalog.query, '');
      platform.invokeHandler = (_) async => page('新结果', more: false);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('新结果'), findsOneWidget);
      expect(find.text('原热门'), findsNothing);
      expect(catalog.query, '新关键词');
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'append progress appears below the existing covers without moving them',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      platform.invokeHandler = (_) async => page('第一页');
      await show(tester);
      final load = find.byKey(const ValueKey('source-load-more'));
      await tester.ensureVisible(load);
      await tester.pumpAndSettle();
      final first = find.byKey(const ValueKey(('source-manga', '/第一页')));
      final initial = tester.getRect(first);
      final nextPage = Completer<wire.SourceResult>();
      platform.invokeHandler = (call) {
        expect(call.popular.page, 2);
        return nextPage.future;
      };
      try {
        await tester.tap(load);
        await tester.pump();
        final waiting = find.text('正在加载下一页');
        expect(waiting, findsOneWidget);
        expect(tester.getRect(first), initial);
        expect(tester.getTopLeft(waiting).dy, greaterThan(initial.bottom));
        expect(catalog.page, 1);
      } finally {
        nextPage.complete(page('第二页', more: false));
        await tester.pumpAndSettle();
      }
      expect(find.text('正在加载下一页'), findsNothing);
      expect(first, findsOneWidget);
      expect(find.text('第二页'), findsOneWidget);
      expect(catalog.page, 2);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'refresh and append failures preserve existing results and retry the correct page',
    (tester) async {
      platform.invokeHandler = (_) async => page('第一页');
      await show(tester);
      platform.invokeHandler = (_) async =>
          throw const RuntimeException(RuntimeErrorCode.sourceError, 'failed');
      await tap(tester, 'source-load-more');
      expect(find.text('第一页'), findsOneWidget);
      expect(find.text('下一页加载失败'), findsOneWidget);
      expect(catalog.page, 1);
      platform.invokeHandler = (call) async {
        expect(call.popular.page, 2);
        return page('第二页', more: false);
      };
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('第一页'), findsOneWidget);
      expect(find.text('第二页'), findsOneWidget);
      expect(find.text('全部加载完成'), findsOneWidget);
      platform.invokeHandler = (_) async =>
          throw const RuntimeException(RuntimeErrorCode.sourceError, 'failed');
      await tap(tester, 'source-refresh');
      expect(find.text('刷新失败，原作品仍可查看'), findsOneWidget);
      expect(find.text('第一页'), findsOneWidget);
      expect(find.text('第二页'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'empty successful results and initial failure have separate recovery states',
    (tester) async {
      platform.invokeHandler = (_) async =>
          throw const RuntimeException(RuntimeErrorCode.sourceError, 'failed');
      await show(tester);
      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('没有结果'), findsNothing);
      platform.invokeHandler = (_) async =>
          wire.SourceResult(mangaPage: wire.MangaPage());
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('没有结果'), findsOneWidget);
      expect(
        tester.getCenter(find.text('没有结果')).dy,
        closeTo(
          tester
              .getCenter(
                find.byKey(const PageStorageKey('source-manga-scroll')),
              )
              .dy,
          80,
        ),
      );
      expect(find.text('加载失败'), findsNothing);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'leaving during a query waits for cleanup and discards its late result',
    (tester) async {
      platform.invokeHandler = (_) async => page('原结果');
      await show(tester);
      final entered = Completer<void>(), release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      platform.invokeHandler = (_) async {
        entered.complete();
        await release.future;
        return page('迟到结果');
      };
      await tap(tester, 'source-search-toggle');
      await tester.enterText(
        find.byKey(const ValueKey('source-manga-search')),
        '迟到',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.runAsync(
        () => entered.future.timeout(const Duration(seconds: 5)),
      );
      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pump();
      expect(find.text('正在停止并收尾'), findsOneWidget);
      release.complete();
      await tester.pumpAndSettle();
      expect(find.text('打开源'), findsOneWidget);
      expect(catalog.mangas.single.title, '原结果');
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'leaving while details load waits and prevents late chapter requests or navigation',
    (tester) async {
      await show(tester);
      final entered = Completer<void>(), release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final callsBefore = platform.invocations.length;
      platform.invokeHandler = (call) async {
        expect(call.hasDetails(), isTrue);
        entered.complete();
        await release.future;
        return wire.SourceResult(manga: call.details.manga);
      };
      await tester.tap(find.text(testManga.title));
      await tester.pump();
      await tester.runAsync(
        () => entered.future.timeout(const Duration(seconds: 5)),
      );
      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pump();
      expect(find.text('正在停止并收尾'), findsOneWidget);
      release.complete();
      await tester.pumpAndSettle();
      expect(find.text('打开源'), findsOneWidget);
      expect(find.byType(SourceBrowsePage), findsNothing);
      expect(platform.invocations, hasLength(callsBefore + 1));
      expect(catalog.busy, isFalse);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );
}
