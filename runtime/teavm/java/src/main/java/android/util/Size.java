package android.util;

/** Immutable integer dimensions. */
public final class Size {
  private final int width;
  private final int height;

  public Size(int width, int height) {
    this.width = width;
    this.height = height;
  }

  public int getWidth() {
    return width;
  }

  public int getHeight() {
    return height;
  }

  @Override
  public boolean equals(Object other) {
    return other instanceof Size size && width == size.width && height == size.height;
  }

  @Override
  public int hashCode() {
    return height ^ Integer.rotateLeft(width, 16);
  }

  @Override
  public String toString() {
    return width + "x" + height;
  }
}
