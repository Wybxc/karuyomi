package android.graphics;

public class ColorMatrixColorFilter extends ColorFilter {
  private final float[] matrix;

  public ColorMatrixColorFilter(ColorMatrix matrix) {
    this(matrix.getArray());
  }

  public ColorMatrixColorFilter(float[] matrix) {
    this.matrix = new float[20];
    System.arraycopy(matrix, 0, this.matrix, 0, this.matrix.length);
  }

  @Override
  int filterColor(int argb) {
    return filterColor(argb, 255);
  }

  int filterColor(int argb, int paintAlpha) {
    int r = Color.red(argb), g = Color.green(argb), b = Color.blue(argb);
    float a = Color.alpha(argb) * (paintAlpha / 255f);
    return Color.argb(
        channel(15, r, g, b, a),
        channel(0, r, g, b, a),
        channel(5, r, g, b, a),
        channel(10, r, g, b, a));
  }

  private int channel(int offset, int r, int g, int b, float a) {
    float value =
        matrix[offset] * r
            + matrix[offset + 1] * g
            + matrix[offset + 2] * b
            + matrix[offset + 3] * a
            + matrix[offset + 4];
    return Math.max(0, Math.min(255, Math.round(value)));
  }
}
