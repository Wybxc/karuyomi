package prototype;

import android.graphics.*;
import android.text.*;
import com.google.gson.*;
import java.io.ByteArrayOutputStream;

/** Shared Android-NATIVE/TeaVM plain-text semantics; neither side uses SDK stubs as an oracle. */
public final class TextLayoutScenarios {
  private static int checks;

  private static void check(boolean value, String message) {
    checks++;
    if (!value) throw new AssertionError(message);
  }

  public static JsonObject run() throws Exception {
    checks = 0;
    String[][] htmlCases = {
      {"a<br>b", "a\nb"},
      {"<p>a</p><p>b</p>", "a\n\nb\n\n"},
      {"a &amp; &lt; &nbsp; &#x1F600;", "a & < \u00A0 😀"},
      {"  a \n\t b  ", "a \t b "},
      {"a<div>b</div>c", "a\n\nb\n\nc"},
      {"a<br><br>b", "a\n\nb"},
      {"a <b>bold</b> text", "a bold text"},
      {"<p>a<br>b</p>", "a\nb\n\n"},
      {"a\r\nb", "a b"},
      {"x <img src='x'> y", "x \uFFFC y"}
    };
    for (String[] html : htmlCases)
      check(
          Html.fromHtml(html[0], Html.FROM_HTML_MODE_LEGACY).toString().equals(html[1]),
          "Android HTML plain-string projection: " + html[0]);
    check(
        Html.fromHtml("<p>a</p><p>b</p>", Html.FROM_HTML_MODE_COMPACT).toString().equals("a\nb\n"),
        "compact HTML paragraphs");
    String actualXkcdTitle = "Elevators";
    String actualXkcdAlt =
        "\"A reusable elevator would also be great because we'd save so much on the bulky and expensive shields that people currently use to avoid bruises and rug burns when sliding down the stairs.\"";
    check(
        Html.fromHtml(actualXkcdTitle, 0).toString().equals(actualXkcdTitle)
            && Html.fromHtml(actualXkcdAlt, 0).toString().equals(actualXkcdAlt),
        "xkcd3319 original title and alt projection");
    TextPaint paint = new TextPaint(Paint.ANTI_ALIAS_FLAG);
    paint.setTextSize(30);
    paint.setTypeface(Typeface.DEFAULT);
    Paint.FontMetrics metrics = paint.getFontMetrics();
    check(metrics.ascent < 0 && metrics.descent > 0, "actual font metrics");
    paint.bgColor = Color.WHITE;
    paint.baselineShift = 2;
    paint.density = 2;
    TextPaint copy = new TextPaint(paint);
    check(
        copy.bgColor == 0 && copy.baselineShift == 0 && copy.density == 1,
        "paint constructor excludes text-only state");
    copy.set(paint);
    check(
        copy.getTextSize() == 30
            && copy.bgColor == Color.WHITE
            && copy.baselineShift == 2
            && copy.density == 2,
        "copy text paint state");
    paint.bgColor = 0;
    paint.baselineShift = 0;
    String complete = "xxABzz";
    StaticLayout ranged =
        new StaticLayout(complete, 2, 4, paint, 900, Layout.Alignment.ALIGN_NORMAL, 1, 0, true);
    check(ranged.getText() == complete, "ranged layout retains original source");
    check(
        ranged.getLineCount() == 1
            && ranged.getLineStart(0) == 2
            && ranged.getLineEnd(0) == 4
            && ranged.getLineVisibleEnd(0) == 4,
        "ranged UTF16 offsets");
    check(ranged.getLineStart(ranged.getLineCount()) == 4, "ranged final offset");
    StaticLayout rangeEmpty =
        new StaticLayout(complete, 2, 2, paint, 900, Layout.Alignment.ALIGN_NORMAL, 1, 0, true);
    check(
        rangeEmpty.getLineCount() == 1
            && rangeEmpty.getLineStart(0) == 2
            && rangeEmpty.getLineEnd(0) == 2,
        "empty ranged layout offsets");
    StaticLayout empty =
        new StaticLayout("", paint, 900, Layout.Alignment.ALIGN_NORMAL, 1.1f, 2, true);
    check(empty.getLineCount() == 1 && empty.getHeight() > 0, "empty one line");
    StaticLayout newlines =
        new StaticLayout("a\nb\n", paint, 900, Layout.Alignment.ALIGN_NORMAL, 1.1f, 2, true);
    check(newlines.getLineCount() == 3, "trailing blank line");
    check(
        newlines.getLineStart(0) == 0
            && newlines.getLineStart(1) == 2
            && newlines.getLineStart(2) == 4,
        "utf16 newline offsets");
    check(
        newlines.getLineVisibleEnd(0) == 1 && newlines.getLineVisibleEnd(1) == 3,
        "newline not drawn");
    check(
        newlines.getLineBaseline(1) > newlines.getLineBaseline(0)
            && newlines.getLineTop(3) == newlines.getHeight(),
        "line baseline and final top");
    for (int line = 0; line < newlines.getLineCount(); line++)
      check(
          newlines.getLineBaseline(line)
              == newlines.getLineBottom(line) - newlines.getLineDescent(line),
          "baseline equals bottom minus padded descent");
    StaticLayout spaces =
        new StaticLayout("A  ", paint, 900, Layout.Alignment.ALIGN_NORMAL, 1, 0, true);
    check(
        spaces.getLineVisibleEnd(0) == 3
            && Math.abs(spaces.getLineWidth(0) - paint.measureText("A  ")) < 1,
        "last line trailing spaces remain visible and measured");
    StaticLayout hardBreak =
        new StaticLayout("A  \nB", paint, 900, Layout.Alignment.ALIGN_NORMAL, 1, 0, true);
    check(
        hardBreak.getLineVisibleEnd(0) == 3
            && Math.abs(hardBreak.getLineMax(0) - paint.measureText("A  ")) < 1,
        "hard break visible extent retains spaces before newline");
    check(
        Math.abs(hardBreak.getLineWidth(0) - paint.measureText("A  \n")) < 1,
        "raw line width includes newline advance");
    TextPaint statePaint = new TextPaint();
    statePaint.set(paint);
    statePaint.bgColor = Color.RED;
    statePaint.baselineShift = 25;
    statePaint.setColor(Color.BLACK);
    StaticLayout stateLayout =
        new StaticLayout("A", statePaint, 100, Layout.Alignment.ALIGN_NORMAL, 1, 0, false);
    check(
        statePaint.bgColor == 0 && statePaint.baselineShift == 0,
        "Layout resets paint text-only offsets at construction");
    statePaint.bgColor = Color.RED;
    statePaint.baselineShift = 25;
    Bitmap stateImage =
        Bitmap.createBitmap(100, stateLayout.getHeight() + 40, Bitmap.Config.ARGB_8888);
    try {
      Canvas stateCanvas = new Canvas(stateImage);
      stateCanvas.drawColor(Color.WHITE);
      stateLayout.draw(stateCanvas);
      int[] statePixels = new int[100 * stateImage.getHeight()];
      stateImage.getPixels(statePixels, 0, 100, 0, 0, 100, stateImage.getHeight());
      int red = 0, firstBlack = stateImage.getHeight();
      for (int index = 0; index < statePixels.length; index++) {
        if (statePixels[index] == Color.RED) red++;
        if (statePixels[index] == Color.BLACK) firstBlack = Math.min(firstBlack, index / 100);
      }
      check(red == 0, "plain String drawing ignores span-only background color");
      check(firstBlack < 20, "plain String drawing ignores span-only baseline shift");
    } finally {
      stateImage.recycle();
    }
    String words = "words with several spaces ".repeat(20);
    StaticLayout wrap =
        new StaticLayout(words, paint, 160, Layout.Alignment.ALIGN_NORMAL, 1.1f, 2, true);
    check(wrap.getLineCount() > 1, "width measured wrap");
    StringBuilder joined = new StringBuilder();
    for (int line = 0; line < wrap.getLineCount(); line++) {
      joined.append(words, wrap.getLineStart(line), wrap.getLineEnd(line));
      check(wrap.getLineVisibleEnd(line) <= wrap.getLineEnd(line), "visible range");
    }
    check(joined.toString().equals(words), "no text lost in soft wrapping");
    StaticLayout centered =
        new StaticLayout("Hi", paint, 900, Layout.Alignment.ALIGN_CENTER, 1, 0, false);
    check(
        Math.abs(centered.getLineLeft(0) - (900 - centered.getLineWidth(0)) / 2) < 1,
        "center alignment");
    StaticLayout rtl =
        new StaticLayout("مرحبا بالعالم", paint, 900, Layout.Alignment.ALIGN_NORMAL, 1, 0, true);
    check(rtl.getParagraphDirection(0) == -1 && rtl.getLineLeft(0) > 0, "rtl normal alignment");
    String emoji = "👩‍👩‍👧‍👦👨‍👩‍👦";
    StaticLayout graphemes =
        new StaticLayout(emoji, paint, 1, Layout.Alignment.ALIGN_NORMAL, 1, 0, true);
    check(
        graphemes.getLineCount() == 2 && graphemes.getLineStart(1) == 11,
        "do not split emoji grapheme");
    TextPaint heading = new TextPaint(paint);
    heading.setTextSize(36);
    heading.setTypeface(Typeface.DEFAULT_BOLD);
    StaticLayout title =
        new StaticLayout("Elevators", heading, 900, Layout.Alignment.ALIGN_NORMAL, 1.1f, 2, true);
    StaticLayout body =
        new StaticLayout(
            "A text-only second page rendered by the unchanged interceptor.",
            paint,
            900,
            Layout.Alignment.ALIGN_NORMAL,
            1.1f,
            2,
            true);
    int height = title.getHeight() + body.getHeight() + 50;
    Bitmap image = Bitmap.createBitmap(1000, height, Bitmap.Config.ARGB_8888);
    JsonObject result = new JsonObject();
    try {
      Canvas canvas = new Canvas(image);
      canvas.drawColor(Color.WHITE);
      canvas.save();
      canvas.translate(50, 25);
      title.draw(canvas);
      canvas.restore();
      canvas.save();
      canvas.translate(50, 25 + title.getHeight());
      body.draw(canvas);
      canvas.restore();
      int[] pixels = new int[1000 * height];
      image.getPixels(pixels, 0, 1000, 0, 0, 1000, height);
      int nonWhite = 0;
      for (int pixel : pixels) if (pixel != Color.WHITE) nonWhite++;
      check(nonWhite > 100, "actual glyph pixels");
      ByteArrayOutputStream png = new ByteArrayOutputStream();
      check(image.compress(Bitmap.CompressFormat.PNG, 0, png), "png compression");
      byte[] bytes = png.toByteArray();
      check(bytes.length > 8 && (bytes[0] & 255) == 137 && bytes[1] == 80, "real PNG signature");
      result.addProperty("width", 1000);
      result.addProperty("height", height);
      result.addProperty("nonWhitePixels", nonWhite);
      result.addProperty("pngBytes", bytes.length);
    } finally {
      image.recycle();
    }
    result.addProperty("newlineLines", newlines.getLineCount());
    result.addProperty("emojiLines", graphemes.getLineCount());
    result.addProperty("wrapLines", wrap.getLineCount());
    result.addProperty("checks", checks);
    result.addProperty("passed", true);
    return result;
  }
}
