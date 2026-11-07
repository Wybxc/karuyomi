package prototype;

import static org.junit.Assert.*;

import android.graphics.Bitmap;
import android.graphics.Paint;
import android.os.Build;
import android.text.TextPaint;
import com.google.gson.JsonObject;
import java.net.URL;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import org.robolectric.shadow.api.Shadow;

/** Real Android classes and Robolectric's native Skia runtime, isolated from owned adapters. */
@RunWith(RobolectricTestRunner.class)
@Config(manifest = Config.NONE, sdk = 35)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public final class AndroidTextTest {
  @Test
  public void nativeAndroidBitmapCopyContracts() {
    JsonObject result = BitmapLifetimeScenarios.run();
    assertTrue(result.get("passed").getAsBoolean());
    assertEquals(13, result.get("checks").getAsInt());
    System.out.println("Android NATIVE Bitmap copy: " + result);
  }

  @Test
  public void nativeAndroidCanvasRotation() {
    CanvasRotationScenarios.run();
  }

  @Test
  public void nativeAndroidCanvasClipAndMiter() {
    CanvasRotationScenarios.runClipAndMiter();
  }

  @Test
  public void nativeAndroidSharedScenarios() throws Exception {
    assertEquals(35, Build.VERSION.SDK_INT);
    Paint paint = new Paint();
    assertEquals(
        "org.robolectric.shadows.ShadowNativePaint", Shadow.extract(paint).getClass().getName());
    Bitmap bitmap = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888);
    try {
      assertEquals(
          "org.robolectric.shadows.ShadowNativeBitmap",
          Shadow.extract(bitmap).getClass().getName());
    } finally {
      bitmap.recycle();
    }
    URL sdk = TextPaint.class.getResource("TextPaint.class");
    assertNotNull("Android framework class resource", sdk);
    assertTrue(
        "Fixed instrumented SDK: " + sdk,
        sdk.toExternalForm().contains("android-all-instrumented-15-robolectric-13954326-i7.jar"));
    JsonObject result = TextLayoutScenarios.run();
    assertTrue(result.get("passed").getAsBoolean());
    result.addProperty("sdk", Build.VERSION.SDK_INT);
    result.addProperty("androidFramework", sdk.toExternalForm());
    result.addProperty("paintShadow", Shadow.extract(paint).getClass().getName());
    result.addProperty("architecture", System.getProperty("os.arch"));
    System.out.println("Android NATIVE text layout: " + result);
  }
}
