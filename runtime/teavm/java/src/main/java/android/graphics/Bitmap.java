package android.graphics;

import java.io.*;
import java.nio.*;
import java.util.*;
import com.google.gson.*;
import prototype.Graphics;

public final class Bitmap {
  public enum Config {
    ALPHA_8,
    RGB_565,
    ARGB_4444,
    ARGB_8888,
    RGBA_F16,
    HARDWARE
  }

  public enum CompressFormat {
    JPEG,
    PNG,
    WEBP,
    WEBP_LOSSY,
    WEBP_LOSSLESS
  }

  private Graphics.BitmapLease lease;
  private final int width, height;
  private final Config config;
  private boolean mutable;
  private int density = 160;

  private Bitmap(int id, int w, int h, Config c, boolean mutable) {
    lease = Graphics.claimBitmap(id);
    width = w;
    height = h;
    config = c;
    this.mutable = mutable;
  }

  static Bitmap wrap(JsonObject r, Config c, boolean mutable) {
    return new Bitmap(
        r.get("id").getAsInt(), r.get("width").getAsInt(), r.get("height").getAsInt(), c, mutable);
  }

  public static Bitmap createBitmap(int w, int h, Config c) {
    Objects.requireNonNull(c);
    if (w <= 0 || h <= 0) throw new IllegalArgumentException("width and height must be > 0");
    if (c != Config.ARGB_8888 && c != Config.RGBA_F16)
      throw new UnsupportedOperationException("Bitmap config " + c);
    JsonObject a = Graphics.args();
    a.addProperty("width", w);
    a.addProperty("height", h);
    a.addProperty("f16", c == Config.RGBA_F16);
    return wrap(Graphics.call("create", a), c, true);
  }

  public static Bitmap createBitmap(Bitmap b) {
    return b.copy(b.config, false);
  }

  public static Bitmap createBitmap(Bitmap b, int x, int y, int w, int h) {
    b.region(x, y, w, h);
    Bitmap n = createBitmap(w, h, b.config);
    try {
      n.density = b.density;
      new Canvas(n).drawBitmap(b, new Rect(x, y, x + w, y + h), new Rect(0, 0, w, h), null);
      return n;
    } catch (RuntimeException | Error error) {
      n.recycle();
      throw error;
    }
  }

  public static Bitmap createScaledBitmap(Bitmap b, int w, int h, boolean filter) {
    b.check();
    if (w == b.width && h == b.height && !b.mutable) return b;
    Bitmap n = createBitmap(w, h, b.config);
    try {
      n.density = b.density;
      Paint p = new Paint();
      p.setFilterBitmap(filter);
      new Canvas(n).drawBitmap(b, null, new Rect(0, 0, w, h), p);
      return n;
    } catch (RuntimeException | Error error) {
      n.recycle();
      throw error;
    }
  }

  public Bitmap copy(Config c, boolean mutable) {
    check();
    Bitmap b = createBitmap(width, height, c);
    try {
      new Canvas(b)
          .drawBitmap(this, new Rect(0, 0, width, height), new Rect(0, 0, width, height), null);
      b.density = density;
      b.mutable = mutable;
      return b;
    } catch (RuntimeException | Error error) {
      b.recycle();
      throw error;
    }
  }

  void check() {
    if (lease == null) throw new IllegalStateException("Bitmap has been recycled");
  }

  public int id() {
    check();
    return Graphics.bitmapId(lease);
  }

  public int getWidth() {
    return width;
  }

  public int getHeight() {
    return height;
  }

  public Config getConfig() {
    return config;
  }

  public boolean isMutable() {
    return mutable;
  }

  public boolean isRecycled() {
    return lease == null;
  }

  public int getDensity() {
    return density;
  }

  public void setDensity(int n) {
    density = n;
  }

  public int getByteCount() {
    return Math.multiplyExact(Math.multiplyExact(width, height), config == Config.RGBA_F16 ? 8 : 4);
  }

  public int getAllocationByteCount() {
    return getByteCount();
  }

  public int getRowBytes() {
    return width * (config == Config.RGBA_F16 ? 8 : 4);
  }

