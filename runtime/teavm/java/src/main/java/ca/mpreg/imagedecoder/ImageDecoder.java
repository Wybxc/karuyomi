package ca.mpreg.imagedecoder;

import prototype.Graphics;
import com.google.gson.*;
import java.io.*;
import java.nio.*;

public final class ImageDecoder implements Closeable {
  public static final Companion Companion = new Companion();
  private int id;
  private final boolean hdr;

  private ImageDecoder(JsonObject result) {
    id = result.get("id").getAsInt();
    hdr = result.get("hdr").getAsBoolean();
  }

  public boolean isHdr() {
    check();
    return hdr;
  }

  private void check() {
    if (id == 0) throw new IllegalStateException("Decoder closed");
  }

  public Frame decodeNext() {
    check();
    JsonObject a = Graphics.args();
    a.addProperty("id", id);
    JsonObject r = Graphics.async("nextFrame", a);
    return r.get("end").getAsBoolean() ? null : new Frame(r);
  }

  public void close() {
    if (id != 0) {
      JsonObject a = Graphics.args();
      a.addProperty("id", id);
      Graphics.call("closeDecoder", a);
      id = 0;
    }
  }

  public static final class Frame implements Closeable {
    private ByteBuffer image;
    private String bytes;
    private final int width, height;

    Frame(JsonObject result) {
      width = result.get("width").getAsInt();
      height = result.get("height").getAsInt();
      bytes = result.get("bytes").getAsString();
      image = Graphics.readFrame(result).order(ByteOrder.LITTLE_ENDIAN);
    }

    public int getWidth() {
      return width;
    }

    public int getHeight() {
      return height;
    }

    public ByteBuffer getImage() {
      if (image == null) throw new IllegalStateException("Frame closed");
      return image.duplicate().order(ByteOrder.LITTLE_ENDIAN);
    }

    public void close() {
      if (bytes != null) Graphics.closeBytes(bytes);
      bytes = null;
      image = null;
    }
  }

  public static final class Companion {
    public ImageDecoder open(InputStream in, boolean cropBorders) throws IOException {
      if (cropBorders) throw new UnsupportedOperationException("Automatic border detection");
      JsonObject a = Graphics.args();
      String handle = Graphics.upload(in, Graphics.IMAGE_LIMIT, false);
      try {
        a.addProperty("bytes", handle);
        return new ImageDecoder(Graphics.async("openDecoder", a));
      } finally {
        Graphics.closeBytes(handle);
      }
    }

    public static ImageDecoder open$default(
        Companion self, InputStream in, boolean crop, int mask, Object marker) throws IOException {
      return self.open(in, (mask & 2) != 0 ? false : crop);
    }
  }
}
