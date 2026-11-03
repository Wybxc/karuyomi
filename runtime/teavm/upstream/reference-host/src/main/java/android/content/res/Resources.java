package android.content.res;
/** Configuration queries only; APK resource inflation is outside this browser host. */
public class Resources {
  private static final Resources SYSTEM=new Resources();
  private final Configuration configuration=new Configuration();
  private final android.util.DisplayMetrics metrics=new android.util.DisplayMetrics();
  public static Resources getSystem(){return SYSTEM;}
  public Configuration getConfiguration(){return configuration;}
  public android.util.DisplayMetrics getDisplayMetrics(){return metrics;}
}
