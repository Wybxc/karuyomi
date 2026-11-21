package android.graphics;

import java.util.Arrays;

public class ColorMatrix {
  private final float[] values = new float[20];

  public ColorMatrix() {
    reset();
  }

  public ColorMatrix(float[] values) {
    set(values);
  }

  public ColorMatrix(ColorMatrix source) {
    set(source.values);
  }

  public float[] getArray() {
    return values;
  }

  public void reset() {
    Arrays.fill(values, 0);
    values[0] = values[6] = values[12] = values[18] = 1;
  }

  public void set(float[] values) {
    System.arraycopy(values, 0, this.values, 0, this.values.length);
  }
}
