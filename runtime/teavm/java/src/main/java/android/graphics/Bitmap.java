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

  private int id;
  private final int width, height;
  private final Config config;
  private final boolean mutable;
  private int density = 160;

  private Bitmap(int id, int w, int h, Config c, boolean mutable) {
    this.id = id;
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
    n.density = b.density;
    new Canvas(n).drawBitmap(b, new Rect(x, y, x + w, y + h), new Rect(0, 0, w, h), null);
    return n;
  }

  public static Bitmap createScaledBitmap(Bitmap b, int w, int h, boolean filter) {
    b.check();
    if (w == b.width && h == b.height) return b;
    Bitmap n = createBitmap(w, h, b.config);
    n.density = b.density;
    Paint p = new Paint();
    p.setFilterBitmap(filter);
    new Canvas(n).drawBitmap(b, null, new Rect(0, 0, w, h), p);
    return n;
  }

  public Bitmap copy(Config c, boolean mutable) {
    check();
    Bitmap b = createBitmap(width, height, c);
    new Canvas(b)
        .drawBitmap(this, new Rect(0, 0, width, height), new Rect(0, 0, width, height), null);
    b.density = density;
    return mutable ? b : new Bitmap(b.id, b.width, b.height, c, false);
  }

  void check() {
    if (id == 0) throw new IllegalStateException("Bitmap has been recycled");
  }

  public int id() {
    check();
    return id;
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
    return id == 0;
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
    if (id != 0) {
      JsonObject a = Graphics.args();
      a.addProperty("id", id);
      Graphics.call("recycle", a);
      id = 0;
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
    JsonObject a = Graphics.args();
    a.addProperty("id", id);
    a.add("rect", Graphics.numbers(x, y, w, h));
    byte[] data = Base64.getDecoder().decode(Graphics.call("pixels", a).get("body").getAsString());
    for (int row = 0; row < h; row++)
      for (int col = 0; col < w; col++) {
        int p = (row * w + col) * 4;
        out[offset + row * stride + col] =
            Color.argb(data[p + 3] & 255, data[p] & 255, data[p + 1] & 255, data[p + 2] & 255);
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
    byte[] bytes = new byte[w * h * 4];
    for (int row = 0; row < h; row++)
      for (int col = 0; col < w; col++) {
        int c = data[offset + row * stride + col], p = (row * w + col) * 4;
        bytes[p] = (byte) Color.red(c);
        bytes[p + 1] = (byte) Color.green(c);
        bytes[p + 2] = (byte) Color.blue(c);
        bytes[p + 3] = (byte) Color.alpha(c);
      }
    JsonObject a = Graphics.args();
    a.addProperty("id", id);
    a.add("rect", Graphics.numbers(x, y, w, h));
    a.addProperty("body", Base64.getEncoder().encodeToString(bytes));
    Graphics.call("putPixels", a);
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
    byte[] bytes = new byte[getByteCount()];
    b.get(bytes);
    JsonObject a = Graphics.args();
    a.addProperty("id", id);
    a.addProperty("f16", config == Config.RGBA_F16);
    a.addProperty("body", Base64.getEncoder().encodeToString(bytes));
    Graphics.call("putRaw", a);
  }

  public void copyPixelsToBuffer(Buffer buffer) {
    check();
    if (!(buffer instanceof ByteBuffer))
      throw new UnsupportedOperationException("Pixel target must be a ByteBuffer");
    ByteBuffer b = (ByteBuffer) buffer;
    if (b.remaining() < getByteCount())
      throw new RuntimeException("Buffer not large enough for pixels");
    JsonObject a = Graphics.args();
    a.addProperty("id", id);
    a.addProperty("f16", config == Config.RGBA_F16);
    b.put(Base64.getDecoder().decode(Graphics.call("raw", a).get("body").getAsString()));
  }

  public boolean compress(CompressFormat format, int quality, OutputStream stream) {
    check();
    Objects.requireNonNull(format);
    Objects.requireNonNull(stream);
    if (quality < 0 || quality > 100) throw new IllegalArgumentException("quality must be 0..100");
    JsonObject a = Graphics.args();
    a.addProperty("id", id);
    a.addProperty("format", format.name());
    a.addProperty("quality", quality);
    JsonObject r = Graphics.async("encode", a);
    if (!r.get("ok").getAsBoolean()) return false;
    try {
      stream.write(Base64.getDecoder().decode(r.get("body").getAsString()));
      return true;
    } catch (IOException e) {
      return false;
    }
  }
}
