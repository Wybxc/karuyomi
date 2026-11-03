package prototype;

import com.google.gson.*;
import java.io.*;
import java.nio.ByteBuffer;
import org.teavm.jso.*;
import org.teavm.jso.typedarrays.Uint8Array;

/** Raster bridge. Decode/encode suspend the cooperative thread; drawing is synchronous. */
public final class Graphics {
  public static final int CHUNK = 65536;
  public static final int IMAGE_LIMIT = 64 * 1024 * 1024;
  public static final int HEADER_LIMIT = 1024 * 1024;
  public static final int FONT_LIMIT = 8 * 1024 * 1024;

  public static JsonObject args() {
    return new JsonObject();
  }

  public static JsonObject call(String op, JsonObject a) {
    return JsonParser.parseString(sync(control(op, a))).getAsJsonObject();
  }

  public static JsonObject async(String op, JsonObject a) {
    return JsonParser.parseString(Bridge.graphics(control(op, a))).getAsJsonObject();
  }

  private static String control(String op, JsonObject args) {
    args.addProperty("op", op);
    String request = args.toString();
    if (request.length() > CHUNK
        || request.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > CHUNK)
      throw new IllegalArgumentException("Graphics control exceeds 64 KiB");
    return request;
  }

  public static String upload(byte[] input, int offset, int length, int maximum) {
    java.util.Objects.checkFromIndexSize(offset, length, input.length);
    if (length > maximum) throw new IllegalArgumentException("Graphics input exceeds byte budget");
    String handle = openBytes(maximum);
    try {
      for (int position = 0; position < length; position += CHUNK)
        writeBytes(handle, input, offset + position, Math.min(CHUNK, length - position));
      return handle;
    } catch (RuntimeException | Error error) {
      closeBytes(handle);
      throw error;
    }
  }

  public static String upload(InputStream input, int maximum, boolean prefixOnly)
      throws IOException {
    String handle = openBytes(maximum);
    try {
      GraphicsStreams.copyChunks(
          input, (bytes, length) -> writeBytes(handle, bytes, 0, length), maximum, prefixOnly);
      return handle;
    } catch (IOException | RuntimeException | Error error) {
      closeBytes(handle);
      throw error;
    }
  }

  public static void writeBytes(String handle, byte[] input, int offset, int length) {
    java.util.Objects.checkFromIndexSize(offset, length, input.length);
    if (length < 1 || length > CHUNK) throw new IllegalArgumentException("Graphics block size");
    Uint8Array copy = new Uint8Array(length);
    for (int index = 0; index < length; index++)
      copy.set(index, (short) (input[offset + index] & 255));
    writeChunk(handle, copy);
  }

  public static byte[] readBytes(String handle) {
    Uint8Array input = readChunk(handle, CHUNK);
    if (input == null) return null;
    int length = input.getByteLength();
    if (length < 1 || length > CHUNK) throw new IllegalStateException("Graphics block size");
    byte[] copy = new byte[length];
    for (int index = 0; index < length; index++) copy[index] = (byte) input.get(index);
    return copy;
  }

  public static void copyOutput(JsonObject result, OutputStream output) throws IOException {
    String handle = result.get("bytes").getAsString();
    try {
      int expected = result.get("length").getAsInt();
      if (expected < 0 || expected > IMAGE_LIMIT)
        throw new IOException("Graphics output byte budget");
      int total = 0;
      byte[] chunk;
      while ((chunk = readBytes(handle)) != null) {
        if (chunk.length > expected - total)
          throw new IOException("Graphics output length exceeded");
        output.write(chunk);
        total += chunk.length;
      }
      if (total != expected) throw new IOException("Truncated graphics output");
    } finally {
      closeBytes(handle);
    }
  }

  public static ByteBuffer readFrame(JsonObject result) {
    String handle = result.get("bytes").getAsString();
    try {
      int length = result.get("length").getAsInt();
      if (length < 1 || length > IMAGE_LIMIT)
        throw new IllegalStateException("Graphics frame byte budget");
      ByteBuffer output = ByteBuffer.allocate(length);
      byte[] chunk;
      while ((chunk = readBytes(handle)) != null) output.put(chunk);
      if (output.position() != length) throw new IllegalStateException("Truncated graphics frame");
      detachBytes(handle);
      output.flip();
      return output;
    } catch (RuntimeException | Error error) {
      closeBytes(handle);
      throw error;
    }
  }

  /** Opaque JS object strongly held by its Java Bitmap and weakly held by the bridge. */
  public interface BitmapLease extends JSObject {}

  @JSFunctor
  interface BitmapReply extends JSObject {
    void call(BitmapLease value);
  }

  @JSFunctor
  interface IntReply extends JSObject {
    void call(int value);
  }

  public static BitmapLease claimBitmap(int id) {
    BitmapLease[] result = new BitmapLease[1];
    ErrorResult error = new ErrorResult();
    claimBitmap(id, value -> result[0] = value, error::accept);
    error.check();
    return java.util.Objects.requireNonNull(result[0]);
  }

