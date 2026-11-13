import '../test_support/cupertino.dart';

import 'package:karuyomi/widgets/app_page_route.dart';
import 'package:karuyomi/widgets/choice_field.dart';

import 'test_app.dart';

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
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

  for (final size in [const Size(360, 800), const Size(1280, 900)]) {
    testWidgets('empty shell navigation at ${size.width}px', (tester) async {
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
      expect(find.byKey(const ValueKey('app-navigation')), findsOneWidget);
      await tester.tap(find.text('去浏览'));
      await tester.pumpAndSettle();
      expect(find.text('连接漫画服务'), findsOneWidget);
      await tester.tap(appNavigation('设置'));
      await tester.pumpAndSettle();
      expect(find.text('连接并确认身份后可读取和保存同步设置。'), findsOneWidget);
      expect(find.byType(ChoiceField<wire.AppTheme>), findsNothing);
      expect(tester.takeException(), isNull);
    });
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
      await tester.tap(appBackButton);
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
      await tester.tap(appBackButton);
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
