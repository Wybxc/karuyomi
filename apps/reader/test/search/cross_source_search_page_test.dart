import 'package:karuyomi/widgets/app_page_route.dart';

import '../test_app.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/browse/source_browse_page.dart';
import 'package:karuyomi/features/search/cross_source_search_page.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';
import 'fakes.dart';

void main() {
  Future<void> openPage(
    WidgetTester tester,
    FakeSourceSearch service, {
    OpenSourceSearchDetails? onOpen,
    Brightness? brightness,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await tester.pumpApp(
      CupertinoApp(
        theme: readerAppTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: Builder(
          builder: (context) => CupertinoPageScaffold(
            child: CupertinoButton(
              onPressed: () => Navigator.of(context).push<void>(
                AppPageRoute<void>(
                  builder: (_) => CrossSourceSearchPage(
                    service: service,
                    onOpen: onOpen ?? (_) async {},
                  ),
                ),
              ),
              child: const Text('开始'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();
  }

  Future<void> chooseAndSearch(
    WidgetTester tester,
    FakeSourceSearch service,
  ) async {
    final source = find.byKey(
      ValueKey(('cross-search-source', service.targets.first.key)),
    );
    await tester.ensureVisible(source);
    await tester.tap(source);
    final query = find.byKey(const ValueKey('cross-search-query'));
    await tester.ensureVisible(query);
    await tester.enterText(query, '测试作品');
    await tester.pumpAndSettle();
    final submit = find.byKey(const ValueKey('cross-search-submit'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pump();
  }

  for (final brightness in Brightness.values) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('mixed source states fit narrow $brightness at ${scale}x', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = FakeSourceSearch(
          targets: [searchTarget(1), searchTarget(2), searchTarget(3)],
        );
        await openPage(
          tester,
          service,
          brightness: brightness,
          textScaler: TextScaler.linear(scale),
        );
        for (final target in service.targets.skip(1)) {
          final source = find.byKey(
            ValueKey(('cross-search-source', target.key)),
          );
          await tester.ensureVisible(source);
          await tester.tap(source);
          await tester.pump();
        }
        await chooseAndSearch(tester, service);
        await tester.pump(const Duration(milliseconds: 400));
        expect(service.tasks, hasLength(3));
        expect(tester.takeException(), isNull);
        const title = '这是一个很长的漫画作品名称，显示在封面下方';
        service.tasks[0].complete([searchManga(title)], more: true);
        service.tasks[1].complete([]);
        service.tasks[2].fail('这个漫画源暂时不可用');
        await tester.pumpAndSettle();
        final result = find.byKey(
          ValueKey(('cross-search-result', service.targets[0].key, 0)),
        );
        await tester.ensureVisible(result);
        await tester.pumpAndSettle();
        final cover = find.descendant(
          of: result,
          matching: find.byType(AspectRatio),
        );
        expect(tester.getSize(result).width, 96);
        expect(tester.getSize(cover), const Size(88, 132));
        expect(
          tester.getTopLeft(find.text(title)).dy,
          greaterThan(tester.getBottomLeft(cover).dy),
        );
        final context = tester.element(result);
        expect(
          tester.widget<Text>(find.text(title)).style!.color,
          AppColors.label.resolveFrom(context),
        );
        await tester.tap(result);
        await tester.pumpAndSettle();
        expect(service.openedManga?.title, title);
        final empty = find.text('此漫画源没有找到漫画。');
        await tester.ensureVisible(empty);
        await tester.pumpAndSettle();
        expect(empty, findsOneWidget);
        final failure = find.byKey(
          ValueKey(('cross-search-error', service.targets[2].key)),
        );
        await tester.ensureVisible(failure);
        await tester.pumpAndSettle();
        expect(
          tester.widget<Text>(failure).style!.color,
          AppColors.error.resolveFrom(tester.element(failure)),
        );
        final retry = find.byKey(
          ValueKey(('cross-search-more', service.targets[2].key)),
        );
        await tester.ensureVisible(retry);
        await tester.pumpAndSettle();
        expect(tester.widget<CupertinoButton>(retry).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox());
        await tester.pump();
      });
    }
  }

  testWidgets(
    'explicit selection, per-Source paging and exact result opening',
    (tester) async {
      final service = FakeSourceSearch();
      var opened = 0;
      await openPage(
        tester,
        service,
        onOpen: (details) async {
          ++opened;
          expect(details.source.sourceId, service.targets.first.source.id);
          expect(details.manga.title, '第一页作品');
        },
      );
      expect(service.loads, 1);
      expect(service.tasks, isEmpty);
      expect(find.text('选择漫画源（已选 0 / 32）'), findsOneWidget);
      await chooseAndSearch(tester, service);
      expect(service.tasks.single.query, '测试作品');
      service.tasks.single.complete([searchManga('第一页作品')], more: true);
      await tester.pumpAndSettle();
      final more = find.byKey(
        ValueKey(('cross-search-more', service.targets.first.key)),
      );
      await tester.scrollUntilVisible(
        more,
        180,
        scrollable: find
            .descendant(
              of: find.byType(CrossSourceSearchPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pump();
      expect(service.tasks.last.page, 2);
      service.tasks.last.fail('下一页暂时失败');
      await tester.pumpAndSettle();
      expect(find.text('下一页暂时失败'), findsOneWidget);
      expect(find.text('第一页作品'), findsOneWidget);
      final result = find.byKey(
        ValueKey(('cross-search-result', service.targets.first.key, 0)),
      );
      await tester.ensureVisible(result);
      await tester.pumpAndSettle();
      await tester.tap(result);
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(service.openedTarget, same(service.targets.first));
      await tester.pumpApp(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'back waits for confirmed cleanup and exposes a retry on failure',
    (tester) async {
      final service = FakeSourceSearch();
      var attempts = 0;
      service.beforeClose = () async {
        if (++attempts == 1) throw const FormatException('关闭未确认');
      };
      await openPage(tester, service);
      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pumpAndSettle();
      expect(find.byType(CrossSourceSearchPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cross-search-cleanup-error')),
        findsOneWidget,
      );
      expect(find.textContaining('关闭未确认'), findsOneWidget);
      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pumpAndSettle();
      expect(find.byType(CrossSourceSearchPage), findsNothing);
      expect(find.text('开始'), findsOneWidget);
    },
  );

  testWidgets(
    'retirement before first frame never loads or searches new identity',
    (tester) async {
      final service = FakeSourceSearch();
      service.changeAvailability(false);
      await openPage(tester, service);
      expect(service.loads, 0);
      expect(service.tasks, isEmpty);
      expect(
        find.byKey(const ValueKey('cross-search-unavailable')),
        findsOneWidget,
      );
      service.changeAvailability(true);
      await tester.pump();
      expect(
        tester
            .widget<CupertinoButton>(
              find.byKey(const ValueKey('cross-search-submit')),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpApp(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'backgrounding cancels active searches without replay on resume',
    (tester) async {
      final service = FakeSourceSearch();
      await openPage(tester, service);
      await chooseAndSearch(tester, service);
      final before = service.stops;
      setAppLifecycleState(tester.binding, AppLifecycleState.inactive);
      setAppLifecycleState(tester.binding, AppLifecycleState.hidden);
      setAppLifecycleState(tester.binding, AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(service.stops, before + 1);
      expect(service.tasks.single.cancelCalls, 1);
      setAppLifecycleState(tester.binding, AppLifecycleState.hidden);
      setAppLifecycleState(tester.binding, AppLifecycleState.inactive);
      setAppLifecycleState(tester.binding, AppLifecycleState.resumed);
      await tester.pump();
      expect(service.tasks, hasLength(1));
      await tester.pumpApp(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('the browse entry and latest capability hint use runtime facts', (
    tester,
  ) async {
    final platform = TestPlatform();
    platform.sourceInventory = [
      wire.SourceInfo(
        id: sourceId,
        name: '测试漫画源',
        lang: 'zh',
        supportsLatest: false,
      ),
    ];
    final catalog = CatalogController(
      api: platform,
      runtime: platform.runtime,
      rebuildRuntime: platform.rebuild,
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
    await catalog.openBuild(catalog.builds.single);
    await catalog.selectSource(catalog.session!.sources.single);
    await tester.pumpApp(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: CatalogPage(
            controller: catalog,
            onConnect: () {},
            onAuthenticate: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('cross-source-search-open')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        const ValueKey((
          'source-directory-row',
          'eu.kanade.source.test',
          sourceId,
        )),
      ),
    );
    await tester.pumpAndSettle();
    final hint = find.byKey(const ValueKey('source-query-context'));
    await tester.scrollUntilVisible(
      hint,
      200,
      scrollable: find
          .descendant(
            of: find.byType(SourceBrowsePage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(hint, findsOneWidget);
    expect(find.widgetWithText(CupertinoButton, '最新'), findsNothing);
    await tester.pumpApp(const SizedBox());
    catalog.dispose();
    await catalog.closeReadingProgress();
    await platform.dispose();
  });
}
