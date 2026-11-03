package prototype;

import java.io.IOException;
import java.util.*;
import org.teavm.runtime.fs.VirtualFileAccessor;
import prototype.jcl.FileInputStreamMethods;
import prototype.jcl.RandomAccessFileMethods;

/** Product Java accessor boundary with a narrow binary store fixture. */
public final class FileAccessorTest {
  private static int checks;

  private static void check(boolean value) {
    checks++;
    if (!value) throw new AssertionError();
  }

  private static VirtualFileAccessor open() {
    return new PersistentFileSystem().getFile("/fixture").createAccessor(true, true, false);
  }

  private static <T> T attach(Class<T> type, VirtualFileAccessor accessor) throws Exception {
    T instance = type.getConstructor().newInstance();
    var field = type.getDeclaredField("accessor");
    field.setAccessible(true);
    field.set(instance, accessor);
    return instance;
  }

  public static void main(String[] args) throws Exception {
    byte[] input = new byte[131081];
    for (int index = 0; index < input.length; index++) input[index] = (byte) index;
    byte[] original = input.clone();
    VirtualFileAccessor accessor = open();
    accessor.write(input, 1, 131079);
    check(Bridge.writes.equals(List.of(65536, 65536, 7)));
    check(Bridge.accepted.size() == 131079);
    for (int index = 0; index < Bridge.accepted.size(); index++)
      if (Bridge.accepted.get(index) != input[index + 1])
        throw new AssertionError("wrong input range");
    check(Arrays.equals(input, original));
    accessor.write(input, 0, 0);
    check(Bridge.writes.size() == 3);
    Bridge.nextRead = new byte[] {0, -1, 7};
    byte[] output = new byte[70000];
    check(accessor.read(output, 1, 69999) == 3 && Bridge.maximum == 65536);
    check(output[0] == 0 && output[1] == 0 && output[2] == -1 && output[3] == 7 && output[4] == 0);
    check(accessor.read(output, 0, 0) == 0 && Bridge.reads == 1);
    Bridge.nextRead = null;
    check(accessor.read(output, 0, output.length) == 0);
    for (byte[] invalid : new byte[][] {new byte[0], new byte[65537]}) {
      Bridge.nextRead = invalid;
      try {
        accessor.read(output, 0, output.length);
        throw new AssertionError("invalid binary response accepted");
      } catch (IOException expected) {
        checks++;
      }
    }
    Bridge.writes.clear();
    Bridge.accepted.clear();
    Bridge.failAt = 1;
    try {
      accessor.write(input, 0, input.length);
      throw new AssertionError("storage error swallowed");
    } catch (IOException expected) {
      check(Bridge.writes.equals(List.of(65536, 65536)) && Bridge.accepted.size() == 65536);
    }
    accessor.close();
    accessor.close();
    check(Bridge.closeCalls == 1);
    try {
      accessor.write(input, 0, 0);
      throw new AssertionError("closed zero write accepted");
    } catch (IOException expected) {
      checks++;
    }
    var inputMethods = attach(FileInputStreamMethods.class, open());
    Bridge.nextRead = new byte[] {(byte) 255};
    check(inputMethods.read() == 255);
    Bridge.nextRead = new byte[] {(byte) 128};
    check(inputMethods.read() == 128);
    Bridge.nextRead = null;
    check(inputMethods.read() == -1 && inputMethods.read() == -1);
    var randomMethods = attach(RandomAccessFileMethods.class, open());
    int reads = Bridge.reads;
    check(randomMethods.read(new byte[0], 0, 0) == 0 && Bridge.reads == reads);
    try {
      randomMethods.read(new byte[4], Integer.MAX_VALUE, 2);
      throw new AssertionError("overflowing range accepted by JCL adapter");
    } catch (IndexOutOfBoundsException expected) {
      checks++;
    }
    check(randomMethods.read(new byte[1], 0, 1) == -1);
    int closes = Bridge.closeCalls;
    Bridge.failClose = true;
    try {
      randomMethods.close();
      throw new AssertionError("failed close was swallowed");
    } catch (IOException expected) {
      checks++;
    }
    check(randomMethods.read(new byte[0], 0, 0) == 0);
    randomMethods.close();
    randomMethods.close();
    check(Bridge.closeCalls == closes + 2);
    try {
      randomMethods.read(new byte[0], 0, 0);
      throw new AssertionError("closed JCL adapter read accepted");
    } catch (IOException expected) {
      checks++;
    }
    try {
      accessor.read(output, 0, 0);
      throw new AssertionError("closed zero read accepted");
    } catch (IOException expected) {
      checks++;
    }
    System.out.println(
        "File accessor and JCL boundary: "
            + checks
            + " checks; bounded binary, exact ranges and storage errors");
  }
}
