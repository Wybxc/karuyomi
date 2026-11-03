package android.os;
import java.util.*;
import java.util.concurrent.*;
public class Handler {
  private final Looper looper;
  private final Map<Runnable,List<ScheduledFuture<?>>> tasks = new IdentityHashMap<>();
  public Handler() { this(Looper.myLooper()!=null?Looper.myLooper():Looper.getMainLooper()); }
  public Handler(Looper looper) { this.looper=Objects.requireNonNull(looper); }
  public static Handler createAsync(Looper looper) { return new Handler(looper); }
  public Looper getLooper() { return looper; }
  public boolean post(Runnable task) { return postDelayed(task,0); }
  public boolean postDelayed(Runnable task,long delayMillis) {
    synchronized(tasks) {
      ScheduledFuture<?>[] holder=new ScheduledFuture<?>[1];
      ScheduledFuture<?> future=looper.executor.schedule(() -> {
        try { task.run(); } finally { synchronized(tasks) { var list=tasks.get(task); if(list!=null){list.remove(holder[0]);if(list.isEmpty())tasks.remove(task);} } }
      }, Math.max(0,delayMillis),TimeUnit.MILLISECONDS);
      holder[0]=future;
      tasks.computeIfAbsent(task,key->new ArrayList<>()).add(future);
    }
    return true;
  }
  public void removeCallbacks(Runnable task) { synchronized(tasks) { var list=tasks.remove(task);if(list!=null)for(var future:list)future.cancel(false); } }
  public void removeCallbacksAndMessages(Object token) { if(token!=null)throw new UnsupportedOperationException("Handler tokens are unsupported"); synchronized(tasks){for(var list:tasks.values())for(var future:list)future.cancel(false);tasks.clear();} }
}
