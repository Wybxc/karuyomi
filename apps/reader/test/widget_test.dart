import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/diagnostics/reader_baseline.dart';
import 'package:karuyomi/diagnostics/reader_baseline_host.dart';
import 'package:karuyomi/features/browse/catalog_page.dart';
import 'package:karuyomi/features/reader/reader_screen.dart';
import 'package:source_runtime/control_protocol.dart' as wire;
import 'browse/fakes.dart';

Future<void> _browseDetails(WidgetTester tester) async {
  await tester.tap(find.text('去浏览'));
  await tester.pumpAndSettle();
  final catalog = find.byType(CatalogPage);
  final scrollable = find
      .descendant(of: catalog, matching: find.byType(Scrollable))
      .first;
  for (final finder in [
    find.text('eu.kanade.source.test · 1.0'),
    find.byKey(ValueKey(('catalog-source', sourceId))),
    find.text('真实源 DTO 测试'),
  ]) {
    final target = find.descendant(of: catalog, matching: finder);
    await tester.scrollUntilVisible(target, 180, scrollable: scrollable);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final size in [const Size(360, 800), const Size(1280, 900)]) {
    testWidgets('empty shell navigation at ${size.width}px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const KaruyomiApp());
      await tester.pumpAndSettle();
      expect(find.text('书架还是空的'), findsOneWidget);
      expect(
        find.byType(ReaderBaselineHost),
        readerBaselineEnabled ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(size.width >= 840 ? NavigationRail : NavigationBar),
        findsOneWidget,
      );
      await tester.tap(find.text('去浏览'));
      await tester.pumpAndSettle();
      expect(find.text('连接漫画服务'), findsOneWidget);
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      expect(find.text('连接并确认身份后可读取和保存同步设置。'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<wire.AppTheme>), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'chapter navigation preserves Source reference and Native reports its image gate',
    (tester) async {
      final platform = TestPlatform();
      await tester.pumpWidget(KaruyomiApp(platform: platform));
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
            .widget<ListTile>(
              find.ancestor(
                of: find.text('第 1 章'),
                matching: find.byType(ListTile),
              ),
            )
            .enabled,
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
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(platform.imageControls.last.$1, 'closePageSession');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'chapter completion during details exit closes its session without opening Reader',
    (tester) async {
      final platform = TestPlatform();
      await tester.pumpWidget(KaruyomiApp(platform: platform));
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
      await tester.tap(find.byType(BackButton));
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
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'successful authentication reconnects and restores pending browse selection',
    (tester) async {
      final platform = TestPlatform()..bootstrapStatus = 401;
      platform.continuation = {
        'returnTo': '/',
        'pending': {'tab': 1, 'buildId': 'build-1', 'sourceId': sourceId},
      };
      await tester.pumpWidget(KaruyomiApp(platform: platform));
      await tester.pumpAndSettle();
      expect(find.text('登录后继续浏览'), findsOneWidget);
      await tester.tap(find.text('登录').first);
      await tester.pumpAndSettle();
      expect(platform.authCalls, 1);
      expect(find.text('eu.kanade.source.test · 1.0'), findsOneWidget);
      expect(find.text('owner@example.com'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('真实源 DTO 测试'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(CatalogPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('真实源 DTO 测试'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
