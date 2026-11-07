package android.graphics;

import com.google.gson.*;
import java.util.*;
import prototype.Graphics;

public class Canvas {
  private static final int MAX_SAVE_DEPTH = 128;
  private Bitmap bitmap;
  private float[] matrix = {1, 0, 0, 1, 0, 0};
  private JsonArray clip;
  private final List<State> stack = new ArrayList<>();

  private record State(float[] matrix, JsonArray clip) {}

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
    matrix = new float[] {1, 0, 0, 1, 0, 0};
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
    if (bitmap == null) throw new IllegalStateException("No bitmap");
    bitmap.check();
    JsonObject a = Graphics.args();
    a.addProperty("id", bitmap.id());
    a.add("matrix", Graphics.numbers(matrix));
    if (clip != null) a.add("clip", clip);
    a.add("paint", (p == null ? new Paint() : p).json());
    return a;
  }

  public int save() {
    if (stack.size() >= MAX_SAVE_DEPTH) throw new IllegalStateException("Canvas save limit");
    int n = getSaveCount();
    stack.add(new State(matrix.clone(), clip));
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
    matrix[4] += matrix[0] * x + matrix[2] * y;
    matrix[5] += matrix[1] * x + matrix[3] * y;
  }

  public void scale(float x, float y) {
    matrix[0] *= x;
    matrix[1] *= x;
    matrix[2] *= y;
    matrix[3] *= y;
  }

  public void rotate(float degrees) {
    if (degrees == 0) return;
    double radians = Math.toRadians(degrees);
    float cos = (float) Math.cos(radians), sin = (float) Math.sin(radians);
    float a = matrix[0], b = matrix[1], c = matrix[2], d = matrix[3];
    // Compose in local coordinates, keeping the existing translation.
    matrix[0] = a * cos + c * sin;
    matrix[1] = b * cos + d * sin;
    matrix[2] = c * cos - a * sin;
    matrix[3] = d * cos - b * sin;
  }

  public void rotate(float degrees, float px, float py) {
    if (degrees == 0) return;
    translate(px, py);
    rotate(degrees);
    translate(-px, -py);
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
    JsonObject a = args(p);
    a.addProperty("source", s.id());
    a.add("src", Graphics.numbers(0, 0, s.getWidth(), s.getHeight()));
    float ratio =
        bitmap.getDensity() == 0 || s.getDensity() == 0
            ? 1
            : (float) bitmap.getDensity() / s.getDensity();
    a.add("dst", Graphics.numbers(x, y, x + s.getWidth() * ratio, y + s.getHeight() * ratio));
    Graphics.call("drawBitmap", a);
  }

  public void drawBitmap(Bitmap s, Rect src, Rect dst, Paint p) {
    drawBitmap(s, src, new RectF(dst), p);
  }

  public void drawBitmap(Bitmap s, Rect src, RectF dst, Paint p) {
    s.check();
    JsonObject a = args(p);
    a.addProperty("source", s.id());
    a.add(
        "src",
        src == null
            ? Graphics.numbers(0, 0, s.getWidth(), s.getHeight())
            : Graphics.numbers(src.left, src.top, src.right, src.bottom));
    a.add("dst", Graphics.numbers(dst.left, dst.top, dst.right, dst.bottom));
    Graphics.call("drawBitmap", a);
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
