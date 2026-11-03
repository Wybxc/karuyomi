package prototype;

import com.google.gson.JsonObject;
import java.io.File;
import org.teavm.jso.JSBody;
import org.teavm.jso.JSExport;

/** Real TeaVM Fiber entry for the exact original-JVM failure scenarios. */
public final class CacheFailureProbe {
  public static void main(String[] args) {}

  @JSExport
  public static void cacheFailureRun() {
    new Thread(
            () -> {
              try {
                done(
                    CacheFailureScenarios.run(
                            "http://fixture.example.org", new File("/failure-cache"))
                        .toString());
              } catch (Throwable error) {
                JsonObject result = new JsonObject();
                result.addProperty("passed", false);
                result.addProperty("error", error.toString());
                StringBuilder stack = new StringBuilder();
                for (StackTraceElement frame : error.getStackTrace())
                  stack.append(frame).append('\n');
                result.addProperty("stack", stack.toString());
                done(result.toString());
              }
            })
        .start();
  }

  @JSBody(params = "json", script = "self.cacheFailureDone(json);")
  private static native void done(String json);
}
