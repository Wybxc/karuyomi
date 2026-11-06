package java.util.concurrent.locks;

import java.util.*;

public class LockSupport {
  private static final Map<Thread, Boolean> permits = new HashMap<>();

  public static void unpark(Thread t) {
    if (t == null) return;
    synchronized (t) {
      permits.put(t, true);
      t.notifyAll();
    }
  }

  public static void park() {
    parkMillis(0);
  }

  public static void park(Object b) {
    park();
  }

  public static void parkNanos(Object b, long n) {
    parkNanos(n);
  }

  public static void parkNanos(long n) {
    if (n <= 0) return;
    parkMillis(Math.max(1, n / 1000000));
  }

  private static void parkMillis(long millis) {
    Thread t = Thread.currentThread();
    synchronized (t) {
      if (Boolean.TRUE.equals(permits.remove(t))) return;
      try {
        t.wait(millis);
      } catch (InterruptedException e) {
        t.interrupt();
      }
      permits.remove(t);
    }
  }
}
