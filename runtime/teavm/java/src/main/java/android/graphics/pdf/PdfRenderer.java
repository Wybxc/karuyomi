package android.graphics.pdf;

import android.graphics.Bitmap;
import android.graphics.Matrix;
import android.graphics.Rect;
import android.os.ParcelFileDescriptor;
import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.Objects;
import prototype.Graphics;

/** Display rendering via the Source graphics bridge and bundled PDFium. */
public final class PdfRenderer implements AutoCloseable {
  private final ParcelFileDescriptor file;
  private final int id;
  private final int pageCount;
  private Page page;
  private boolean closed;

  public PdfRenderer(ParcelFileDescriptor file) throws IOException {
    this.file = Objects.requireNonNull(file);
    try {
      var opened = open(file);
      id = opened.get("id").getAsInt();
      pageCount = opened.get("pageCount").getAsInt();
    } catch (IOException | RuntimeException | Error error) {
      try {
        file.close();
      } catch (IOException closeError) {
        error.addSuppressed(closeError);
      }
      throw error;
    }
  }

  private static JsonObject open(ParcelFileDescriptor file) throws IOException {
    var input = Graphics.upload(file.hostInput(), Graphics.IMAGE_LIMIT, false);
    try {
      var request = Graphics.args();
      request.addProperty("bytes", input);
      return Graphics.async("openPdf", request);
    } catch (UncheckedIOException error) {
      throw error.getCause();
    } finally {
      Graphics.closeBytes(input);
    }
  }

  public int getPageCount() {
    checkOpen();
    return pageCount;
  }

  public Page openPage(int index) {
    checkOpen();
    if (page != null) throw new IllegalStateException("A PDF page is already open");
    if (index < 0 || index >= pageCount) throw new IllegalArgumentException("PDF page index");
    var request = Graphics.args();
    request.addProperty("id", id);
    request.addProperty("pageIndex", index);
    var size = Graphics.call("openPdfPage", request);
    page = new Page(index, size.get("width").getAsInt(), size.get("height").getAsInt());
    return page;
  }

  private void checkOpen() {
    if (closed) throw new IllegalStateException("PDF renderer is closed");
  }

  @Override
  public void close() {
    checkOpen();
    if (page != null) throw new IllegalStateException("A PDF page is still open");
    closed = true;
    var request = Graphics.args();
    request.addProperty("id", id);
    try {
      Graphics.call("closePdf", request);
    } finally {
      try {
        file.close();
      } catch (IOException ignored) {
        // Closing the Android renderer releases its descriptor without a checked error.
      }
    }
  }

  public final class Page implements AutoCloseable {
    public static final int RENDER_MODE_FOR_DISPLAY = 1;
    public static final int RENDER_MODE_FOR_PRINT = 2;
    private final int index;
    private final int width;
    private final int height;

    private Page(int index, int width, int height) {
      this.index = index;
      this.width = width;
      this.height = height;
    }

    public int getIndex() {
      checkOpen();
      return index;
    }

    public int getWidth() {
      checkOpen();
      return width;
    }

    public int getHeight() {
      checkOpen();
      return height;
    }

    private void checkOpen() {
      if (PdfRenderer.this.page != this) throw new IllegalStateException("PDF page is closed");
    }

    public void render(Bitmap destination, Rect clip, Matrix transform, int mode) {
      checkOpen();
      if (destination.getConfig() != Bitmap.Config.ARGB_8888 || !destination.isMutable())
        throw new IllegalArgumentException("PDF rendering requires a mutable ARGB_8888 bitmap");
      if (mode != RENDER_MODE_FOR_DISPLAY && mode != RENDER_MODE_FOR_PRINT)
        throw new IllegalArgumentException("Unknown PDF render mode");
      if (transform != null)
        throw new UnsupportedOperationException(
            "PDF display rendering requires a default transform");
      if (mode == RENDER_MODE_FOR_PRINT)
        throw new UnsupportedOperationException("PDF print rendering is unavailable");
      var request = Graphics.args();
      request.addProperty("id", destination.id());
      request.addProperty("source", id);
      if (clip != null) {
        var rect = new JsonArray();
        rect.add(clip.left);
        rect.add(clip.top);
        rect.add(clip.right);
        rect.add(clip.bottom);
        request.add("rect", rect);
      }
      Graphics.async("renderPdfPage", request);
    }

    @Override
    public void close() {
      checkOpen();
      var request = Graphics.args();
      request.addProperty("id", id);
      Graphics.call("closePdfPage", request);
      page = null;
    }
  }
}
