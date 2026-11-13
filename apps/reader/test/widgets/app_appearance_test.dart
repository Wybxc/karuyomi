import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/widgets/app_appearance.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('solid and high contrast policy removes blur ($brightness)', (
      tester,
    ) async {
      late BuildContext chrome;
      Widget app({
        bool solid = false,
        bool contrast = false,
        bool motion = false,
      }) => CupertinoApp(
        theme: CupertinoThemeData(brightness: brightness),
        home: MediaQuery(
          data: MediaQueryData(
            highContrast: contrast,
            disableAnimations: motion,
          ),
          child: AppAppearance(
            reduceTransparency: solid,
            child: Builder(
              builder: (context) {
                chrome = context;
                return GlassScaffold(
                  enableBackgroundSampling: false,
                  extendBody: false,
                  appBar: GlassAppBar(
                    title: const Text('导航'),
                    backgroundColor: AppAppearance.chromeColor(context),
                  ),
                  bottomBar: GlassTabBar.bottom(
                    tabs: const [
                      GlassTab(label: '书架', icon: Icon(CupertinoIcons.book)),
                      GlassTab(label: '浏览', icon: Icon(CupertinoIcons.compass)),
                    ],
                    selectedIndex: 0,
                    onTabSelected: (_) {},
                    enableBlend: false,
                  ),
                  body: const Center(child: Text('正文')),
                );
              },
            ),
          ),
        ),
      );
      for (final highContrast in [false, true]) {
        await tester.pumpWidget(
          app(solid: !highContrast, contrast: highContrast, motion: true),
        );
        await tester.pumpAndSettle();
        final theme = GlassThemeData.of(chrome);
        expect(GlassTheme.brightnessOf(chrome), brightness);
        expect(theme.qualityFor(chrome), GlassQuality.minimal);
        expect(theme.settingsFor(chrome)!.blur, 0);
        expect(theme.settingsFor(chrome)!.glassColor?.a, 1);
        expect(GlassAccessibilityData.of(chrome).reduceMotion, true);
        expect(
          tester
              .widget<GlassAppBar>(find.byType(GlassAppBar))
              .backgroundColor
              .a,
          1,
        );
        expect(find.byType(BackdropFilter), findsNothing);
        expect(tester.binding.hasScheduledFrame, false);
      }
    });
  }

  testWidgets(
    'changing material keeps the focused input and its unsaved text',
    (tester) async {
      final controller = TextEditingController(text: '未确认草稿');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      Widget app(bool solid) => CupertinoApp(
        home: AppAppearance(
          reduceTransparency: solid,
          child: GlassScaffold(
            enableBackgroundSampling: false,
            body: Center(
              child: CupertinoTextField(
                controller: controller,
                focusNode: focus,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(false));
      focus.requestFocus();
      await tester.pumpAndSettle();
      final input = tester.element(find.byType(CupertinoTextField));
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(CupertinoTextField)), same(input));
      expect(controller.text, '未确认草稿');
      expect(focus.hasFocus, true);
      expect(tester.takeException(), isNull);
    },
  );
}
