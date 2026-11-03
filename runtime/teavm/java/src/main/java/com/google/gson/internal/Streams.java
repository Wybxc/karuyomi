package com.google.gson.internal;

import com.google.gson.*;
import com.google.gson.stream.*;
import java.io.*;

public final class Streams {
  public static JsonElement parse(JsonReader r) {
    try {
      return read(r);
    } catch (IOException e) {
      throw new JsonSyntaxException(e);
    }
  }

  private static JsonElement read(JsonReader r) throws IOException {
    switch (r.peek()) {
      case BEGIN_OBJECT:
        JsonObject o = new JsonObject();
        r.beginObject();
        while (r.hasNext()) o.add(r.nextName(), read(r));
        r.endObject();
        return o;
      case BEGIN_ARRAY:
        JsonArray a = new JsonArray();
        r.beginArray();
        while (r.hasNext()) a.add(read(r));
        r.endArray();
        return a;
      case STRING:
        return new JsonPrimitive(r.nextString());
      case NUMBER:
        return new JsonPrimitive(new LazilyParsedNumber(r.nextString()));
      case BOOLEAN:
        return new JsonPrimitive(r.nextBoolean());
      case NULL:
        r.nextNull();
        return JsonNull.INSTANCE;
      case END_DOCUMENT:
        return JsonNull.INSTANCE;
      default:
        throw new JsonSyntaxException("Unexpected token " + r.peek());
    }
  }

  public static void write(JsonElement e, JsonWriter w) throws IOException {
    if (e == null || e.isJsonNull()) {
      w.nullValue();
      return;
    }
    if (e.isJsonObject()) {
      w.beginObject();
      for (var x : e.getAsJsonObject().entrySet()) {
        w.name(x.getKey());
        write(x.getValue(), w);
      }
      w.endObject();
    } else if (e.isJsonArray()) {
      w.beginArray();
      for (JsonElement x : e.getAsJsonArray()) write(x, w);
      w.endArray();
    } else {
      JsonPrimitive p = e.getAsJsonPrimitive();
      if (p.isBoolean()) w.value(p.getAsBoolean());
      else if (p.isNumber()) w.value(p.getAsNumber());
      else w.value(p.getAsString());
    }
  }

  public static Writer writerForAppendable(Appendable a) {
    if (a instanceof Writer) return (Writer) a;
    return new Writer() {
      public void write(char[] c, int o, int n) throws IOException {
        a.append(new String(c, o, n));
      }

      public void flush() {}

      public void close() {}
    };
  }
}
