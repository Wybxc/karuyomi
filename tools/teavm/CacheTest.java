package prototype;

import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;

/** Original locked OkHttp JVM oracle; the shared scenario has no JVM HTTP-server dependency. */
public final class CacheTest {
  public static void main(String[] args) throws Exception {
    for (Class<?> type : new Class<?>[] {okhttp3.Cache.class, okhttp3.OkHttpClient.class})
      if (!type.getProtectionDomain()
          .getCodeSource()
          .getLocation()
          .toString()
          .endsWith("/okhttp-jvm-5.5.0.jar"))
        throw new AssertionError("Oracle must load original locked OkHttp: " + type);
    HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    server.createContext(
        "/",
        exchange -> {
          String path = exchange.getRequestURI().getPath();
          byte[] body = CacheScenarios.body();
          exchange.getResponseHeaders().set("Cache-Control", "max-age=600");
          if (path.equals("/etag") || path.equals("/no-cache")) {
            exchange
                .getResponseHeaders()
                .set("Cache-Control", path.equals("/no-cache") ? "no-cache" : "max-age=0");
            exchange.getResponseHeaders().set("ETag", "\"cache-fixture\"");
            if ("\"cache-fixture\""
                .equals(exchange.getRequestHeaders().getFirst("If-None-Match"))) {
              exchange.getResponseHeaders().set("X-Revalidated", "yes");
              exchange.sendResponseHeaders(304, -1);
              exchange.close();
              return;
            }
          } else if (path.equals("/no-store")) {
            exchange.getResponseHeaders().set("Cache-Control", "no-store");
          } else if (path.equals("/vary")) {
            exchange.getResponseHeaders().set("Vary", "Cookie");
            body = exchange.getRequestHeaders().getFirst("Cookie").getBytes(StandardCharsets.UTF_8);
          }
          if (path.equals("/invalidate") && exchange.getRequestMethod().equals("POST"))
            body = exchange.getRequestBody().readAllBytes();
          exchange.sendResponseHeaders(200, body.length);
          exchange.getResponseBody().write(body);
          exchange.close();
        });
    server.start();
    java.io.File directory = Files.createTempDirectory("karuyomi-cache-oracle").toFile();
    try {
      System.out.println(
          "Original OkHttp 5.5.0 CacheInterceptor oracle: "
              + CacheScenarios.run("http://127.0.0.1:" + server.getAddress().getPort(), directory));
    } finally {
      server.stop(0);
      new okhttp3.Cache(directory, 1048576).delete();
    }
  }
}
