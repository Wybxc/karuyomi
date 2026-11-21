import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:karuyomi/theme/app_theme.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Cupertino semantic colors honor increased contrast in $brightness',
      (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(highContrast: true);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await tester.pumpWidget(
          CupertinoApp(
            theme: readerAppTheme(null),
            home: const CupertinoPageScaffold(child: Text('高对比度')),
          ),
        );
        final context = tester.element(find.text('高对比度'));
        expect(
          CupertinoTheme.of(context).primaryColor.toARGB32(),
          brightness == Brightness.light ? 0xFF0040DD : 0xFF409CFF,
        );
        expect(
          AppColors.groupedSurface.resolveFrom(context),
          CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
        );
        expect(
          AppColors.secondaryLabel.resolveFrom(context).a,
          greaterThan(.6),
        );
      },
    );

    testWidgets('Cupertino surfaces and controls follow $brightness', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        CupertinoApp(
          theme: readerAppTheme(null),
          home: CupertinoPageScaffold(
            navigationBar: const CupertinoNavigationBar(middle: Text('书架')),
            child: Center(
              child: CupertinoButton.filled(
                onPressed: () {},
                child: const Text('保存'),
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.text('保存'));
      final theme = CupertinoTheme.of(context);
      expect(
        theme.primaryColor,
        CupertinoColors.systemBlue.resolveFrom(context),
      );
      expect(
        theme.scaffoldBackgroundColor,
        CupertinoColors.systemGroupedBackground.resolveFrom(context),
      );
      expect(
        theme.barBackgroundColor,
        CupertinoColors.systemBackground.resolveFrom(context),
      );
      expect(
        theme.textTheme.textStyle.color,
        CupertinoColors.label.resolveFrom(context),
      );
      expect(
        theme.applyThemeToAll,
        false,
        reason: 'switches retain their standard Cupertino colors',
      );
      expect(DefaultTextStyle.of(context).style.color, CupertinoColors.white);
      for (final surface in [
        theme.scaffoldBackgroundColor,
        theme.barBackgroundColor,
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
      ]) {
        expect(
          _contrast(theme.textTheme.textStyle.color!, surface),
          greaterThanOrEqualTo(4.5),
        );
      }
      final title = tester.element(find.text('书架'));
      expect(
        _contrast(
          DefaultTextStyle.of(title).style.color!,
          theme.barBackgroundColor,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('confirmed appearance overrides system color resolution', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      CupertinoApp(
        theme: readerAppTheme(Brightness.dark),
        home: const CupertinoPageScaffold(child: Text('已确认的主题')),
      ),
    );
    final theme = CupertinoTheme.of(tester.element(find.text('已确认的主题')));
    expect(theme.scaffoldBackgroundColor.toARGB32(), 0xFF000000);
    expect(theme.primaryColor.toARGB32(), 0xFF0A84FF);
    expect(theme.barBackgroundColor.toARGB32(), 0xFF000000);
    expect(theme.textTheme.textStyle.color!.toARGB32(), 0xFFFFFFFF);
  });
}
