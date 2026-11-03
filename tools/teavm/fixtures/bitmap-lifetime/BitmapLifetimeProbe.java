package prototype;

import com.google.gson.JsonObject;
import org.teavm.jso.JSBody;
import org.teavm.jso.JSExport;

/** Minimal real TeaVM entry for the maintained Bitmap lifetime browser gate. */
public final class BitmapLifetimeProbe {
  public static void main(String[] args) {}

  @JSExport
  public static void bitmapLifetimeRun() {
    execute(() -> {
      JsonObject result = BitmapLifetimeScenarios.run();
      result.add("text", TextLayoutScenarios.run());
      done(result.toString());
    });
  }

  @JSExport
  public static void bitmapLifetimeRetain() {
    execute(() -> {
      BitmapLifetimeScenarios.retainBitmap();
      BitmapLifetimeScenarios.retainCanvasOnly();
      success();
    });
  }

  @JSExport
  public static void bitmapLifetimeAllocate() {
    execute(() -> {
      BitmapLifetimeScenarios.allocateUnrecycled(8);
      success();
    });
  }

  @JSExport
  public static void bitmapLifetimeUse() {
    execute(() -> {
      BitmapLifetimeScenarios.useRetainedOwners();
      success();
    });
  }

  @JSExport
  public static void bitmapLifetimeDrop() {
    execute(() -> {
      BitmapLifetimeScenarios.dropRetainedOwners();
      success();
    });
  }

  private interface Action {
    void run() throws Exception;
  }

  private static void execute(Action action) {
    new Thread(
            () -> {
              try {
                action.run();
              } catch (Throwable failure) {
                JsonObject result = new JsonObject();
                result.addProperty("passed", false);
                result.addProperty("error", failure.toString());
                done(result.toString());
              }
            })
        .start();
  }

  private static void success() {
    JsonObject result = new JsonObject();
    result.addProperty("passed", true);
    done(result.toString());
  }

  @JSBody(params = "json", script = "self.bitmapLifetimeDone(json);")
  private static native void done(String json);
}
