package prototype.jcl;

import java.io.IOException;
import org.teavm.runtime.fs.VirtualFileAccessor;

/** Copied into TeaVM's FileInputStream; single-byte reads are unsigned and EOF-safe. */
public final class FileInputStreamMethods {
  private VirtualFileAccessor accessor;

  public int read() throws IOException {
    if (accessor == null) throw new IOException("This stream is already closed");
    byte[] bytes = new byte[1];
    return accessor.read(bytes, 0, 1) > 0 ? bytes[0] & 255 : -1;
  }
}
