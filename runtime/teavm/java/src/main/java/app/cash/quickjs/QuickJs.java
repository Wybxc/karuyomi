package app.cash.quickjs;

import prototype.Bridge;
import com.google.gson.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicLong;

public final class QuickJs implements java.io.Closeable {
  private boolean closed;

  private void checkOpen() {
    if (closed) throw new IllegalStateException("QuickJs is closed");
  }

  private static final AtomicLong ids = new AtomicLong();
  private final String id = "js-" + ids.incrementAndGet();

  public static QuickJs create() {
    return new QuickJs();
  }

  public Object evaluate(String source) {
    checkOpen();
    JsonObject r = JsonParser.parseString(Bridge.js(id, "evaluate", source)).getAsJsonObject();
    if (r.has("error")) throw new QuickJsException(r.get("error").getAsString());
    JsonElement v = r.get("value");
    if (v == null || v.isJsonNull()) return null;
    if (v.isJsonPrimitive()) {
      JsonPrimitive p = v.getAsJsonPrimitive();
      if (p.isBoolean()) return p.getAsBoolean();
      if (p.isString()) return p.getAsString();
      double d = p.getAsDouble();
      if (d == (int) d) return (int) d;
      return d;
    }
    return prototype.JsonValues.decode(v);
  }

  public Object evaluate(String source, String file) {
    return evaluate(source);
  }

  public byte[] compile(String source, String file) {
    checkOpen();
    return source.getBytes(StandardCharsets.UTF_8);
  }

  public Object execute(byte[] bytes) {
    return evaluate(new String(bytes, StandardCharsets.UTF_8));
  }

  public <T> void set(String name, Class<T> type, T object) {
    checkOpen();
    JsonObject result =
        JsonParser.parseString(
                Bridge.js(id, "bind", prototype.Callbacks.register(id, name, type, object, false)))
            .getAsJsonObject();
    if (result.has("error")) throw new QuickJsException(result.get("error").getAsString());
  }

  public void close() {
    if (closed) return;
    closed = true;
    prototype.Callbacks.close(id);
    Bridge.js(id, "close", "");
  }
}
