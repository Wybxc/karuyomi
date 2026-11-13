import 'dart:ui' as ui;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Map confirmed account appearance and accessibility to the glass renderer.
/// The library's old SDK Cupertino theme is distinct from cupertino_ui's theme.
class const AppAppearance({
  super.key,
  required final bool reduceTransparency,
  required final Widget child,
}) extends StatelessWidget {
  static bool solidOf(BuildContext context) =>
      GlassThemeData.of(context).qualityFor(context) == GlassQuality.minimal;

  static Color chromeColor(BuildContext context) => solidOf(context)
      ? CupertinoTheme.of(context).scaffoldBackgroundColor
      : const Color(0x00000000);

  @override
  Widget build(BuildContext context) {
    final solid = reduceTransparency || MediaQuery.highContrastOf(context);
    final quality = solid
        ? GlassQuality.minimal
        : ui.ImageFilter.isShaderFilterSupported
        ? GlassQuality.premium
        : GlassQuality.standard;
    GlassThemeVariant variant(GlassThemeVariant base, Color color) =>
        base.copyWith(
          quality: quality,
          settings: solid
              ? GlassThemeSettings(glassColor: color, blur: 0, saturation: 1)
              : null,
          indicatorSettings: solid
              ? GlassThemeSettings(glassColor: color, blur: 0, saturation: 1)
              : null,
        );
    return LiquidGlassWidgets.wrap(
      brightnessResolver: CupertinoTheme.brightnessOf,
      theme: GlassThemeData(
        style: GlassStyle.ios26,
        brightness: CupertinoTheme.brightnessOf(context),
        light: variant(GlassThemeVariant.ios26Light, const Color(0xFFF6F7FA)),
        dark: variant(GlassThemeVariant.ios26Dark, const Color(0xFF17191E)),
      ),
      child: GlassAccessibilityScope(
        reduceMotion:
            MediaQuery.reduceMotionOf(context) ||
            MediaQuery.disableAnimationsOf(context),
        // The library's accessibility frost remains translucent. Our policy
        // uses zero-blur minimal surfaces and opaque chrome for both requests.
        reduceTransparency: false,
        child: child,
      ),
    );
  }
}
