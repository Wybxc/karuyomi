package android.graphics;

import com.google.gson.*;
import java.util.*;
import prototype.Graphics;

public class Canvas {
  private static final int MAX_SAVE_DEPTH = 128;
  private Bitmap bitmap;
  private Matrix matrix = new Matrix();
  private JsonArray clip;
  private final List<State> stack = new ArrayList<>();

  private record State(Matrix matrix, JsonArray clip) {}

  public Canvas() {}

  public Canvas(Bitmap b) {
    setBitmap(b);
  }

  public void setBitmap(Bitmap b) {
    if (b != null) {
      b.check();
      if (!b.isMutable()) throw new IllegalStateException("Immutable bitmap");
    }
    bitmap = b;
    matrix = new Matrix();
    clip = null;
    stack.clear();
  }

  public int getWidth() {
    return bitmap == null ? 0 : bitmap.getWidth();
  }

  public int getHeight() {
    return bitmap == null ? 0 : bitmap.getHeight();
  }

  private JsonObject args(Paint p) {
    return args(p, matrix);
  }

  private JsonObject args(Paint p, Matrix transform) {
    if (bitmap == null) throw new IllegalStateException("No bitmap");
    bitmap.check();
    JsonObject a = Graphics.args();
    a.addProperty("id", bitmap.id());
    a.add("matrix", Graphics.numbers(transform.rasterValues()));
    if (clip != null) a.add("clip", clip);
    a.add("paint", (p == null ? new Paint() : p).json());
    return a;
  }

  public int save() {
    if (stack.size() >= MAX_SAVE_DEPTH) throw new IllegalStateException("Canvas save limit");
    int n = getSaveCount();
    stack.add(new State(new Matrix(matrix), clip));
    return n;
  }

  public int getSaveCount() {
    return stack.size() + 1;
  }

  public void restore() {
    if (stack.isEmpty()) throw new IllegalStateException("Underflow in restore");
    State saved = stack.remove(stack.size() - 1);
    matrix = saved.matrix();
    clip = saved.clip();
  }

  public void restoreToCount(int n) {
    if (n < 1) throw new IllegalArgumentException();
    while (getSaveCount() > n) restore();
  }

  public void translate(float x, float y) {
    matrix.preTranslate(x, y);
  }

  public void scale(float x, float y) {
    matrix.preScale(x, y);
  }

  public void scale(float x, float y, float px, float py) {
    matrix.preScale(x, y, px, py);
  }

  public void rotate(float degrees) {
    rotate(degrees, 0, 0);
  }

  public void rotate(float degrees, float px, float py) {
    if (degrees == 0) return;
    matrix.preRotate(degrees, px, py);
  }

  public boolean clipRect(float left, float top, float right, float bottom) {
    if (bitmap == null) return false;
    JsonObject a = args(null);
    a.add("rect", Graphics.numbers(left, top, right, bottom));
    clip = Graphics.call("clipRect", a).getAsJsonArray("clip");
    return !clip.isEmpty();
  }

  public void drawColor(int color) {
    JsonObject a = args(null);
    a.addProperty("color", color);
    Graphics.call("color", a);
  }

  public void drawBitmap(Bitmap s, float x, float y, Paint p) {
    s.check();
    if (bitmap == null) throw new IllegalStateException("No bitmap");
    float ratio =
        bitmap.getDensity() == 0 || s.getDensity() == 0
            ? 1
            : (float) bitmap.getDensity() / s.getDensity();
    RectF dst = new RectF(x, y, x + s.getWidth() * ratio, y + s.getHeight() * ratio);
    drawBitmap(s, null, dst, p, matrix);
  }

  public void drawBitmap(Bitmap s, Rect src, Rect dst, Paint p) {
    drawBitmap(s, src, new RectF(dst), p);
  }

  public void drawBitmap(Bitmap s, Rect src, RectF dst, Paint p) {
    drawBitmap(s, src, dst, p, matrix);
  }

  public void drawBitmap(Bitmap s, Matrix transform, Paint p) {
    Matrix composed = new Matrix(matrix);
    composed.preConcat(Objects.requireNonNull(transform));
    drawBitmap(s, null, new RectF(0, 0, s.getWidth(), s.getHeight()), p, composed);
  }

  private void drawBitmap(Bitmap s, Rect src, RectF dst, Paint p, Matrix transform) {
    s.check();
    if (bitmap == null) throw new IllegalStateException("No bitmap");
    bitmap.check();
    Objects.requireNonNull(dst);
    Bitmap input = s;
    try {
      ColorFilter filter = p == null ? null : p.getColorFilter();
      Paint paint = p;
      if (filter instanceof ColorMatrixColorFilter colorMatrix) {
        int width = src == null ? s.getWidth() : src.width();
        int height = src == null ? s.getHeight() : src.height();
        // Filtering a temporary source is equivalent only when rasterization does not resample it.
        if (!transform.mapsWholePixels()
            || !Matrix.whole(dst.left)
            || !Matrix.whole(dst.top)
            || dst.width() != width
            || dst.height() != height)
          throw new UnsupportedOperationException(
              "Color matrix requires pixel-aligned bitmap draw");
        input = s.copyFiltered(colorMatrix, p.getAlpha());
        paint = new Paint(p);
        paint.setColorFilter(null);
        paint.setAlpha(255);
      }
      JsonObject a = args(paint, transform);
      a.addProperty("source", input.id());
      a.add(
          "src",
          src == null
              ? Graphics.numbers(0, 0, s.getWidth(), s.getHeight())
              : Graphics.numbers(src.left, src.top, src.right, src.bottom));
      a.add("dst", Graphics.numbers(dst.left, dst.top, dst.right, dst.bottom));
      Graphics.call("drawBitmap", a);
    } finally {
      if (input != s) input.recycle();
    }
  }

  public void drawRoundRect(RectF r, float rx, float ry, Paint p) {
    JsonObject a = args(p);
    a.add("rect", Graphics.numbers(r.left, r.top, r.right, r.bottom));
    a.addProperty("rx", rx);
    a.addProperty("ry", ry);
    Graphics.call("roundRect", a);
  }

  public void drawRect(float l, float t, float r, float b, Paint p) {
    drawRoundRect(new RectF(l, t, r, b), 0, 0, p);
  }

  public void drawRect(Rect r, Paint p) {
    drawRect(r.left, r.top, r.right, r.bottom, p);
  }

  public void drawText(String s, float x, float y, Paint p) {
    JsonObject a = args(p);
    a.addProperty("text", s);
    a.addProperty("x", x);
    a.addProperty("y", y);
    Graphics.call("text", a);
  }
}
