package prototype;

import java.io.*;
import java.util.*;

/** JVM checks for the same bounded stream loop used by product graphics uploads. */
public final class GraphicsTest {
  static int checks;

  static void check(boolean value) {
    checks++;
    if (!value) throw new AssertionError();
  }

  public static void main(String[] args) throws Exception {
    byte[] vector = new byte[131079];
    new Random(19).nextBytes(vector);
    vector[0] = 0;
    vector[1] = (byte) 255;
    ByteArrayOutputStream output = new ByteArrayOutputStream();
    List<Integer> chunks = new ArrayList<>();
    GraphicsStreams.copyChunks(
        new ByteArrayInputStream(vector),
        (bytes, length) -> {
          check(length > 0 && length <= 65536);
          chunks.add(length);
          output.write(bytes, 0, length);
        },
        vector.length,
        false);
    check(Arrays.equals(vector, output.toByteArray()));
    check(chunks.equals(List.of(65536, 65536, 7)));
    ByteArrayInputStream prefix = new ByteArrayInputStream(vector);
    output.reset();
    GraphicsStreams.copyChunks(prefix, (bytes, length) -> output.write(bytes, 0, length), 33, true);
    check(output.size() == 33);
    check(prefix.available() == vector.length - 33);
    try {
      GraphicsStreams.copyChunks(
          new ByteArrayInputStream(vector), (bytes, length) -> {}, 33, false);
      throw new AssertionError("oversize accepted");
    } catch (IOException expected) {
      check(expected.getMessage().contains("budget"));
    }
    GraphicsStreams.copyChunks(
        new ByteArrayInputStream(new byte[0]),
        (bytes, length) -> {
          throw new AssertionError("empty emitted");
        },
        33,
        false);
    InputStream zeroThenBytes =
        new InputStream() {
          boolean zero = true;
          int value;

          public int read() {
            return value < 7 ? value++ : -1;
          }

          public int read(byte[] bytes, int offset, int length) {
            if (zero) {
              zero = false;
              return 0;
            }
            return superRead(bytes, offset, length);
          }

          private int superRead(byte[] bytes, int offset, int length) {
            int n = 0;
            while (n < length) {
              int b = read();
              if (b < 0) break;
              bytes[offset + n++] = (byte) b;
            }
            return n == 0 ? -1 : n;
          }
        };
    output.reset();
    GraphicsStreams.copyChunks(
        zeroThenBytes, (bytes, length) -> output.write(bytes, 0, length), 7, false);
    check(Arrays.equals(output.toByteArray(), new byte[] {0, 1, 2, 3, 4, 5, 6}));
    try {
      GraphicsStreams.copyChunks(
          new ByteArrayInputStream(vector),
          (bytes, length) -> {
            throw new IOException("consumer failure");
          },
          33,
          false);
      throw new AssertionError();
    } catch (IOException expected) {
      check(expected.getMessage().equals("consumer failure"));
    }
    for (int maximum : new int[] {0, -1, 67108865})
      try {
        GraphicsStreams.copyChunks(
            new ByteArrayInputStream(vector), (bytes, length) -> {}, maximum, false);
        throw new AssertionError();
      } catch (IllegalArgumentException expected) {
        checks++;
      }
    System.out.println("Graphics stream oracle: " + checks + " checks");
  }
}
