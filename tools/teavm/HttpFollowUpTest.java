package prototype;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;
import okhttp3.Authenticator;
import okhttp3.Credentials;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okio.BufferedSink;

/** Source authentication and body lifetimes through BrowserCall and a loopback transport. */
public final class HttpFollowUpTest {
  private static final String CREDENTIAL = Credentials.basic("fixture-user", "fixture-password");
  private static int checks;

  private static void check(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
    checks++;
  }

  private static void reply(HttpExchange exchange, int status) throws IOException {
    try {
      exchange.getRequestBody().readAllBytes();
      byte[] bytes = (status == 200 ? "authorized" : "challenge").getBytes(StandardCharsets.UTF_8);
      if (status == 401)
        exchange.getResponseHeaders().set("WWW-Authenticate", "Basic realm=fixture");
      exchange.sendResponseHeaders(status, bytes.length);
      exchange.getResponseBody().write(bytes);
    } finally {
      exchange.close();
    }
  }

  private static Request request(String url) {
    return new Request.Builder().url(url).build();
  }

  private static Response execute(Authenticator authenticator, Request request) throws IOException {
    OkHttpClient client = new OkHttpClient.Builder().authenticator(authenticator).build();
    return BrowserCall.create(client, request).execute();
  }

  public static void main(String[] args) throws IOException {
    HttpServer origin = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    HttpServer redirected = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    String base = "http://127.0.0.1:" + origin.getAddress().getPort();
    String other = "http://127.0.0.1:" + redirected.getAddress().getPort() + "/challenge";
    AtomicInteger requests = new AtomicInteger(), crossOrigin = new AtomicInteger();
    AtomicInteger forwardedCredentials = new AtomicInteger(), challenges = new AtomicInteger();
    origin.createContext(
        "/protected",
        exchange -> {
          requests.incrementAndGet();
          reply(
              exchange,
              CREDENTIAL.equals(exchange.getRequestHeaders().getFirst("Authorization"))
                  ? 200
                  : 401);
        });
    origin.createContext(
        "/cross-origin",
        exchange -> {
          exchange.getResponseHeaders().set("Location", other);
          reply(exchange, 302);
        });
    origin.createContext(
        "/always-challenge",
        exchange -> {
          challenges.incrementAndGet();
          reply(exchange, 401);
        });
    redirected.createContext(
        "/challenge",
        exchange -> {
          crossOrigin.incrementAndGet();
          if (exchange.getRequestHeaders().containsKey("Authorization"))
            forwardedCredentials.incrementAndGet();
          reply(exchange, 401);
        });
    origin.start();
    redirected.start();
    try {
      Authenticator source =
          (route, response) -> {
            check(route == null && response.code() == 401, "challenge delivered to the Source");
            return response.request().newBuilder().header("Authorization", CREDENTIAL).build();
          };
      try (Response response = execute(source, request(base + "/protected"))) {
        check(
            response.code() == 200 && response.body().string().equals("authorized"),
            "the retried request carries the Source credentials");
        check(response.priorResponse().code() == 401, "authentication preserves response history");
        check(requests.get() == 2, "exactly one authenticated follow-up");
      }

      try (Response response =
          execute(
              (route, challenge) -> {
                throw new AssertionError("Authentication crossed an origin");
              },
              request(base + "/cross-origin")
                  .newBuilder()
                  .header("Authorization", CREDENTIAL)
                  .build())) {
        check(
            response.code() == 401 && response.body().string().equals("challenge"),
            "the other origin's challenge is delivered without authentication");
        check(
            crossOrigin.get() == 1 && forwardedCredentials.get() == 0,
            "Authorization is stripped on a cross-origin redirect");
      }
      try {
        execute(
            (route, challenge) -> challenge.request().newBuilder().url(other).build(),
            request(base + "/protected"));
        throw new AssertionError("Authenticator redirected a request to another origin");
      } catch (IOException expected) {
        check(
            expected.getMessage().equals("Authenticator changed request origin"),
            "another origin is explicitly rejected");
        check(
            crossOrigin.get() == 1 && Bridge.openHandles() == 0,
            "routed challenge never opened an extra handle");
      }

      RequestBody oneShot =
          new RequestBody() {
            public MediaType contentType() {
              return null;
            }

            public boolean isOneShot() {
              return true;
            }

            public void writeTo(BufferedSink sink) throws IOException {
              sink.writeUtf8("one upload");
            }
          };
      try (Response response =
          execute(source, request(base + "/always-challenge").newBuilder().post(oneShot).build())) {
        check(response.code() == 401 && challenges.get() == 1, "one-shot request is not replayed");
      }

      try {
        execute(source, request(base + "/always-challenge"));
        throw new AssertionError("Endless authentication was accepted");
      } catch (IOException expected) {
        check(
            expected.getMessage().equals("Too many authentication follow-ups"),
            "retry limit enforced");
        check(
            challenges.get() == 12 && Bridge.openHandles() == 0,
            "the failed sequence released every response handle");
      }
      try (Response response = execute(Authenticator.NONE, request(base + "/protected"))) {
        check(
            response.code() == 401 && response.priorResponse() == null,
            "the default has no follow-up");
      }
      System.out.println("Source HTTP follow-ups: " + checks + " checks passed");
    } finally {
      Bridge.closeTransport();
      origin.stop(0);
      redirected.stop(0);
    }
  }
}
