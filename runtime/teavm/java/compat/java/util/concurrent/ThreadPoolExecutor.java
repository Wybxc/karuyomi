package java.util.concurrent;

import java.util.*;

/** Bounded cooperative executor. Threads are event-loop continuations, not OS threads. */
public class ThreadPoolExecutor implements ExecutorService {
  protected boolean shutdown, stopped;
  private int active, core, max;
  private ThreadFactory factory;
  private RejectedExecutionHandler rejection;
  private final BlockingQueue<Runnable> queue;
  private final Set<Thread> workers = new HashSet<>();

  public ThreadPoolExecutor(
      int core, int max, long keep, TimeUnit unit, BlockingQueue<Runnable> q) {
    this(core, max, keep, unit, q, r -> new Thread(r), new AbortPolicy());
  }

  public ThreadPoolExecutor(
      int core, int max, long keep, TimeUnit unit, BlockingQueue<Runnable> q, ThreadFactory f) {
    this(core, max, keep, unit, q, f, new AbortPolicy());
  }

  public ThreadPoolExecutor(
      int core,
      int max,
      long keep,
      TimeUnit unit,
      BlockingQueue<Runnable> q,
      ThreadFactory f,
      RejectedExecutionHandler rejection) {
    if (core < 0 || max <= 0 || max < core || keep < 0) throw new IllegalArgumentException();
    this.core = core;
    this.max = max;
    queue = Objects.requireNonNull(q);
    factory = Objects.requireNonNull(f);
    this.rejection = Objects.requireNonNull(rejection);
    Objects.requireNonNull(unit);
  }

  public synchronized void execute(Runnable task) {
    Objects.requireNonNull(task);
    if (shutdown) {
      rejection.rejectedExecution(task, this);
      return;
    }
    if (active < Math.max(1, core)) {
      start(task);
      return;
    }
    if (!queue.offer(task)) {
      if (active < max) start(task);
      else rejection.rejectedExecution(task, this);
    }
  }

  private void start(Runnable first) {
    active++;
    Thread worker =
        factory.newThread(() -> {
          Runnable r = first;
          try {
            while (r != null) {
              try {
                r.run();
              } catch (Throwable t) {
                Thread.currentThread()
                    .getUncaughtExceptionHandler()
                    .uncaughtException(Thread.currentThread(), t);
              }
              synchronized (this) {
                r = stopped ? null : queue.poll();
              }
            }
          } finally {
            synchronized (this) {
              active--;
              workers.remove(Thread.currentThread());
              notifyAll();
            }
          }
        });
    if (worker == null) {
      active--;
      throw new RejectedExecutionException("ThreadFactory returned null");
    }
    workers.add(worker);
    worker.start();
  }

  public synchronized void shutdown() {
    shutdown = true;
    notifyAll();
  }

  public synchronized List<Runnable> shutdownNow() {
    shutdown = true;
    stopped = true;
    List<Runnable> pending = new ArrayList<>();
    queue.drainTo(pending);
    for (Thread t : new ArrayList<>(workers)) t.interrupt();
    notifyAll();
    return pending;
  }

  public synchronized boolean isShutdown() {
    return shutdown;
  }

  public synchronized boolean isTerminated() {
    return shutdown && active == 0;
  }

  public synchronized boolean awaitTermination(long t, TimeUnit u) throws InterruptedException {
    long deadline = System.nanoTime() + u.toNanos(t);
    while (!isTerminated()) {
      long n = deadline - System.nanoTime();
      if (n <= 0) return false;
      wait(n / 1000000, (int) (n % 1000000));
    }
    return true;
  }

  public <T> Future<T> submit(Callable<T> c) {
    FutureTask<T> f = new FutureTask<>(c);
    execute(f);
    return f;
  }

  public <T> Future<T> submit(Runnable r, T result) {
    return submit(() -> {
      r.run();
      return result;
    });
  }

  public Future<?> submit(Runnable r) {
    return submit(r, null);
  }

  public <T> List<Future<T>> invokeAll(Collection<? extends Callable<T>> tasks)
      throws InterruptedException {
    List<Future<T>> list = new ArrayList<>();
    try {
      for (Callable<T> c : tasks) list.add(submit(c));
      for (Future<T> f : list)
        try {
          f.get();
        } catch (ExecutionException | CancellationException ignored) {
        }
      return list;
    } finally {
      for (Future<T> f : list) if (!f.isDone()) f.cancel(true);
    }
  }

  public <T> List<Future<T>> invokeAll(Collection<? extends Callable<T>> tasks, long t, TimeUnit u)
      throws InterruptedException {
    long deadline = System.nanoTime() + u.toNanos(t);
    List<Future<T>> list = new ArrayList<>();
    try {
      for (Callable<T> c : tasks) list.add(submit(c));
      for (Future<T> f : list)
        try {
          f.get(Math.max(0, deadline - System.nanoTime()), TimeUnit.NANOSECONDS);
        } catch (ExecutionException | CancellationException ignored) {
        } catch (TimeoutException end) {
          break;
        }
      return list;
    } finally {
      for (Future<T> f : list) if (!f.isDone()) f.cancel(true);
    }
  }

  public <T> T invokeAny(Collection<? extends Callable<T>> tasks)
      throws InterruptedException, ExecutionException {
    try {
      return invokeAny(tasks, Long.MAX_VALUE / 2, TimeUnit.NANOSECONDS);
    } catch (TimeoutException e) {
      throw new ExecutionException(e);
    }
  }

  public <T> T invokeAny(Collection<? extends Callable<T>> tasks, long t, TimeUnit u)
      throws InterruptedException, ExecutionException, TimeoutException {
    if (tasks.isEmpty()) throw new IllegalArgumentException();
    List<Future<T>> fs = new ArrayList<>();
    long deadline = System.nanoTime() + u.toNanos(t);
    ExecutionException error = null;
    try {
      for (Callable<T> c : tasks) fs.add(submit(c));
      while (!fs.isEmpty()) {
        for (Iterator<Future<T>> i = fs.iterator(); i.hasNext(); ) {
          Future<T> f = i.next();
          if (f.isDone()) {
            try {
              return f.get();
            } catch (ExecutionException e) {
              error = e;
              i.remove();
            }
          }
        }
        if (fs.isEmpty()) throw error;
        if (System.nanoTime() >= deadline) throw new TimeoutException();
        Thread.sleep(1);
      }
      throw new ExecutionException(new IllegalStateException());
    } finally {
      for (Future<T> f : fs) f.cancel(true);
    }
  }

  public BlockingQueue<Runnable> getQueue() {
    return queue;
  }

  public void allowCoreThreadTimeOut(boolean b) {
    if (!b) throw new UnsupportedOperationException("Cooperative workers are released when idle");
  }

  public synchronized void setCorePoolSize(int c) {
    if (c < 0 || c > max) throw new IllegalArgumentException();
    core = c;
  }

  public int getCorePoolSize() {
    return core;
  }

  public int getMaximumPoolSize() {
    return max;
  }

  public synchronized int getActiveCount() {
    return active;
  }

  public static class AbortPolicy implements RejectedExecutionHandler {
    public void rejectedExecution(Runnable r, ThreadPoolExecutor e) {
      throw new RejectedExecutionException("Executor rejected task");
    }
  }
}
