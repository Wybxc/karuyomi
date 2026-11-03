package prototype;

import java.io.*;
import java.util.*;
import java.security.*;
import okio.*;

public class HttpBodyTest {
  static int assertions;

  static void check(boolean value) {
    assertions++;
    if (!value) throw new AssertionError();
  }

  interface Checked {
    void run() throws Exception;
  }

  static void fails(Checked operation, String expected) throws Exception {
    try {
      operation.run();
      throw new AssertionError("Expected failure");
    } catch (IOException error) {
      check(error.getMessage().contains(expected));
    }
  }

  static class Reader implements HttpBodySource.Reader {
    byte[] bytes;
    int offset, reads, closes, maximum;

    Reader(byte[] bytes) {
      this.bytes = bytes;
    }

    public byte[] read(int max) {
      reads++;
      maximum = Math.max(maximum, max);
      if (offset == bytes.length) return null;
      int end = Math.min(bytes.length, offset + max);
      byte[] value = Arrays.copyOfRange(bytes, offset, end);
      offset = end;
      return value;
    }

    public void close() {
      closes++;
    }
  }

  public static void main(String[] args) throws Exception {
    byte[] vector = new byte[131079];
    for (int i = 0; i < vector.length; i++) vector[i] = (byte) i;
    Reader reader = new Reader(vector);
    HttpBodySource source = new HttpBodySource(reader, vector.length);
    Buffer sink = new Buffer();
    check(source.read(sink, 0) == 0 && reader.reads == 0);
    check(source.read(sink, 3) == 3 && reader.reads == 1 && reader.maximum == 3);
    while (source.read(sink, Long.MAX_VALUE) != -1) {}
    check(
        reader.maximum == 65536
            && reader.closes == 1
            && Arrays.equals(sink.readByteArray(), vector));
    check(source.read(sink, 1) == -1 && reader.closes == 1);
    source.close();
    source.close();
    check(reader.closes == 1);
    fails(() -> source.read(sink, 1), "closed");
    Reader zero =
        new Reader(new byte[0]) {
          public byte[] read(int max) {
            return new byte[0];
          }
        };
    fails(() -> new HttpBodySource(zero, -1).read(new Buffer(), 1), "chunk size");
    check(zero.closes == 1);
    Reader oversized =
        new Reader(new byte[0]) {
          public byte[] read(int max) {
            return new byte[max + 1];
          }
        };
    fails(() -> new HttpBodySource(oversized, -1).read(new Buffer(), 2), "chunk size");
    check(oversized.closes == 1);
    Reader shortBody = new Reader(new byte[2]);
    HttpBodySource truncated = new HttpBodySource(shortBody, 3);
    check(truncated.read(new Buffer(), 8) == 2);
    fails(() -> truncated.read(new Buffer(), 8), "length mismatch");
    check(shortBody.closes == 1);
    Reader longBody = new Reader(new byte[4]);
    Buffer untouched = new Buffer();
    fails(() -> new HttpBodySource(longBody, 3).read(untouched, 8), "length limit");
    check(untouched.size() == 0 && longBody.closes == 1);
    fails(
        () -> new HttpBodySource(new Reader(new byte[0]), HttpBodySource.MAX_RESPONSE + 1),
        "length");
    final HttpBodySource[] race = new HttpBodySource[1];
    final int[] closed = {0};
    race[0] =
        new HttpBodySource(
            new HttpBodySource.Reader() {
              public byte[] read(int max) throws IOException {
                race[0].close();
                return new byte[] {0, (byte) 255};
              }

              public void close() {
                closed[0]++;
              }
            },
            -1);
    Buffer late = new Buffer();
    fails(() -> race[0].read(late, 2), "closed during");
    check(late.size() == 0 && closed[0] == 1);
    Reader cancelled =
        new Reader(new byte[0]) {
          public byte[] read(int max) {
            throw new RuntimeException("cancel fixture");
          }
        };
    try {
      new HttpBodySource(cancelled, -1).read(new Buffer(), 1);
      throw new AssertionError();
    } catch (RuntimeException expected) {
      check(cancelled.closes == 1);
    }
    final byte[] block = new byte[65536];
    final int[] chunks = {0}, released = {0};
    HttpBodySource bounded =
        new HttpBodySource(
            new HttpBodySource.Reader() {
              public byte[] read(int max) {
                chunks[0]++;
                return block;
              }

              public void close() {
                released[0]++;
              }
            },
            -1);
    Buffer consumed = new Buffer();
    for (int i = 0; i < 1024; i++) {
      check(bounded.read(consumed, 65536) == 65536);
      consumed.clear();
    }
    fails(() -> bounded.read(consumed, 65536), "length limit");
    check(released[0] == 1 && chunks[0] == 1025 && consumed.size() == 0);
    MessageDigest hash = MessageDigest.getInstance("SHA-256");
    List<Integer> sizes = new ArrayList<>();
    HttpRequestSink upload =
        new HttpRequestSink(bytes -> {
          hash.update(bytes);
          sizes.add(bytes.length);
        });
    Buffer original = new Buffer().write(vector);
    upload.write(original, vector.length);
    upload.finish(vector.length);
    check(sizes.equals(List.of(65536, 65536, 7)) && original.size() == 0);
    check(Arrays.equals(hash.digest(), MessageDigest.getInstance("SHA-256").digest(vector)));
    fails(() -> upload.finish(vector.length + 1), "length mismatch");
    upload.close();
    fails(() -> upload.write(new Buffer(), 0), "closed");
    final int[] writes = {0};
    HttpRequestSink limit = new HttpRequestSink(bytes -> writes[0]++);
    Buffer huge = new Buffer().write(new byte[8 * 1024 * 1024 + 1]);
    fails(() -> limit.write(huge, huge.size()), "8 MiB");
    check(writes[0] == 0);
    System.out.println(
        "HTTP v2 JVM boundary passed: "
            + assertions
            + " assertions; demand, binary bytes, EOF/limits, close race, upload chunks");
  }
}
