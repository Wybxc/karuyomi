import '../test_app.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/browse/source_browse_page.dart';
import 'package:karuyomi/features/search/cross_source_search_page.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import '../browse/fakes.dart';
import 'fakes.dart';

void main() {
  Future<void> openPage(
    WidgetTester tester,
    FakeSourceSearch service, {
    OpenSourceSearchDetails? onOpen,
  }) async {
    await tester.pumpApp(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
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
    await tester.tap(
      find.byKey(ValueKey(('cross-search-source', service.targets.first.key))),
    );
    final query = find.byKey(const ValueKey('cross-search-query'));
    await tester.ensureVisible(query);
    await tester.enterText(query, '测试作品');
    final submit = find.byKey(const ValueKey('cross-search-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
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
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(CrossSourceSearchPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cross-search-cleanup-error')),
        findsOneWidget,
      );
      expect(find.textContaining('关闭未确认'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
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
            .widget<FilledButton>(
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
      MaterialApp(
        home: Scaffold(
          body: CatalogPage(
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
    expect(find.widgetWithText(ChoiceChip, '最新'), findsNothing);
    await tester.pumpApp(const SizedBox());
    catalog.dispose();
    await catalog.closeReadingProgress();
    await platform.dispose();
  });
}
