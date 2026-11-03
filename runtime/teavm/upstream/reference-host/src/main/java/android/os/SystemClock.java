package android.os;
public final class SystemClock {
 public static long elapsedRealtime(){return System.nanoTime()/1000000;}
 public static long elapsedRealtimeNanos(){return System.nanoTime();}
 public static long uptimeMillis(){return elapsedRealtime();}
 public static void sleep(long millis){try{Thread.sleep(millis);}catch(InterruptedException e){Thread.currentThread().interrupt();}}
}
