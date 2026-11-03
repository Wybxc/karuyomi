package prototype;
public final class Bridge {
  public static native String trace(String message);
  public static native String http(String request);
  private static native String jsNative(String instance, String operation, String source);
  private static native String domNative(String instance, String operation, String payload);
  private static final String ERROR_PREFIX="!prototype-bridge-error!";
  public static String js(String instance, String operation, String source) {
    checkReentry(operation);
    return checked(jsNative(instance, operation, source));
  }
  public static String dom(String instance, String operation, String payload) {
    checkReentry(operation);
    return checked(domNative(instance, operation, payload));
  }
  private static void checkReentry(String operation) {
    if (!operation.equals("close") && Callbacks.isInvokingOnCurrentThread())
      throw new IllegalStateException("Reentrant browser evaluation from a synchronous Java callback is unsupported");
  }
  private static String checked(String value) {
    if (value.startsWith(ERROR_PREFIX)) throw new IllegalStateException(value.substring(ERROR_PREFIX.length()));
    return value;
  }
  public static native String zstd(String operation, String payload);
}
