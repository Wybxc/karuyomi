package prototype;

import com.google.gson.*;
import java.io.*;
import java.net.URI;
import java.net.http.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

/** JVM-only HTTP platform fixture; never compiled into a product bundle. */
public final class Bridge {
  private static final HttpClient client =
      HttpClient.newBuilder().followRedirects(HttpClient.Redirect.NEVER).build();
  private static final Map<String, Exchange> exchanges = new ConcurrentHashMap<>();
  private static IOException nextFailure;

  public static void failNextRequest(IOException error) {
    nextFailure = error;
  }

  private static final class Exchange {
    final JsonObject metadata;
    final ByteArrayOutputStream upload = new ByteArrayOutputStream();
    InputStream body;

    Exchange(JsonObject metadata) {
      this.metadata = metadata;
    }
  }

  public static String trace(String message) {
    return "";
  }

  public static final class NetworkFailure extends IOException {
    public NetworkFailure(String message) {
      super(message);
    }
  }

  public static boolean networkFailure(IOException error) {
    return error instanceof NetworkFailure;
  }

  public static String cache(String request) {
    if (!JsonParser.parseString(request)
        .getAsJsonObject()
        .get("operation")
        .getAsString()
        .equals("close"))
      throw new AssertionError("Image calls must not access the configured cache");
    return "{}";
  }

  public static String httpOpen(String metadata) throws IOException {
    JsonObject value = JsonParser.parseString(metadata).getAsJsonObject();
    URI uri = URI.create(value.get("url").getAsString());
    if (!"http".equals(uri.getScheme()) || !"127.0.0.1".equals(uri.getHost()))
      throw new IOException("JVM image fixture permits localhost only");
    String handle = UUID.randomUUID().toString();
    exchanges.put(handle, new Exchange(value));
    return handle;
  }

  private static Exchange exchange(String handle) throws IOException {
    Exchange exchange = exchanges.get(handle);
    if (exchange == null) throw new IOException("Unknown JVM HTTP handle");
    return exchange;
  }

  public static void httpWrite(String handle, byte[] bytes) throws IOException {
    Exchange exchange = exchange(handle);
    if (bytes.length < 1
        || bytes.length > HttpBodySource.MAX_CHUNK
        || bytes.length > HttpRequestSink.MAX_REQUEST - exchange.upload.size())
      throw new IOException("Invalid JVM upload size");
    exchange.upload.write(bytes);
  }

  public static String httpFinish(String handle) throws IOException {
    if (nextFailure != null) {
      IOException failure = nextFailure;
      nextFailure = null;
      throw failure;
    }
    Exchange exchange = exchange(handle);
    JsonObject metadata = exchange.metadata;
    HttpRequest.Builder request =
        HttpRequest.newBuilder(URI.create(metadata.get("url").getAsString()))
            .timeout(Duration.ofMillis(metadata.get("timeoutMs").getAsLong()));
    for (JsonElement element : metadata.getAsJsonArray("headers")) {
      JsonArray pair = element.getAsJsonArray();
      request.header(pair.get(0).getAsString(), pair.get(1).getAsString());
    }
    request.method(
        metadata.get("method").getAsString(),
        metadata.get("hasBody").getAsBoolean()
            ? HttpRequest.BodyPublishers.ofByteArray(exchange.upload.toByteArray())
            : HttpRequest.BodyPublishers.noBody());
    HttpResponse<InputStream> response;
    try {
      response = client.send(request.build(), HttpResponse.BodyHandlers.ofInputStream());
    } catch (InterruptedException error) {
      Thread.currentThread().interrupt();
      throw new InterruptedIOException("JVM HTTP interrupted");
    }
    exchange.body = response.body();
    JsonObject result = new JsonObject();
    result.addProperty("handle", handle);
    result.addProperty("upstreamStatus", response.statusCode());
    result.addProperty("hasBody", true);
    result.addProperty(
        "bodyLength", response.headers().firstValueAsLong("content-length").orElse(-1));
    result.addProperty("message", "JVM fixture");
    JsonArray headers = new JsonArray();
    response
        .headers()
        .map()
        .forEach((name, values) ->
            values.forEach(value -> {
              JsonArray pair = new JsonArray();
              pair.add(name);
              pair.add(value);
              headers.add(pair);
            }));
    result.add("headers", headers);
    return result.toString();
  }

  public static byte[] httpRead(String handle, int maximum) throws IOException {
    if (maximum < 1 || maximum > HttpBodySource.MAX_CHUNK)
      throw new IOException("Invalid JVM read size");
    byte[] bytes = new byte[maximum];
    int count = exchange(handle).body.read(bytes);
    return count == -1 ? null : Arrays.copyOf(bytes, count);
  }

  public static void httpClose(String handle) throws IOException {
    Exchange exchange = exchanges.remove(handle);
    if (exchange != null && exchange.body != null) exchange.body.close();
  }

  public static void httpCancel(String handle) throws IOException {
    httpClose(handle);
  }

  public static void closeTransport() throws IOException {
    for (String handle : new ArrayList<>(exchanges.keySet())) httpClose(handle);
  }

  public static int openHandles() {
    return exchanges.size();
  }
}
