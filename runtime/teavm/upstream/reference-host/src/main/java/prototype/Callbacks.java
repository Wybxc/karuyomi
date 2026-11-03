package prototype;
import com.google.gson.*;
import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/** Only explicitly bound interface methods or @JavascriptInterface methods are callable. */
public final class Callbacks {
  private record Binding(Object object, Map<String,List<Method>> methods) {}
  private static final Map<String,Map<String,Binding>> instances=new ConcurrentHashMap<>();
  private static final Gson gson=new Gson();
  private static final ThreadLocal<Boolean> invoking=ThreadLocal.withInitial(()->false);
  public static boolean isInvokingOnCurrentThread(){return invoking.get();}
  public static String register(String instance,String name,Class<?> type,Object object,boolean annotated) {
    if(object==null||!type.isInstance(object))throw new IllegalArgumentException("Invalid callback object");
    Map<String,List<Method>> methods=new LinkedHashMap<>();
    for(Method method:type.getMethods()){
      if(method.getDeclaringClass()==Object.class||Modifier.isStatic(method.getModifiers()))continue;
      if(annotated&&!method.isAnnotationPresent(android.webkit.JavascriptInterface.class))continue;
      methods.computeIfAbsent(method.getName(),key->new ArrayList<>()).add(method);
    }
    instances.computeIfAbsent(instance,key->new ConcurrentHashMap<>()).put(name,new Binding(object,methods));
    return gson.toJson(Map.of("name",name,"methods",methods.keySet()));
  }
  public static String invoke(String instance,String name,String methodName,String arguments) {
    try {
      Binding binding=Optional.ofNullable(instances.get(instance)).map(map->map.get(name)).orElseThrow(()->new IllegalArgumentException("Unknown callback binding"));
      List<Method> candidates=binding.methods().getOrDefault(methodName,List.of());
      JsonArray args=JsonParser.parseString(arguments).getAsJsonArray();
      List<Method> matching=candidates.stream().filter(method->method.getParameterCount()==args.size()).toList();
      if(matching.size()!=1)throw new IllegalArgumentException("Unknown or ambiguous callback method: "+methodName);
      Method method=matching.get(0);Object[] values=new Object[args.size()];
      for(int i=0;i<values.length;i++)values[i]=gson.fromJson(args.get(i),method.getGenericParameterTypes()[i]);
      if(!method.canAccess(binding.object()))method.setAccessible(true);
      Object value;
      invoking.set(true);
      try { value=method.invoke(binding.object(),values); } finally { invoking.remove(); }
      JsonObject result=new JsonObject();result.add("value",gson.toJsonTree(value));return result.toString();
    }catch(Throwable error){
      if(error instanceof InvocationTargetException invocation)error=invocation.getTargetException();
      return gson.toJson(Map.of("error",error.toString()));
    }
  }
  public static void close(String instance){instances.remove(instance);}
}
