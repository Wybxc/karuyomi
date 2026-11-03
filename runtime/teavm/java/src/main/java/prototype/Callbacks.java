package prototype;

import com.google.gson.*;
import java.lang.reflect.*;
import java.util.*;

/** Export only methods on the supplied interface, or methods explicitly annotated for WebView. */
public final class Callbacks {
  private record Binding(Object object, Map<String, List<Method>> methods) {}

  private static final Map<String, Map<String, Binding>> instances = new HashMap<>();
  private static final ThreadLocal<Boolean> invoking = ThreadLocal.withInitial(() -> false);

  public static boolean isInvokingOnCurrentThread() {
    return invoking.get();
  }

  public static String register(
      String instance, String name, Class<?> type, Object object, boolean annotated) {
    if (object == null || !type.isInstance(object))
      throw new IllegalArgumentException("Invalid callback object");
    Map<String, List<Method>> methods = new LinkedHashMap<>();
    for (Method method : type.getMethods()) {
      if (method.getDeclaringClass() == Object.class || Modifier.isStatic(method.getModifiers()))
        continue;
      if (annotated && !method.isAnnotationPresent(android.webkit.JavascriptInterface.class))
        continue;
      methods.computeIfAbsent(method.getName(), key -> new ArrayList<>()).add(method);
    }
    synchronized (instances) {
      instances
          .computeIfAbsent(instance, key -> new HashMap<>())
          .put(name, new Binding(object, methods));
    }
    return JsonValues.encode(Map.of("name", name, "methods", methods.keySet())).toString();
  }

  public static String invoke(String instance, String name, String methodName, String arguments) {
    try {
      Binding binding;
      synchronized (instances) {
        Map<String, Binding> group = instances.get(instance);
        binding = group == null ? null : group.get(name);
      }
      if (binding == null) throw new IllegalArgumentException("Unknown callback binding");
      JsonArray args = JsonParser.parseString(arguments).getAsJsonArray();
      Method selected = null;
      for (Method method : binding.methods().getOrDefault(methodName, List.of()))
        if (method.getParameterCount() == args.size()) {
          if (selected != null)
            throw new IllegalArgumentException("Ambiguous callback method " + methodName);
          selected = method;
        }
      if (selected == null)
        throw new IllegalArgumentException("Unknown callback method " + methodName);
      Class<?>[] types = selected.getParameterTypes();
      Object[] values = new Object[args.size()];
      for (int i = 0; i < values.length; i++)
        values[i] = JsonValues.argument(args.get(i), types[i]);
      selected.setAccessible(true);
      Object value;
      invoking.set(true);
      try {
        value = selected.invoke(binding.object(), values);
      } finally {
        invoking.remove();
      }
      JsonObject result = new JsonObject();
      result.add("value", JsonValues.encode(value));
      return result.toString();
    } catch (Throwable error) {
      if (error instanceof InvocationTargetException)
        error = ((InvocationTargetException) error).getTargetException();
      JsonObject result = new JsonObject();
      result.addProperty("error", error.toString());
      return result.toString();
    }
  }

  public static void close(String instance) {
    synchronized (instances) {
      instances.remove(instance);
    }
  }
}
