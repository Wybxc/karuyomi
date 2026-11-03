package okhttp3;

import com.google.gson.*;
import java.io.*;
import java.util.*;
import okio.*;
import okhttp3.internal.cache.*;
import prototype.Bridge;

/** Persistent browser cache backend. OkHttp's original interceptor and strategy remain in use. */
public final class Cache implements Closeable, Flushable {
  private static final java.util.concurrent.atomic.AtomicLong handles =
      new java.util.concurrent.atomic.AtomicLong();
  private final String handle = Long.toString(handles.incrementAndGet());
  private final File directory;
  private final long limit;
  private boolean closed;
  private int writes, aborts, requests, networks, hits;

  public Cache(File directory, long maxSize) {
    if (maxSize <= 0) throw new IllegalArgumentException("maxSize <= 0");
    this.directory = Objects.requireNonNull(directory);
    limit = maxSize;
  }

  public Cache(FileSystem fs, okio.Path directory, long maxSize) {
    this(directory.toFile(), maxSize);
    throw new UnsupportedOperationException("Custom Okio FileSystem cache backend is unsupported");
  }

  public Cache(
      okio.Path directory,
      long maxSize,
      FileSystem fs,
      okhttp3.internal.concurrent.TaskRunner runner) {
    this(fs, directory, maxSize);
  }

  private void checkOpen() {
    if (closed) throw new IllegalStateException("cache is closed");
  }

  private JsonObject command(String operation, String url, JsonObject extra) throws IOException {
    JsonObject request = extra == null ? new JsonObject() : extra;
    request.addProperty("operation", operation);
    request.addProperty("directory", directory.getAbsolutePath());
    request.addProperty("handle", handle);
    request.addProperty("maxSize", limit);
    if (url != null) request.addProperty("url", url);
    try {
      JsonObject result =
          JsonParser.parseString(Bridge.cache(request.toString())).getAsJsonObject();
      if (result.has("error")) throw new IOException(result.get("error").getAsString());
      return result;
    } catch (IOException error) {
      throw error;
    } catch (RuntimeException error) {
      throw new IOException("Browser cache: " + error, error);
    }
  }

  private static Set<String> varyFields(Headers headers) {
    Set<String> fields = new TreeSet<>(String.CASE_INSENSITIVE_ORDER);
    for (String value : headers.values("Vary"))
      for (String field : value.split(",")) fields.add(field.trim());
    return fields;
  }

  private static JsonArray headers(Headers headers) {
    JsonArray out = new JsonArray();
    for (int i = 0; i < headers.size(); i++) {
      JsonArray pair = new JsonArray();
      pair.add(headers.name(i));
      pair.add(headers.value(i));
      out.add(pair);
    }
    return out;
  }

  private static Headers headers(JsonArray value) {
    Headers.Builder out = new Headers.Builder();
    for (JsonElement element : value) {
      JsonArray pair = element.getAsJsonArray();
      out.add(pair.get(0).getAsString(), pair.get(1).getAsString());
    }
    return out.build();
  }

  private static JsonObject metadata(Response response) {
    JsonObject value = new JsonObject();
    Request request = response.request();
    value.addProperty("url", request.url().toString());
    value.addProperty("method", request.method());
    value.addProperty("code", response.code());
    value.addProperty("message", response.message());
    value.addProperty("protocol", response.protocol().toString());
    value.add("headers", headers(response.headers()));
    Headers.Builder varied = new Headers.Builder();
    Headers sent =
        response.networkResponse() == null
            ? request.headers()
            : response.networkResponse().request().headers();
    for (String name : varyFields(response.headers()))
      for (String v : sent.values(name)) varied.add(name, v);
    value.add("vary", headers(varied.build()));
    value.addProperty("sent", response.sentRequestAtMillis());
    value.addProperty("received", response.receivedResponseAtMillis());
    return value;
  }

  private static final class BrowserEntry {
    final String version;
    final long generation;

    BrowserEntry(String version, long generation) {
      this.version = version;
      this.generation = generation;
    }
  }

  /** Only entries restored by this backend can omit a Java-owned TLS session. */
  public static boolean requiresJavaHandshake(Request request, Response cached) {
    return request.isHttps()
        && (cached == null || cached.request().tag(BrowserEntry.class) == null);
  }

  public Response get$okhttp(Request request) {
    checkOpen();
    try {
      JsonObject stored = command("get", request.url().toString(), null);
      if (!stored.has("entry")) return null;
      JsonObject value = stored.getAsJsonObject("entry"), meta = value.getAsJsonObject("metadata");
      if (!request.url().toString().equals(meta.get("url").getAsString())
          || !request.method().equals(meta.get("method").getAsString())) return null;
      Headers responseHeaders = headers(meta.getAsJsonArray("headers")),
          varied = headers(meta.getAsJsonArray("vary"));
      for (String name : varyFields(responseHeaders))
        if (!request.headers(name).equals(varied.values(name))) return null;
      byte[] bytes = Base64.getDecoder().decode(value.get("body").getAsString());
      BrowserEntry entry =
          new BrowserEntry(value.get("version").getAsString(), value.get("generation").getAsLong());
      Request storedRequest = request.newBuilder().tag(BrowserEntry.class, entry).build();
      return new Response.Builder()
          .request(storedRequest)
          .protocol(Protocol.get(meta.get("protocol").getAsString()))
          .code(meta.get("code").getAsInt())
          .message(meta.get("message").getAsString())
          .headers(responseHeaders)
          .sentRequestAtMillis(meta.get("sent").getAsLong())
          .receivedResponseAtMillis(meta.get("received").getAsLong())
          .body(
              ResponseBody.create(
                  bytes,
                  MediaType.parse(
                      responseHeaders.get("Content-Type") == null
                          ? "application/octet-stream"
                          : responseHeaders.get("Content-Type"))))
          .build();
    } catch (IOException | IllegalArgumentException error) {
      return null;
    }
  }

