package android.graphics;

import java.util.Locale;

public class Color {
  public static final int BLACK = 0xff000000,
      DKGRAY = 0xff444444,
      GRAY = 0xff888888,
      LTGRAY = 0xffcccccc,
      WHITE = 0xffffffff,
      RED = 0xffff0000,
      GREEN = 0xff00ff00,
      BLUE = 0xff0000ff,
      YELLOW = 0xffffff00,
      CYAN = 0xff00ffff,
      MAGENTA = 0xffff00ff,
      TRANSPARENT = 0;

  public static int alpha(int c) {
    return c >>> 24;
  }

  public static int red(int c) {
    return (c >> 16) & 255;
  }

  public static int green(int c) {
    return (c >> 8) & 255;
  }

  public static int blue(int c) {
    return c & 255;
  }

  public static int rgb(int r, int g, int b) {
    return argb(255, r, g, b);
  }

  public static int argb(int a, int r, int g, int b) {
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  public static int parseColor(String s) {
    if (s == null) throw new IllegalArgumentException("Unknown color");
    if (s.startsWith("#")) {
      if (s.length() != 7 && s.length() != 9) throw new IllegalArgumentException("Unknown color");
      try {
        long n = Long.parseLong(s.substring(1), 16);
        return (int) (s.length() == 7 ? n | 0xff000000L : n);
      } catch (NumberFormatException e) {
        throw new IllegalArgumentException("Unknown color", e);
      }
    }
    switch (s.toLowerCase(Locale.ROOT)) {
      case "black":
        return BLACK;
      case "darkgray":
      case "darkgrey":
        return DKGRAY;
      case "gray":
      case "grey":
        return GRAY;
      case "lightgray":
      case "lightgrey":
        return LTGRAY;
      case "white":
        return WHITE;
      case "red":
        return RED;
      case "green":
      case "lime":
        return GREEN;
      case "blue":
        return BLUE;
      case "yellow":
        return YELLOW;
      case "cyan":
      case "aqua":
        return CYAN;
      case "magenta":
      case "fuchsia":
        return MAGENTA;
      case "transparent":
        return TRANSPARENT;
      case "maroon":
        return 0xff800000;
      case "navy":
        return 0xff000080;
      case "olive":
        return 0xff808000;
      case "purple":
        return 0xff800080;
      case "silver":
        return 0xffc0c0c0;
      case "teal":
        return 0xff008080;
      default:
        throw new IllegalArgumentException("Unknown color");
    }
  }
}
