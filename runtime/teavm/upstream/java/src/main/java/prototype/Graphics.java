package prototype;
import com.google.gson.*;import org.teavm.jso.JSBody;
/** Raster bridge. Decode/encode suspend the cooperative thread; drawing is synchronous. */
public final class Graphics {
 public static JsonObject args(){return new JsonObject();}
 public static JsonObject call(String op,JsonObject a){a.addProperty("op",op);return JsonParser.parseString(sync(a.toString())).getAsJsonObject();}
 public static JsonObject async(String op,JsonObject a){a.addProperty("op",op);return JsonParser.parseString(Bridge.graphics(a.toString())).getAsJsonObject();}
 public static JsonArray numbers(float... values){JsonArray a=new JsonArray();for(float n:values)a.add(n);return a;}
 @JSBody(params="request",script="return JSON.stringify(self.teaGraphicsSync(JSON.parse(request)));") static native String sync(String request);
}
