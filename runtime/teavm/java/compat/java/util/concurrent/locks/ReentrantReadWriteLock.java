package java.util.concurrent.locks;

import java.util.*;
import java.util.concurrent.TimeUnit;

/** Reentrant shared/exclusive locking for TeaVM's cooperative threads. */
public class ReentrantReadWriteLock implements java.io.Serializable {
  private final ReentrantLock gate;
  private final Condition changed;
  private final Map<Thread, Integer> readers = new IdentityHashMap<>();
  private int readCount, writersWaiting, writeDepth;
  private Thread writer;
  private final ReadLock read = new ReadLock(this);
  private final WriteLock write = new WriteLock(this);

  public ReentrantReadWriteLock() {
    this(false);
  }

  public ReentrantReadWriteLock(boolean fair) {
    gate = new ReentrantLock(fair);
    changed = gate.newCondition();
  }

  public ReadLock readLock() {
    return read;
  }

  public WriteLock writeLock() {
    return write;
  }

  public boolean isFair() {
    return gate.isFair();
  }

  public boolean isWriteLocked() {
    return writer != null;
  }

  public boolean isWriteLockedByCurrentThread() {
    return writer == Thread.currentThread();
  }

  public int getWriteHoldCount() {
    return isWriteLockedByCurrentThread() ? writeDepth : 0;
  }

  public int getReadLockCount() {
    return readCount;
  }

  public int getReadHoldCount() {
    return readers.getOrDefault(Thread.currentThread(), 0);
  }

  public boolean hasQueuedThreads() {
    return writersWaiting > 0 || gate.hasQueuedThreads();
  }

  public int getQueueLength() {
    return writersWaiting + gate.getQueueLength();
  }

  private boolean readAllowed(boolean barging) {
    return writer == Thread.currentThread()
        || getReadHoldCount() > 0
        || writersWaiting == 0
        || barging;
  }

  private void addRead() {
    if (readCount == 65535) throw new Error("Maximum lock count exceeded");
    Thread t = Thread.currentThread();
    readers.put(t, readers.getOrDefault(t, 0) + 1);
    readCount++;
  }

  public static class ReadLock implements Lock, java.io.Serializable {
    private final ReentrantReadWriteLock state;

    protected ReadLock(ReentrantReadWriteLock state) {
      this.state = state;
    }

    public void lock() {
      ReentrantReadWriteLock s = state;
      s.gate.lock();
      try {
        while (!s.readAllowed(false)) s.changed.awaitUninterruptibly();
        s.addRead();
      } finally {
        s.gate.unlock();
      }
    }

    public void lockInterruptibly() throws InterruptedException {
      ReentrantReadWriteLock s = state;
      s.gate.lockInterruptibly();
      try {
        while (!s.readAllowed(false)) s.changed.await();
        s.addRead();
      } finally {
        s.gate.unlock();
      }
    }

    public boolean tryLock() {
      ReentrantReadWriteLock s = state;
      if (!s.gate.tryLock()) return false;
      try {
        s.addRead();
        return true;
      } finally {
        s.gate.unlock();
      }
    }

    public boolean tryLock(long time, TimeUnit unit) throws InterruptedException {
      ReentrantReadWriteLock s = state;
      long nanos = Objects.requireNonNull(unit).toNanos(time), start = System.nanoTime();
      if (!s.gate.tryLock(time, unit)) return false;
      try {
        while (!s.readAllowed(false)) {
          long left = nanos - (System.nanoTime() - start);
          if (left <= 0) return false;
          s.changed.awaitNanos(left);
        }
        s.addRead();
        return true;
      } finally {
        s.gate.unlock();
      }
    }

    public void unlock() {
      ReentrantReadWriteLock s = state;
      s.gate.lock();
      try {
        Thread t = Thread.currentThread();
        int count = s.readers.getOrDefault(t, 0);
        if (count == 0) throw new IllegalMonitorStateException();
        if (count == 1) s.readers.remove(t);
        else s.readers.put(t, count - 1);
        if (--s.readCount == 0) s.changed.signalAll();
      } finally {
        s.gate.unlock();
      }
    }

    public Condition newCondition() {
      throw new UnsupportedOperationException();
    }
  }

  public static class WriteLock implements Lock, java.io.Serializable {
    private final ReentrantReadWriteLock state;

    protected WriteLock(ReentrantReadWriteLock state) {
      this.state = state;
    }

    private void acquired() {
      ReentrantReadWriteLock s = state;
      if (s.writeDepth == 65535) {
        s.gate.unlock();
        throw new Error("Maximum lock count exceeded");
      }
      s.writer = Thread.currentThread();
      s.writeDepth++;
    }

