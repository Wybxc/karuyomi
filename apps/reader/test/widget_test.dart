import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/main.dart';
import 'browse/fakes.dart';

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
        find.byType(size.width >= 840 ? NavigationRail : NavigationBar),
        findsOneWidget,
      );
      await tester.tap(find.text('去浏览'));
      await tester.pumpAndSettle();
      expect(find.text('连接漫画服务'), findsOneWidget);
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      expect(find.text('外观'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'real DTO flow shows metadata and keeps chapters unreadable until images are supported',
    (tester) async {
      final platform = TestPlatform();
      await tester.pumpWidget(KaruyomiApp(platform: platform));
      await tester.pumpAndSettle();
      await tester.tap(find.text('去浏览'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('source.test · 1.0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试漫画源 · zh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('真实源 DTO 测试'));
      await tester.pumpAndSettle();
      expect(find.text('漫画源返回的完整简介'), findsOneWidget);
      expect(find.text('第 1 章'), findsOneWidget);
      expect(find.text('暂不可读'), findsOneWidget);
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
        false,
      );
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
      expect(find.text('source.test · 1.0'), findsOneWidget);
      expect(find.text('owner@example.com'), findsOneWidget);
      expect(find.text('真实源 DTO 测试'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
