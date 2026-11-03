package prototype;

import com.google.gson.JsonParser;
import java.io.IOException;
import java.util.Base64;
import java.util.Objects;
import okio.Buffer;
import okio.Sink;
import okio.Source;
import okio.Timeout;

/** Okio ABI adapter. Real Zstd frames are encoded by WASM in the JVM's browser Worker. */
public final class BrowserZstd {
  public static final long PLAIN_LIMIT = 8L * 1024 * 1024;
  public static final long COMPRESSED_LIMIT = 9L * 1024 * 1024;
  private static final long CHUNK_SIZE = 256 * 1024;
  private static final int FRAME_LIMIT = 1024;
  private BrowserZstd() {}

  static byte[] transform(String operation, byte[] input) throws IOException {
    try {
      var result = JsonParser.parseString(Bridge.zstd(operation, Base64.getEncoder().encodeToString(input))).getAsJsonObject();
      if (result.has("error")) throw new IOException("WASM Zstd: " + result.get("error").getAsString());
      byte[] output = Base64.getDecoder().decode(result.get("body").getAsString());
      long limit = operation.equals("compress") ? COMPRESSED_LIMIT : PLAIN_LIMIT;
      if (output.length > limit) throw new IOException("WASM Zstd output limit exceeded");
      return output;
    } catch (LinkageError | RuntimeException error) {
      throw new IOException("WASM Zstd bridge failed", error);
    }
  }

  public static Sink compress(Sink target) {
    Objects.requireNonNull(target);
    return new Sink() {
      final Buffer pending = new Buffer();
      long total;
      int frames;
      boolean closed;
      IOException failure;
      void check() throws IOException {
        if (closed) throw new IllegalStateException("closed");
        if (failure != null) throw failure;
      }
      void emit(boolean emptyFrame) throws IOException {
        if (pending.size() == 0 && !emptyFrame) return;
        if (frames >= FRAME_LIMIT) throw new IOException("Zstd frame count limit exceeded");
        byte[] output = transform("compress", pending.readByteArray());
        Buffer encoded = new Buffer().write(output);
        target.write(encoded, encoded.size());
        frames++;
      }
      public void write(Buffer source, long byteCount) throws IOException {
        check();
        if (byteCount < 0 || byteCount > source.size()) throw new IllegalArgumentException("byteCount");
        try {
          if (byteCount > PLAIN_LIMIT - total) throw new IOException("Zstd input limit exceeded");
          total += byteCount;
          while (byteCount > 0) {
            long count = Math.min(byteCount, CHUNK_SIZE - pending.size());
            pending.write(source, count);
            byteCount -= count;
            if (pending.size() == CHUNK_SIZE) emit(false);
          }
        } catch (IOException error) { failure = error; throw error; }
      }
      // A flush completes a frame; later writes start another standard concatenated frame.
      public void flush() throws IOException {
        check();
        try { emit(frames == 0); target.flush(); }
        catch (IOException error) { failure = error; throw error; }
      }
      public void close() throws IOException {
        if (closed) return;
        IOException error = failure;
        try { if (error == null) emit(frames == 0); }
        catch (IOException e) { error = e; }
        finally {
          closed = true;
          pending.clear();
          try { target.close(); }
          catch (IOException e) { if (error == null) error = e; else if (error != e) error.addSuppressed(e); }
        }
        if (error != null) throw error;
      }
      public Timeout timeout() { return target.timeout(); }
    };
  }

  public static Source decompress(Source source) {
    Objects.requireNonNull(source);
    return new Source() {
      Buffer decoded;
      boolean closed;
      IOException failure;
      public long read(Buffer sink, long byteCount) throws IOException {
        if (closed) throw new IllegalStateException("closed");
        if (byteCount < 0) throw new IllegalArgumentException("byteCount");
        if (failure != null) throw failure;
        if (byteCount == 0) return 0;
        try {
          if (decoded == null) {
            Buffer encoded = new Buffer();
            long read;
            while ((read = source.read(encoded, Math.min(8192, COMPRESSED_LIMIT - encoded.size() + 1))) != -1) {
              if (encoded.size() > COMPRESSED_LIMIT) throw new IOException("Zstd compressed input limit exceeded");
              if (read == 0) throw new IOException("Zstd upstream Source made no progress");
            }
            decoded = new Buffer().write(transform("decompress", encoded.readByteArray()));
          }
          return decoded.read(sink, byteCount);
        } catch (IOException error) { failure = error; throw error; }
      }
      public void close() throws IOException {
        if (closed) return;
        closed = true;
        if (decoded != null) decoded.clear();
        source.close();
      }
      public Timeout timeout() { return source.timeout(); }
    };
  }
}
