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

  JsonObject json() {
    JsonObject j = Graphics.args();
    j.addProperty("color", color);
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
