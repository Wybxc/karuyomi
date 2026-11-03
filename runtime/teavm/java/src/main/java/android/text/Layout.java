package android.text;

import android.graphics.Canvas;
import android.graphics.Paint;
import com.google.gson.*;
import prototype.Graphics;

/** Bounded plain-text layout. Glyph shaping and Unicode rules run in the browser. */
public abstract class Layout {
  public enum Alignment {
    ALIGN_NORMAL,
    ALIGN_OPPOSITE,
    ALIGN_CENTER
  }

  public static final int DIR_LEFT_TO_RIGHT = 1, DIR_RIGHT_TO_LEFT = -1;
  public static final float DEFAULT_LINESPACING_MULTIPLIER = 1, DEFAULT_LINESPACING_ADDITION = 0;
  protected final CharSequence text;
  protected final TextPaint paint;
  protected final int width;
  protected final Alignment alignment;
  protected final float spacingMult, spacingAdd;
  private JsonArray lines;
  private int height, topPadding, bottomPadding, layoutEnd;

  protected Layout(
      CharSequence source,
      TextPaint paint,
      int width,
      Alignment alignment,
      float spacingMult,
      float spacingAdd) {
    java.util.Objects.requireNonNull(source);
    if (source instanceof Spanned)
      throw new UnsupportedOperationException("Styled text layout is unsupported");
    if (source.length() > 8192)
      throw new IllegalArgumentException("Text exceeds 8192 UTF-16 units");
    if (width < 0
        || width > 16384
        || !Float.isFinite(spacingMult)
        || spacingMult < 0
        || !Float.isFinite(spacingAdd))
      throw new IllegalArgumentException("Invalid layout dimensions or spacing");
    this.text = source;
    this.paint = java.util.Objects.requireNonNull(paint);
    this.paint.bgColor = 0;
    this.paint.baselineShift = 0;
    this.width = width;
    this.alignment = java.util.Objects.requireNonNull(alignment);
    this.spacingMult = spacingMult;
    this.spacingAdd = spacingAdd;
  }

  protected final void generate(boolean includePad) {
    generate(0, text.length(), includePad);
  }

  protected final void generate(int start, int end, boolean includePad) {
    java.util.Objects.checkFromToIndex(start, end, text.length());
    String selected = text.subSequence(start, end).toString();
    JsonObject args = Graphics.args();
    args.addProperty("text", selected);
    args.addProperty("width", width);
    args.addProperty("alignment", alignment.name());
    args.addProperty("spacingMult", spacingMult);
    args.addProperty("spacingAdd", spacingAdd);
    args.addProperty("includePad", includePad);
    args.add("paint", paint.runtimePaint());
    JsonObject result = Graphics.call("layout", args);
    JsonArray rows = result.getAsJsonArray("lines");
    if (rows == null || rows.size() < 1 || rows.size() > 512)
      throw new IllegalStateException("Invalid layout line count");
    int previous = 0;
    for (JsonElement item : rows) {
      JsonArray row = item.getAsJsonArray();
      if (row.size() != 10
          || row.get(0).getAsInt() != previous
          || row.get(1).getAsInt() < previous
          || row.get(1).getAsInt() > selected.length()
          || row.get(2).getAsInt() < previous
          || row.get(2).getAsInt() > row.get(1).getAsInt())
        throw new IllegalStateException("Invalid layout line range");
      previous = row.get(1).getAsInt();
      for (int index = 0; index < 3; index++)
        row.set(index, new JsonPrimitive(row.get(index).getAsInt() + start));
    }
    layoutEnd = end;
    if (previous != selected.length()) throw new IllegalStateException("Truncated text layout");
    height = result.get("height").getAsInt();
    if (height < 0 || height > 16384) throw new IllegalStateException("Invalid layout height");
    topPadding = result.get("topPadding").getAsInt();
    bottomPadding = result.get("bottomPadding").getAsInt();
    lines = rows;
  }

  private JsonArray line(int line) {
    if (lines == null) throw new IllegalStateException("Layout not generated");
    if (line < 0 || line >= lines.size()) throw new IndexOutOfBoundsException();
    return lines.get(line).getAsJsonArray();
  }

  public final CharSequence getText() {
    return text;
  }

  public final TextPaint getPaint() {
    return paint;
  }

  public final int getWidth() {
    return width;
  }

  public final Alignment getAlignment() {
    return alignment;
  }

  public final float getSpacingMultiplier() {
    return spacingMult;
  }

  public final float getSpacingAdd() {
    return spacingAdd;
  }

  public int getHeight() {
    return height;
  }

  public int getLineCount() {
    return lines.size();
  }

  public int getLineStart(int index) {
    return index == getLineCount() ? layoutEnd : line(index).get(0).getAsInt();
  }

  public int getLineEnd(int index) {
    return line(index).get(1).getAsInt();
  }

  public int getLineVisibleEnd(int index) {
    return line(index).get(2).getAsInt();
  }

  public int getLineTop(int index) {
    return index == getLineCount() ? height : line(index).get(3).getAsInt();
  }

  public int getLineBottom(int index) {
    line(index);
    return getLineTop(index + 1);
  }

  public int getLineBaseline(int index) {
    return line(index).get(4).getAsInt();
  }

  public int getLineDescent(int index) {
    return line(index).get(5).getAsInt();
  }

  public int getLineAscent(int index) {
    return getLineTop(index) - getLineBaseline(index);
  }

  public float getLineLeft(int index) {
    return line(index).get(6).getAsFloat();
  }

  public float getLineRight(int index) {
    return getLineLeft(index) + getLineMax(index);
  }

  public float getLineWidth(int index) {
    return line(index).get(9).getAsFloat();
  }

  public float getLineMax(int index) {
    return line(index).get(7).getAsFloat();
  }

  public int getParagraphDirection(int index) {
    return line(index).get(8).getAsInt();
  }

  public int getTopPadding() {
    return topPadding;
  }

  public int getBottomPadding() {
    return bottomPadding;
  }

  public int getLineForVertical(int y) {
    int lo = 0, hi = getLineCount() - 1;
    while (lo < hi) {
      int mid = (lo + hi + 1) >>> 1;
      if (getLineTop(mid) <= y) lo = mid;
      else hi = mid - 1;
    }
    return lo;
  }

  public int getLineForOffset(int offset) {
    if (offset < 0 || offset > text.length()) throw new IndexOutOfBoundsException();
    int lo = 0, hi = getLineCount() - 1;
    while (lo < hi) {
      int mid = (lo + hi + 1) >>> 1;
      if (getLineStart(mid) <= offset) lo = mid;
      else hi = mid - 1;
    }
    return lo;
  }

  public void draw(Canvas canvas) {
    // Android plain-String drawing uses Paint fields; span-only background and
    // baselineShift are not applied by this path.
    TextPaint drawing = new TextPaint(paint);
    drawing.setTextAlign(Paint.Align.LEFT);
    for (int index = 0; index < getLineCount(); index++) {
      drawing.setTextDirectionForLayout(getParagraphDirection(index));
      canvas.drawText(
          text.subSequence(getLineStart(index), getLineVisibleEnd(index)).toString(),
          getLineLeft(index),
          getLineBaseline(index),
          drawing);
    }
  }
}
