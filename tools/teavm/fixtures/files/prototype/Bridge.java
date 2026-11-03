package prototype;

import com.google.gson.*;
import java.io.IOException;
import java.util.*;

/** Accessor unit fixture, not a filesystem or TeaVM JSO substitute. */
public final class Bridge {
  static final List<Integer> writes = new ArrayList<>();
  static final List<Byte> accepted = new ArrayList<>();
  static byte[] nextRead;
  static int maximum, reads, closeCalls, failAt = -1;
  static boolean failClose;

  public static String file(String request) {
    String operation =
        JsonParser.parseString(request).getAsJsonObject().get("operation").getAsString();
    if (operation.equals("open")) return "{\"handle\":\"fixture\"}";
    if (operation.equals("close")) {
      closeCalls++;
      if (failClose) {
        failClose = false;
        return "{\"error\":\"controlled close transaction failure\"}";
      }
    }
    return "{}";
  }

  public static byte[] fileRead(String handle, int limit) {
    if (!handle.equals("fixture")) throw new AssertionError("wrong handle");
    maximum = limit;
    reads++;
    return nextRead;
  }

  public static void fileWrite(String handle, byte[] bytes, int offset, int length)
      throws IOException {
    if (!handle.equals("fixture") || length < 1 || length > 65536)
      throw new AssertionError("unbounded accessor write");
    writes.add(length);
    if (writes.size() - 1 == failAt) throw new IOException("controlled storage refusal");
    for (int index = 0; index < length; index++) accepted.add(bytes[offset + index]);
  }
}
