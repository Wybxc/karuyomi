package android.graphics;

import com.google.gson.*;
import prototype.Graphics;

public class Paint {
  public static final int ANTI_ALIAS_FLAG = 1, FILTER_BITMAP_FLAG = 2, DITHER_FLAG = 4;

  public enum Style {
    FILL,
    STROKE,
    FILL_AND_STROKE
  }

  public enum Join {
    MITER,
    ROUND,
    BEVEL
  }

  public enum Cap {
    BUTT,
    ROUND,
    SQUARE
  }

  public enum Align {
    LEFT,
    CENTER,
    RIGHT
  }

  int color = Color.BLACK, flags;
  float textSize = 12, textScaleX = 1, strokeWidth = 0;
  Style style = Style.FILL;
  Join join = Join.MITER;
  Cap cap = Cap.BUTT;
  Align align = Align.LEFT;
  Typeface typeface;
  private int layoutDirection;

  public Paint() {
    flags = ANTI_ALIAS_FLAG | FILTER_BITMAP_FLAG;
  }

  public Paint(int f) {
    flags = f | FILTER_BITMAP_FLAG;
  }

  public Paint(Paint p) {
    set(p);
  }

  public void set(Paint p) {
    color = p.color;
    flags = p.flags;
    textSize = p.textSize;
    textScaleX = p.textScaleX;
    strokeWidth = p.strokeWidth;
    style = p.style;
    join = p.join;
    cap = p.cap;
    align = p.align;
    typeface = p.typeface;
    layoutDirection = p.layoutDirection;
  }

  public void setColor(int c) {
    color = c;
  }

  public int getColor() {
    return color;
  }

  public void setAlpha(int a) {
    color = (color & 0xffffff) | ((a & 255) << 24);
  }

  public int getAlpha() {
    return color >>> 24;
  }

  public void setTextSize(float v) {
    textSize = v;
  }

  public float getTextSize() {
    return textSize;
  }

  public void setTextScaleX(float v) {
    textScaleX = v;
  }

  public float getTextScaleX() {
    return textScaleX;
  }

  public Typeface setTypeface(Typeface t) {
    typeface = t;
    return t;
  }

  public Typeface getTypeface() {
    return typeface;
  }

  public void setStyle(Style s) {
    style = java.util.Objects.requireNonNull(s);
  }

  public Style getStyle() {
    return style;
  }

  public void setStrokeWidth(float w) {
    if (w < 0) throw new IllegalArgumentException("strokeWidth < 0");
    strokeWidth = w;
  }

  public float getStrokeWidth() {
    return strokeWidth;
  }

  public void setStrokeJoin(Join j) {
    join = j;
  }

  public void setStrokeCap(Cap c) {
    cap = c;
  }

  public void setTextAlign(Align a) {
    align = a;
  }

  public void setFlags(int f) {
    flags = f;
  }

  public int getFlags() {
    return flags;
  }

  public void setAntiAlias(boolean v) {
    flags = v ? flags | 1 : flags & ~1;
  }

  public boolean isAntiAlias() {
    return (flags & 1) != 0;
  }

  public void setFilterBitmap(boolean v) {
    flags = v ? flags | 2 : flags & ~2;
  }

  public float measureText(String text) {
    return measureText(text, 0, text.length());
  }

  public float measureText(String text, int start, int end) {
    if (start < 0 || end < start || end > text.length()) throw new IndexOutOfBoundsException();
    JsonObject a = Graphics.args();
    a.add("paint", json());
    a.addProperty("text", text.substring(start, end));
    return Graphics.call("measure", a).get("width").getAsFloat();
  }

  /** Project-internal layout state; ordinary Android drawText keeps its default direction. */
  public void setTextDirectionForLayout(int direction) {
    if (direction != 1 && direction != -1)
      throw new IllegalArgumentException("Invalid layout direction");
    layoutDirection = direction;
  }

  public JsonObject runtimePaint() {
    return json();
  }

  public static class FontMetrics {
    public float top, ascent, descent, bottom, leading;
  }

  public static class FontMetricsInt {
    public int top, ascent, descent, bottom, leading;
  }

  public float getFontMetrics(FontMetrics result) {
    JsonObject args = Graphics.args();
    args.add("paint", json());
    JsonObject metrics = Graphics.call("measure", args);
    if (result != null) {
      result.top = metrics.get("top").getAsFloat();
      result.ascent = metrics.get("ascent").getAsFloat();
      result.descent = metrics.get("descent").getAsFloat();
      result.bottom = metrics.get("bottom").getAsFloat();
      result.leading = metrics.get("leading").getAsFloat();
    }
    return metrics.get("descent").getAsFloat()
        - metrics.get("ascent").getAsFloat()
        + metrics.get("leading").getAsFloat();
  }

  public FontMetrics getFontMetrics() {
    FontMetrics result = new FontMetrics();
    getFontMetrics(result);
    return result;
  }

  public int getFontMetricsInt(FontMetricsInt result) {
    FontMetrics metrics = getFontMetrics();
    if (result != null) {
      result.top = (int) Math.floor(metrics.top);
      result.ascent = Math.round(metrics.ascent);
      result.descent = Math.round(metrics.descent);
      result.bottom = (int) Math.ceil(metrics.bottom);
      result.leading = Math.round(metrics.leading);
    }
    return Math.round(metrics.descent) - Math.round(metrics.ascent) + Math.round(metrics.leading);
  }

  public FontMetricsInt getFontMetricsInt() {
    FontMetricsInt result = new FontMetricsInt();
    getFontMetricsInt(result);
    return result;
  }

  public float ascent() {
    return getFontMetrics().ascent;
  }

  public float descent() {
    return getFontMetrics().descent;
  }

  public float getFontSpacing() {
    return getFontMetrics(null);
  }

  JsonObject json() {
    JsonObject j = Graphics.args();
    j.addProperty("color", color);
    j.addProperty(
        "direction", layoutDirection == 0 ? "auto" : layoutDirection == 1 ? "ltr" : "rtl");
    j.addProperty("flags", flags);
    j.addProperty("size", textSize);
    j.addProperty("scaleX", textScaleX);
    j.addProperty("strokeWidth", strokeWidth);
    j.addProperty("style", style.name());
    j.addProperty("join", join.name());
    j.addProperty("cap", cap.name());
    j.addProperty("align", align.name());
    Typeface face = typeface == null ? Typeface.DEFAULT : typeface;
    j.addProperty("family", face.family);
    j.addProperty("fontStyle", face.style);
    return j;
  }
}
