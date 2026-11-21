import 'package:cupertino_ui/cupertino_ui.dart';

enum AppAppearance {
  system,
  light,
  dark;

  Brightness? get brightness => switch (this) {
    system => null,
    light => Brightness.light,
    dark => Brightness.dark,
  };
}

/// Cupertino semantic roles resolve against the confirmed appearance, contrast,
/// and interface elevation. Mihon's palette remains reference evidence only.
abstract final class AppColors {
  static const accent = CupertinoColors.activeBlue;
  static const onAccent = CupertinoDynamicColor.withBrightness(
    color: CupertinoColors.white,
    darkColor: CupertinoColors.white,
  );
  static const selection = CupertinoColors.tertiarySystemFill;
  static const onSelection = CupertinoColors.label;
  static const background = CupertinoColors.systemGroupedBackground;
  static const label = CupertinoColors.label;
  static const secondaryLabel = CupertinoColors.secondaryLabel;
  static const groupedSurface =
      CupertinoColors.secondarySystemGroupedBackground;
  static const toolbar = CupertinoColors.systemBackground;
  static const separator = CupertinoColors.separator;
  static const error = CupertinoColors.destructiveRed;
}

CupertinoThemeData readerAppTheme(Brightness? brightness) => CupertinoThemeData(
  brightness: brightness,
  scaffoldBackgroundColor: AppColors.background,
  barBackgroundColor: AppColors.toolbar,
);
