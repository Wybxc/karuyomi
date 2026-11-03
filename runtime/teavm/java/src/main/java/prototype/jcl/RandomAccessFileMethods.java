package prototype.jcl;

import java.io.IOException;
import java.util.Objects;
import org.teavm.runtime.fs.VirtualFileAccessor;

/** Copied into TeaVM's RandomAccessFile; retain Java ranges and acknowledged close semantics. */
public final class RandomAccessFileMethods {
  private VirtualFileAccessor accessor;

  public void close() throws IOException {
    if (accessor != null) {
      accessor.close();
      accessor = null;
    }
  }

  public int read(byte[] bytes, int offset, int length) throws IOException {
    Objects.requireNonNull(bytes);
    Objects.checkFromIndexSize(offset, length, bytes.length);
    if (accessor == null) throw new IOException("This stream is already closed");
    if (length == 0) return 0;
    int count = accessor.read(bytes, offset, length);
    return count > 0 ? count : -1;
  }
}