    public void lock() {
      ReentrantReadWriteLock s = state;
      s.gate.lock();
      s.writersWaiting++;
      try {
        while (s.writer != Thread.currentThread() && s.readCount > 0)
          s.changed.awaitUninterruptibly();
        acquired();
      } finally {
        s.writersWaiting--;
      }
    }

    public void lockInterruptibly() throws InterruptedException {
      ReentrantReadWriteLock s = state;
      s.gate.lockInterruptibly();
      boolean success = false;
      s.writersWaiting++;
      try {
        while (s.writer != Thread.currentThread() && s.readCount > 0) s.changed.await();
        acquired();
        success = true;
      } finally {
        s.writersWaiting--;
        if (!success) {
          s.changed.signalAll();
          s.gate.unlock();
        }
      }
    }

    public boolean tryLock() {
      ReentrantReadWriteLock s = state;
      if (!s.gate.tryLock()) return false;
      if (s.writer != Thread.currentThread() && s.readCount > 0) {
        s.gate.unlock();
        return false;
      }
      acquired();
      return true;
    }

    public boolean tryLock(long time, TimeUnit unit) throws InterruptedException {
      ReentrantReadWriteLock s = state;
      long nanos = Objects.requireNonNull(unit).toNanos(time), start = System.nanoTime();
      if (!s.gate.tryLock(time, unit)) return false;
      boolean success = false;
      s.writersWaiting++;
      try {
        while (s.writer != Thread.currentThread() && s.readCount > 0) {
          long left = nanos - (System.nanoTime() - start);
          if (left <= 0) return false;
          s.changed.awaitNanos(left);
        }
        acquired();
        success = true;
        return true;
      } finally {
        s.writersWaiting--;
        if (!success) {
          s.changed.signalAll();
          s.gate.unlock();
        }
      }
    }

    public void unlock() {
      ReentrantReadWriteLock s = state;
      if (s.writer != Thread.currentThread()) throw new IllegalMonitorStateException();
      if (--s.writeDepth == 0) {
        s.writer = null;
        s.changed.signalAll();
      }
      s.gate.unlock();
    }

    public boolean isHeldByCurrentThread() {
      return state.isWriteLockedByCurrentThread();
    }

    public int getHoldCount() {
      return state.getWriteHoldCount();
    }

    public Condition newCondition() {
      ReentrantReadWriteLock s = state;
      Condition inner = s.gate.newCondition();
      return new Condition() {
        private int release() {
          if (!isHeldByCurrentThread()) throw new IllegalMonitorStateException();
          int saved = s.writeDepth;
          s.writer = null;
          s.writeDepth = 0;
          s.changed.signalAll();
          return saved;
        }

        private void restore(int saved) {
          s.writersWaiting++;
          try {
            while (s.readCount > 0) s.changed.awaitUninterruptibly();
            s.writer = Thread.currentThread();
            s.writeDepth = saved;
          } finally {
            s.writersWaiting--;
          }
        }

        public void await() throws InterruptedException {
          if (Thread.interrupted()) throw new InterruptedException();
          int saved = release();
          try {
            inner.await();
          } finally {
            restore(saved);
          }
        }

        public void awaitUninterruptibly() {
          int saved = release();
          try {
            inner.awaitUninterruptibly();
          } finally {
            restore(saved);
          }
        }

        public long awaitNanos(long nanos) throws InterruptedException {
          if (Thread.interrupted()) throw new InterruptedException();
          int saved = release();
          long start = System.nanoTime();
          try {
            inner.awaitNanos(nanos);
          } finally {
            restore(saved);
          }
          return nanos - (System.nanoTime() - start);
        }

        public boolean await(long time, TimeUnit unit) throws InterruptedException {
          Objects.requireNonNull(unit);
          if (Thread.interrupted()) throw new InterruptedException();
          int saved = release();
          try {
            return inner.await(time, unit);
          } finally {
            restore(saved);
          }
        }

        public boolean awaitUntil(Date deadline) throws InterruptedException {
          Objects.requireNonNull(deadline);
          if (Thread.interrupted()) throw new InterruptedException();
          int saved = release();
          try {
            return inner.awaitUntil(deadline);
          } finally {
            restore(saved);
          }
        }

        public void signal() {
          if (!isHeldByCurrentThread()) throw new IllegalMonitorStateException();
          inner.signal();
        }

        public void signalAll() {
          if (!isHeldByCurrentThread()) throw new IllegalMonitorStateException();
          inner.signalAll();
        }
      };
    }
  }
}
