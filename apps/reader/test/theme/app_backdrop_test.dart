import 'dart:async';
import 'dart:ui' show ImageByteFormat;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/features/settings/settings_widgets.dart';
import 'package:karuyomi/main.dart';
import 'package:karuyomi/theme/app_theme.dart';
import 'package:karuyomi/widgets/app_routes.dart';

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
      await tester.tap(
        find.byKey(const ValueKey(('app-destination', 'settings'))),
      );
      await tester.pumpAndSettle();
      tester
          .widget<DeviceAppearanceSettings>(
            find.byType(DeviceAppearanceSettings),
          )
          .onChanged(
            brightness == Brightness.dark
                ? AppAppearance.dark
                : AppAppearance.light,
          );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey(('app-destination', 'library'))),
      );
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(AppShell));
      final expected = AppColors.background.resolveFrom(context);
      unawaited(
        showAppSheet<void>(
          context: context,
          enableDrag: false,
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

  for (final reduced in [false, true]) {
    testWidgets(
      'page transitions follow the motion setting on the home page: $reduced',
      (tester) async {
        final platform = tester.platformDispatcher;
        platform.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
          reduceMotion: reduced,
        );
        addTearDown(platform.clearAccessibilityFeaturesTestValue);
        await tester.pumpApp(KaruyomiApp(platform: TestPlatform()));
        await tester.pumpAndSettle();
        final background = find.byType(AppShell, skipOffstage: false);
        final resting = tester.getRect(background);
        final navigator = Navigator.of(tester.element(background));
        void expectBackdrop() {
          final actual = tester.getRect(background);
          if (reduced) {
            expect(actual, resting);
          } else {
            expect(actual.left, lessThan(resting.left));
          }
        }

        unawaited(
          navigator.push<void>(
            AppPageRoute(
              builder: (_) => const CupertinoPageScaffold(
                child: Center(child: Text('设置详情')),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expectBackdrop();
        await tester.pumpAndSettle();

        if (!reduced) {
          final detail = find.text('设置详情');
          final foregroundLeft = tester.getTopLeft(detail).dx;
          final coveredLeft = tester.getTopLeft(background).dx;
          final gesture = await tester.startGesture(
            Offset(1, resting.center.dy),
          );
          await gesture.moveBy(const Offset(50, 0));
          await tester.pump();
          await gesture.moveBy(const Offset(160, 0));
          await tester.pump();
          final foregroundTravel =
              tester.getTopLeft(detail).dx - foregroundLeft;
          expect(foregroundTravel, greaterThan(0));
          expect(
            tester.getTopLeft(background).dx,
            closeTo(coveredLeft * (1 - foregroundTravel / resting.width), 0.5),
          );
          await gesture.cancel();
          await tester.pumpAndSettle();
        }

        navigator.pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expectBackdrop();
        await tester.pumpAndSettle();
        expect(find.text('设置详情'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final initiallyReduced in [false, true]) {
    testWidgets(
      'an open sheet follows changed motion settings: $initiallyReduced',
      (tester) async {
        final platform = tester.platformDispatcher;
        void setReduced(bool reduced) {
          platform.accessibilityFeaturesTestValue = FakeAccessibilityFeatures(
            reduceMotion: reduced,
          );
        }

        setReduced(initiallyReduced);
        addTearDown(platform.clearAccessibilityFeaturesTestValue);
        await tester.pumpApp(KaruyomiApp(platform: TestPlatform()));
        await tester.pumpAndSettle();
        final background = find.byType(AppShell, skipOffstage: false);
        final resting = tester.getRect(background);
        void expectBackdrop(bool reduced) {
          final actual = tester.getRect(background);
          if (reduced) {
            expect(actual, resting);
          } else {
            expect(actual.width, lessThan(resting.width));
          }
        }

        unawaited(
          showAppSheet<void>(
            context: tester.element(background),
            enableDrag: false,
            scrollableBuilder: (_, _) =>
                const CupertinoPageScaffold(child: Center(child: Text('分类设置'))),
          ),
        );
        await tester.pumpAndSettle();
        expectBackdrop(initiallyReduced);

        final sheet = find.text('分类设置');
        final sheetPosition = tester.getRect(sheet);
        setReduced(!initiallyReduced);
        await tester.pump();
        expect(
          MediaQuery.reduceMotionOf(tester.element(sheet)),
          !initiallyReduced,
        );
        expectBackdrop(!initiallyReduced);
        expect(tester.getRect(sheet), sheetPosition);

        setReduced(true);
        await tester.pump();
        Navigator.of(tester.element(sheet)).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expectBackdrop(true);
        await tester.pumpAndSettle();
        expect(sheet, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
