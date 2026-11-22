package android.graphics;

import android.util.Size;
import java.io.IOException;
import java.util.Objects;
import prototype.Graphics;

/** Byte-array bitmap decoding through the host's bounded software raster bridge. */
public final class ImageDecoder {
  public static final int ALLOCATOR_DEFAULT = 0;
  public static final int ALLOCATOR_SOFTWARE = 1;
  public static final int ALLOCATOR_SHARED_MEMORY = 2;
  public static final int ALLOCATOR_HARDWARE = 3;

  public static final class Source {
    private final byte[] data;
    private final int offset;
    private final int length;

    private Source(byte[] data, int offset, int length) {
      this.data = data;
      this.offset = offset;
      this.length = length;
    }
  }

  public static final class ImageInfo {
    private final Size size;
    private final String mimeType;

    private ImageInfo(BitmapFactory.Options bounds) {
      size = new Size(bounds.outWidth, bounds.outHeight);
      mimeType = bounds.outMimeType;
    }

    public Size getSize() {
      return size;
    }

    public String getMimeType() {
      return mimeType;
    }
  }

  @FunctionalInterface
  public interface OnHeaderDecodedListener {
    void onHeaderDecoded(ImageDecoder decoder, ImageInfo info, Source source);
  }

  private int allocator = ALLOCATOR_DEFAULT;

  private ImageDecoder() {}

  public static Source createSource(byte[] data) {
    return createSource(data, 0, data.length);
  }

  public static Source createSource(byte[] data, int offset, int length) {
    Objects.requireNonNull(data);
    if (offset < 0 || length < 0 || offset > data.length - length)
      throw new ArrayIndexOutOfBoundsException();
    return new Source(data, offset, length);
  }

  public int getAllocator() {
    return allocator;
  }

  public void setAllocator(int allocator) {
    if (allocator < ALLOCATOR_DEFAULT || allocator > ALLOCATOR_HARDWARE)
      throw new IllegalArgumentException("Invalid image allocator");
    this.allocator = allocator;
  }

  public static Bitmap decodeBitmap(Source source) throws IOException {
    return decode(Objects.requireNonNull(source), null);
  }

  public static Bitmap decodeBitmap(Source source, OnHeaderDecodedListener listener)
      throws IOException {
    return decode(Objects.requireNonNull(source), Objects.requireNonNull(listener));
  }

  private static Bitmap decode(Source source, OnHeaderDecodedListener listener) throws IOException {
    String handle =
        Graphics.upload(source.data, source.offset, source.length, Graphics.IMAGE_LIMIT);
    try {
      if (listener != null) {
        BitmapFactory.Options bounds = new BitmapFactory.Options();
        bounds.inJustDecodeBounds = true;
        BitmapFactory.decodeHandle(handle, bounds);
        if (bounds.outMimeType == null) throw new IOException("Cannot read image header");
        ImageDecoder decoder = new ImageDecoder();
        listener.onHeaderDecoded(decoder, new ImageInfo(bounds), source);
        if (decoder.allocator > ALLOCATOR_SOFTWARE)
          throw new UnsupportedOperationException("Image allocator " + decoder.allocator);
      }
      Bitmap bitmap = BitmapFactory.decodeHandle(handle, null);
      if (bitmap == null) throw new IOException("Cannot decode image");
      return bitmap;
    } finally {
      Graphics.closeBytes(handle);
    }
  }
}
