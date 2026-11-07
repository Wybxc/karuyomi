package prototype;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
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

  public static void runClipAndMiter() {
    Bitmap tile = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888);
    Bitmap output = Bitmap.createBitmap(10, 10, Bitmap.Config.ARGB_8888);
    try {
      tile.eraseColor(Color.YELLOW);
      Canvas canvas = new Canvas(output);
      int original = canvas.save();
      canvas.rotate(45, 5, 5);
      require(canvas.clipRect(3, 3, 7, 7), "pivot clip");
      canvas.rotate(-45, 5, 5);
      canvas.drawColor(Color.RED);
      canvas.drawBitmap(tile, 5, 5, null);
      canvas.drawRect(3, 5, 5, 6, new Paint());
      pixel(output, 5, 5, Color.YELLOW);
      pixel(output, 4, 5, Color.BLACK);
      pixel(output, 5, 6, Color.RED);
      pixel(output, 3, 3, Color.TRANSPARENT);
      pixel(output, 2, 5, Color.TRANSPARENT);
      pixel(output, 3, 5, Color.BLACK);

      int clipped = canvas.save();
      require(!canvas.clipRect(8, 8, 10, 10), "nonoverlapping clips");
      canvas.drawColor(Color.BLUE);
      pixel(output, 5, 6, Color.RED);
      canvas.restoreToCount(clipped);
      require(canvas.clipRect(4, 5, 6, 6), "restored clip");
      canvas.drawColor(Color.GREEN);
      pixel(output, 4, 5, Color.GREEN);
      pixel(output, 4, 6, Color.RED);
      canvas.restoreToCount(original);
      canvas.drawColor(Color.WHITE);
      pixel(output, 0, 0, Color.WHITE);

      canvas.save();
      require(!canvas.clipRect(11, 1, 20, 3), "outside drawable");
      canvas.drawColor(Color.RED);
      pixel(output, 0, 0, Color.WHITE);
      canvas.restore();

      canvas.save();
      require(canvas.clipRect(4, 2, 2, 4), "inverted rectangle is sorted");
      canvas.drawColor(Color.BLUE);
      pixel(output, 2, 2, Color.BLUE);
      pixel(output, 4, 2, Color.WHITE);
      canvas.restore();
      canvas.drawColor(Color.WHITE);

      canvas.save();
      require(!canvas.clipRect(0.1f, 0.1f, 0.2f, 0.2f), "subpixel clip contains no bitmap pixel");
      canvas.restore();

      Paint paint = new Paint();
      paint.setStyle(Paint.Style.STROKE);
      paint.setStrokeJoin(Paint.Join.MITER);
      paint.setStrokeWidth(4);
      require(paint.getStrokeMiter() == 4, "default miter");
      canvas.drawRect(3, 3, 7, 7, paint);
      pixel(output, 1, 1, Color.BLACK);
      canvas.drawColor(Color.WHITE);
      paint.setStrokeMiter(1);
      Paint copied = new Paint(paint);
      copied.setStrokeMiter(-1);
      require(copied.getStrokeMiter() == 1, "copied miter, negative ignored");
      canvas.drawRect(3, 3, 7, 7, copied);
      pixel(output, 1, 1, Color.WHITE);
      pixel(output, 4, 2, Color.BLACK);
    } finally {
      output.recycle();
      tile.recycle();
    }
  }

  private static void require(boolean value, String message) {
    if (!value) throw new AssertionError(message);
  }

  private static void pixel(Bitmap bitmap, int x, int y, int expected) {
    int actual = bitmap.getPixel(x, y);
    if (actual != expected) {
      throw new AssertionError(
          "Pixel (" + x + ", " + y + "): expected " + expected + ", got " + actual);
    }
  }
}
