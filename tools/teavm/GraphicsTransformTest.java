package android.graphics;

/** Direct checks of the owned raster coefficients and Java-side color filter. */
public final class GraphicsTransformTest {
  private static int checks;

  public static void main(String[] args) {
    Matrix bitmap = new Matrix();
    bitmap.postScale(-1, 1, 1, .5f);
    bitmap.postTranslate(1, 0);
    expect(bitmap, -1, 0, 0, 1, 3, 0);
    Matrix canvas = new Matrix();
    canvas.preTranslate(2, 1);
    Matrix composed = new Matrix(canvas);
    composed.preConcat(bitmap);
    expect(composed, -1, 0, 0, 1, 5, 1);
    require(composed.mapsWholePixels(), "integer mirror and translation");
    expect(canvas, 1, 0, 0, 1, 2, 1);
    expect(bitmap, -1, 0, 0, 1, 3, 0);
    Matrix pivot = new Matrix();
    pivot.preRotate(90, 1, 1);
    expect(pivot, 0, 1, -1, 0, 2, 0);
    require(pivot.mapsWholePixels(), "quarter-turn about a pixel-aligned pivot");
    pivot.setTranslate(3, 2);
    expect(pivot, 1, 0, 0, 1, 3, 2);
    pivot.preScale(2, 1);
    require(!pivot.mapsWholePixels(), "scale resamples the source");
    pivot.setTranslate(.5f, 0);
    require(!pivot.mapsWholePixels(), "fractional translation resamples the source");
    Rect bounds = new Rect(-4, 2, -1, 7);
    require(bounds.exactCenterX() == -2.5f && bounds.exactCenterY() == 4.5f, "half-pixel center");
    Matrix centered = new Matrix();
    centered.preRotate(90, bounds.exactCenterX(), bounds.exactCenterY());
    expect(centered, 0, 1, -1, 0, 2, 7);
    bounds.offset(3, -2);
    require(bounds.exactCenterX() == .5f && bounds.exactCenterY() == 2.5f, "offset center");
    bounds.set(Integer.MAX_VALUE, Integer.MIN_VALUE, Integer.MAX_VALUE, Integer.MIN_VALUE);
    require(bounds.exactCenterX() == -1f && bounds.exactCenterY() == 0f, "Android int arithmetic");

    ColorMatrix source =
        new ColorMatrix(new float[] {0, 0, 1, 0, 0, 0, 1, 0, 0, 32, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0});
    var copied = new ColorMatrix(source);
    var filter = new ColorMatrixColorFilter(copied);
    source.reset();
    copied.getArray()[9] = 0;
    require(filter.filterColor(Color.RED) == Color.rgb(0, 32, 255), "matrix snapshot");
    require(
        filter.filterColor(Color.BLUE, 128) == Color.argb(128, 255, 32, 0),
        "paint alpha with an alpha-preserving filter");
    require(filter.filterColor(Color.WHITE) == Color.WHITE, "RGB clamp");
    var forcedOpaque =
        new ColorMatrixColorFilter(
            new float[] {1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 255});
    require(
        forcedOpaque.filterColor(Color.RED, 128) == Color.RED, "filter can override paint alpha");
    var alphaToRed =
        new ColorMatrixColorFilter(
            new float[] {0, 0, 0, 1, 0, 0, 0, 0, 0, -15, 0, 0, 0, 0, 290, 0, 0, 0, 0, 255});
    require(
        alphaToRed.filterColor(Color.BLUE, 128) == Color.rgb(128, 0, 255),
        "modulated alpha reaches the channel matrix before clamping");
    System.out.println("Graphics transform oracle: " + checks + " checks");
  }

  private static void expect(Matrix matrix, float... expected) {
    float[] actual = matrix.rasterValues();
    for (int i = 0; i < actual.length; i++)
      require(Math.abs(actual[i] - expected[i]) < .0001f, "matrix coefficient " + i);
  }

  private static void require(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
    checks++;
  }
}
