package java.util.concurrent;

public interface ScheduledExecutorService extends ExecutorService {
  ScheduledFuture<?> schedule(Runnable r, long delay, TimeUnit u);

  <V> ScheduledFuture<V> schedule(Callable<V> c, long delay, TimeUnit u);

  ScheduledFuture<?> scheduleAtFixedRate(Runnable r, long initial, long period, TimeUnit u);

  ScheduledFuture<?> scheduleWithFixedDelay(Runnable r, long initial, long delay, TimeUnit u);
}
