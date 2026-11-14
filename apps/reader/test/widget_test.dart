import '../test_support/cupertino.dart';

import 'package:karuyomi/widgets/app_page_route.dart';
import 'package:karuyomi/widgets/choice_field.dart';

import 'test_app.dart';

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/theme/app_theme.dart';
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
        unawaited(
          navigator.push<void>(
            AppPageRoute<void>(
              builder: (_) => const SizedBox.expand(key: pageKey),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        final page = find.byKey(pageKey);
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
        navigator.pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final brightness in Brightness.values) {
    for (final (size, usesSidebar) in [
      (const Size(360, 800), false),
      (const Size(800, 360), false),
      (const Size(768, 1024), true),
      (const Size(1024, 768), true),
      (const Size(1280, 900), true),
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
        expect(
          find.byType(CupertinoTabBar),
          usesSidebar ? findsNothing : findsOneWidget,
        );
        if (usesSidebar) {
          final sidebar = find.byKey(const ValueKey('app-sidebar'));
          expect(tester.getRect(sidebar), Rect.fromLTWH(0, 0, 80, size.height));
          expect(
            tester.getTopLeft(find.byType(CupertinoNavigationBar)).dx,
            80,
            reason: 'the content header starts after the rail',
          );
          expect(
            tester.widget<ColoredBox>(sidebar).color,
            AppColors.sidebar.resolveFrom(tester.element(sidebar)),
          );
          for (var i = 0; i < 3; i++) {
            final destination = find.byKey(ValueKey(('app-destination', i)));
            expect(tester.getSize(destination), const Size(80, 60));
            final icon = find.descendant(
              of: destination,
              matching: find.byType(Icon),
            );
            final label = find.descendant(
              of: destination,
              matching: find.byType(Text),
            );
            expect(tester.getCenter(icon).dx, 40);
            expect(tester.getCenter(label).dx, 40);
            expect(
              tester.getTopLeft(label).dy,
              greaterThan(tester.getBottomRight(icon).dy),
            );
            expect(
              tester
                  .getSemantics(destination)
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected,
              i == 0 ? Tristate.isTrue : Tristate.isFalse,
            );
          }
        }
        await tester.tap(find.text('去浏览'));
        await tester.pumpAndSettle();
        expect(find.text('连接漫画服务'), findsOneWidget);
        await tester.tap(find.text('设置').last);
        await tester.pumpAndSettle();
        expect(find.text('连接并确认身份后可读取和保存同步设置。'), findsOneWidget);
        expect(find.byType(ChoiceField<wire.AppTheme>), findsNothing);

        tester.view.physicalSize = usesSidebar
            ? const Size(800, 360)
            : const Size(768, 1024);
        await tester.pumpAndSettle();
        expect(navigation, findsOneWidget);
        expect(
          find.byType(CupertinoTabBar),
          usesSidebar ? findsOneWidget : findsNothing,
        );
        expect(find.text('连接并确认身份后可读取和保存同步设置。'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
      'large rail keeps focus and drafts across $brightness changes',
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
          reason: 'keyboard scrolling has one content target, not the rail',
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
