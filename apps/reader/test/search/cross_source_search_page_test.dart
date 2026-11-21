import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:karuyomi/widgets/app_routes.dart';

import '../test_app.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/browse/catalog_controller.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/browse/source_browse_page.dart';
import 'package:karuyomi/features/extensions/extensions_page.dart';
import 'package:karuyomi/features/search/cross_source_search_page.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'package:source_runtime/source_runtime.dart';

import '../browse/fakes.dart';
import 'fakes.dart';

final class _NonlinearTextScaler extends TextScaler {
  const _NonlinearTextScaler();

  @override
  double scale(double fontSize) => fontSize * (fontSize <= 14 ? 2 : 1.5);

  @override
  double get textScaleFactor => 2;
}

void main() {
  Future<void> openPage(
    WidgetTester tester,
    FakeSourceSearch service, {
    OpenSourceSearchDetails? onOpen,
    ValueChanged<bool?>? onExit,
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
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  AppPageRoute<bool>(
                    builder: (_) => CrossSourceSearchPage(
                      service: service,
                      onOpen: onOpen ?? (_) async {},
                    ),
                  ),
                );
                onExit?.call(result);
              },
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
    testWidgets(
      'no available Source opens extension management in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final platform = TestPlatform(seedDefaultInstallation: false);
        final catalog = CatalogController(
          api: platform,
          runtime: platform.runtime,
          rebuildRuntime: platform.rebuild,
          deploymentOrigin: platform.origin,
        );
        try {
          await catalog.connect();
          await tester.pumpApp(
            CupertinoApp(
              theme: readerAppTheme(brightness),
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
          await tester.tap(
            find.byKey(const ValueKey('cross-source-search-open')),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('没有可选漫画源'), findsOneWidget);
          final submit = find.byKey(const ValueKey('cross-search-submit'));
          final refresh = find.byKey(const ValueKey('cross-search-refresh'));
          final disabledSubmit = tester.widget<CupertinoButton>(submit);
          expect(disabledSubmit.enabled, isFalse);
          expect(
            disabledSubmit.foregroundColor,
            CupertinoColors.tertiaryLabel.resolveFrom(tester.element(submit)),
          );
          expect(
            tester
                .getSemantics(submit)
                .getSemanticsData()
                .flagsCollection
                .isEnabled,
            Tristate.isFalse,
          );
          expect(tester.widget<CupertinoButton>(refresh).enabled, isTrue);
          final manage = find.widgetWithText(CupertinoButton, '打开扩展管理');
          expect(manage, findsOneWidget);
          await tester.ensureVisible(manage);
          await tester.tap(manage);
          await tester.pump();
          // The real search service cancels transport subscriptions before pop.
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();

          expect(find.byType(CrossSourceSearchPage), findsNothing);
          expect(find.byType(ExtensionsPage), findsOneWidget);
          expect(platform.openedBuilds, isEmpty);
          expect(
            platform.businessServer.requests.where(
              (request) => request.method == 'POST',
            ),
            isEmpty,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpApp(const SizedBox());
          await tester.pump();
          catalog.dispose();
          await catalog.closeReadingProgress();
          await platform.dispose();
        }
      },
    );

    testWidgets(
      'search controls stay in reach while choosing from a long list in $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(360, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final service = FakeSourceSearch(
          targets: [for (var i = 1; i <= 56; i++) searchTarget(i)],
        );
        await openPage(
          tester,
          service,
          brightness: brightness,
          textScaler: TextScaler.linear(2),
        );
        final query = find.byKey(const ValueKey('cross-search-query'));
        final submit = find.byKey(const ValueKey('cross-search-submit'));
        final refresh = find.byKey(const ValueKey('cross-search-refresh'));
        final stop = find.byKey(const ValueKey('cross-search-stop'));
        final scope = find.byKey(const ValueKey('cross-search-scope-toggle'));
        final selected = service.targets[24];
        final checkbox = find.byKey(
          ValueKey(('cross-search-source', selected.key)),
        );
        expect(submit.hitTestable(), findsOneWidget);
        expect(refresh.hitTestable(), findsOneWidget);
        final initialQueryTop = tester.getTopLeft(query);
        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        expect(checkbox.hitTestable(), findsOneWidget);
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
        expect(scope.hitTestable(), findsNothing);
        expect(tester.getTopLeft(query), initialQueryTop);
        expect(submit.hitTestable(), findsOneWidget);
        expect(service.tasks, isEmpty);

        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('cross-search-error')).hitTestable(),
          findsOneWidget,
        );
        expect(service.tasks, isEmpty);

        await tester.enterText(query, '  远处的作品  ');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pump(const Duration(milliseconds: 400));
        final task = service.tasks.single;
        expect(task.target.key, selected.key);
        expect(task.query, '远处的作品');
        expect(stop.hitTestable(), findsOneWidget);
        expect(scope.hitTestable(), findsOneWidget);
        expect(
          tester
              .getSemantics(scope)
              .getSemanticsData()
              .flagsCollection
              .isExpanded,
          Tristate.isFalse,
        );

        task.complete([]);
        await tester.pumpAndSettle();
        expect(
          find
              .byKey(const ValueKey('cross-search-results-heading'))
              .hitTestable(),
          findsOneWidget,
        );
        expect(find.text('此漫画源没有找到漫画。'), findsOneWidget);
        await tester.tap(scope);
        await tester.pumpAndSettle();
        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        expect(checkbox.hitTestable(), findsOneWidget);
        expect(tester.widget<CupertinoCheckbox>(checkbox).value, isTrue);
        expect(tester.takeException(), isNull);
      },
    );

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'source scope uses native sections, complete names and whole-row selection in $brightness at $scale',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final original = searchTarget(1);
          final name = '完整漫画源名称与备用站点' * 5;
          final target = SourceSearchTarget(
            build: original.build,
            source: original.source.deepCopy()..name = name,
            bundleSha256: original.bundleSha256,
          );
          final service = FakeSourceSearch(targets: [target, searchTarget(2)]);
          await openPage(
            tester,
            service,
            brightness: brightness,
            textScaler: TextScaler.linear(scale),
          );
          final checkbox = find.byKey(
            ValueKey(('cross-search-source', target.key)),
          );
          expect(
            find.ancestor(
              of: checkbox,
              matching: find.byType(CupertinoFormSection),
            ),
            findsOneWidget,
          );
          final caption = tester.element(
            find.text('仅列出已安装、启用且来源仍有效的漫画源；最多选择32个。'),
          );
          expect(DefaultTextStyle.of(caption).style.fontSize, 13);
          expect(
            DefaultTextStyle.of(caption).style.color,
            AppColors.secondaryLabel.resolveFrom(caption),
          );
          final label = find.text(name);
          expect(
            tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
            isFalse,
          );
          await tester.ensureVisible(label);
          await tester.tap(label);
          await tester.pumpAndSettle();
          expect(tester.widget<CupertinoCheckbox>(checkbox).value, isTrue);
          expect(find.text('选择漫画源（已选 1 / 32）'), findsOneWidget);
          expect(service.tasks, isEmpty);
          final semantics = tester.ensureSemantics();
          await tester.pump();
          try {
            final spoken = tester.getSemantics(checkbox).label;
            expect(spoken, contains(name));
            expect(spoken, isNot(contains('仅列出已安装')));
            expect(spoken, isNot(contains('选择漫画源')));
          } finally {
            semantics.dispose();
          }
          final filter = find.byKey(
            const ValueKey('cross-search-source-filter'),
          );
          await tester.ensureVisible(filter);
          await tester.enterText(filter, '没有匹配的来源');
          await tester.pumpAndSettle();
          expect(find.text('没有符合筛选条件的漫画源。'), findsOneWidget);
          expect(find.text('选择漫画源（已选 1 / 32）'), findsOneWidget);
          await tester.enterText(filter, '');
          await tester.pumpAndSettle();
          expect(tester.widget<CupertinoCheckbox>(checkbox).value, isTrue);
          Key? focusedCheckbox() => FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<CupertinoCheckbox>()
              ?.key;
          for (
            var attempt = 0;
            attempt < 16 && focusedCheckbox() != tester.widget(checkbox).key;
            attempt++
          ) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
          }
          expect(focusedCheckbox(), tester.widget(checkbox).key);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(tester.widget<CupertinoCheckbox>(checkbox).value, isFalse);
          expect(service.tasks, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
      testWidgets(
        'search validation and cleanup failures keep native error roles in $brightness at $scale',
        (tester) async {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final service = FakeSourceSearch();
          var closes = 0;
          service.beforeClose = () async {
            if (++closes == 1) throw const FormatException('关闭未确认，请明确重试');
          };
          await openPage(
            tester,
            service,
            brightness: brightness,
            textScaler: TextScaler.linear(scale),
          );
          final submit = find.byKey(const ValueKey('cross-search-submit'));
          await tester.ensureVisible(submit);
          await tester.pumpAndSettle();
          await tester.tap(submit);
          await tester.pumpAndSettle();
          final validation = find.byKey(const ValueKey('cross-search-error'));
          expect(
            tester.widget<Text>(validation).style?.color,
            AppColors.error.resolveFrom(tester.element(validation)),
          );
          expect(service.tasks, isEmpty);
          await tester.tap(find.byType(CupertinoNavigationBarBackButton));
          await tester.pumpAndSettle();
          final cleanup = find.byKey(
            const ValueKey('cross-search-cleanup-error'),
          );
          expect(
            tester.widget<Text>(cleanup).style?.color,
            AppColors.error.resolveFrom(tester.element(cleanup)),
          );
          expect(
            find.ancestor(
              of: cleanup,
              matching: find.byType(CupertinoFormSection),
            ),
            findsOneWidget,
          );
          final retry = find.byKey(
            const ValueKey('cross-search-cleanup-retry'),
          );
          await tester.ensureVisible(retry);
          expect(retry.hitTestable(), findsOneWidget);
          expect(service.tasks, isEmpty);
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(find.byType(CrossSourceSearchPage), findsNothing);
          expect(closes, 2);
          expect(tester.takeException(), isNull);
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
    testWidgets(
      'search waits for the same stop acknowledgement in $brightness',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = FakeSourceSearch();
        final stopReply = Completer<void>();
        try {
          await openPage(tester, service, brightness: brightness);
          await chooseAndSearch(tester, service);
          await tester.pump(const Duration(milliseconds: 400));
          final task = service.tasks.single;
          task.beforeCancel = () async {
            if (task.cancelCalls == 1) await stopReply.future;
          };
          final stop = find.byKey(
            ValueKey(('cross-search-cancel', task.target.key)),
          );
          final submit = find.byKey(const ValueKey('cross-search-submit'));
          await tester.ensureVisible(stop);
          await tester.tap(stop);
          await tester.pump();
          expect(find.textContaining('正在停止'), findsOneWidget);
          expect(tester.widget<CupertinoButton>(submit).enabled, isFalse);

          stopReply.completeError(const FormatException('停止确认丢失'));
          await tester.pumpAndSettle();
          expect(find.textContaining('停止确认丢失'), findsOneWidget);
          expect(tester.widget<CupertinoButton>(submit).enabled, isFalse);
          expect(service.tasks, [task]);
          final retry = find.byKey(
            ValueKey(('cross-search-cancel-retry', task.target.key)),
          );
          await tester.ensureVisible(retry);
          await tester.tap(retry);
          await tester.pumpAndSettle();
          expect(task.cancelCalls, 2);
          expect(service.tasks, [task]);
          expect(tester.widget<CupertinoButton>(submit).enabled, isTrue);
          expect(find.textContaining('已停止'), findsOneWidget);
        } finally {
          if (!stopReply.isCompleted) stopReply.complete();
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets(
      'opening keeps the exact work above the results until ready in $brightness',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final service = FakeSourceSearch();
        final releaseStop = Completer<void>();
        final releaseOpen = Completer<void>();
        MangaEntry? opened;
        try {
          await openPage(
            tester,
            service,
            brightness: brightness,
            textScaler: const _NonlinearTextScaler(),
            onOpen: (details) async {
              opened = details.manga;
            },
          );
          await chooseAndSearch(tester, service);
          final task = service.tasks.single;
          final work = searchManga('保持精确身份的长篇作品名称');
          task.complete([work]);
          await tester.pumpAndSettle();
          final result = find.byKey(
            ValueKey(('cross-search-result', task.target.key, 0)),
          );
          service.beforeStop = () => releaseStop.future;
          service.beforeOpen = () => releaseOpen.future;
          await tester.ensureVisible(result);
          await tester.tap(result);
          await tester.pump();

          final status = find.byKey(const ValueKey('cross-search-opening'));
          expect(status.hitTestable(), findsOneWidget);
          expect(
            find.ancestor(of: status, matching: find.byType(Scrollable)),
            findsNothing,
          );
          expect(
            find.descendant(of: status, matching: find.text(work.title)),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: status,
              matching: find.text(task.target.source.name),
            ),
            findsOneWidget,
          );
          expect(tester.widget<CupertinoButton>(result).enabled, isFalse);
          final disabledResult = tester.getSemantics(result).getSemanticsData();
          expect(disabledResult.flagsCollection.isEnabled, Tristate.isFalse);
          expect(disabledResult.label, work.title);
          expect(opened, isNull);

          releaseStop.complete();
          await tester.pump();
          expect(status, findsOneWidget);
          expect(service.openedTarget, same(task.target));
          expect(opened, isNull);

          releaseOpen.complete();
          await tester.pumpAndSettle();
          expect(status, findsNothing);
          expect(opened, same(work));
          expect(result, findsOneWidget);
          expect(
            tester
                .getSemantics(result)
                .getSemanticsData()
                .flagsCollection
                .isEnabled,
            Tristate.isTrue,
          );
          final heading = find.byKey(
            const ValueKey('cross-search-results-heading'),
          );
          expect(tester.widget<Text>(heading).data, contains('测试作品'));
        } finally {
          if (!releaseStop.isCompleted) releaseStop.complete();
          if (!releaseOpen.isCompleted) releaseOpen.complete();
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets('search scope opens and closes by keyboard in $brightness', (
      tester,
    ) async {
      final service = FakeSourceSearch();
      await openPage(tester, service, brightness: brightness);
      final option = find.byKey(
        ValueKey(('cross-search-source', service.targets.first.key)),
      );
      expect(option.hitTestable(), findsOneWidget);
      const key = ValueKey('cross-search-scope-toggle');
      Key? focusedButton() => FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<CupertinoButton>()
          ?.key;
      for (var attempt = 0; attempt < 12 && focusedButton() != key; attempt++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focusedButton(), key);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(option.hitTestable(), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(option.hitTestable(), findsOneWidget);
      expect(service.tasks, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('long source failure keeps retry reachable in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeSourceSearch();
      await openPage(tester, service, brightness: brightness);
      final second = service.targets.last;
      await tester.tap(
        find.byKey(ValueKey(('cross-search-source', second.key))),
      );
      await chooseAndSearch(tester, service);
      service.tasks.first.complete([]);
      final diagnostic =
          'HTTP error 500\n${List.generate(100, (i) => 'at source frame $i').join('\n')}';
      final failure = RuntimeException(
        RuntimeErrorCode.sourceError,
        diagnostic,
      );
      service.tasks.last.completion.completeError(failure);
      await tester.pumpAndSettle();
      final retry = find.byKey(ValueKey(('cross-search-more', second.key)));
      expect(find.text('漫画源请求失败，请重试。'), findsOneWidget);
      expect(find.text(failure.toString()), findsNothing);
      expect(tester.getBottomRight(retry).dy, lessThanOrEqualTo(800));
      expect(tester.getSemantics(retry).getSemanticsData().label, '重试此源');
      final details = find.byKey(
        ValueKey(('cross-search-error-details', second.key)),
      );
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(find.text(failure.toString()), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(service.tasks, hasLength(2));
      await tester.tap(retry);
      await tester.pump();
      expect(service.tasks, hasLength(3));
      expect(service.tasks.last.target.key, second.key);
      expect(service.tasks.last.query, '测试作品');
      expect(service.tasks.last.page, 1);
      expect(find.text('错误详情'), findsNothing);
      expect(find.text('此漫画源没有找到漫画。'), findsOneWidget);
      service.tasks.last.complete([]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpApp(const SizedBox());
      await tester.pump();
    });

    for (final (label, scaler) in [
      ('1x', TextScaler.noScaling),
      ('2x', TextScaler.linear(2)),
      ('nonlinear', const _NonlinearTextScaler()),
    ]) {
      testWidgets('mixed source states fit narrow $brightness at $label', (
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
          textScaler: scaler,
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
      final firstClose = Completer<void>();
      var attempts = 0;
      service.beforeClose = () async {
        if (++attempts == 1) await firstClose.future;
      };
      try {
        await openPage(tester, service);
        await chooseAndSearch(tester, service);
        await tester.pump(const Duration(milliseconds: 400));
        final back = find.byType(CupertinoNavigationBarBackButton);
        await tester.tap(back);
        await tester.pump();
        expect(find.text('正在释放搜索资源'), findsOneWidget);
        expect(find.textContaining('正在停止'), findsOneWidget);
        expect(find.textContaining('正在搜索'), findsNothing);
        expect(find.widgetWithText(CupertinoButton, '停止此源'), findsNothing);

        firstClose.completeError(const FormatException('关闭未确认'));
        await tester.pumpAndSettle();
        expect(find.byType(CrossSourceSearchPage), findsOneWidget);
        expect(
          find.byKey(const ValueKey('cross-search-cleanup-error')),
          findsOneWidget,
        );
        expect(find.text('关闭未确认'), findsOneWidget);
        expect(find.textContaining('停止尚未确认'), findsOneWidget);
        expect(find.widgetWithText(CupertinoButton, '重试停止'), findsNothing);
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.byType(CrossSourceSearchPage), findsNothing);
        expect(find.text('开始'), findsOneWidget);
      } finally {
        if (!firstClose.isCompleted) firstClose.complete();
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('retrying exit cleanup keeps the extension destination', (
    tester,
  ) async {
    final service = FakeSourceSearch(targets: const []);
    service.beforeClose = () async {
      if (service.closes == 1) throw const FormatException('关闭未确认');
    };
    bool? destination;
    await openPage(tester, service, onExit: (result) => destination = result);
    final manage = find.widgetWithText(CupertinoButton, '打开扩展管理');
    await tester.ensureVisible(manage);
    await tester.tap(manage);
    await tester.pumpAndSettle();
    expect(service.closes, 1);
    expect(destination, isNull);

    setAppLifecycleState(tester.binding, AppLifecycleState.inactive);
    await tester.pump();
    expect(service.stops, 0);
    setAppLifecycleState(tester.binding, AppLifecycleState.resumed);
    await tester.pump();
    final retry = find.byKey(const ValueKey('cross-search-cleanup-retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(service.closes, 2);
    expect(service.stops, 1);
    expect(destination, isTrue);
    expect(find.byType(CrossSourceSearchPage), findsNothing);
  });

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
    'retirement hides previous results and waits for an explicit release retry',
    (tester) async {
      final service = FakeSourceSearch();
      final retry = Completer<void>();
      var returned = false;
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      try {
        await openPage(
          tester,
          service,
          textScaler: TextScaler.linear(2),
          brightness: Brightness.dark,
          onExit: (value) => returned = value == false,
        );
        await chooseAndSearch(tester, service);
        service.tasks.single.complete([searchManga('上一会话的作品')]);
        await tester.pumpAndSettle();
        expect(find.text('上一会话的作品'), findsOneWidget);

        const reason = '访问验证已失效，请重新登录。';
        service.reportRetirement((
          reason: reason,
          releasing: true,
          releaseError: null,
        ));
        await tester.pump();
        final back = find.byType(CupertinoNavigationBarBackButton);
        final releaseRetry = find.byKey(
          const ValueKey('cross-search-cleanup-retry'),
        );
        expect(find.text('正在释放搜索资源').hitTestable(), findsOneWidget);
        expect(find.text('上一会话的作品'), findsNothing);
        expect(find.byKey(const ValueKey('cross-search-query')), findsNothing);
        expect(find.byKey(const ValueKey('cross-search-submit')), findsNothing);
        expect(releaseRetry, findsNothing);
        expect(
          tester
              .getSemantics(back)
              .getSemanticsData()
              .flagsCollection
              .isEnabled,
          Tristate.isFalse,
        );

        service.reportRetirement((
          reason: reason,
          releasing: false,
          releaseError: '搜索资源尚未确认关闭。',
        ));
        await tester.pumpAndSettle();
        expect(find.text(reason), findsOneWidget);
        expect(find.text('搜索资源尚未确认关闭。'), findsOneWidget);
        expect(releaseRetry.hitTestable(), findsOneWidget);
        final stops = service.stops;
        setAppLifecycleState(tester.binding, AppLifecycleState.inactive);
        await tester.pump();
        setAppLifecycleState(tester.binding, AppLifecycleState.resumed);
        await tester.pump();
        expect(service.stops, stops);
        expect(service.closes, 0);

        service.beforeClose = () => retry.future;
        await tester.tap(releaseRetry);
        await tester.pump();
        expect(find.text('正在释放搜索资源'), findsOneWidget);
        expect(releaseRetry, findsNothing);
        expect(service.closes, 1);
        expect(returned, false);
        retry.complete();
        await tester.pumpAndSettle();
        expect(returned, true);
        expect(service.tasks, hasLength(1));
        expect(find.byType(CrossSourceSearchPage), findsNothing);
      } finally {
        if (!retry.isCompleted) retry.complete();
        semantics.dispose();
        await tester.pumpApp(const SizedBox());
        await tester.pump();
      }
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
