package tachiyomi.decoder;

import android.graphics.*;
import java.io.*;

/** The deprecated region-decoder ABI, implemented with the browser raster backend. */
public final class ImageDecoder {
  public static final Companion Companion = new Companion();
  private Bitmap bitmap;

  private ImageDecoder(Bitmap b) {
    bitmap = b;
  }

  private void check() {
    if (bitmap == null) throw new IllegalStateException("Decoder recycled");
  }

  public int getWidth() {
    check();
    return bitmap.getWidth();
  }

  public int getHeight() {
    check();
    return bitmap.getHeight();
  }

  public Bitmap decode(Rect region, int sampleSize) {
    check();
    int sample = Math.max(1, Integer.highestOneBit(Math.max(1, sampleSize)));
    Bitmap cropped =
        Bitmap.createBitmap(bitmap, region.left, region.top, region.width(), region.height());
    if (sample == 1) return cropped;
    Bitmap scaled =
        Bitmap.createScaledBitmap(
            cropped,
            Math.max(1, cropped.getWidth() / sample),
            Math.max(1, cropped.getHeight() / sample),
            true);
    cropped.recycle();
    return scaled;
  }

  public static Bitmap decode$default(
      ImageDecoder decoder, Rect region, int sample, int mask, Object marker) {
    return decoder.decode(region, (mask & 2) != 0 ? 1 : sample);
  }

  public void recycle() {
    if (bitmap != null) {
      bitmap.recycle();
      bitmap = null;
    }
  }

  public static final class Companion {
    public ImageDecoder newInstance(InputStream in, boolean cropBorders, byte[] background) {
      if (cropBorders) throw new UnsupportedOperationException("Automatic border detection");
      Bitmap b = BitmapFactory.decodeStream(in);
      return b == null ? null : new ImageDecoder(b);
    }

    public static ImageDecoder newInstance$default(
        Companion self, InputStream in, boolean crop, byte[] background, int mask, Object marker) {
      return self.newInstance(
          in, (mask & 2) != 0 ? false : crop, (mask & 4) != 0 ? null : background);
    }
  }
}
