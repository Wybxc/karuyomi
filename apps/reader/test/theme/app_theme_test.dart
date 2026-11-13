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
    testWidgets('Mihon color roles remain readable in $brightness', (
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
      Color resolve(CupertinoDynamicColor color) => color.resolveFrom(context);
      for (final (foreground, background) in [
        (AppColors.label, AppColors.background),
        (AppColors.secondaryLabel, AppColors.background),
        (AppColors.secondaryLabel, AppColors.groupedSurface),
        (AppColors.secondaryLabel, AppColors.toolbar),
        (AppColors.accent, AppColors.background),
        (AppColors.onAccent, AppColors.accent),
        (AppColors.onSelection, AppColors.selection),
        (AppColors.error, AppColors.background),
        (AppColors.success, AppColors.background),
      ]) {
        expect(
          _contrast(resolve(foreground), resolve(background)),
          greaterThanOrEqualTo(4.5),
          reason: 'text and its actual surface must remain readable',
        );
      }
      final theme = CupertinoTheme.of(context);
      expect(
        _contrast(
          theme.textTheme.textStyle.color!,
          theme.scaffoldBackgroundColor,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(
          DefaultTextStyle.of(context).style.color!,
          theme.primaryColor,
        ),
        greaterThanOrEqualTo(4.5),
        reason: 'filled buttons need the matching on-primary color',
      );
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
    // Fixed reference: Mihon v0.21.3 TachiyomiColorScheme.darkScheme.
    expect(theme.scaffoldBackgroundColor.toARGB32(), 0xFF1B1B1F);
    expect(theme.primaryColor.toARGB32(), 0xFFB0C6FF);
    expect(theme.barBackgroundColor.toARGB32(), 0xFF211F26);
    expect(theme.textTheme.textStyle.color!.toARGB32(), 0xFFE3E2E6);
  });
}
