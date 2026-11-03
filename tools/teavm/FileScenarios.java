package prototype;

import com.google.gson.JsonObject;
import java.io.*;
import java.security.MessageDigest;
import java.util.Arrays;
import okio.Buffer;
import okio.Okio;

/** Shared original-JVM/TeaVM File, RandomAccessFile and Okio semantics. */
public final class FileScenarios {
  private static int checks;

  private static void check(boolean value, String message) {
    checks++;
    if (!value) throw new AssertionError(message);
  }

  private static String digest(byte[] bytes) throws Exception {
    StringBuilder result = new StringBuilder();
    for (byte value : MessageDigest.getInstance("SHA-256").digest(bytes))
      result.append(String.format("%02x", value & 255));
    return result.toString();
  }

  public static JsonObject run(File directory) throws Exception {
    checks = 0;
    check(directory.isDirectory() || directory.mkdirs(), "scenario directory");
    byte[] fixture = new byte[131079];
    for (int i = 0; i < fixture.length; i++) fixture[i] = (byte) i;
    File file = new File(directory, "binary");
    try (OutputStream stream = new FileOutputStream(file)) {
      stream.write(fixture, 0, fixture.length);
    }
    check(file.length() == fixture.length, "large output length");
    try (InputStream stream = new FileInputStream(file)) {
      ByteArrayOutputStream result = new ByteArrayOutputStream();
      byte[] part = new byte[70000];
      for (int count; (count = stream.read(part)) != -1; ) result.write(part, 0, count);
      check(Arrays.equals(result.toByteArray(), fixture), "large input exact");
    }
    try (RandomAccessFile a = new RandomAccessFile(file, "rw");
        RandomAccessFile b = new RandomAccessFile(file, "r")) {
      a.seek(65535);
      a.write(new byte[] {5, 6, 7, 8});
      check(b.getFilePointer() == 0 && b.read() == 0, "independent cursors");
      b.seek(100000);
      a.setLength(65537);
      a.setLength(fixture.length);
      check(b.getFilePointer() == 100000 && b.read() == 0, "sibling cursor after truncate");
      a.seek(65535);
      byte[] range = new byte[5];
      a.readFully(range);
      check(Arrays.equals(range, new byte[] {5, 6, 0, 0, 0}), "truncate reextend zero tail");
      File target = new File(directory, "replacement");
      try (OutputStream stream = new FileOutputStream(target)) {
        stream.write(new byte[] {19, 20});
      }
      try (RandomAccessFile displaced = new RandomAccessFile(target, "rw")) {
        check(file.renameTo(target), "rename replaces existing path");
        check(displaced.read() == 19, "replaced target open inode");
        check(target.delete(), "unlink open source inode");
        a.seek(65535);
        check(a.read() == 5, "renamed unlinked handle remains readable");
        b.seek(65536);
        check(b.read() == 6, "cold sibling read after unlink");
        a.write(22);
        b.seek(65536);
        check(b.read() == 22, "unlinked inode remains writable");
      }
    }
    check(!file.exists() && !new File(directory, "replacement").exists(), "retired paths absent");
    File sparse = new File(directory, "sparse");
    try (RandomAccessFile stream = new RandomAccessFile(sparse, "rw")) {
      stream.setLength(64 * 1024 * 1024);
      stream.seek(stream.length() - 1);
      stream.write(42);
      stream.seek(stream.length() - 2);
      check(stream.read() == 0 && stream.read() == 42, "sparse range reads zero");
      check(stream.read() == -1, "sparse EOF");
    }
    check(sparse.delete(), "delete sparse file");
    File append = new File(directory, "append");
    for (int value : new int[] {31, 32})
      try (OutputStream stream = new FileOutputStream(append, true)) {
        stream.write(value);
      }
    try (InputStream stream = new FileInputStream(append)) {
      check(
          stream.read() == 31 && stream.read() == 32 && stream.read() == -1,
          "append preserves old data");
    }
    check(append.delete(), "delete appended file");
    File unsigned = new File(directory, "unsigned");
    try (OutputStream stream = new FileOutputStream(unsigned)) {
      stream.write(new byte[] {0, 127, (byte) 128, (byte) 255});
    }
    try (InputStream stream = new FileInputStream(unsigned)) {
      check(
          stream.read() == 0
              && stream.read() == 127
              && stream.read() == 128
              && stream.read() == 255,
          "single-byte input is unsigned");
      check(stream.read() == -1 && stream.read() == -1, "single-byte repeated EOF");
    }
    try (RandomAccessFile stream = new RandomAccessFile(unsigned, "r")) {
      check(stream.read(new byte[0]) == 0, "random-access zero-length read");
      check(stream.getFilePointer() == 0, "zero-length read keeps cursor");
      try {
        stream.read(new byte[4], Integer.MAX_VALUE, 2);
        throw new AssertionError("overflowing read range accepted");
      } catch (IndexOutOfBoundsException expected) {
        checks++;
      }
      stream.seek(2);
      check(stream.read() == 128 && stream.read() == 255, "random-access unsigned read");
      check(stream.read(new byte[0]) == 0 && stream.read() == -1, "zero-length read at EOF");
    }
    check(unsigned.delete(), "delete unsigned file");
    File sourceDir = new File(directory, "source"), movedDir = new File(directory, "moved");
    check(sourceDir.mkdir(), "create nested directory");
    File nested = new File(sourceDir, "chapter-章节-😀");
    try (RandomAccessFile stream = new RandomAccessFile(nested, "rw")) {
      stream.write(47);
      check(sourceDir.renameTo(movedDir), "directory rename");
      stream.seek(0);
      check(
          stream.read() == 47 && new File(movedDir, "chapter-章节-😀").exists(),
          "directory rename keeps open inode and Unicode name");
    }
    check(new File(movedDir, "chapter-章节-😀").delete() && movedDir.delete(), "nested cleanup");
    File okio = new File(directory, "okio");
    try (var sink = Okio.buffer(Okio.sink(okio))) {
      sink.write(new Buffer().write(fixture), fixture.length);
    }
    try (var source = Okio.buffer(Okio.source(okio))) {
      check(Arrays.equals(source.readByteArray(), fixture), "original Okio file streams");
    }
    check(okio.delete(), "Okio cleanup");
    JsonObject result = new JsonObject();
    result.addProperty("passed", true);
    result.addProperty("checks", checks);
    result.addProperty("bodySha256", digest(fixture));
    return result;
  }
}
