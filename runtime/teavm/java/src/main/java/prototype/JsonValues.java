package prototype;

import com.google.gson.*;
import java.util.*;

/** JSON-compatible values only: the browser bridge does not serialize arbitrary beans. */
public final class JsonValues {
 public static JsonElement encode(Object value){
  if(value==null)return JsonNull.INSTANCE;
  if(value instanceof JsonElement)return (JsonElement)value;
  if(value instanceof String)return new JsonPrimitive((String)value);
  if(value instanceof Character)return new JsonPrimitive((Character)value);
  if(value instanceof Boolean)return new JsonPrimitive((Boolean)value);
  if(value instanceof Number)return new JsonPrimitive((Number)value);
  if(value instanceof Map){JsonObject out=new JsonObject();for(var e:((Map<?,?>)value).entrySet()){if(!(e.getKey() instanceof String))throw new IllegalArgumentException("JSON object keys must be strings");out.add((String)e.getKey(),encode(e.getValue()));}return out;}
  if(value instanceof Iterable){JsonArray out=new JsonArray();for(Object item:(Iterable<?>)value)out.add(encode(item));return out;}
  if(value.getClass().isArray()){JsonArray out=new JsonArray();for(int i=0;i<java.lang.reflect.Array.getLength(value);i++)out.add(encode(java.lang.reflect.Array.get(value,i)));return out;}
  throw new IllegalArgumentException("Unsupported bridge value "+value.getClass().getName());
 }
 public static Object decode(JsonElement value){
  if(value==null||value.isJsonNull())return null;
  if(value.isJsonPrimitive()){JsonPrimitive p=value.getAsJsonPrimitive();if(p.isBoolean())return p.getAsBoolean();if(p.isString())return p.getAsString();return p.getAsDouble();}
  if(value.isJsonArray()){List<Object> out=new ArrayList<>();for(JsonElement item:value.getAsJsonArray())out.add(decode(item));return out;}
  Map<String,Object> out=new LinkedHashMap<>();for(var e:value.getAsJsonObject().entrySet())out.put(e.getKey(),decode(e.getValue()));return out;
 }
 public static Object argument(JsonElement value,Class<?> type){
  if(value.isJsonNull()){if(type.isPrimitive())throw new IllegalArgumentException("null primitive callback argument");return null;}
  if(type==String.class)return value.getAsString();
  if(type==boolean.class||type==Boolean.class)return value.getAsBoolean();
  if(type==int.class||type==Integer.class)return value.getAsInt();
  if(type==long.class||type==Long.class)return value.getAsLong();
  if(type==double.class||type==Double.class)return value.getAsDouble();
  if(type==float.class||type==Float.class)return value.getAsFloat();
  if(type==short.class||type==Short.class)return value.getAsShort();
  if(type==byte.class||type==Byte.class)return value.getAsByte();
  if(type==char.class||type==Character.class){String s=value.getAsString();if(s.length()!=1)throw new IllegalArgumentException("Expected one UTF-16 code unit");return s.charAt(0);}
  if(type==JsonElement.class||type.isInstance(value))return value;
  if(type.isArray()){JsonArray a=value.getAsJsonArray();Object out=java.lang.reflect.Array.newInstance(type.getComponentType(),a.size());for(int i=0;i<a.size();i++)java.lang.reflect.Array.set(out,i,argument(a.get(i),type.getComponentType()));return out;}
  Object out=decode(value);if(type==Object.class||type.isInstance(out))return out;
  throw new IllegalArgumentException("Unsupported callback argument type "+type.getName());
 }
}
