package android.graphics;

import java.io.*;
import java.util.Base64;
import prototype.Graphics;

public class Typeface {
  public static final int NORMAL = 0, BOLD = 1, ITALIC = 2, BOLD_ITALIC = 3;
  public static final Typeface DEFAULT = new Typeface("sans-serif", 0),
      DEFAULT_BOLD = new Typeface("sans-serif", 1),
      SANS_SERIF = DEFAULT,
      SERIF = new Typeface("serif", 0),
      MONOSPACE = new Typeface("monospace", 0);
  final String family;
  final int style;

  Typeface(String family, int style) {
    this.family = family;
    this.style = style & 3;
  }

  public static Typeface create(String name, int style) {
    return new Typeface(name == null ? "sans-serif" : name, style);
  }

  public static Typeface create(Typeface face, int style) {
    return create(face == null ? null : face.family, style);
  }

  public static Typeface defaultFromStyle(int style) {
    return create(DEFAULT, style);
  }

  public int getStyle() {
    return style;
  }

  public boolean isBold() {
    return (style & BOLD) != 0;
  }

  public boolean isItalic() {
    return (style & ITALIC) != 0;
  }

  public static Typeface createFromFile(String path) {
    return createFromFile(new File(path));
  }

  public static Typeface createFromFile(File file) {
    try (InputStream in = new FileInputStream(file)) {
      var a = Graphics.args();
      a.addProperty("body", Base64.getEncoder().encodeToString(in.readAllBytes()));
      return new Typeface(Graphics.async("font", a).get("family").getAsString(), 0);
    } catch (IOException e) {
      throw new RuntimeException("Font asset not found: " + file, e);
    }
  }
}
