package prototype;

import static org.junit.Assert.*;

import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.ImageDecoder;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.graphics.text.LineBreaker;
import android.os.Build;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;
import com.google.gson.JsonObject;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.net.URL;
import java.util.Arrays;
import java.util.Locale;
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
  public void nativeAndroidBitmapColorArrayCreation() {
    int[] colors = {Color.RED, Color.BLUE, Color.WHITE, Color.GREEN, Color.BLACK, Color.YELLOW};
    Bitmap packed = Bitmap.createBitmap(colors, 2, 2, Bitmap.Config.ARGB_8888);
    Bitmap reversed = Bitmap.createBitmap(colors, 3, -3, 2, 2, Bitmap.Config.ARGB_8888);
    try {
      assertFalse(packed.isMutable());
      assertFalse(reversed.isMutable());
      colors[0] = Color.CYAN;
      assertEquals(Color.RED, packed.getPixel(0, 0));
      assertEquals(Color.BLUE, packed.getPixel(1, 0));
      assertEquals(Color.WHITE, packed.getPixel(0, 1));
      assertEquals(Color.GREEN, packed.getPixel(1, 1));
      assertEquals(Color.GREEN, reversed.getPixel(0, 0));
      assertEquals(Color.BLACK, reversed.getPixel(1, 0));
      assertEquals(Color.RED, reversed.getPixel(0, 1));
      assertEquals(Color.BLUE, reversed.getPixel(1, 1));
      assertThrows(IllegalStateException.class, () -> packed.setPixel(0, 0, Color.YELLOW));
      assertThrows(
          IllegalArgumentException.class,
          () -> Bitmap.createBitmap(colors, 0, 1, 2, 2, Bitmap.Config.ARGB_8888));
      assertThrows(
          ArrayIndexOutOfBoundsException.class,
          () -> Bitmap.createBitmap(colors, 2, -3, 2, 2, Bitmap.Config.ARGB_8888));
      assertThrows(
          IllegalArgumentException.class,
          () -> Bitmap.createBitmap(colors, 0, 2, Bitmap.Config.ARGB_8888));
    } finally {
      packed.recycle();
      reversed.recycle();
    }
  }

  @Test
  public void nativeAndroidByteArrayImageDecoder() throws IOException {
    ByteArrayOutputStream png = new ByteArrayOutputStream();
    Bitmap fixture = Bitmap.createBitmap(2, 3, Bitmap.Config.ARGB_8888);
    try {
      fixture.eraseColor(Color.RED);
      assertTrue(fixture.compress(Bitmap.CompressFormat.PNG, 100, png));
    } finally {
      fixture.recycle();
    }
    byte[] image = png.toByteArray();
    byte[] padded = new byte[image.length + 5];
    System.arraycopy(image, 0, padded, 2, image.length);
    ImageDecoder.Source source = ImageDecoder.createSource(padded, 2, image.length);
    int[] callbacks = {0};
    Bitmap bitmap =
        ImageDecoder.decodeBitmap(
            source,
            (decoder, info, callbackSource) -> {
              callbacks[0]++;
              assertSame(source, callbackSource);
              assertEquals(2, info.getSize().getWidth());
              assertEquals(3, info.getSize().getHeight());
              assertEquals("image/png", info.getMimeType());
              assertEquals(ImageDecoder.ALLOCATOR_DEFAULT, decoder.getAllocator());
              decoder.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE);
              assertEquals(ImageDecoder.ALLOCATOR_SOFTWARE, decoder.getAllocator());
            });
    try {
      assertEquals(1, callbacks[0]);
      assertEquals(2, bitmap.getWidth());
      assertEquals(3, bitmap.getHeight());
      assertFalse(bitmap.isMutable());
      assertEquals(Color.RED, bitmap.getPixel(1, 2));
      ByteArrayOutputStream encoded = new ByteArrayOutputStream();
      assertTrue(bitmap.compress(Bitmap.CompressFormat.WEBP_LOSSY, 90, encoded));
      assertArrayEquals(
          new byte[] {'W', 'E', 'B', 'P'}, Arrays.copyOfRange(encoded.toByteArray(), 8, 12));
    } finally {
      bitmap.recycle();
    }
    assertThrows(
        ArrayIndexOutOfBoundsException.class,
        () -> ImageDecoder.createSource(padded, 6, image.length));
    assertThrows(
        IOException.class, () -> ImageDecoder.decodeBitmap(ImageDecoder.createSource(new byte[8])));
  }

  @Test
  public void nativeAndroidCanvasRotation() {
    CanvasRotationScenarios.run();
    CanvasRotationScenarios.runRectCenterPivot();
  }

  @Test
  public void nativeAndroidCanvasScaleAtPivot() {
    CanvasRotationScenarios.runScaleAtPivot();
  }

  @Test
  public void nativeAndroidCanvasClipAndMiter() {
    CanvasRotationScenarios.runClipAndMiter();
  }

  @Test
  public void nativeAndroidBitmapMatrixAndColorFilter() {
    CanvasRotationScenarios.runBitmapMatrixAndColorFilter();
  }

  @Test
  public void nativeAndroidParagraphBreakStrategiesAndHyphenation() {
    String text =
        "We can read internationalization documentation while selecting worthwhile recommendations.";
    TextPaint paint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
    paint.setTextSize(18);
    paint.setTypeface(Typeface.DEFAULT);
    paint.setTextLocale(Locale.US);
    int none = Layout.HYPHENATION_FREQUENCY_NONE;
    int full = Layout.HYPHENATION_FREQUENCY_FULL;
    int high = LineBreaker.BREAK_STRATEGY_HIGH_QUALITY;
    int[] simple80 = lineEnds(text, paint, 80, LineBreaker.BREAK_STRATEGY_SIMPLE, none);
    int[] high80 = lineEnds(text, paint, 80, high, none);
    int[] full80 = lineEnds(text, paint, 80, high, full);
    assertFalse("high-quality changes some line breaks", Arrays.equals(simple80, high80));
    assertFalse("automatic hyphenation changes some line breaks", Arrays.equals(high80, full80));

    int[] high85 = lineEnds(text, paint, 85, high, none);
    int[] balanced85 = lineEnds(text, paint, 85, LineBreaker.BREAK_STRATEGY_BALANCED, none);
    assertFalse("balanced breaking uses different offsets", Arrays.equals(high85, balanced85));
    System.out.println(
        "Android NATIVE paragraph options: SIMPLE "
            + Arrays.toString(simple80)
            + ", HIGH_QUALITY "
            + Arrays.toString(high80)
            + ", FULL "
            + Arrays.toString(full80)
            + ", BALANCED "
            + Arrays.toString(balanced85));
  }

  private static int[] lineEnds(
      String text, TextPaint paint, int width, int strategy, int hyphenation) {
    StaticLayout layout =
        StaticLayout.Builder.obtain(text, 0, text.length(), paint, width)
            .setBreakStrategy(strategy)
            .setHyphenationFrequency(hyphenation)
            .build();
    int[] ends = new int[layout.getLineCount()];
    for (int i = 0; i < ends.length; i++) ends[i] = layout.getLineEnd(i);
    assertEquals("final offset includes all UTF-16 units", text.length(), ends[ends.length - 1]);
    return ends;
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
