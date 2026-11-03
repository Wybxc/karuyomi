package java.util.concurrent;

public class CountDownLatch {
  private int n;

  public CountDownLatch(int n) {
    this.n = n;
  }

  public synchronized void countDown() {
    if (n > 0) n--;
    notifyAll();
  }

  public synchronized void await() throws InterruptedException {
    while (n > 0) wait();
  }

  public long getCount() {
    return n;
  }
}
