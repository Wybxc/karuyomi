package android.graphics;

/** Affine matrix using the six coefficients accepted by the raster bridge. */
public class Matrix {
  private float[] values = {1, 0, 0, 1, 0, 0};

  public Matrix() {}

  public Matrix(Matrix source) {
    if (source != null) values = source.values.clone();
  }

  public void setTranslate(float dx, float dy) {
    values = translation(dx, dy);
  }

  public boolean preTranslate(float dx, float dy) {
    return pre(translation(dx, dy));
  }

  public boolean postTranslate(float dx, float dy) {
    return post(translation(dx, dy));
  }

  public boolean preScale(float sx, float sy) {
    return preScale(sx, sy, 0, 0);
  }

  public boolean preScale(float sx, float sy, float px, float py) {
    return pre(scaling(sx, sy, px, py));
  }

  public boolean postScale(float sx, float sy, float px, float py) {
    return post(scaling(sx, sy, px, py));
  }

  public boolean preRotate(float degrees, float px, float py) {
    double radians = Math.toRadians(degrees);
    float cos = (float) Math.cos(radians), sin = (float) Math.sin(radians);
    if (degrees % 90 == 0) {
      cos = Math.round(cos);
      sin = Math.round(sin);
    }
    return pre(
        new float[] {cos, sin, -sin, cos, px - px * cos + py * sin, py - px * sin - py * cos});
  }

  public boolean preConcat(Matrix other) {
    return pre(other.values);
  }

  float[] rasterValues() {
    return values;
  }

  boolean mapsWholePixels() {
    boolean diagonal =
        Math.abs(values[0]) == 1 && values[1] == 0 && values[2] == 0 && Math.abs(values[3]) == 1;
    boolean swapped =
        values[0] == 0 && Math.abs(values[1]) == 1 && Math.abs(values[2]) == 1 && values[3] == 0;
    return (diagonal || swapped) && whole(values[4]) && whole(values[5]);
  }

  static boolean whole(float value) {
    return Float.isFinite(value) && value == Math.floor(value);
  }

  private boolean pre(float[] other) {
    values = multiply(values, other);
    return true;
  }

  private boolean post(float[] other) {
    values = multiply(other, values);
    return true;
  }

  private static float[] translation(float x, float y) {
    return new float[] {1, 0, 0, 1, x, y};
  }

  private static float[] scaling(float x, float y, float px, float py) {
    return new float[] {x, 0, 0, y, px * (1 - x), py * (1 - y)};
  }

  private static float[] multiply(float[] left, float[] right) {
    return new float[] {
      left[0] * right[0] + left[2] * right[1],
      left[1] * right[0] + left[3] * right[1],
      left[0] * right[2] + left[2] * right[3],
      left[1] * right[2] + left[3] * right[3],
      left[0] * right[4] + left[2] * right[5] + left[4],
      left[1] * right[4] + left[3] * right[5] + left[5],
    };
  }
}
