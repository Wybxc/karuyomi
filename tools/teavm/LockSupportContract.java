import java.util.concurrent.locks.LockSupport;

public final class LockSupportContract {
  private static final long BOUND_MILLIS = 2000;
  private static int cases;

  private static final class Worker extends Thread {
    private final Runnable action;
    volatile Throwable failure;
    volatile boolean released;

    Worker(String name, Runnable action) {
      super(name);
      this.action = action;
      setDaemon(true);
    }

    public void run() {
      try {
        action.run();
      } catch (Throwable error) {
        failure = error;
      }
    }
  }

  private static void require(boolean value, String message) {
    if (!value) throw new AssertionError(message);
  }

  private static void finish(Worker worker) throws Exception {
    worker.join(BOUND_MILLIS);
    if (worker.isAlive()) {
      worker.interrupt();
      worker.join(BOUND_MILLIS);
      throw new AssertionError(worker.getName() + " did not finish within the bound");
    }
    if (worker.failure != null) throw new AssertionError(worker.getName(), worker.failure);
    cases++;
    System.out.println(worker.getName() + ": passed");
  }

  private static void completes(String name, Runnable action) throws Exception {
    Worker worker = new Worker(name, action);
    worker.start();
    finish(worker);
  }

  private static void awaitParked(Worker worker, Thread.State state) throws Exception {
    long deadline = System.nanoTime() + BOUND_MILLIS * 1000000;
    while (worker.isAlive() && worker.getState() != state && System.nanoTime() < deadline)
      Thread.sleep(1);
    if (!worker.isAlive() || worker.getState() != state) {
      worker.interrupt();
      worker.join(BOUND_MILLIS);
      throw new AssertionError(worker.getName() + " did not park as " + state, worker.failure);
    }
  }

  private static void unparkWaiting(boolean timed, boolean blocker) throws Exception {
    String name = timed ? "timed-unpark" : blocker ? "blocker-unpark" : "untimed-unpark";
    Worker[] holder = new Worker[1];
    Worker worker =
        new Worker(
            name,
            () -> {
              while (!holder[0].released) {
                if (timed) LockSupport.parkNanos(holder[0], 30000000000L);
                else if (blocker) LockSupport.park(holder[0]);
                else LockSupport.park();
              }
              require(!Thread.currentThread().isInterrupted(), "unpark must not interrupt");
            });
    holder[0] = worker;
    worker.start();
    awaitParked(worker, timed ? Thread.State.TIMED_WAITING : Thread.State.WAITING);
    worker.released = true;
    LockSupport.unpark(worker);
    finish(worker);
  }

  public static void main(String[] args) throws Exception {
    // Force class initialization before preparing any worker's permit.
    LockSupport.unpark(null);
    for (long nanos : new long[] {0, -1, Long.MIN_VALUE}) {
      completes(
          "nonpositive-" + nanos,
          () -> {
            LockSupport.parkNanos(nanos);
            LockSupport.parkNanos(new Object(), nanos);
          });
      completes(
          "permit-kept-" + nanos,
          () -> {
            LockSupport.unpark(Thread.currentThread());
            LockSupport.parkNanos(nanos);
            LockSupport.park();
          });
      completes(
          "blocker-permit-kept-" + nanos,
          () -> {
            LockSupport.unpark(Thread.currentThread());
            LockSupport.parkNanos(new Object(), nanos);
            LockSupport.park();
          });
    }
    completes(
        "positive-timeout",
        () -> {
          LockSupport.parkNanos(1);
          LockSupport.parkNanos(new Object(), 10000000);
          require(!Thread.currentThread().isInterrupted(), "timeout must not interrupt");
        });
    completes(
        "positive-permit",
        () -> {
          LockSupport.unpark(Thread.currentThread());
          LockSupport.parkNanos(Long.MAX_VALUE);
        });
    completes(
        "untimed-permit",
        () -> {
          LockSupport.unpark(Thread.currentThread());
          LockSupport.park();
        });
    unparkWaiting(false, false);
    unparkWaiting(false, true);
    unparkWaiting(true, true);
    completes(
        "preinterrupted",
        () -> {
          Thread.currentThread().interrupt();
          LockSupport.park();
          require(Thread.currentThread().isInterrupted(), "park must preserve interrupt status");
          LockSupport.parkNanos(Long.MAX_VALUE);
          require(
              Thread.currentThread().isInterrupted(), "timed park must preserve interrupt status");
          LockSupport.parkNanos(0);
          LockSupport.parkNanos(-1);
          require(Thread.interrupted(), "nonpositive park must preserve interrupt status");
          require(!Thread.interrupted(), "Thread.interrupted must clear the status");
        });
    Worker interrupted =
        new Worker(
            "interrupt-wakes-park",
            () -> {
              while (!Thread.currentThread().isInterrupted()) LockSupport.park();
              require(Thread.interrupted(), "interrupt must survive waking park");
            });
    interrupted.start();
    awaitParked(interrupted, Thread.State.WAITING);
    interrupted.interrupt();
    finish(interrupted);
    System.out.println("LockSupport: " + cases + " behavioral cases passed");
  }
}