  @JSBody(
      params = {"id", "ok", "fail"},
      script =
          "try {ok(self.teaGraphicsBitmapClaim(id));} catch(e) {fail(String(e.message || e),String(e.code || ''));}")
  private static native void claimBitmap(int id, BitmapReply ok, Failure fail);

  public static int bitmapId(BitmapLease lease) {
    int[] result = new int[1];
    ErrorResult error = new ErrorResult();
    bitmapId(lease, value -> result[0] = value, error::accept);
    error.check();
    return result[0];
  }

  @JSBody(
      params = {"lease", "ok", "fail"},
      script =
          "try {ok(self.teaGraphicsBitmapId(lease));} catch(e) {fail(String(e.message || e),String(e.code || ''));}")
  private static native void bitmapId(BitmapLease lease, IntReply ok, Failure fail);

  public static void recycleBitmap(BitmapLease lease) {
    ErrorResult error = new ErrorResult();
    recycleBitmap(lease, error::accept);
    error.check();
  }

  @JSBody(
      params = {"lease", "fail"},
      script =
          "try {self.teaGraphicsBitmapRecycle(lease);} catch(e) {fail(String(e.message || e),String(e.code || ''));}")
  private static native void recycleBitmap(BitmapLease lease, Failure fail);

  @JSFunctor
  interface StringReply extends JSObject {
    void call(String value);
  }

  @JSFunctor
  interface BytesReply extends JSObject {
    void call(Uint8Array value);
  }

  @JSFunctor
  interface Failure extends JSObject {
    void call(String message, String code);
  }

  private static final class ErrorResult {
    RuntimeException error;

    void accept(String message, String code) {
      error = Bridge.graphicsFailure(message, code);
    }

    void check() {
      if (error != null) throw error;
    }
  }

  public static String openBytes(int maximum) {
    String[] result = new String[1];
    ErrorResult error = new ErrorResult();
    openBytes(maximum, value -> result[0] = value, error::accept);
    error.check();
    return result[0];
  }

  @JSBody(
      params = {"maximum", "ok", "fail"},
      script =
          "try {ok(self.teaGraphicsBytesOpen(maximum));} catch(e) {fail(String(e.message || e),String(e.code || ''));}")
  private static native void openBytes(int maximum, StringReply ok, Failure fail);

  private static void writeChunk(String handle, Uint8Array bytes) {
    ErrorResult error = new ErrorResult();
    writeChunk(handle, bytes, error::accept);
    error.check();
  }

  @JSBody(
      params = {"handle", "bytes", "fail"},
      script =
          "try {self.teaGraphicsBytesWrite(handle,bytes);} catch(e) {fail(String(e.message || e),String(e.code || ''));}")
  private static native void writeChunk(String handle, Uint8Array bytes, Failure fail);

  private static Uint8Array readChunk(String handle, int maximum) {
    Uint8Array[] result = new Uint8Array[1];
    ErrorResult error = new ErrorResult();
    readChunk(handle, maximum, value -> result[0] = value, error::accept);
    error.check();
    return result[0];
  }

  @JSBody(
      params = {"handle", "maximum", "ok", "fail"},
      script =
          "try {ok(self.teaGraphicsBytesRead(handle,maximum));} catch(e) {fail(String(e.message || e),String(e.code || ''));}")
  private static native void readChunk(String handle, int maximum, BytesReply ok, Failure fail);

  public static void closeBytes(String handle) {
    ErrorResult error = new ErrorResult();
    closeBytes(handle, error::accept);
    error.check();
  }

  @JSBody(
      params = {"handle", "fail"},
      script =
          "try {self.teaGraphicsBytesClose(handle);} catch(e) {fail(String(e.message || e),String(e.code || ''));}")
  private static native void closeBytes(String handle, Failure fail);

  private static void detachBytes(String handle) {
    ErrorResult error = new ErrorResult();
    detachBytes(handle, error::accept);
    error.check();
  }

  @JSBody(
      params = {"handle", "fail"},
      script =
          "try {self.teaGraphicsBytesDetach(handle);} catch(e) {fail(String(e.message || e),String(e.code || ''));}")
  private static native void detachBytes(String handle, Failure fail);

  public static JsonArray numbers(float... values) {
    JsonArray a = new JsonArray();
    for (float n : values) a.add(n);
    return a;
  }

  static String sync(String request) {
    String[] result = new String[1];
    ErrorResult error = new ErrorResult();
    sync(request, value -> result[0] = value, error::accept);
    error.check();
    return result[0];
  }

  @JSBody(
      params = {"request", "ok", "fail"},
      script =
          "try {ok(JSON.stringify(self.teaGraphicsSync(JSON.parse(request))));} catch(e) {fail(String(e.message || e),String(e.code || ''));}")
  private static native void sync(String request, StringReply ok, Failure fail);
}
