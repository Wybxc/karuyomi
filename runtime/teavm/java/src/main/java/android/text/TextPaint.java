package android.text;

import android.graphics.Paint;

/** Android text-paint state backed by the owned raster adapter. */
public class TextPaint extends Paint {
  public int bgColor, baselineShift, linkColor;
  public int[] drawableState;
  public float density = 1;

  public TextPaint() {
    super();
  }

  public TextPaint(int flags) {
    super(flags);
  }

  public TextPaint(Paint paint) {
    super(paint);
  }

  public void set(TextPaint paint) {
    super.set(paint);
    copyText(paint);
  }

  private void copyText(TextPaint paint) {
    bgColor = paint.bgColor;
    baselineShift = paint.baselineShift;
    linkColor = paint.linkColor;
    drawableState = paint.drawableState;
    density = paint.density;
  }
}
