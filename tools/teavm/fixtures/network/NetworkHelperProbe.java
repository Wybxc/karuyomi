package prototype;

import com.google.gson.JsonObject;
import org.teavm.jso.JSExport;

/** Runs the same owned configuration assertions in TeaVM; no upstream or storage calls. */
public final class NetworkHelperProbe {
  public static void main(String[] args) {}

  @JSExport
  public static String networkConfiguration() {
    try {
      return NetworkHelperTest.run().toString();
    } catch (Throwable error) {
      JsonObject result = new JsonObject();
      result.addProperty("passed", false);
      result.addProperty("error", error.toString());
      return result.toString();
    }
  }
}
