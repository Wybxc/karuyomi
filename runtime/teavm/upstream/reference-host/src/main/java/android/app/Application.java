package android.app;
public class Application extends android.content.ContextWrapper {
 private final java.util.Set<ActivityLifecycleCallbacks> callbacks=new java.util.concurrent.CopyOnWriteArraySet<>();
 public interface ActivityLifecycleCallbacks {
   void onActivityCreated(Activity activity,android.os.Bundle state);
   void onActivityStarted(Activity activity);
   void onActivityResumed(Activity activity);
   void onActivityPaused(Activity activity);
   void onActivityStopped(Activity activity);
   void onActivitySaveInstanceState(Activity activity,android.os.Bundle state);
   void onActivityDestroyed(Activity activity);
 }
 public void registerActivityLifecycleCallbacks(ActivityLifecycleCallbacks callback){callbacks.add(java.util.Objects.requireNonNull(callback));}
 public void unregisterActivityLifecycleCallbacks(ActivityLifecycleCallbacks callback){callbacks.remove(callback);}
 public Application(){super(null);}
 public void onCreate(){}
}
