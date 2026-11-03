package java.util.concurrent;

import java.util.*;

public class ScheduledThreadPoolExecutor extends ThreadPoolExecutor
    implements ScheduledExecutorService {
  private final Set<Scheduled<?>> timers = new HashSet<>();
  private boolean removeOnCancel;

  public void setRemoveOnCancelPolicy(boolean b) {
    removeOnCancel = b;
  }

  public boolean getRemoveOnCancelPolicy() {
    return removeOnCancel;
  }

  public ScheduledThreadPoolExecutor(int core) {
    this(core, r -> new Thread(r));
  }

  public ScheduledThreadPoolExecutor(int core, ThreadFactory f) {
    super(core, Integer.MAX_VALUE, 0, TimeUnit.MILLISECONDS, new LinkedBlockingQueue<>(), f);
  }

  class Scheduled<V> implements ScheduledFuture<V> {
    final Callable<V> callable;
    final FutureTask<V> future;
    final long period;
    long due;
    Thread timer;

    Scheduled(Callable<V> c, long delay, long period) {
      callable = c;
      due = System.nanoTime() + Math.max(0, delay);
      this.period = period;
      future = new FutureTask<>(c);
      synchronized (timers) {
        timers.add(this);
      }
      timer =
          new Thread(() -> {
            try {
              while (!future.isCancelled()) {
                long remaining = due - System.nanoTime();
                if (remaining > 0) {
                  Thread.sleep((remaining + 999999) / 1000000);
                  continue;
                }
                if (period == 0) {
                  ScheduledThreadPoolExecutor.super.execute(future);
                  break;
                }
                FutureTask<V> iteration = new FutureTask<>(callable);
                ScheduledThreadPoolExecutor.super.execute(iteration);
                try {
                  iteration.get();
                } catch (ExecutionException e) {
                  future.setException(e.getCause());
                  break;
                }
                due = period > 0 ? due + period : System.nanoTime() - period;
              }
            } catch (InterruptedException e) {
              future.cancel(false);
            } catch (Throwable e) {
              future.setException(e);
            } finally {
              synchronized (timers) {
                timers.remove(this);
              }
            }
          });
      timer.start();
    }

    public long getDelay(TimeUnit u) {
      return u.convert(due - System.nanoTime(), TimeUnit.NANOSECONDS);
    }

    public int compareTo(Delayed other) {
      return Long.compare(getDelay(TimeUnit.NANOSECONDS), other.getDelay(TimeUnit.NANOSECONDS));
    }

    public boolean cancel(boolean interrupt) {
      boolean b = future.cancel(interrupt);
      if (b && (removeOnCancel || interrupt)) {
        timer.interrupt();
        synchronized (timers) {
          timers.remove(this);
        }
      }
      return b;
    }

    public boolean isDone() {
      return future.isDone();
    }

    public boolean isCancelled() {
      return future.isCancelled();
    }

    public V get() throws InterruptedException, ExecutionException {
      return future.get();
    }

    public V get(long t, TimeUnit u)
        throws InterruptedException, ExecutionException, TimeoutException {
      return future.get(t, u);
    }
  }

  public <V> ScheduledFuture<V> schedule(Callable<V> c, long delay, TimeUnit u) {
    if (isShutdown()) throw new RejectedExecutionException();
    return new Scheduled<>(c, u.toNanos(delay), 0);
  }

  public ScheduledFuture<?> schedule(Runnable r, long d, TimeUnit u) {
    return schedule(
        () -> {
          r.run();
          return null;
        },
        d,
        u);
  }

  public ScheduledFuture<?> scheduleAtFixedRate(Runnable r, long d, long p, TimeUnit u) {
    if (p <= 0) throw new IllegalArgumentException();
    if (isShutdown()) throw new RejectedExecutionException();
    return new Scheduled<>(
        () -> {
          r.run();
          return null;
        },
        u.toNanos(d),
        u.toNanos(p));
  }

  public ScheduledFuture<?> scheduleWithFixedDelay(Runnable r, long d, long p, TimeUnit u) {
    if (p <= 0) throw new IllegalArgumentException();
    if (isShutdown()) throw new RejectedExecutionException();
    return new Scheduled<>(
        () -> {
          r.run();
          return null;
        },
        u.toNanos(d),
        -u.toNanos(p));
  }

  public void shutdown() {
    synchronized (timers) {
      for (Scheduled<?> s : new ArrayList<>(timers)) s.cancel(true);
    }
    super.shutdown();
  }

  public List<Runnable> shutdownNow() {
    synchronized (timers) {
      for (Scheduled<?> s : new ArrayList<>(timers)) s.cancel(true);
    }
    return super.shutdownNow();
  }
}
