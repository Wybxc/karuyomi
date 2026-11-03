package prototype;

import java.io.IOException;
import java.util.function.BooleanSupplier;
import okio.Buffer;
import okio.Sink;
import okio.Timeout;

/** Bounded, fault-hiding cache writer. A storage failure must not fail a network response. */
public final class CacheSink implements Sink {
  public interface Store {
    boolean write(int sequence, byte[] bytes) throws IOException;

    boolean commit() throws IOException;

    void abort() throws IOException;
  }

  private final Store store;
  private final BooleanSupplier cacheClosed;
  private final Runnable success, aborted;
  private boolean closed, failed;
  private int sequence;

  public CacheSink(Store store, BooleanSupplier cacheClosed, Runnable success, Runnable aborted) {
    this.store = store;
    this.cacheClosed = cacheClosed;
    this.success = success;
    this.aborted = aborted;
  }

  private void fail() {
    if (failed) return;
    failed = true;
    aborted.run();
    try {
      store.abort();
    } catch (IOException ignored) {
      /* Owner cleanup can retry at restart. */
    }
  }

  public void write(Buffer source, long count) throws IOException {
    if (closed) throw new IllegalStateException("closed cache writer");
    if (count < 0 || count > source.size())
      throw new IllegalArgumentException("Invalid cache write count");
    if (cacheClosed.getAsBoolean()) fail();
    long remaining = count;
    while (remaining > 0) {
      if (failed) {
        source.skip(remaining);
        return;
      }
      int size = (int) Math.min(remaining, HttpBodySource.MAX_CHUNK);
      byte[] bytes = source.readByteArray(size);
      remaining -= size;
      try {
        if (!store.write(sequence++, bytes)) fail();
      } catch (IOException error) {
        fail();
      } catch (RuntimeException error) {
        fail();
        throw error;
      }
    }
  }

  public void close() {
    if (closed) return;
    closed = true;
    if (cacheClosed.getAsBoolean()) fail();
    if (failed) return;
    try {
      if (store.commit()) success.run();
      else fail();
    } catch (IOException error) {
      fail();
    } catch (RuntimeException error) {
      fail();
      throw error;
    }
  }

  public void abort() {
    if (closed) return;
    closed = true;
    fail();
  }

  public void flush() {}

  public Timeout timeout() {
    return Timeout.NONE;
  }
}
