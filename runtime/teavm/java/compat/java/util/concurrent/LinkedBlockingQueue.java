package java.util.concurrent;import java.util.*;
public class LinkedBlockingQueue<E> extends AbstractQueue<E> implements BlockingQueue<E>{
 private final ArrayDeque<E> data=new ArrayDeque<>();private final int capacity;
 public LinkedBlockingQueue(){this(Integer.MAX_VALUE);}public LinkedBlockingQueue(int capacity){if(capacity<=0)throw new IllegalArgumentException();this.capacity=capacity;}
 public synchronized int size(){return data.size();}public synchronized int remainingCapacity(){return capacity-data.size();}public synchronized Iterator<E> iterator(){return new ArrayList<>(data).iterator();}
 public synchronized boolean offer(E e){Objects.requireNonNull(e);if(data.size()==capacity)return false;data.add(e);notifyAll();return true;}
 public synchronized E poll(){E e=data.poll();if(e!=null)notifyAll();return e;}public synchronized E peek(){return data.peek();}
 public synchronized void put(E e)throws InterruptedException{while(!offer(e))wait();}
 public synchronized E take()throws InterruptedException{E e;while((e=poll())==null)wait();return e;}
 public synchronized boolean offer(E e,long timeout,TimeUnit unit)throws InterruptedException{long end=System.nanoTime()+unit.toNanos(timeout);while(!offer(e)){long n=end-System.nanoTime();if(n<=0)return false;wait((n+999999)/1000000);}return true;}
 public synchronized E poll(long timeout,TimeUnit unit)throws InterruptedException{long end=System.nanoTime()+unit.toNanos(timeout);E e;while((e=poll())==null){long n=end-System.nanoTime();if(n<=0)return null;wait((n+999999)/1000000);}return e;}
 public synchronized int drainTo(Collection<? super E> c){return drainTo(c,Integer.MAX_VALUE);}public synchronized int drainTo(Collection<? super E> c,int max){Objects.requireNonNull(c);if(c==this)throw new IllegalArgumentException();int n=0;while(n<max&&!data.isEmpty()){c.add(data.peek());data.remove();n++;}if(n>0)notifyAll();return n;}
 public synchronized boolean remove(Object o){boolean b=data.remove(o);if(b)notifyAll();return b;}public synchronized void clear(){data.clear();notifyAll();}
}