  public boolean hasAlpha() {
    return true;
  }

  public void recycle() {
    if (lease != null) {
      Graphics.recycleBitmap(lease);
      lease = null;
    }
  }

  void region(int x, int y, int w, int h) {
    check();
    if (x < 0 || y < 0 || w < 0 || h < 0 || x > width - w || y > height - h)
      throw new IllegalArgumentException("Bitmap region out of bounds");
  }

  public int getPixel(int x, int y) {
    int[] out = new int[1];
    getPixels(out, 0, 1, x, y, 1, 1);
    return out[0];
  }

  public void getPixels(int[] out, int offset, int stride, int x, int y, int w, int h) {
    region(x, y, w, h);
    checkArray(out.length, offset, stride, w, h);
    if (w == 0 || h == 0) return;
    for (int row = 0; row < h; row++)
      for (int col = 0; col < w; col += Graphics.CHUNK / 4) {
        int count = Math.min(Graphics.CHUNK / 4, w - col);
        byte[] data = readPixelBlock(x + col, y + row, count, 1);
        for (int pixel = 0; pixel < count; pixel++)
          out[offset + row * stride + col + pixel] = packedColor(data, pixel * 4);
      }
  }

  public void setPixel(int x, int y, int color) {
    setPixels(new int[] {color}, 0, 1, x, y, 1, 1);
  }

  public void setPixels(int[] data, int offset, int stride, int x, int y, int w, int h) {
    region(x, y, w, h);
    if (!mutable) throw new IllegalStateException("Immutable bitmap");
    checkArray(data.length, offset, stride, w, h);
    if (w == 0 || h == 0) return;
    for (int row = 0; row < h; row++)
      for (int col = 0; col < w; col += Graphics.CHUNK / 4) {
        int count = Math.min(Graphics.CHUNK / 4, w - col);
        byte[] bytes = new byte[count * 4];
        for (int pixel = 0; pixel < count; pixel++)
          writeColor(bytes, pixel * 4, data[offset + row * stride + col + pixel]);
        putTile("putPixels", tile(x + col, y + row, count, 1, false), bytes);
      }
  }

  Bitmap copyFiltered(ColorMatrixColorFilter filter, int paintAlpha) {
    check();
    if (config != Config.ARGB_8888)
      throw new UnsupportedOperationException("Color matrix requires an ARGB_8888 bitmap");
    Bitmap filtered = createBitmap(width, height, config);
    try {
      filtered.density = density;
      int tileWidth = Math.min(width, Graphics.CHUNK / 4);
      int tileHeight = Graphics.CHUNK / (4 * tileWidth);
      for (int y = 0; y < height; y += tileHeight) {
        int rows = Math.min(tileHeight, height - y);
        for (int x = 0; x < width; x += tileWidth) {
          int columns = Math.min(tileWidth, width - x);
          byte[] rgba = readPixelBlock(x, y, columns, rows);
          for (int offset = 0; offset < rgba.length; offset += 4)
            writeColor(rgba, offset, filter.filterColor(packedColor(rgba, offset), paintAlpha));
          filtered.putTile("putPixels", filtered.tile(x, y, columns, rows, false), rgba);
        }
      }
      return filtered;
    } catch (RuntimeException | Error error) {
      filtered.recycle();
      throw error;
    }
  }

  private static int packedColor(byte[] rgba, int offset) {
    return Color.argb(
        rgba[offset + 3] & 255, rgba[offset] & 255, rgba[offset + 1] & 255, rgba[offset + 2] & 255);
  }

  private static void writeColor(byte[] rgba, int offset, int color) {
    rgba[offset] = (byte) Color.red(color);
    rgba[offset + 1] = (byte) Color.green(color);
    rgba[offset + 2] = (byte) Color.blue(color);
    rgba[offset + 3] = (byte) Color.alpha(color);
  }

  private byte[] readPixelBlock(int x, int y, int width, int height) {
    JsonObject result = Graphics.call("pixels", tile(x, y, width, height, false));
    String handle = result.get("bytes").getAsString();
    try {
      byte[] data = Graphics.readBytes(handle);
      if (data == null || data.length != width * height * 4)
        throw new IllegalStateException("Invalid pixel block");
      return data;
    } finally {
      Graphics.closeBytes(handle);
    }
  }

