package android.content;
/** Preserve Android's inheritance ABI; optimized APK calls may name this superclass. */
public class ContextWrapper extends Context {
  @Override public java.io.File getCacheDir() { return base == null ? super.getCacheDir() : base.getCacheDir(); }
  @Override public java.io.File getFilesDir() { return base == null ? super.getFilesDir() : base.getFilesDir(); }
  @Override public java.io.File getExternalCacheDir() { return base == null ? super.getExternalCacheDir() : base.getExternalCacheDir(); }
  private final Context base;
  public ContextWrapper(Context base) { this.base = base; }
  public Context getBaseContext() { return base; }
  @Override public android.content.res.Resources getResources() { return base == null ? super.getResources() : base.getResources(); }
  @Override public Context getApplicationContext() { return base == null ? this : base.getApplicationContext(); }
  @Override public SharedPreferences getSharedPreferences(String name, int mode) {
    return base == null ? super.getSharedPreferences(name, mode) : base.getSharedPreferences(name, mode);
  }
}
