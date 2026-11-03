package android.content;
import java.io.File;
import java.lang.reflect.Proxy;
import java.util.*;
public class Context {
  public static final int MODE_PRIVATE=0;
  private static final Map<String,SharedPreferences> preferences=new java.util.concurrent.ConcurrentHashMap<>();
  public Context getApplicationContext(){return this;}
  public android.content.res.Resources getResources(){return android.content.res.Resources.getSystem();}
  public String getPackageName(){return "prototype.host";}
  public File getCacheDir(){return new File("/files/cache");}
  public File getExternalCacheDir(){return new File(getCacheDir(),"external");}
  public File getFilesDir(){return new File("/files/data");}
  public SharedPreferences getSharedPreferences(String name,int mode){return preferences.computeIfAbsent(name,k->makePreferences());}
  private static SharedPreferences makePreferences(){
    Map<String,Object> values=Collections.synchronizedMap(new HashMap<>());
    Set<SharedPreferences.OnSharedPreferenceChangeListener> listeners=Collections.synchronizedSet(new HashSet<>());
    final SharedPreferences[] preference=new SharedPreferences[1];
    preference[0]=(SharedPreferences)Proxy.newProxyInstance(Context.class.getClassLoader(),new Class[]{SharedPreferences.class},(p,m,a)->{
      String n=m.getName();
      if(n.equals("hashCode"))return System.identityHashCode(p);
      if(n.equals("equals"))return p==a[0];
      if(n.equals("toString"))return "BrowserSharedPreferences";
      if(n.equals("registerOnSharedPreferenceChangeListener")){listeners.add((SharedPreferences.OnSharedPreferenceChangeListener)a[0]);return null;}
      if(n.equals("unregisterOnSharedPreferenceChangeListener")){listeners.remove(a[0]);return null;}
      if(n.equals("getAll")){synchronized(values){return new HashMap<>(values);}}
      if(n.equals("contains"))return values.containsKey(a[0]);
      if(n.startsWith("get")){Object value=values.getOrDefault(a[0],a[1]);return value instanceof Set?new HashSet<>((Set<?>)value):value;}
      if(!n.equals("edit"))throw new UnsupportedOperationException(m.toString());
      Map<String,Object> changes=new LinkedHashMap<>();Set<String> removed=new HashSet<>();boolean[] clear={false};
      return Proxy.newProxyInstance(Context.class.getClassLoader(),new Class[]{SharedPreferences.Editor.class},(editor,method,args)->{
        String name=method.getName();
        if(name.equals("hashCode"))return System.identityHashCode(editor);
        if(name.equals("equals"))return editor==args[0];
        if(name.equals("toString"))return "BrowserPreferencesEditor";
        if(name.startsWith("put")){String key=(String)args[0];Object value=args[1];if(value instanceof Set)value=new HashSet<>((Set<?>)value);changes.put(key,value);removed.remove(key);return editor;}
        if(name.equals("remove")){String key=(String)args[0];removed.add(key);changes.remove(key);return editor;}
        if(name.equals("clear")){clear[0]=true;return editor;}
        if(!name.equals("apply")&&!name.equals("commit"))throw new UnsupportedOperationException(method.toString());
        Set<String> changed=new LinkedHashSet<>();
        synchronized(values){
          if(clear[0]){changed.addAll(values.keySet());values.clear();}
          for(String key:removed)if(values.remove(key)!=null)changed.add(key);
          for(var entry:changes.entrySet()){
            Object old=values.get(entry.getKey());
            if(entry.getValue()==null)values.remove(entry.getKey());else values.put(entry.getKey(),entry.getValue());
            if(!Objects.equals(old,entry.getValue()))changed.add(entry.getKey());
          }
        }
        changes.clear();removed.clear();clear[0]=false;
        List<SharedPreferences.OnSharedPreferenceChangeListener> snapshot;
        synchronized(listeners){snapshot=new ArrayList<>(listeners);}
        for(String key:changed)for(var listener:snapshot)listener.onSharedPreferenceChanged(preference[0],key);
        return name.equals("commit")?Boolean.TRUE:null;
      });
    });
    return preference[0];
  }
}
