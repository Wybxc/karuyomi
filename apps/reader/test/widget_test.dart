import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/main.dart';

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
      expect(find.text('尚未安装漫画源'), findsOneWidget);
      await tester.tap(find.text('设置').last);
      await tester.pumpAndSettle();
      expect(find.text('外观'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
