package prototype;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import com.google.gson.JsonObject;
import java.io.ByteArrayOutputStream;

/** Original Android and TeaVM share copy contracts; GC timing is tested separately in real JS. */
public final class BitmapLifetimeScenarios {
  private static Bitmap retainedBitmap;
  private static Canvas retainedCanvas;

  public static JsonObject run() {
    int checks = 0;
    Bitmap source = Bitmap.createBitmap(2, 1, Bitmap.Config.ARGB_8888);
    Bitmap immutable = null, mutable = null, scaled = null;
    try {
      source.setPixel(0, 0, Color.RED);
      source.setPixel(1, 0, Color.BLUE);
      immutable = source.copy(Bitmap.Config.ARGB_8888, false);
      check(immutable != source, "copy is a separate Bitmap");
      checks++;
      check(!immutable.isMutable(), "immutable copy flag");
      checks++;
      check(immutable.getPixel(0, 0) == Color.RED, "copied first pixel");
      checks++;
      check(immutable.getPixel(1, 0) == Color.BLUE, "copied second pixel");
      checks++;
      source.setPixel(0, 0, Color.GREEN);
      check(immutable.getPixel(0, 0) == Color.RED, "copy has independent storage");
      checks++;
      boolean rejected = false;
      try {
        immutable.setPixel(0, 0, Color.BLACK);
      } catch (IllegalStateException expected) {
        rejected = true;
      }
      check(rejected, "immutable pixels reject writes");
      checks++;
      check(
          Bitmap.createScaledBitmap(immutable, 2, 1, true) == immutable,
          "same-size immutable scale preserves owner");
      checks++;
      immutable.recycle();
      immutable.recycle();
      check(immutable.isRecycled(), "recycle is idempotent");
      checks++;
      check(
          !source.isRecycled() && source.getPixel(0, 0) == Color.GREEN,
          "recycling copy preserves source");
      checks++;
      mutable = source.copy(Bitmap.Config.ARGB_8888, true);
      check(mutable.isMutable(), "mutable copy flag");
      checks++;
      mutable.eraseColor(Color.WHITE);
      check(source.getPixel(0, 0) == Color.GREEN, "mutable copy writes preserve source");
      checks++;
      scaled = Bitmap.createScaledBitmap(source, 2, 1, true);
      check(scaled != source && scaled.isMutable(), "same-size mutable scale copies storage");
      checks++;
      check(
          mutable.compress(Bitmap.CompressFormat.PNG, 100, new ByteArrayOutputStream()),
          "copy remains encodable");
      checks++;
    } finally {
      if (immutable != null) immutable.recycle();
      if (mutable != null) mutable.recycle();
      if (scaled != null) scaled.recycle();
      source.recycle();
    }
    JsonObject result = new JsonObject();
    result.addProperty("passed", true);
    result.addProperty("checks", checks);
    return result;
  }

  /** Deliberately follows Source code which never explicitly recycles local Bitmaps. */
  public static void allocateUnrecycled(int count) {
    for (int index = 0; index < count; index++) {
      Bitmap bitmap = Bitmap.createBitmap(16, 16, Bitmap.Config.ARGB_8888);
      bitmap.eraseColor(Color.WHITE);
      check(
          bitmap.compress(Bitmap.CompressFormat.PNG, 100, new ByteArrayOutputStream()),
          "unrecycled Bitmap encode");
    }
  }

  public static void retainBitmap() {
    retainedBitmap = Bitmap.createBitmap(16, 16, Bitmap.Config.ARGB_8888);
    retainedBitmap.eraseColor(Color.RED);
  }

  public static void retainCanvasOnly() {
    retainedCanvas = new Canvas(Bitmap.createBitmap(16, 16, Bitmap.Config.ARGB_8888));
  }

  public static void useRetainedOwners() {
    check(retainedBitmap != null && retainedCanvas != null, "retained Java owners");
    check(retainedBitmap.getPixel(0, 0) == Color.RED, "retained Bitmap pixels");
    retainedCanvas.drawColor(Color.BLUE);
    check(retainedCanvas.getWidth() == 16, "Canvas retains its Bitmap");
  }

  public static void dropRetainedOwners() {
    retainedBitmap = null;
    retainedCanvas = null;
  }

  private static void check(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
  }
}
