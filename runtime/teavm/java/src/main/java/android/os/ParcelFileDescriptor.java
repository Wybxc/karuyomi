package android.os;

import java.io.Closeable;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;

/** An owned read-only handle to a file in the Source filesystem. */
public final class ParcelFileDescriptor implements Closeable {
  public static final int MODE_READ_ONLY = 0x10000000;

  private FileInputStream input;

  private ParcelFileDescriptor(FileInputStream input) {
    this.input = input;
  }

  public static ParcelFileDescriptor open(File file, int mode) throws FileNotFoundException {
    if (mode != MODE_READ_ONLY)
      throw new IllegalArgumentException("Only read-only file descriptors are supported");
    return new ParcelFileDescriptor(new FileInputStream(file));
  }

  public InputStream hostInput() throws IOException {
    if (input == null) throw new IOException("File descriptor is closed");
    return input;
  }

  @Override
  public void close() throws IOException {
    var stream = input;
    input = null;
    if (stream != null) stream.close();
  }
}
