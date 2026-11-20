import '../test_support/cupertino.dart';

import 'package:karuyomi/widgets/app_routes.dart';
import 'package:karuyomi/widgets/choice_field.dart';

import 'test_app.dart';

import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/diagnostics/reader_baseline.dart';
import 'package:karuyomi/diagnostics/reader_baseline_host.dart';
import 'package:karuyomi/features/browse/manga_details_page.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/browse/source_browse_page.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:source_runtime/control_protocol.dart' as wire;

import 'browse/fakes.dart';

Future<void> _browseDetails(WidgetTester tester) async {
  await tester.tap(find.text('去浏览'));
  await tester.pumpAndSettle();
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
  await tester.tap(find.text('真实源 DTO 测试'));
  await tester.pumpAndSettle();
}

void main() {
  for (final key in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  ]) {
    testWidgets('app buttons activate with Web ${key.keyLabel}', (
      tester,
    ) async {
      await tester.pumpApp(const KaruyomiApp());
      await tester.pumpAndSettle();
      final shortcuts = tester
          .widget<CupertinoApp>(find.byType(CupertinoApp))
          .shortcuts;
      var first = 0;
      var second = 0;
      const input = ValueKey('shortcut-input');
      const secondButton = ValueKey('shortcut-second');
      await tester.pumpApp(
        CupertinoApp(
          shortcuts: {
            ...WidgetsApp.defaultShortcuts,
            const SingleActivator(LogicalKeyboardKey.enter):
                const ButtonActivateIntent(),
            const SingleActivator(LogicalKeyboardKey.numpadEnter):
                const ButtonActivateIntent(),
            ...?shortcuts,
          },
          home: CupertinoPageScaffold(
            child: Column(
              children: [
                CupertinoButton(
                  autofocus: true,
                  onPressed: () => first++,
                  child: const Text('第一个操作'),
                ),
                const CupertinoTextField(key: input),
                const CupertinoButton(onPressed: null, child: Text('不可用操作')),
                CupertinoButton(
                  key: secondButton,
                  onPressed: () => second++,
                  child: const Text('第二个操作'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(first, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.enterText(find.byKey(input), '草稿');
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(
        first,
        1,
        reason: 'text input does not activate an unrelated button',
      );
      expect(second, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<CupertinoButton>()
            ?.key,
        secondButton,
      );
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
      expect(second, 1);
      expect(tester.takeException(), isNull);
    });
  }

  for (final disableAnimations in [false, true]) {
    testWidgets(
      'reduced motion keeps pages stationary (disabled: $disableAnimations)',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(
              reduceMotion: true,
              disableAnimations: disableAnimations,
            );
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpApp(const KaruyomiApp());
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(AppShell));
        expect(MediaQuery.reduceMotionOf(context), true);
        expect(MediaQuery.disableAnimationsOf(context), disableAnimations);
        const pageKey = ValueKey('motion-test-page');
        final navigator = Navigator.of(context);
        final route = AppPageRoute<void>(
          builder: (_) => const SizedBox.expand(key: pageKey),
        );
        unawaited(navigator.push<void>(route));
        await tester.pump();
        if (disableAnimations) {
          expect(route.animation!.status, AnimationStatus.completed);
        }
        await tester.pump(const Duration(milliseconds: 60));
        final page = find.byKey(pageKey, skipOffstage: false);
        expect(tester.getTopLeft(page), Offset.zero);
        final fades = tester.widgetList<FadeTransition>(
          find.ancestor(of: page, matching: find.byType(FadeTransition)),
        );
        if (disableAnimations) {
          expect(fades, isEmpty);
        } else {
          expect(
            fades.any(
              (fade) => fade.opacity.value > 0 && fade.opacity.value < 1,
            ),
            true,
          );
        }
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(page), Offset.zero);
        if (disableAnimations) {
          navigator.pop();
          await tester.pump();
          expect(page, findsNothing);
        } else {
          final bounds = tester.getRect(page);
          final gesture = await tester.startGesture(
            Offset(bounds.left + 1, bounds.center.dy),
          );
          try {
            await gesture.moveBy(const Offset(30, 0));
            await tester.pump();
            await gesture.moveBy(Offset(bounds.width * 0.6, 0));
            await tester.pump();
            expect(route.popGestureInProgress, isTrue);
            expect(tester.getTopLeft(page), Offset.zero);
            expect(route.animation!.value, lessThan(1));
          } finally {
            await gesture.up();
          }
        }
        await tester.pumpAndSettle();
        expect(page, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a page pop uses the latest disabled-animation preference', (
    tester,
  ) async {
    await tester.pumpApp(const KaruyomiApp());
    await tester.pumpAndSettle();
    final navigator = Navigator.of(tester.element(find.byType(AppShell)));
    const pageKey = ValueKey('motion-preference-page');
    unawaited(
      navigator.push<void>(
        AppPageRoute<void>(builder: (_) => const SizedBox.expand(key: pageKey)),
      ),
    );
    await tester.pumpAndSettle();

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    navigator.pop();
    await tester.pump();
    expect(find.byKey(pageKey, skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    for (final size in [
      const Size(360, 800),
      const Size(800, 360),
      const Size(768, 1024),
      const Size(1024, 768),
      const Size(1280, 900),
    ]) {
      testWidgets('empty shell navigation at $size in $brightness', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpApp(const KaruyomiApp());
        await tester.pumpAndSettle();
        expect(find.text('书架还是空的'), findsOneWidget);
        expect(
          find.byType(ReaderBaselineHost),
          readerBaselineEnabled ? findsOneWidget : findsNothing,
        );
        final navigation = find.byKey(const ValueKey('app-navigation'));
        expect(navigation, findsOneWidget);
        expect(find.byType(CupertinoTabBar), findsOneWidget);
        expect(tester.getTopLeft(find.byType(CupertinoNavigationBar)).dx, 0);
        for (var i = 0; i < 3; i++) {
          final destination = find.byKey(ValueKey(('app-destination', i)));
          expect(
            tester
                .getSemantics(destination)
                .getSemanticsData()
                .flagsCollection
                .isSelected,
            i == 0 ? Tristate.isTrue : Tristate.isFalse,
          );
        }
        await tester.tap(find.text('去浏览'));
        await tester.pumpAndSettle();
        expect(find.text('连接漫画服务'), findsOneWidget);
        await tester.tap(find.text('设置').last);
        await tester.pumpAndSettle();
        expect(find.text('连接并确认身份后可读取和保存同步设置。'), findsOneWidget);
        expect(find.byType(ChoiceField<wire.AppTheme>), findsNothing);

        tester.view.physicalSize = size.shortestSide >= 600
            ? const Size(800, 360)
            : const Size(768, 1024);
        await tester.pumpAndSettle();
        expect(navigation, findsOneWidget);
        expect(find.byType(CupertinoTabBar), findsOneWidget);
        expect(find.text('连接并确认身份后可读取和保存同步设置。'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'Cupertino navigation keeps focus and drafts across $brightness changes',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        tester.view.physicalSize = const Size(768, 1024);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpApp(const KaruyomiApp());
        await tester.pumpAndSettle();
        final settings = find.byKey(const ValueKey(('app-destination', 2)));
        await tester.tap(settings);
        await tester.pumpAndSettle();
        expect(
          tester
              .getSemantics(settings)
              .getSemanticsData()
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        final origin = find.byKey(const ValueKey('service-origin'));
        await tester.ensureVisible(origin);
        await tester.enterText(origin, 'https://draft.example');
        expect(
          PrimaryScrollController.of(tester.element(find.byType(AppShell)))
              .positions,
          hasLength(1),
          reason: 'keyboard scrolling has one content target',
        );
        final field = tester.element(origin);
        final editing = tester.widget<EditableText>(
          find.descendant(of: origin, matching: find.byType(EditableText)),
        );
        expect(editing.focusNode.hasFocus, true);
        final selection = editing.controller.selection;
        for (final size in [const Size(800, 360), const Size(768, 1024)]) {
          tester.platformDispatcher.platformBrightnessTestValue =
              brightness == Brightness.light
              ? Brightness.dark
              : Brightness.light;
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(tester.element(origin), same(field));
          expect(editing.controller.text, 'https://draft.example');
          expect(editing.controller.selection, selection);
          expect(editing.focusNode.hasFocus, true);
          expect(find.text('连接并确认身份后可读取和保存同步设置。'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'settings panes retain the focused connection draft in $brightness at large text',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        tester.view.physicalSize = const Size(768, 1024);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final platform = TestPlatform(seedDefaultInstallation: false);
        await tester.pumpApp(KaruyomiApp(platform: platform));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey(('app-destination', 2))));
        await tester.pumpAndSettle();
        final connection = find.byKey(
          const ValueKey('settings-section-connection'),
        );
        await tester.ensureVisible(connection);
        await tester.tap(connection);
        await tester.pumpAndSettle();
        final origin = find.byKey(const ValueKey('service-origin'));
        await tester.ensureVisible(origin);
        await tester.enterText(origin, 'https://draft.example');
        final field = tester.element(origin);
        final editing = tester.widget<EditableText>(
          find.descendant(of: origin, matching: find.byType(EditableText)),
        );
        final selection = editing.controller.selection;
        for (final size in [const Size(800, 360), const Size(768, 1024)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(tester.element(origin), same(field));
          expect(editing.controller.text, 'https://draft.example');
          expect(editing.controller.selection, selection);
          expect(editing.focusNode.hasFocus, true);
          expect(tester.takeException(), isNull);
        }
        expect(platform.businessServer.appliedMutations, 0);
      },
    );

    testWidgets(
      'tablet settings exposes both panes to accessibility in $brightness',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        tester.view.physicalSize = const Size(768, 1024);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final platform = TestPlatform(seedDefaultInstallation: false);
          await tester.pumpApp(KaruyomiApp(platform: platform));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey(('app-destination', 2))));
          await tester.pumpAndSettle();

          void expectDirectory() {
            for (final label in ['外观与主题', '阅读显示', '翻页与快捷键', '服务连接', '关于']) {
              expect(
                find.semantics.byPredicate(
                  (node) =>
                      node.label.startsWith(label) &&
                      node.getSemanticsData().hasAction(SemanticsAction.tap),
                ),
                findsOne,
                reason:
                    'the visible directory $label must remain reachable from the semantics root',
              );
            }
          }

          expectDirectory();
          await tester.tap(
            find.byKey(const ValueKey('settings-section-connection')),
          );
          await tester.pumpAndSettle();
          expectDirectory();
          expect(find.semantics.byLabel('连接服务'), findsOne);
          tester.view.physicalSize = const Size(360, 800);
          await tester.pumpAndSettle();
          expect(find.semantics.byLabel('连接服务'), findsOne);
          expect(find.semantics.byLabel(RegExp('^外观与主题')), findsNothing);
          tester.view.physicalSize = const Size(768, 1024);
          await tester.pumpAndSettle();
          expectDirectory();
          expect(find.semantics.byLabel('连接服务'), findsOne);
          expect(platform.businessServer.appliedMutations, 0);
          expect(tester.takeException(), isNull);
          await tester.pumpApp(const SizedBox.shrink());
          await tester.pumpAndSettle();
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'service origin leaves no autofill clients after $brightness navigation',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        tester.view.physicalSize = const Size(768, 1024);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final platform = TestPlatform(seedDefaultInstallation: false);
        await tester.pumpApp(KaruyomiApp(platform: platform));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey(('app-destination', 2))));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('settings-section-connection')),
        );
        await tester.pumpAndSettle();
        final origin = find.byKey(const ValueKey('service-origin'));
        await tester.enterText(origin, 'https://draft.example');
        expect(tester.testTextInput.hasAnyClients, true);
        expect(tester.testTextInput.setClientArgs!['autofill'], isNull);
        await tester.tap(
          find.byKey(const ValueKey('settings-section-appearance')),
        );
        await tester.pumpAndSettle();
        expect(tester.testTextInput.hasAnyClients, false);
        await tester.tap(
          find.byKey(const ValueKey('settings-section-connection')),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<CupertinoTextField>(origin).controller!.text,
          'https://draft.example',
        );
        await tester.enterText(origin, 'https://second.example');
        expect(tester.testTextInput.setClientArgs!['autofill'], isNull);
        await tester.tap(find.byKey(const ValueKey(('app-destination', 0))));
        await tester.pumpAndSettle();
        expect(tester.testTextInput.hasAnyClients, false);
        expect(platform.businessServer.appliedMutations, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'search does not retain autofill clients after $brightness navigation',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final platform = TestPlatform(seedDefaultInstallation: false);
        await tester.pumpApp(KaruyomiApp(platform: platform));
        await tester.pumpAndSettle();
        final navigation = find.byKey(const ValueKey('app-navigation'));
        await tester.tap(
          find.descendant(of: navigation, matching: find.text('浏览')),
        );
        await tester.pumpAndSettle();
        final search = find.byKey(const ValueKey('source-directory-search'));
        await tester.enterText(search, '草稿');
        expect(tester.testTextInput.hasAnyClients, true);
        expect(tester.testTextInput.setClientArgs, isNotNull);
        expect(
          tester.testTextInput.setClientArgs!['autofill'],
          isNull,
          reason: 'search must not create a dormant browser autofill form',
        );
        await tester.tap(
          find.descendant(of: navigation, matching: find.text('设置')),
        );
        await tester.pumpAndSettle();
        expect(tester.testTextInput.hasAnyClients, false);
        await tester.tap(
          find.descendant(of: navigation, matching: find.text('浏览')),
        );
        await tester.pumpAndSettle();
        await tester.enterText(search, '另一个查询');
        expect(tester.testTextInput.setClientArgs!['autofill'], isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpApp(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'chapter navigation preserves Source reference and Native reports its image gate',
    (tester) async {
      final platform = TestPlatform();
      await tester.pumpApp(KaruyomiApp(platform: platform));
      await tester.pumpAndSettle();
      await _browseDetails(tester);
      expect(find.text('漫画源返回的完整简介'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('第 1 章'),
        160,
        // The outer Scrollable is the detail ListView; fields and menus can
        // contain their own nested Scrollables.
        scrollable: find
            .descendant(
              of: find.byType(MangaDetailsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('第 1 章'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(
        tester
                .widget<CupertinoButton>(
                  buttonAbove(
                    find.ancestor(
                      of: find.text('第 1 章'),
                      matching: find.byType(CupertinoListTile),
                    ),
                  ),
                )
                .onPressed !=
            null,
        true,
      );
      await tester.tap(find.text('第 1 章'));
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(
        platform.invocations.last.whichRequest(),
        wire.SourceCall_Request.pages,
      );
      expect(
        platform.invocations.last.pages.chapter.url,
        '/chapter/opaque-ref',
      );
      expect(platform.invocations.last.pages.chapter.name, '第 1 章');
      expect(find.text('当前平台尚未支持图片阅读'), findsOneWidget);
      expect(platform.imageControls.single.$1, 'acquireImage');
      expect(platform.imageControls.single.$2['pageKey'], 'p-0');
      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pumpAndSettle();
      expect(platform.imageControls.last.$1, 'closePageSession');
      expect(tester.takeException(), isNull);
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'chapter completion during details exit closes its session without opening Reader',
    (tester) async {
      final platform = TestPlatform();
      await tester.pumpApp(KaruyomiApp(platform: platform));
      await tester.pumpAndSettle();
      await _browseDetails(tester);
      await tester.scrollUntilVisible(
        find.text('第 1 章'),
        160,
        // The outer Scrollable is the detail ListView; fields and menus can
        // contain their own nested Scrollables.
        scrollable: find
            .descendant(
              of: find.byType(MangaDetailsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();

      final pages = Completer<wire.SourceResult>();
      platform.invokeHandler = (payload) {
        expect(payload.whichRequest(), wire.SourceCall_Request.pages);
        return pages.future;
      };
      final detailsContext = tester.element(find.byType(MangaDetailsPage));
      final detailsRoute = ModalRoute.of(detailsContext)!;
      await tester.tap(find.text('第 1 章'));
      await tester.pump();
      await tester.tap(find.byType(CupertinoNavigationBarBackButton));
      await tester.pump(const Duration(milliseconds: 50));
      expect(detailsContext.mounted, true);
      expect(detailsRoute.isCurrent, false);
      expect(detailsRoute.isActive, false);

      pages.complete(
        wire.SourceResult(
          pageList: wire.PageList(
            pageSessionId: 'departed-details-session',
            pages: [
              wire.Page(
                pageKey: 'p-0',
                index: 0,
                sourceIndex: 0,
                url: '/page/stable-1',
                imageUrl: 'https://source.invalid/raw-1.png',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReaderScreen), findsNothing);
      expect(find.byType(MangaDetailsPage), findsNothing);
      expect(find.text('真实源 DTO 测试'), findsOneWidget);
      expect(platform.imageControls, hasLength(1));
      expect(platform.imageControls.single.$1, 'closePageSession');
      expect(platform.imageControls.single.$2, {
        'pageSessionId': 'departed-details-session',
        'generation': 'generation-1',
      });
      expect(tester.takeException(), isNull);
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'successful authentication reconnects and restores pending browse selection',
    (tester) async {
      final platform = TestPlatform()..bootstrapStatus = 401;
      platform.continuation = {
        'returnTo': '/',
        'pending': {
          'tab': 1,
          'packageName': 'eu.kanade.source.test',
          'sourceId': sourceId,
        },
      };
      await tester.pumpApp(KaruyomiApp(platform: platform));
      await tester.pumpAndSettle();
      expect(find.text('登录后继续浏览'), findsOneWidget);
      await tester.tap(find.text('登录').first);
      await tester.pumpAndSettle();
      expect(platform.authCalls, 1);
      final catalog = tester.widget<CatalogPage>(find.byType(CatalogPage));
      expect(
        catalog.controller?.activeBuild?.packageName,
        'eu.kanade.source.test',
      );
      expect(catalog.controller?.activeSource?.id, sourceId);
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
      expect(find.byType(SourceBrowsePage), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('真实源 DTO 测试'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpApp(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
