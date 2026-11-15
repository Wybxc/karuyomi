import 'dart:async';
import 'dart:ui' show ImageByteFormat;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/theme/app_theme.dart';

import '../browse/fakes.dart';
import '../test_app.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('sheet gap paints the confirmed $brightness appearance', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue =
          brightness == Brightness.light ? Brightness.dark : Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      const capture = ValueKey('app-backdrop-capture');
      await tester.pumpApp(
        RepaintBoundary(
          key: capture,
          child: KaruyomiApp(platform: TestPlatform()),
        ),
      );
      await tester.pumpAndSettle();
      tester.widget<AppShell>(find.byType(AppShell)).onThemeChanged(brightness);
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AppShell));
      final expected = AppColors.background.resolveFrom(context);
      unawaited(
        showCupertinoSheet<void>(
          context: context,
          scrollableBuilder: (_, _) =>
              const CupertinoPageScaffold(child: Center(child: Text('漫画源设置'))),
        ),
      );
      await tester.pumpAndSettle();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final pixel = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final bytes = (await image.toByteData(
            format: ImageByteFormat.rawRgba,
          ))!;
          final offset = (4 * image.width + 4) * 4;
          return List.generate(
            4,
            (channel) => bytes.getUint8(offset + channel),
          );
        } finally {
          image.dispose();
        }
      });
      expect(pixel, isNotNull);
      expect(
        pixel![3],
        255,
        reason: 'the uncovered Navigator gap must not expose the host surface',
      );
      // The official route may dim the backdrop with its navigation scrim.
      for (final (index, channel) in [
        expected.r,
        expected.g,
        expected.b,
      ].indexed) {
        expect(pixel[index], closeTo((channel * 255).round(), 26));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