  private JsonObject tile(int x, int y, int width, int height, boolean f16) {
    JsonObject a = Graphics.args();
    a.addProperty("id", id());
    a.addProperty("f16", f16);
    a.add("rect", Graphics.numbers(x, y, width, height));
    return a;
  }

  private void putTile(String operation, JsonObject args, byte[] bytes) {
    String handle = Graphics.upload(bytes, 0, bytes.length, Graphics.CHUNK);
    try {
      args.addProperty("bytes", handle);
      Graphics.call(operation, args);
    } finally {
      Graphics.closeBytes(handle);
    }
  }

  private static void checkArray(int len, int offset, int stride, int w, int h) {
    if (w == 0 || h == 0) return;
    if (Math.abs((long) stride) < w) throw new IllegalArgumentException("abs(stride) < width");
    long last = offset + (long) (h - 1) * stride;
    if (offset < 0 || offset > len - w || last < 0 || last > len - w)
      throw new ArrayIndexOutOfBoundsException();
  }

  public void eraseColor(int color) {
    if (!mutable) throw new IllegalStateException("Immutable bitmap");
    JsonObject a = Graphics.args();
    a.addProperty("id", id());
    a.addProperty("color", color);
    Graphics.call("erase", a);
  }

  public void copyPixelsFromBuffer(Buffer buffer) {
    check();
    if (!mutable) throw new IllegalStateException("Immutable bitmap");
    if (!(buffer instanceof ByteBuffer))
      throw new UnsupportedOperationException("Pixel source must be a ByteBuffer");
    ByteBuffer b = (ByteBuffer) buffer;
    if (b.remaining() < getByteCount())
      throw new RuntimeException("Buffer not large enough for pixels");
    boolean f16 = config == Config.RGBA_F16;
    int pixelBytes = f16 ? 8 : 4, blockPixels = Graphics.CHUNK / pixelBytes;
    for (int row = 0; row < height; row++)
      for (int col = 0; col < width; col += blockPixels) {
        int count = Math.min(blockPixels, width - col);
        byte[] bytes = new byte[count * pixelBytes];
        b.get(bytes);
        putTile("putRaw", tile(col, row, count, 1, f16), bytes);
      }
  }

  public void copyPixelsToBuffer(Buffer buffer) {
    check();
    if (!(buffer instanceof ByteBuffer))
      throw new UnsupportedOperationException("Pixel target must be a ByteBuffer");
    ByteBuffer b = (ByteBuffer) buffer;
    if (b.remaining() < getByteCount())
      throw new RuntimeException("Buffer not large enough for pixels");
    boolean f16 = config == Config.RGBA_F16;
    int pixelBytes = f16 ? 8 : 4, blockPixels = Graphics.CHUNK / pixelBytes;
    for (int row = 0; row < height; row++)
      for (int col = 0; col < width; col += blockPixels) {
        int count = Math.min(blockPixels, width - col);
        JsonObject result = Graphics.call("raw", tile(col, row, count, 1, f16));
        String handle = result.get("bytes").getAsString();
        try {
          byte[] bytes = Graphics.readBytes(handle);
          if (bytes == null || bytes.length != count * pixelBytes)
            throw new IllegalStateException("Invalid raw block");
          b.put(bytes);
        } finally {
          Graphics.closeBytes(handle);
        }
      }
  }

  public boolean compress(CompressFormat format, int quality, OutputStream stream) {
    check();
    Objects.requireNonNull(format);
    Objects.requireNonNull(stream);
    if (quality < 0 || quality > 100) throw new IllegalArgumentException("quality must be 0..100");
    JsonObject a = Graphics.args();
    a.addProperty("id", id());
    a.addProperty("format", format.name());
    a.addProperty("quality", quality);
    JsonObject r = Graphics.async("encode", a);
    if (!r.get("ok").getAsBoolean()) return false;
    try {
      Graphics.copyOutput(r, stream);
      return true;
    } catch (IOException e) {
      return false;
    }
  }
}
