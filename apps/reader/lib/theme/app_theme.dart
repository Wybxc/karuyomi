import 'package:cupertino_ui/cupertino_ui.dart';

/// Semantic colors from Mihon v0.21.3's fixed DEFAULT scheme. Dynamic colors
/// follow the confirmed Cupertino brightness, including the system setting.
abstract final class AppColors {
  static const accent = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF0058CA),
    darkColor: Color(0xFFB0C6FF),
  );
  static const onAccent = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF002D6E),
  );
  static const selection = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFD9E2FF),
    darkColor: Color(0xFF00429B),
  );
  static const onSelection = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF001945),
    darkColor: Color(0xFFD9E2FF),
  );
  static const background = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFEFBFF),
    darkColor: Color(0xFF1B1B1F),
  );
  static const label = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF1B1B1F),
    darkColor: Color(0xFFE3E2E6),
  );
  static const secondaryLabel = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF44464F),
    darkColor: Color(0xFFC5C6D0),
  );
  static const groupedSurface = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF7F2FA),
    darkColor: Color(0xFF1E1C22),
  );
  static const toolbar = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF3EDF7),
    darkColor: Color(0xFF211F26),
  );
  static const separator = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFC5C6D0),
    darkColor: Color(0xFF44464F),
  );
  static const error = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFBA1A1A),
    darkColor: Color(0xFFFFB4AB),
  );
  static const success = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF006E1B),
    darkColor: Color(0xFF7ADC77),
  );
}

CupertinoThemeData readerAppTheme(Brightness? brightness) {
  const typography = CupertinoTextThemeData();
  return CupertinoThemeData(
    brightness: brightness,
    primaryColor: AppColors.accent,
    primaryContrastingColor: AppColors.onAccent,
    scaffoldBackgroundColor: AppColors.background,
    barBackgroundColor: AppColors.toolbar,
    selectionHandleColor: AppColors.accent,
    textTheme: CupertinoTextThemeData(
      primaryColor: AppColors.accent,
      textStyle: typography.textStyle.copyWith(color: AppColors.label),
      tabLabelTextStyle: typography.tabLabelTextStyle.copyWith(
        color: AppColors.secondaryLabel,
      ),
      navTitleTextStyle: typography.navTitleTextStyle.copyWith(
        color: AppColors.label,
      ),
      navLargeTitleTextStyle: typography.navLargeTitleTextStyle.copyWith(
        color: AppColors.label,
      ),
      pickerTextStyle: typography.pickerTextStyle.copyWith(
        color: AppColors.label,
      ),
      dateTimePickerTextStyle: typography.dateTimePickerTextStyle.copyWith(
        color: AppColors.label,
      ),
    ),
  );
}
