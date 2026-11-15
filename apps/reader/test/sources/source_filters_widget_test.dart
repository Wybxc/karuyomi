import '../../test_support/cupertino.dart';
import '../test_app.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/source_browse_page.dart';
import 'package:karuyomi/theme/app_theme.dart';
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

  Future<void> show(
    WidgetTester tester, {
    Brightness? brightness,
    double textScale = 1,
    Size size = const Size(480, 800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpApp(
      CupertinoApp(
        theme: readerAppTheme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: CupertinoPageScaffold(
          child: SourceBrowsePage(
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
    await tester.pumpApp(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final form = find.byKey(const ValueKey('source-filter-form'));
    final scrollable = find
        .descendant(
          of: form.evaluate().isEmpty ? find.byType(SourceBrowsePage) : form,
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
        tester
            .widget<CupertinoTextFormFieldRow>(control('text', '1'))
            .initialValue,
        '输入的作者',
      );
      await tester.enterText(control('text', '1'), '取消的作者');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(iconLabel('取消筛选编辑'));
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

  for (final brightness in Brightness.values) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'Cupertino filter sections preserve nested paths and drafts in $brightness at ${textScale}x',
        (tester) async {
          tester.platformDispatcher.platformBrightnessTestValue =
              brightness == Brightness.light
              ? Brightness.dark
              : Brightness.light;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          final description = filterSnapshot('nested-filters');
          description.nodes[6].group.nodes.addAll([
            wire.FilterNode(
              name: '嵌套分类',
              group: wire.FilterGroup(
                nodes: [
                  wire.FilterNode(
                    name: '包含长篇与特别篇',
                    checkBox: wire.FilterCheckBox(state: false),
                  ),
                ],
              ),
            ),
            wire.FilterNode(
              name: '保留后续条件',
              checkBox: wire.FilterCheckBox(state: false),
            ),
          ]);
          description.nodes.add(
            wire.FilterNode(name: '独立说明标题', header: wire.Empty()),
          );
          platform.invokeHandler = (call) async => call.hasGetFilters()
              ? wire.SourceResult(filters: description.deepCopy())
              : wire.SourceResult(
                  mangaPage: wire.MangaPage(mangas: [testManga]),
                );
          await show(
            tester,
            brightness: brightness,
            textScale: textScale,
            size: const Size(360, 800),
          );
          await tap(tester, open());
          final form = find.byKey(const ValueKey('source-filter-form'));
          final sections = find.descendant(
            of: form,
            matching: find.byType(CupertinoFormSection),
          );
          expect(sections, findsNWidgets(4));
          for (final section in sections.evaluate()) {
            expect(
              find.ancestor(
                of: find.byWidget(section.widget),
                matching: find.byType(CupertinoFormSection),
              ),
              findsNothing,
              reason: 'nested Source groups remain sibling Cupertino sections',
            );
          }
          final heading = tester.element(find.text('作品条件'));
          expect(DefaultTextStyle.of(heading).style.fontSize, 13);
          expect(
            DefaultTextStyle.of(heading).style.color,
            CupertinoColors.secondaryLabel.resolveFrom(heading),
          );
          final callsBefore = platform.invocations.length;
          await reveal(tester, control('text', '1'));
          final input = find.descendant(
            of: control('text', '1'),
            matching: find.byType(CupertinoTextField),
          );
          expect(
            tester.widget<CupertinoTextField>(input).autofillHints,
            isNull,
          );
          await tester.enterText(control('text', '1'), '新的检索草稿');
          expect(tester.testTextInput.setClientArgs!['autofill'], isNull);
          tester.testTextInput.hide();
          await tester.pumpAndSettle();
          await tap(tester, control('check', '6.1.0'));
          expect(
            tester.widget<CupertinoSwitch>(control('check', '6.1.0')).value,
            isTrue,
          );
          await reveal(tester, find.text('独立说明标题'));
          expect(platform.invocations, hasLength(callsBefore));
          expect(catalog.appliedSourceFilters, isNull);
          await tester.tap(apply());
          await tester.pumpAndSettle();
          final filters = platform.invocations.last.search.filters;
          expect(filters.snapshotId, 'nested-filters');
          expect(filters.updates.first.text, '新的检索草稿');
          expect(
            filters.updates
                .singleWhere((update) => update.path.join('.') == '6.1.0')
                .checkBox,
            isTrue,
          );
          expect(
            filters.updates
                .singleWhere((update) => update.path.join('.') == '6.2')
                .checkBox,
            isFalse,
          );
          expect(tester.takeException(), isNull);
          await hide(tester);
        },
      );
    }
  }

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
        tester
            .widget<CupertinoTextFormFieldRow>(control('text', '1'))
            .initialValue,
        '',
      );
      expect(catalog.appliedSourceFilters, applied);
      expect(catalog.query, '关键词');
      await tester.tap(iconLabel('取消筛选编辑'));
      await tester.pumpAndSettle();
      await tap(tester, find.byKey(const ValueKey('source-load-more')));
      expect(platform.invocations.last.search.page, 2);
      expect(platform.invocations.last.search.filters, applied);
      expect(platform.invocations.last.search.query, '关键词');
      expect(tester.takeException(), isNull);
      await hide(tester);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'filter loading and application show the active operation and retain a failed draft in $brightness',
      (tester) async {
        final loading = Completer<wire.SourceResult>();
        final applying = Completer<wire.SourceResult>();
        addTearDown(() {
          if (!loading.isCompleted) {
            loading.complete(
              wire.SourceResult(filters: filterSnapshot('busy')),
            );
          }
          if (!applying.isCompleted) {
            applying.complete(wire.SourceResult(mangaPage: wire.MangaPage()));
          }
        });
        platform.invokeHandler = (call) async => call.hasGetFilters()
            ? loading.future
            : wire.SourceResult(mangaPage: wire.MangaPage(mangas: [testManga]));
        await show(tester, brightness: brightness, size: const Size(360, 800));
        final writesBefore = platform.businessServer.requests
            .where((request) => request.method == 'POST')
            .length;
        await reveal(tester, open());
        await tester.tap(open());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('正在读取筛选条件'), findsOneWidget);
        expect(tester.widget<CupertinoButton>(apply()).onPressed, isNull);
        expect(tester.widget<CupertinoButton>(reset()).onPressed, isNull);
        loading.complete(wire.SourceResult(filters: filterSnapshot('busy')));
        await tester.pumpAndSettle();
        await reveal(tester, control('text', '1'));
        await tester.enterText(control('text', '1'), '保留的检索草稿');
        tester.testTextInput.hide();
        await tester.pumpAndSettle();
        platform.invokeHandler = (_) => applying.future;
        await tester.tap(apply());
        await tester.pump();
        expect(find.text('正在应用筛选条件'), findsOneWidget);
        expect(tester.widget<CupertinoButton>(apply()).onPressed, isNull);
        expect(tester.widget<CupertinoButton>(reset()).onPressed, isNull);
        final input = find.descendant(
          of: control('text', '1'),
          matching: find.byType(CupertinoTextField),
        );
        expect(tester.widget<CupertinoTextField>(input).enabled, isFalse);
        final originalFilters = platform.invocations.last.search.filters
            .deepCopy();
        applying.completeError(
          const RuntimeException(RuntimeErrorCode.sourceError, '检索暂时失败'),
        );
        await tester.pumpAndSettle();
        expect(catalog.appliedSourceFilters, isNull);
        expect(catalog.mangas.single.title, testManga.title);
        final error = find.text(catalog.error!);
        expect(
          tester.widget<Text>(error).style?.color,
          AppColors.error.resolveFrom(tester.element(error)),
        );
        expect(tester.widget<CupertinoTextField>(input).enabled, isTrue);
        platform.invokeHandler = (_) async =>
            wire.SourceResult(mangaPage: wire.MangaPage(mangas: [testManga]));
        await tester.tap(apply());
        await tester.pumpAndSettle();
        expect(platform.invocations.last.search.filters, originalFilters);
        expect(catalog.appliedSourceFilters!.updates.first.text, '保留的检索草稿');
        expect(find.text('筛选漫画'), findsNothing);
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
      'failed descriptors can retry without changing results; closing an executing reset cancels and retires its generation in $brightness',
      (tester) async {
        failDescription = true;
        await show(tester, brightness: brightness);
        await tap(tester, open());
        expect(find.text('重试加载筛选'), findsOneWidget);
        final error = find.text(catalog.sourceFilterError!);
        expect(
          tester.widget<Text>(error).style?.color,
          AppColors.error.resolveFrom(tester.element(error)),
        );
        expect(catalog.mangas.single.title, testManga.title);
        expect(catalog.listing, 'popular');
        failDescription = false;
        await tap(tester, find.text('重试加载筛选'));
        expect(control('text', '1'), findsOneWidget);
        final delayed = Completer<wire.SourceResult>();
        addTearDown(() {
          if (!delayed.isCompleted) {
            delayed.complete(
              wire.SourceResult(filters: filterSnapshot('late')),
            );
          }
        });
        platform.invokeHandler = (_) => delayed.future;
        await tester.tap(reset());
        await tester.pump();
        expect(find.text('正在重置筛选条件'), findsOneWidget);
        expect(find.text('关闭将取消请求，可能需要重新连接漫画源。'), findsOneWidget);
        final caption = tester.widget<Text>(find.text('关闭将取消请求，可能需要重新连接漫画源。'));
        expect(caption.style?.fontSize, 13);
        expect(
          caption.style?.color,
          AppColors.secondaryLabel.resolveFrom(tester.element(apply())),
        );
        expect(tester.widget<CupertinoButton>(apply()).onPressed, isNull);
        await tester.tap(iconLabel('取消请求并关闭筛选'));
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
}
