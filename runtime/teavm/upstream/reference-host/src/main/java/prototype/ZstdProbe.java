package prototype;

import com.google.gson.*;
import com.squareup.zstd.okio.OkioZstd;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import okio.*;

/** Browser integration tests: real Okio facade -> JVM native callback -> WASM. */
public final class ZstdProbe {
  private static final Base64.Decoder BASE64 = Base64.getDecoder();
  private static byte[] decode(byte[] frame) throws IOException {
    try (var source = Okio.buffer(OkioZstd.zstdDecompress(new Buffer().write(frame)))) {
      return source.readByteArray();
    }
  }
  private static byte[] encode(byte[] plain) throws IOException {
    Buffer result = new Buffer();
    try (var sink = Okio.buffer(OkioZstd.zstdCompress(result))) { sink.write(plain); }
    return result.readByteArray();
  }
  private static void check(boolean condition, String message) throws IOException {
    if (!condition) throw new IOException("Zstd probe: " + message);
  }
  public static String run(String fixtures) throws IOException {
    JsonObject vectors = JsonParser.parseString(fixtures).getAsJsonObject();
    int nativeVectors = 0;
    Buffer concatenated = new Buffer();
    Buffer concatenatedPlain = new Buffer();
    for (var item : vectors.getAsJsonArray("vectors")) {
      var vector = item.getAsJsonObject();
      byte[] frame = BASE64.decode(vector.get("frame").getAsString());
      byte[] plain = BASE64.decode(vector.get("plain").getAsString());
      check(Arrays.equals(decode(frame), plain), "native vector " + vector.get("name"));
      check(Arrays.equals(decode(encode(plain)), plain), "round trip " + vector.get("name"));
      concatenated.write(frame); concatenatedPlain.write(plain); nativeVectors++;
    }
    check(Arrays.equals(decode(concatenated.readByteArray()), concatenatedPlain.readByteArray()), "concatenated native frames");
    byte[] large = new byte[600_001];
    for (int i = 0; i < large.length; i++) large[i] = (byte) i;
    check(Arrays.equals(decode(encode(large)), large), "automatic chunk boundaries");

    Buffer encoded = new Buffer();
    int[] closed = {0};
    var sink = OkioZstd.zstdCompress(new ForwardingSink(encoded) {
      public void close() { closed[0]++; }
    });
    sink.write(new Buffer().writeUtf8("first"), 5);
    sink.flush();
    check(new String(decode(encoded.clone().readByteArray()), StandardCharsets.UTF_8).equals("first"), "flush emits a complete frame");
    sink.write(new Buffer().writeUtf8("second"), 6);
    sink.close(); sink.close();
    byte[] flushedFrame = encoded.readByteArray();
    check(new String(decode(flushedFrame), StandardCharsets.UTF_8).equals("firstsecond"), "write after flush");
    check(closed[0] == 1, "close delegate exactly once");
    try { sink.write(new Buffer(), 0); throw new IOException("write after close accepted"); }
    catch (IllegalStateException expected) {}

    int errors = 0;
    for (byte[] invalid : new byte[][] {new byte[0], {1, 2, 3}, BASE64.decode(vectors.get("oversized").getAsString())}) {
      try { decode(invalid); throw new AssertionError("Invalid/oversized Zstd accepted"); }
      catch (IOException expected) { errors++; }
    }
    var unread = OkioZstd.zstdDecompress(new Buffer().writeUtf8("invalid"));
    check(unread.read(new Buffer(), 0) == 0, "zero read performs no decoding");
    unread.close();
    int[] failureClosed = {0};
    var failing = OkioZstd.zstdCompress(new Sink() {
      public void write(Buffer b, long n) throws IOException { throw new IOException("expected downstream failure"); }
      public void flush() {}
      public void close() { failureClosed[0]++; }
      public Timeout timeout() { return Timeout.NONE; }
    });
    failing.write(new Buffer().writeUtf8("x"), 1);
    try { failing.flush(); throw new AssertionError("Downstream error swallowed"); } catch (IOException expected) {}
    try { failing.close(); } catch (IOException expected) {}
    check(failureClosed[0] == 1, "close after failure");

    File directory = new File("/files/cache/zstd-wasm-probe");
    check(directory.isDirectory() || directory.mkdirs(), "cache directory");
    File temp = File.createTempFile("filters", ".tmp", directory);
    File cache = new File(directory, "filters.json.zst");
    String json = "[{\"slug\":\"action\",\"name\":\"动作😀\"}]";
    try {
      try (var output = Okio.buffer(OkioZstd.zstdCompress(Okio.sink(temp)))) { output.writeUtf8(json); }
      if (!temp.renameTo(cache)) {
        check(!cache.exists() || cache.delete(), "replace probe cache");
        check(temp.renameTo(cache), "atomic cache rename");
      }
      for (int i = 0; i < 2; i++)
        try (var input = Okio.buffer(OkioZstd.zstdDecompress(Okio.source(cache)))) {
          check(input.readUtf8().equals(json), "fresh Source reads cached JSON");
        }
    } finally { temp.delete(); }
    return new Gson().toJson(Map.of(
        "nativeVectors", nativeVectors, "roundTrip", true, "chunking", true,
        "flush", true, "closeAndErrors", true, "rejectedInputs", errors, "fileCache", true,
        "cacheBytes", cache.length(), "browserFrame", Base64.getEncoder().encodeToString(flushedFrame),
        "browserPlain", "firstsecond"));
  }
}