  public CacheRequest put$okhttp(Response response) {
    checkOpen();
    String method = response.request().method(), url = response.request().url().toString();
    if (okhttp3.internal.http.HttpMethod.INSTANCE.invalidatesCache(method)) {
      try {
        remove$okhttp(response.request());
      } catch (IOException ignored) {
      }
      return null;
    }
    if (!method.equals("GET") || varyFields(response.headers()).contains("*")) return null;
    try {
      JsonObject begin = command("begin", url, null);
      if (!begin.get("accepted").getAsBoolean()) return null;
      JsonObject meta = metadata(response);
      return new CacheRequest() {
        private boolean done;
        private final Buffer bytes = new Buffer();
        private final Sink sink =
            new Sink() {
              public void write(Buffer source, long count) throws IOException {
                if (done) throw new IllegalStateException("closed cache writer");
                bytes.write(source, count);
              }

              public void flush() {}

              public Timeout timeout() {
                return Timeout.NONE;
              }

              public void close() {
                if (done) return;
                done = true;
                if (closed) {
                  bytes.clear();
                  aborts++;
                  return;
                }
                JsonObject put = new JsonObject();
                put.add("expected", begin.get("version"));
                put.add("generation", begin.get("generation"));
                put.add("editor", begin.get("editor"));
                put.add("metadata", meta);
                put.addProperty("body", Base64.getEncoder().encodeToString(bytes.readByteArray()));
                try {
                  if (command("put", url, put).get("committed").getAsBoolean()) writes++;
                  else aborts++;
                } catch (IOException error) {
                  aborts++;
                }
              }
            };

        public Sink body() {
          return sink;
        }

        public void abort() {
          if (done) return;
          done = true;
          bytes.clear();
          aborts++;
          JsonObject abort = new JsonObject();
          abort.add("editor", begin.get("editor"));
          try {
            command("abort", url, abort);
          } catch (IOException ignored) {
          }
        }
      };
    } catch (IOException error) {
      return null;
    }
  }

  public void update$okhttp(Response cached, Response network) {
    checkOpen();
    BrowserEntry entry = cached.request().tag(BrowserEntry.class);
    if (entry == null) return;
    JsonObject update = new JsonObject();
    update.addProperty("expected", entry.version);
    update.addProperty("generation", entry.generation);
    update.add("metadata", metadata(network));
    try {
      command("update", cached.request().url().toString(), update);
    } catch (IOException ignored) {
    }
  }

  public void remove$okhttp(Request request) throws IOException {
    checkOpen();
    command("remove", request.url().toString(), null);
  }

  public void initialize() throws IOException {
    checkOpen();
    command("initialize", null, null);
  }

  public void evictAll() throws IOException {
    checkOpen();
    command("clear", null, null);
  }

  public void delete() throws IOException {
    command("clear", null, null);
    closed = true;
  }

  public void flush() throws IOException {
    checkOpen();
    command("flush", null, null);
  }

  public void close() throws IOException {
    if (closed) return;
    closed = true;
    command("close", null, null);
  }

  public boolean isClosed() {
    return closed;
  }

  public File directory() {
    return directory;
  }

  public okio.Path directoryPath() {
    return okio.Path.get(directory.toString());
  }

  public long maxSize() {
    return limit;
  }

  public long size() throws IOException {
    checkOpen();
    return command("size", null, null).get("size").getAsLong();
  }

  public Iterator<String> urls() throws IOException {
    checkOpen();
    List<String> values = new ArrayList<>();
    for (JsonElement url : command("urls", null, null).getAsJsonArray("urls"))
      values.add(url.getAsString());
    Iterator<String> iterator = values.iterator();
    return new Iterator<>() {
      private String last;

      public boolean hasNext() {
        return iterator.hasNext();
      }

      public String next() {
        return last = iterator.next();
      }

      public void remove() {
        if (last == null) throw new IllegalStateException();
        try {
          command("remove", last, null);
          last = null;
        } catch (IOException error) {
          throw new IllegalStateException(error);
        }
      }
    };
  }

  public synchronized int writeSuccessCount() {
    return writes;
  }

  public synchronized int writeAbortCount() {
    return aborts;
  }

  public synchronized int requestCount() {
    return requests;
  }

  public synchronized int networkCount() {
    return networks;
  }

  public synchronized int hitCount() {
    return hits;
  }

  public synchronized void trackResponse$okhttp(CacheStrategy strategy) {
    requests++;
    if (strategy.getNetworkRequest() != null) networks++;
    else if (strategy.getCacheResponse() != null) hits++;
  }

  public synchronized void trackConditionalCacheHit$okhttp() {
    hits++;
  }

  public int getWriteSuccessCount$okhttp() {
    return writes;
  }

  public void setWriteSuccessCount$okhttp(int value) {
    writes = value;
  }

  public int getWriteAbortCount$okhttp() {
    return aborts;
  }

  public void setWriteAbortCount$okhttp(int value) {
    aborts = value;
  }

  public static String key(HttpUrl url) {
    return ByteString.encodeUtf8(url.toString()).md5().hex();
  }
}
