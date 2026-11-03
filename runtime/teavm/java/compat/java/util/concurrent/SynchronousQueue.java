package java.util.concurrent;

import java.util.*;

/** Zero-capacity queue: an offer succeeds only while a consumer is waiting. */
public class SynchronousQueue<E> extends AbstractQueue<E> implements BlockingQueue<E> {
  private E slot;
  private int waiting;

  public SynchronousQueue() {}

  public SynchronousQueue(boolean fair) {
    if (fair) throw new UnsupportedOperationException("Fair rendezvous queue");
  }

  public int size() {
    return 0;
  }

  public int remainingCapacity() {
    return 0;
  }

  public Iterator<E> iterator() {
    return Collections.emptyIterator();
  }

  public E peek() {
    return null;
  }

  public synchronized boolean offer(E e) {
    Objects.requireNonNull(e);
    if (waiting == 0 || slot != null) return false;
    slot = e;
    notifyAll();
    return true;
  }

  public synchronized E poll() {
    E e = slot;
    slot = null;
    if (e != null) notifyAll();
    return e;
  }

  public synchronized E take() throws InterruptedException {
    waiting++;
    try {
      E e;
      notifyAll();
      while ((e = poll()) == null) wait();
      return e;
    } finally {
      waiting--;
    }
  }

  public synchronized E poll(long timeout, TimeUnit unit) throws InterruptedException {
    waiting++;
    long end = System.nanoTime() + unit.toNanos(timeout);
    try {
      E e;
      notifyAll();
      while ((e = poll()) == null) {
        long n = end - System.nanoTime();
        if (n <= 0) return null;
        wait((n + 999999) / 1000000);
      }
      return e;
    } finally {
      waiting--;
    }
  }

  public synchronized void put(E e) throws InterruptedException {
    Objects.requireNonNull(e);
    while (!offer(e)) wait();
    try {
      while (slot != null) wait();
    } catch (InterruptedException x) {
      if (slot == e) {
        slot = null;
        notifyAll();
      }
      throw x;
    }
  }

  public synchronized boolean offer(E e, long timeout, TimeUnit unit) throws InterruptedException {
    Objects.requireNonNull(e);
    long end = System.nanoTime() + unit.toNanos(timeout);
    while (!offer(e)) {
      long n = end - System.nanoTime();
      if (n <= 0) return false;
      wait((n + 999999) / 1000000);
    }
    try {
      while (slot != null) {
        long n = end - System.nanoTime();
        if (n <= 0) {
          slot = null;
          notifyAll();
          return false;
        }
        wait((n + 999999) / 1000000);
      }
      return true;
    } catch (InterruptedException x) {
      if (slot == e) {
        slot = null;
        notifyAll();
      }
      throw x;
    }
  }

  public synchronized int drainTo(Collection<? super E> c) {
    return drainTo(c, Integer.MAX_VALUE);
  }

  public synchronized int drainTo(Collection<? super E> c, int max) {
    if (c == this) throw new IllegalArgumentException();
    Objects.requireNonNull(c);
    if (max <= 0 || slot == null) return 0;
    c.add(slot);
    slot = null;
    notifyAll();
    return 1;
  }
}
