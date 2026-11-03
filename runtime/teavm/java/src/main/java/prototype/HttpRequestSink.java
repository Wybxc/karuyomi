package prototype;

import java.io.IOException;
import okio.Buffer;
import okio.Sink;
import okio.Timeout;

/** Bounds an original RequestBody while forwarding only individually bounded binary copies. */
public final class HttpRequestSink implements Sink {
  public static final long MAX_REQUEST = 8L * 1024 * 1024;

  public interface Writer {
    void write(byte[] bytes) throws IOException;
  }

  private final Writer writer;
  private final Timeout timeout = new Timeout();
  private long written;
  private boolean closed;

  public HttpRequestSink(Writer writer) {
    this.writer = writer;
  }

  @Override
  public void write(Buffer source, long byteCount) throws IOException {
    if (closed) throw new IOException("HTTP request body is closed");
    if (byteCount < 0 || byteCount > source.size())
      throw new IllegalArgumentException("Invalid upload byte count");
    if (byteCount > MAX_REQUEST - written) throw new IOException("HTTP request body exceeds 8 MiB");
    while (byteCount > 0) {
      timeout.throwIfReached();
      int count = (int) Math.min(byteCount, HttpBodySource.MAX_CHUNK);
      writer.write(source.readByteArray(count));
      written += count;
      byteCount -= count;
    }
  }

  public void finish(long expected) throws IOException {
    if (expected >= 0 && written != expected)
      throw new IOException("HTTP request body length mismatch");
  }

  @Override
  public Timeout timeout() {
    return timeout;
  }

  @Override
  public void flush() throws IOException {
    if (closed) throw new IOException("HTTP request body is closed");
  }

  @Override
  public void close() {
    closed = true;
  }
}
