package android.util;
/** Browser host logging; preserve the existing host's output and return conventions. */
public final class Log {
 public static int d(String tag,String message){System.out.println(tag+": "+message);return 0;}
 public static int i(String tag,String message){return d(tag,message);}
 public static int v(String tag,String message){return 0;}
 public static int w(String tag,String message){return d(tag,message);}
 public static int e(String tag,String message){return d(tag,message);}
 public static int e(String tag,String message,Throwable error){error.printStackTrace();return d(tag,message);}
 public static int wtf(String tag,String message){return e(tag,message);}
 public static int wtf(String tag,String message,Throwable error){return e(tag,message,error);}
 public static int wtf(String tag,Throwable error){return e(tag,error.toString(),error);}
 public static int println(int priority,String tag,String message){return d(tag,message);}
 public static boolean isLoggable(String tag,int level){return false;}
}
