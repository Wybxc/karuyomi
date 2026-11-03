package java.util.concurrent.locks;
import java.util.*;
import java.util.concurrent.TimeUnit;

/** Locks between TeaVM cooperative Java threads; no claim of OS-thread parallelism. */
public class ReentrantLock implements Lock,java.io.Serializable {
 private Thread owner;private int depth;private final boolean fair;
 private final ArrayDeque<Waiter> queue=new ArrayDeque<>();
 private static final class Waiter{final Thread thread=Thread.currentThread();boolean signaled;}
 public ReentrantLock(){this(false);} public ReentrantLock(boolean fair){this.fair=fair;}
 private boolean available(Waiter waiter,boolean obeyFairness){return owner==null&&(!obeyFairness||queue.isEmpty()||queue.peek()==waiter);}
 private boolean acquire(boolean interruptible,boolean timed,long nanos,boolean obeyFairness,Waiter waiter)throws InterruptedException{
  if(interruptible&&Thread.interrupted())throw new InterruptedException();
  if(owner==Thread.currentThread()){if(depth==Integer.MAX_VALUE)throw new Error("Maximum lock count exceeded");depth++;return true;}
  if(available(waiter,obeyFairness)){owner=Thread.currentThread();depth=1;if(waiter!=null)queue.remove(waiter);return true;}
  if(timed&&nanos<=0)return false;
  if(waiter==null){waiter=new Waiter();queue.add(waiter);}else if(!queue.contains(waiter))queue.add(waiter);
  long start=System.nanoTime();boolean interrupted=false,acquired=false;
  try{
   while(!available(waiter,obeyFairness)){
    try{
     if(timed){long left=nanos-(System.nanoTime()-start);if(left<=0)return false;wait(Math.max(1,(left-1)/1000000+1));}
     else wait();
    }catch(InterruptedException error){if(interruptible)throw error;interrupted=true;}
   }
   owner=Thread.currentThread();depth=1;acquired=true;return true;
  }finally{queue.remove(waiter);if(!acquired)notifyAll();if(interrupted)Thread.currentThread().interrupt();}
 }
 public synchronized void lock(){try{acquire(false,false,0,fair,null);}catch(InterruptedException impossible){throw new AssertionError(impossible);}}
 public synchronized void lockInterruptibly()throws InterruptedException{acquire(true,false,0,fair,null);}
 public synchronized boolean tryLock(){if(owner==Thread.currentThread()){if(depth==Integer.MAX_VALUE)throw new Error("Maximum lock count exceeded");depth++;return true;}if(owner!=null)return false;owner=Thread.currentThread();depth=1;return true;}
 public synchronized boolean tryLock(long time,TimeUnit unit)throws InterruptedException{return acquire(true,true,Objects.requireNonNull(unit).toNanos(time),fair,null);}
 public synchronized void unlock(){checkOwner();if(--depth==0){owner=null;notifyAll();}}
 private void checkOwner(){if(owner!=Thread.currentThread())throw new IllegalMonitorStateException();}
 public boolean isHeldByCurrentThread(){return owner==Thread.currentThread();}public int getHoldCount(){return isHeldByCurrentThread()?depth:0;}
 public boolean isFair(){return fair;}public boolean isLocked(){return owner!=null;}protected Thread getOwner(){return owner;}
 public synchronized boolean hasQueuedThreads(){return !queue.isEmpty();}public synchronized int getQueueLength(){return queue.size();}
 public synchronized boolean hasQueuedThread(Thread thread){Objects.requireNonNull(thread);for(Waiter node:queue)if(node.thread==thread)return true;return false;}
 public Condition newCondition(){return new LockCondition();}
 private final class LockCondition implements Condition {
  private final ArrayDeque<Waiter> waiting=new ArrayDeque<>();
  private final class AwaitResult{final long remaining;final boolean signaled;AwaitResult(long remaining,boolean signaled){this.remaining=remaining;this.signaled=signaled;}}
  private AwaitResult awaitInternal(boolean interruptible,boolean timed,long nanos)throws InterruptedException{
   synchronized(ReentrantLock.this){
    if(interruptible&&Thread.interrupted())throw new InterruptedException();checkOwner();
    int saved=depth;Waiter node=new Waiter();waiting.add(node);depth=0;owner=null;ReentrantLock.this.notifyAll();
    long start=System.nanoTime();boolean interrupted=false,throwInterrupted=false;
    try{
     while(!node.signaled){
      long left=nanos-(System.nanoTime()-start);if(timed&&left<=0)break;
      try{if(timed)ReentrantLock.this.wait(Math.max(1,(left-1)/1000000+1));else ReentrantLock.this.wait();}
      catch(InterruptedException error){if(interruptible&&!node.signaled){throwInterrupted=true;break;}interrupted=true;}
     }
    }finally{
     waiting.remove(node);
     // signal() queues a waiter at signal time, preserving fair acquisition order.
     if(!queue.contains(node))queue.add(node);
     try{acquire(false,false,0,true,node);}catch(InterruptedException impossible){throw new AssertionError(impossible);}
     depth=saved;
    }
    if(interrupted)Thread.currentThread().interrupt();
    if(throwInterrupted)throw new InterruptedException();
    long left=nanos-(System.nanoTime()-start);
    return new AwaitResult(left,node.signaled);
   }
  }
  public void await()throws InterruptedException{awaitInternal(true,false,0);}
  public void awaitUninterruptibly(){try{awaitInternal(false,false,0);}catch(InterruptedException impossible){throw new AssertionError(impossible);}}
  public long awaitNanos(long nanos)throws InterruptedException{return awaitInternal(true,true,nanos).remaining;}
  public boolean await(long time,TimeUnit unit)throws InterruptedException{return awaitInternal(true,true,Objects.requireNonNull(unit).toNanos(time)).signaled;}
  public boolean awaitUntil(Date deadline)throws InterruptedException{return await(Math.max(0,Objects.requireNonNull(deadline).getTime()-System.currentTimeMillis()),TimeUnit.MILLISECONDS);}
  public void signal(){synchronized(ReentrantLock.this){checkOwner();Waiter node=waiting.poll();if(node!=null){node.signaled=true;queue.add(node);ReentrantLock.this.notifyAll();}}}
  public void signalAll(){synchronized(ReentrantLock.this){checkOwner();while(!waiting.isEmpty())signal();}}
 }
}
