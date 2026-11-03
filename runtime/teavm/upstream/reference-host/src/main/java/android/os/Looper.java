package android.os;
import java.util.concurrent.*;
public final class Looper {
  private static final Looper MAIN = new Looper();
  private volatile Thread thread;
  final ScheduledThreadPoolExecutor executor = new ScheduledThreadPoolExecutor(1, task -> {
    Thread worker = new Thread(task,"browser-android-main"); worker.setDaemon(true); thread=worker; return worker;
  });
  private Looper() { executor.setRemoveOnCancelPolicy(true); }
  public static Looper getMainLooper() { return MAIN; }
  public static Looper myLooper() { return Thread.currentThread()==MAIN.thread ? MAIN : null; }
  public Thread getThread() { return thread; }
}
