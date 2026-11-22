package okhttp3;

import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.*;
import java.util.function.Consumer;

/** OkHttp asynchronous call policy for the Source host's browser transport. */
public final class Dispatcher {
  private static final int MAX_QUEUED = 64;
  private final ArrayDeque<Task> queued = new ArrayDeque<>();
  private final Set<Task> running = new HashSet<>();
  private int maxRequests = 64;
  private int maxRequestsPerHost = 5;

  private record Task(Call call, String host, Runnable work, Consumer<IOException> fail) {}

  public synchronized int getMaxRequests() {
    return maxRequests;
  }

  public void setMaxRequests(int maximum) {
    if (maximum < 1) throw new IllegalArgumentException("maxRequests must be positive");
    synchronized (this) {
      maxRequests = maximum;
    }
    promote();
  }

  public synchronized int getMaxRequestsPerHost() {
    return maxRequestsPerHost;
  }

  public void setMaxRequestsPerHost(int maximum) {
    if (maximum < 1) throw new IllegalArgumentException("maxRequestsPerHost must be positive");
    synchronized (this) {
      maxRequestsPerHost = maximum;
    }
    promote();
  }

  public void hostEnqueue(Call call, Runnable work, Consumer<IOException> fail) {
    Task task = new Task(call, call.request().url().host(), work, fail);
    boolean cancelled;
    synchronized (this) {
      cancelled = call.isCanceled();
      if (!cancelled) {
        if (queued.size() >= MAX_QUEUED)
          throw new IllegalStateException("Too many queued Source HTTP calls");
        queued.addLast(task);
      }
    }
    if (cancelled) failCancelled(task);
    else promote();
  }

  public void hostCancelQueued(Call call) {
    Task cancelled = null;
    synchronized (this) {
      var iterator = queued.iterator();
      while (iterator.hasNext()) {
        Task task = iterator.next();
        if (task.call() == call) {
          iterator.remove();
          cancelled = task;
          break;
        }
      }
    }
    if (cancelled != null) failCancelled(cancelled);
  }

  private static void failCancelled(Task task) {
    Runnable failure = () -> task.fail().accept(new InterruptedIOException("Cancelled"));
    try {
      new Thread(failure).start();
    } catch (RuntimeException | Error error) {
      failure.run();
    }
  }

  private void promote() {
    List<Task> ready = new ArrayList<>();
    synchronized (this) {
      if (queued.isEmpty() || running.size() >= maxRequests) return;
      Map<String, Integer> byHost = new HashMap<>();
      for (Task task : running) byHost.merge(task.host(), 1, Integer::sum);
      var iterator = queued.iterator();
      while (iterator.hasNext() && running.size() < maxRequests) {
        Task task = iterator.next();
        int count = byHost.getOrDefault(task.host(), 0);
        if (count >= maxRequestsPerHost) continue;
        iterator.remove();
        byHost.put(task.host(), count + 1);
        running.add(task);
        ready.add(task);
      }
    }
    // Thread starts and callbacks can reenter the dispatcher.
    for (Task task : ready) launch(task);
  }

  private void launch(Task task) {
    try {
      new Thread(
              () -> {
                try {
                  task.work().run();
                } finally {
                  finished(task);
                }
              })
          .start();
    } catch (RuntimeException | Error error) {
      try {
        task.fail().accept(new IOException("Could not start Source HTTP callback", error));
      } finally {
        finished(task);
      }
    }
  }

  private void finished(Task task) {
    synchronized (this) {
      running.remove(task);
    }
    promote();
  }
}
