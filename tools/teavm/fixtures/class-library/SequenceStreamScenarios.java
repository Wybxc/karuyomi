package prototype;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.SequenceInputStream;
import java.util.Collections;
import java.util.Enumeration;
import java.util.List;

final class SequenceStreamScenarios {
  private static int checks;

  static void run() throws IOException {
    var first = new Part(null, 7, 8);
    var empty = new Part(null);
    var last = new Part(null, 9, 255);
    var enumeration = new Parts(first, empty, last);
    var joined = new SequenceInputStream(enumeration);
    verify(enumeration.position == 1 && joined.available() == 2, "starts on the first part");
    byte[] buffer = new byte[6];
    verify(joined.read(buffer, 1, 0) == 0, "zero-length read before EOF");
    verify(
        joined.read(buffer, 1, 5) == 2 && buffer[0] == 0 && buffer[1] == 7 && buffer[2] == 8,
        "one buffered read keeps its offset and stops at the current part");
    verify(
        enumeration.position == 1 && first.closes == 0 && joined.available() == 0,
        "available does not advance an exhausted stream");
    verify(joined.read(buffer, 3, 1) == 1 && buffer[3] == 9, "buffered read skips an empty part");
    verify(
        first.closes == 1 && empty.closes == 1 && last.closes == 0, "exhausted parts are closed");
    verify(
        joined.read() == 255 && joined.read() == -1 && last.closes == 1, "unsigned byte and EOF");
    verify(joined.read(buffer, 0, 0) == -1 && joined.available() == 0, "EOF state");
    joined.close();
    verify(last.closes == 1, "close is idempotent after EOF");

    var causeA = new IOException("first close");
    var causeB = new IOException("second close");
    var a = new Part(causeA, 1);
    var b = new Part(causeB, 2);
    var c = new Part(null, 3);
    var early = new SequenceInputStream(Collections.enumeration(List.of(a, b, c)));
    try {
      early.close();
      throw new AssertionError("close error disappeared");
    } catch (IOException error) {
      verify(error == causeA, "first close error is preserved");
      verify(
          error.getSuppressed().length == 1 && error.getSuppressed()[0] == causeB,
          "later close error is suppressed");
    }
    verify(a.closes == 1 && b.closes == 1 && c.closes == 1, "early close releases unread parts");
    verify(early.read() == -1 && early.available() == 0, "EOF after early close error");

    var pairFirst = new Part(null);
    var pairSecond = new Part(null, 42);
    try (var pair = new SequenceInputStream(pairFirst, pairSecond)) {
      verify(
          pair.read() == 42 && pairFirst.closes == 1, "two-argument constructor preserves order");
    }
    verify(pairSecond.closes == 1, "two-argument stream releases its second part");
    System.out.println("SEQUENCE_STREAM_SCENARIOS_PASS " + checks);
  }

  private static final class Part extends ByteArrayInputStream {
    private final IOException failure;
    int closes;

    Part(IOException failure, int... values) {
      super(bytes(values));
      this.failure = failure;
    }

    @Override
    public void close() throws IOException {
      closes++;
      if (failure != null) throw failure;
    }
  }

  private static final class Parts implements Enumeration<InputStream> {
    private final InputStream[] inputs;
    int position;

    Parts(InputStream... inputs) {
      this.inputs = inputs;
    }

    @Override
    public boolean hasMoreElements() {
      return position < inputs.length;
    }

    @Override
    public InputStream nextElement() {
      return inputs[position++];
    }
  }

  private static byte[] bytes(int[] values) {
    byte[] result = new byte[values.length];
    for (int i = 0; i < values.length; i++) result[i] = (byte) values[i];
    return result;
  }

  private static void verify(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
    checks++;
  }
}
