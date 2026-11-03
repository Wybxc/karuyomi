package android.util;
public final class Log {
 public static int d(String t,String m){System.out.println(t+": "+m);return 0;}
 public static int i(String t,String m){return d(t,m);} public static int v(String t,String m){return 0;}
 public static int w(String t,String m){return d(t,m);} public static int e(String t,String m){return d(t,m);}
 public static int e(String t,String m,Throwable e){e.printStackTrace();return d(t,m);}
 public static int println(int priority,String tag,String message){return d(tag,message);}
 public static boolean isLoggable(String t,int l){return false;}
}
