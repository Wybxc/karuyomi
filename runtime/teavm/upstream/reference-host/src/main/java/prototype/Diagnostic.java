package prototype;
public final class Diagnostic {
  private static final java.util.concurrent.ScheduledExecutorService WATCHDOG=java.util.concurrent.Executors.newSingleThreadScheduledExecutor(task->{Thread thread=new Thread(task,"prototype-watchdog");thread.setDaemon(true);return thread;});
  public static java.util.concurrent.Future<?> watch(String operation){return WATCHDOG.schedule(()->Bridge.trace("Slow Java invocation "+operation+"\n"+stacks()),20,java.util.concurrent.TimeUnit.SECONDS);}
  public static String ping(){return "diagnostic ready";}
  public static String nullUnpark(){try{java.util.concurrent.locks.LockSupport.unpark(null);return "ok";}catch(Throwable error){return error.getClass().getName();}}
  /** Formatting must not prevent a pending invocation from completing, even if a JVM native fails. */
  public static String format(Throwable error){
    StringBuilder result=new StringBuilder();
    java.util.Set<Throwable> seen=java.util.Collections.newSetFromMap(new java.util.IdentityHashMap<>());
    while(error!=null&&seen.add(error)){
      result.append(error.getClass().getName());
      try{String message=error.getMessage();if(message!=null)result.append(": ").append(message);}
      catch(Throwable unavailable){result.append(" [message unavailable: ").append(unavailable.getClass().getName()).append(']');}
      result.append('\n');
      try{for(StackTraceElement frame:error.getStackTrace())result.append("\tat ").append(frame).append('\n');}catch(Throwable unavailable){result.append("\t[stack unavailable]\n");}
      try{error=error.getCause();}catch(Throwable unavailable){break;}
      if(error!=null)result.append("Caused by: ");
    }
    return result.toString();
  }
  public static boolean errorFormattingProbe(){
    Throwable broken=new RuntimeException(){@Override public String getMessage(){throw new UnsatisfiedLinkError("probe unavailable native");}};
    String safe=format(broken);
    if(!safe.contains("message unavailable")||!safe.contains("errorFormattingProbe"))throw new AssertionError("Throwable formatting lost failure");
    try{Object value=null;value.toString();}catch(NullPointerException error){if(!format(error).contains("java.lang.NullPointerException"))throw new AssertionError("NPE formatting");}
    return true;
  }
  public static String stacks(){
    StringBuilder b=new StringBuilder();
    Thread.getAllStackTraces().forEach((t,s)->{b.append(t.getName()).append(" ").append(t.getState()).append('\n');for(StackTraceElement e:s)b.append("  ").append(e).append('\n');});
    return b.toString();
  }
}
