package prototype.jcl;

import java.io.*;

/** Public JDK semantics missing from TeaVM's in-memory-oriented File implementation. */
public final class FileMethods {
  public boolean mkdirs() {
    File file = (File) (Object) this;
    if (file.exists()) return false;
    if (file.mkdir()) return true;
    try {
      file = file.getCanonicalFile();
      File parent = file.getParentFile();
      return parent != null && (parent.mkdirs() || parent.exists()) && file.mkdir();
    } catch (IOException e) {
      return false;
    }
  }

  public static void prepareRandomAccessFile(File file, String mode) throws FileNotFoundException {
    if (!mode.equals("r") && !file.exists()) {
      try {
        file.createNewFile();
      } catch (IOException e) {
        throw new FileNotFoundException(e.getMessage());
      }
    }
  }
}
