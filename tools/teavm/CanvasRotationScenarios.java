package prototype;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Rect;
import android.graphics.RectF;

/** Runs the rotated and mirrored tile draw used by Sources on Android and TeaVM. */
public final class CanvasRotationScenarios {
  public static void run() {
    Bitmap tile = Bitmap.createBitmap(2, 1, Bitmap.Config.ARGB_8888);
    Bitmap output = Bitmap.createBitmap(4, 5, Bitmap.Config.ARGB_8888);
    try {
      tile.setPixel(0, 0, Color.RED);
      tile.setPixel(1, 0, Color.BLUE);
      Canvas canvas = new Canvas(output);
      Rect source = new Rect(0, 0, 2, 1);
      RectF target = new RectF(0, 0, 2, 1);

      canvas.save();
      canvas.translate(2, 0);
      canvas.rotate(90);
      canvas.drawBitmap(tile, source, target, null);
      canvas.restore();

      canvas.save();
      canvas.translate(2, 3);
      canvas.rotate(-90);
      canvas.scale(-1, 1);
      canvas.drawBitmap(tile, source, target, null);
      canvas.restore();

      canvas.drawBitmap(tile, 0, 3, null);

      pixel(output, 1, 0, Color.RED);
      pixel(output, 1, 1, Color.BLUE);
      pixel(output, 2, 3, Color.RED);
      pixel(output, 2, 4, Color.BLUE);
      pixel(output, 0, 3, Color.RED);
      pixel(output, 1, 3, Color.BLUE);
      pixel(output, 3, 3, Color.TRANSPARENT);
    } finally {
      output.recycle();
      tile.recycle();
    }
  }

  private static void pixel(Bitmap bitmap, int x, int y, int expected) {
    int actual = bitmap.getPixel(x, y);
    if (actual != expected) {
      throw new AssertionError(
          "Pixel (" + x + ", " + y + "): expected " + expected + ", got " + actual);
    }
  }
}
