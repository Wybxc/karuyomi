package prototype;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import okio.Buffer;

/** Unit boundary checks for the product cache Sink, independent of storage implementation. */
public final class CacheSinkTest {
  static int checks;

  static void check(boolean value) {
    checks++;
    if (!value) throw new AssertionError();
  }

  static class Store implements CacheSink.Store {
    List<Integer> sizes = new ArrayList<>();
    Buffer bytes = new Buffer();
    int failAt = -1, aborts, commits;
    boolean accepted = true;

    public boolean write(int sequence, byte[] chunk) throws IOException {
      check(sequence == sizes.size());
      sizes.add(chunk.length);
      if (sequence == failAt) throw new IOException("IDB quota fixture");
      bytes.write(chunk);
      return accepted;
    }

    public boolean commit() {
      commits++;
      return accepted;
    }

    public void abort() {
      aborts++;
    }
  }

  public static void main(String[] args) throws Exception {
    byte[] vector = CacheScenarios.body();
    int[] success = {0}, aborted = {0};
    Store store = new Store();
    CacheSink sink = new CacheSink(store, () -> false, () -> success[0]++, () -> aborted[0]++);
    Buffer source = new Buffer().write(vector).writeUtf8("surplus");
    sink.write(source, vector.length);
    sink.close();
    sink.close();
    sink.abort();
    check(store.sizes.equals(List.of(65536, 65536, 7)));
    check(Arrays.equals(store.bytes.readByteArray(), vector));
    check(source.readUtf8().equals("surplus"));
    check(success[0] == 1 && aborted[0] == 0 && store.commits == 1 && store.aborts == 0);
    Store failed = new Store();
    failed.failAt = 1;
    CacheSink discard = new CacheSink(failed, () -> false, () -> success[0]++, () -> aborted[0]++);
    Buffer input = new Buffer().write(vector).writeUtf8("keep");
    discard.write(input, vector.length);
    check(input.readUtf8().equals("keep") && failed.aborts == 1 && aborted[0] == 1);
    Buffer later = new Buffer().writeUtf8("dropkeep");
    discard.write(later, 4);
    check(later.readUtf8().equals("keep"));
    discard.close();
    discard.abort();
    check(failed.commits == 0 && failed.aborts == 1 && aborted[0] == 1);
    Store refused = new Store();
    refused.accepted = false;
    CacheSink declined =
        new CacheSink(refused, () -> false, () -> success[0]++, () -> aborted[0]++);
    declined.write(new Buffer().write(vector), vector.length);
    declined.close();
    check(refused.aborts == 1 && refused.commits == 0 && success[0] == 1 && aborted[0] == 2);
    Store closed = new Store();
    CacheSink closing = new CacheSink(closed, () -> true, () -> success[0]++, () -> aborted[0]++);
    closing.write(new Buffer().write(vector), vector.length);
    closing.close();
    check(closed.sizes.isEmpty() && closed.aborts == 1 && aborted[0] == 3);
    Store finishing = new Store();
    CacheSink commitFailed =
        new CacheSink(finishing, () -> false, () -> success[0]++, () -> aborted[0]++);
    commitFailed.write(new Buffer().write(vector), vector.length);
    finishing.accepted = false;
    commitFailed.close();
    check(finishing.commits == 1 && finishing.aborts == 1 && aborted[0] == 4);
    System.out.println(
        "Cache Sink JVM boundary: "
            + checks
            + " checks; bounded chunks, exact consumption and fault-hidden storage failures");
  }
}
