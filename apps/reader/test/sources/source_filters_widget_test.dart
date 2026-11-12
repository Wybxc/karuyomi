import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/source_browse_page.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

import '../browse/fakes.dart';
import 'filter_fixtures.dart';

void main() {
  late TestPlatform platform;
  late CatalogController catalog;
  late TransportSourceRuntime runtime;
  var snapshotNumber = 0;
  var failDescription = false;

  setUp(() async {
    snapshotNumber = 0;
    failDescription = false;
    platform = TestPlatform()
      ..invokeHandler = (call) async {
        if (call.hasGetFilters()) {
          if (failDescription) {
            throw const RuntimeException(
              RuntimeErrorCode.sourceError,
              'filters failed',
            );
          }
          return wire.SourceResult(
            filters: filterSnapshot('snapshot-${++snapshotNumber}'),
          );
        }
        return wire.SourceResult(
          mangaPage: wire.MangaPage(mangas: [testManga], hasNextPage: true),
        );
      };
    runtime = TransportSourceRuntime(FilterRuntimeTransport(platform));
    catalog = CatalogController(
      api: platform,
      runtime: runtime,
      rebuildRuntime: () async {
        runtime.containerLost('Rebuilt filter test container');
        await platform.rebuild();
      },
      deploymentOrigin: platform.origin,
    );
    await catalog.connect();
    await catalog.openBuild(catalog.builds.single);
    await catalog.selectSource(catalog.session!.sources.single);
  });
  tearDown(() async {
    catalog.dispose();
    await catalog.closeReadingProgress();
    await runtime.dispose();
    await platform.dispose();
  });

  Finder control(String kind, String path) =>
      find.byKey(ValueKey(('source-filter-$kind', path)));
  Finder open() => find.byKey(const ValueKey('source-filters-open'));
  Finder apply() => find.byKey(const ValueKey('source-filter-apply'));
  Finder reset() => find.byKey(const ValueKey('source-filter-reset'));

  Future<void> show(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SourceBrowsePage(
            catalog: catalog,
            build: catalog.activeBuild!,
            source: catalog.activeBuild!.sources.single,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> hide(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final form = find.byKey(const ValueKey('source-filter-form'));
    final scrollable = find
        .descendant(
          of: form.evaluate().isEmpty ? find.byType(ListView).first : form,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(target, 220, scrollable: scrollable);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await reveal(tester, target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, Finder target, String value) async {
    await tap(tester, target);
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'all typed controls are drafts until empty-query application; reopening and cancelling preserve only applied values',
    (tester) async {
      await show(tester);
      await tap(tester, open());
      expect(find.text('作品条件'), findsOneWidget);
      expect(find.byType(Divider), findsWidgets);
      final callsBefore = platform.invocations.length;
      final writesBefore = platform.businessServer.requests
          .where((request) => request.method == 'POST')
          .length;
      await reveal(tester, control('text', '1'));
      await tester.enterText(control('text', '1'), '输入的作者');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tap(tester, control('check', '2'));
      await choose(tester, control('tri', '3'), '排除');
      await choose(tester, control('select', '4'), '完结');
      await choose(tester, control('sort', '5'), '作品名称');
      await tap(tester, control('ascending', '5'));
      await tap(tester, control('check', '6.0'));
      expect(platform.invocations, hasLength(callsBefore));
      expect(catalog.listing, 'popular');
      expect(catalog.appliedSourceFilters, isNull);
      expect(catalog.mangas.single.title, testManga.title);
      await tester.tap(apply());
      await tester.pumpAndSettle();
      final sent = platform.invocations.last;
      expect(sent.hasSearch(), true);
      expect(sent.search.query, '');
      expect(
        sent.search.filters,
        filterSelection(
          'snapshot-1',
          text: '输入的作者',
          check: true,
          tri: 2,
          select: 2,
          sortIndex: 1,
          ascending: true,
          nested: true,
        ),
      );
      expect(catalog.listing, 'search');
      expect(find.text('筛选（已应用）'), findsOneWidget);

      await tap(tester, open());
      expect(
        platform.invocations.where((call) => call.hasGetFilters()),
        hasLength(1),
      );
      await reveal(tester, control('text', '1'));
      expect(
        tester.widget<TextFormField>(control('text', '1')).initialValue,
        '输入的作者',
      );
      await tester.enterText(control('text', '1'), '取消的作者');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('取消筛选编辑'));
      await tester.pumpAndSettle();
      expect(catalog.appliedSourceFilters!.updates.first.text, '输入的作者');
      expect(platform.invocations, hasLength(callsBefore + 1));
      expect(
        platform.controlCommands,
        isNot(contains(wire.ControlRequest_Command.cancel)),
      );

      await tap(tester, open());
      await choose(tester, control('sort', '5'), '默认排序');
      await tester.tap(apply());
      await tester.pumpAndSettle();
      final clearedSort = platform.invocations.last.search.filters.updates[4];
      expect(clearedSort.whichState(), wire.FilterUpdate_State.sort);
      expect(clearedSort.sort.hasSelection(), false);
      expect(
        platform.businessServer.requests.where(
          (request) => request.method == 'POST',
        ),
        hasLength(writesBefore),
      );
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'reset gets a fresh draft while cancelled edits keep the retained applied snapshot for pagination',
    (tester) async {
      await catalog.loadSourceFilters();
      final applied = filterSelection('snapshot-1', text: '已应用');
      await catalog.applySourceFilters(applied, search: '关键词');
      await show(tester);
      await tap(tester, open());
      await tester.tap(reset());
      await tester.pumpAndSettle();
      expect(platform.invocations.last.hasGetFilters(), true);
      expect(
        platform.invocations.last.getFilters.retainedSnapshotId,
        'snapshot-1',
      );
      await reveal(tester, control('text', '1'));
      expect(
        tester.widget<TextFormField>(control('text', '1')).initialValue,
        '',
      );
      expect(catalog.appliedSourceFilters, applied);
      expect(catalog.query, '关键词');
      await tester.tap(find.byTooltip('取消筛选编辑'));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('source-load-more')));
      expect(platform.invocations.last.search.page, 2);
      expect(platform.invocations.last.search.filters, applied);
      expect(platform.invocations.last.search.query, '关键词');
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  testWidgets(
    'failed descriptors can retry without changing results; closing an executing reset cancels and retires its generation',
    (tester) async {
      failDescription = true;
      await show(tester);
      await tap(tester, open());
      expect(find.text('重试加载筛选'), findsOneWidget);
      expect(catalog.mangas.single.title, testManga.title);
      expect(catalog.listing, 'popular');
      failDescription = false;
      await tap(tester, find.text('重试加载筛选'));
      expect(control('text', '1'), findsOneWidget);
      final delayed = Completer<wire.SourceResult>();
      addTearDown(() {
        if (!delayed.isCompleted) {
          delayed.complete(wire.SourceResult(filters: filterSnapshot('late')));
        }
      });
      platform.invokeHandler = (_) => delayed.future;
      await tester.tap(reset());
      await tester.pump();
      expect(find.text('关闭将取消请求，可能需要重新连接漫画源。'), findsOneWidget);
      expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
      await tester.tap(find.byTooltip('取消请求并关闭筛选'));
      await tester.pump();
      expect(
        platform.controlCommands,
        contains(wire.ControlRequest_Command.cancel),
      );
      delayed.complete(wire.SourceResult(filters: filterSnapshot('late')));
      await tester.pumpAndSettle();
      expect(catalog.status, ServiceStatus.failed);
      expect(catalog.sourceFilterSnapshot, isNull);
      expect(catalog.appliedSourceFilters, isNull);
      expect(catalog.mangas, isEmpty);
      expect(find.text('运行容器已中断，请重新连接'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );
}
