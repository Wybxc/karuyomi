package prototype;

import java.io.IOException;
import okio.Buffer;
import okio.Source;
import okio.Timeout;

/** A demand-driven response body. A null chunk means the host verified the final END frame. */
public final class HttpBodySource implements Source {
  public static final int MAX_CHUNK = 64 * 1024;
  public static final long MAX_RESPONSE = 64L * 1024 * 1024;

  public interface Reader {
    byte[] read(int maximum) throws IOException;

    void close() throws IOException;
  }

  private final Reader reader;
  private final long length;
  private final Timeout timeout = new Timeout();
  private long received;
  private boolean closed, ended, released, reading;

  public HttpBodySource(Reader reader, long length) throws IOException {
    if (length < -1 || length > MAX_RESPONSE) throw new IOException("Invalid HTTP body length");
    this.reader = reader;
    this.length = length;
  }

  @Override
  public long read(Buffer sink, long byteCount) throws IOException {
    if (byteCount < 0) throw new IllegalArgumentException("Negative byte count");
    if (closed) throw new IOException("HTTP response body is closed");
    if (byteCount == 0) return 0;
    if (ended) return -1;
    if (reading) throw new IOException("Concurrent HTTP body reads are unsupported");
    reading = true;
    try {
      timeout.throwIfReached();
      int maximum = (int) Math.min(byteCount, MAX_CHUNK);
      byte[] bytes = reader.read(maximum);
      if (closed) throw new IOException("HTTP response body was closed during a read");
      if (bytes == null) {
        if (length >= 0 && received != length) throw new IOException("HTTP body length mismatch");
        ended = true;
        release();
        return -1;
      }
      if (bytes.length < 1 || bytes.length > maximum)
        throw new IOException("Invalid HTTP response chunk size");
      if (bytes.length > MAX_RESPONSE - received || length >= 0 && bytes.length > length - received)
        throw new IOException("HTTP response body exceeds its length limit");
      received += bytes.length;
      sink.write(bytes);
      return bytes.length;
    } catch (IOException | RuntimeException error) {
      closed = true;
      try {
        release();
      } catch (IOException cleanup) {
        error.addSuppressed(cleanup);
      }
      throw error;
    } finally {
      reading = false;
    }
  }

  @Override
  public Timeout timeout() {
    return timeout;
  }

  @Override
  public void close() throws IOException {
    if (closed) return;
    closed = true;
    release();
  }

  private void release() throws IOException {
    if (released) return;
    released = true;
    reader.close();
  }
}
