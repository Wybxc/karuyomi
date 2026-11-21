package java.io;

import java.util.Arrays;
import java.util.Collections;
import java.util.Enumeration;
import java.util.Objects;

/** Reads one underlying stream at a time and releases it when exhausted. */
public class SequenceInputStream extends InputStream {
  private final Enumeration<? extends InputStream> remaining;
  private InputStream current;

  public SequenceInputStream(Enumeration<? extends InputStream> streams) {
    remaining = Objects.requireNonNull(streams);
    selectNext();
  }

  public SequenceInputStream(InputStream first, InputStream second) {
    this(Collections.enumeration(Arrays.asList(first, second)));
  }

  @Override
  public int available() throws IOException {
    return current == null ? 0 : current.available();
  }

  @Override
  public int read() throws IOException {
    while (current != null) {
      int value = current.read();
      if (value >= 0) return value;
      advance();
    }
    return -1;
  }

  @Override
  public int read(byte[] buffer, int offset, int length) throws IOException {
    if (current == null) return -1;
    Objects.checkFromIndexSize(offset, length, buffer.length);
    if (length == 0) return 0;
    while (current != null) {
      int count = current.read(buffer, offset, length);
      if (count > 0) return count;
      advance();
    }
    return -1;
  }

  @Override
  public void close() throws IOException {
    IOException firstFailure = null;
    while (current != null) {
      try {
        current.close();
      } catch (IOException failure) {
        if (firstFailure == null) firstFailure = failure;
        else firstFailure.addSuppressed(failure);
      }
      selectNext();
    }
    if (firstFailure != null) throw firstFailure;
  }

  private void advance() throws IOException {
    current.close();
    selectNext();
  }

  private void selectNext() {
    if (remaining.hasMoreElements()) {
      current = remaining.nextElement();
      Objects.requireNonNull(current);
    } else {
      current = null;
    }
  }
}
