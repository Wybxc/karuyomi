import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/source_browse_page.dart';
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
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
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
    await tester.pumpWidget(const SizedBox());
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
      expect(find.widgetWithText(ChoiceChip, '最新'), findsNothing);
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

  testWidgets(
    'typing does not search and failed new queries retain the previous labeled results',
    (tester) async {
      platform.invokeHandler = (_) async => page('原热门');
      await show(tester);
      final before = platform.invocations.length;
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
      await tester.enterText(
        find.byKey(const ValueKey('source-manga-search')),
        '迟到',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.runAsync(
        () => entered.future.timeout(const Duration(seconds: 5)),
      );
      await tester.tap(find.byType(BackButton));
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
}
