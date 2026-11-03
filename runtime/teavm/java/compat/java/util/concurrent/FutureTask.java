package java.util.concurrent;
/** Future completion and waiters use TeaVM monitors and cooperative threads. */
public class FutureTask<V> implements RunnableFuture<V>{
 private final Callable<V> callable;private V value;private Throwable error;private boolean done,cancelled;private Thread runner;
 public FutureTask(Callable<V> callable){this.callable=java.util.Objects.requireNonNull(callable);}public FutureTask(Runnable r,V value){this(()->{r.run();return value;});}
 public void run(){synchronized(this){if(done||runner!=null)return;runner=Thread.currentThread();}try{set(callable.call());}catch(Throwable t){setException(t);}finally{synchronized(this){runner=null;}}}
 protected synchronized void set(V v){if(done)return;value=v;done=true;notifyAll();done();}protected synchronized void setException(Throwable t){if(done)return;error=t;done=true;notifyAll();done();}protected void done(){}
 public synchronized boolean cancel(boolean interrupt){if(done)return false;cancelled=true;done=true;if(interrupt&&runner!=null)runner.interrupt();notifyAll();done();return true;}
 public synchronized boolean isCancelled(){return cancelled;}public synchronized boolean isDone(){return done;}
 V result()throws ExecutionException{if(cancelled)throw new CancellationException();if(error!=null)throw new ExecutionException(error);return value;}
 public synchronized V get()throws InterruptedException,ExecutionException{while(!done)wait();return result();}
 public synchronized V get(long timeout,TimeUnit unit)throws InterruptedException,ExecutionException,TimeoutException{long deadline=System.nanoTime()+unit.toNanos(timeout);while(!done){long n=deadline-System.nanoTime();if(n<=0)throw new TimeoutException();wait(n/1000000,(int)(n%1000000));}return result();}
}
