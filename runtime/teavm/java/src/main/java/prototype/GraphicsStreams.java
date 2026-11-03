package prototype;

import java.io.*;

/** Bounded InputStream consumption for the browser raster bridge. */
public final class GraphicsStreams {
  private GraphicsStreams() {}

  @FunctionalInterface
  public interface ChunkConsumer {
    void write(byte[] bytes, int length) throws IOException;
  }

  /** Never reads ahead beyond a bounds prefix; full inputs reject the first excess byte. */
  public static void copyChunks(
      InputStream input, ChunkConsumer output, int maximum, boolean prefixOnly) throws IOException {
    if (maximum < 1 || maximum > 64 * 1024 * 1024)
      throw new IllegalArgumentException("Graphics byte budget");
    byte[] chunk = new byte[Math.min(65536, maximum)];
    int total = 0;
    while (total < maximum) {
      int count = input.read(chunk, 0, Math.min(chunk.length, maximum - total));
      if (count < 0) return;
      if (count == 0) {
        int value = input.read();
        if (value < 0) return;
        chunk[0] = (byte) value;
        count = 1;
      }
      output.write(chunk, count);
      total += count;
    }
    if (!prefixOnly && input.read() != -1)
      throw new IOException("Graphics input exceeds byte budget");
  }
}
