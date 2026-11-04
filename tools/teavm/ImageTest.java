package prototype;

import com.sun.net.httpserver.HttpServer;
import eu.kanade.tachiyomi.source.model.Page;
import eu.kanade.tachiyomi.source.online.HttpSource;
import java.io.*;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.atomic.AtomicInteger;
import kotlin.coroutines.Continuation;
import okhttp3.*;
import okio.*;

/** Local JVM fixture only: original HttpSource dispatch, processed bytes and bounded ownership. */
public final class ImageTest {
  static int assertions;

  static void check(boolean condition) {
    assertions++;
    if (!condition) throw new AssertionError();
  }

  interface Checked {
    void run() throws Exception;
  }

  static void fails(Checked action, Class<? extends Throwable> type, String message)
      throws Exception {
    try {
      action.run();
      throw new AssertionError("Expected " + type.getName());
    } catch (Throwable error) {
      if (!type.isInstance(error)) throw error;
      check(error.getMessage().contains(message));
    }
  }

  static final class OriginalPage extends Page {
    final String secret = "original-instance";
    int updates;
    boolean completed;

    OriginalPage(int index) {
      super(index, "/opaque-page", null, null);
    }

    @Override
    public void update(long bytes, long length, boolean done) {
      super.update(bytes, length, done);
      updates++;
      completed |= done;
    }
  }

  static final class TrackedBody extends ResponseBody {
    final BufferedSource source;
    final long length;
    boolean closed;
    int contentTypeReads;

    TrackedBody(byte[] bytes, long length, boolean failRead) {
      this.length = length;
      source =
          Okio.buffer(
              new ForwardingSource(new Buffer().write(bytes)) {
                int reads;

                @Override
                public long read(Buffer sink, long maximum) throws IOException {
                  if (failRead && reads++ > 0) throw new IOException("processed read failed");
                  return super.read(sink, Math.min(maximum, 8192));
                }

                @Override
                public void close() throws IOException {
                  closed = true;
                  super.close();
                }
              });
    }

    @Override
    public MediaType contentType() {
      contentTypeReads++;
      return MediaType.get("application/octet-stream");
    }

    @Override
    public long contentLength() {
      return length;
    }

    @Override
    public BufferedSource source() {
      return source;
    }
  }

  static final class FixtureSource extends HttpSource {
    final String endpoint;
    final OkHttpClient client;
    Page expected;
    TrackedBody processed;
    int resolutions, imageRequests;
    boolean failRead, failStatus;

    FixtureSource(String endpoint, Cache cache) {
      this.endpoint = endpoint;
      List<Cookie> cookies = new ArrayList<>();
      client =
          new OkHttpClient.Builder()
              .cache(cache)
              .cookieJar(
                  new CookieJar() {
                    public List<Cookie> loadForRequest(HttpUrl url) {
                      return new ArrayList<>(cookies);
                    }

                    public void saveFromResponse(HttpUrl url, List<Cookie> values) {
                      cookies.clear();
                      cookies.addAll(values);
                    }
                  })
              .addInterceptor(chain -> {
                Response response = chain.proceed(chain.request());
                byte[] bytes = response.body().bytes();
                // A deterministic stand-in for an extension response interceptor. The
                // pump must receive these transformed bytes, never the URL/raw response.
                for (int index = 0; index < bytes.length; index++) bytes[index] ^= (byte) 0xa5;
                processed = new TrackedBody(bytes, bytes.length, failRead);
                return response.newBuilder().code(failStatus ? 503 : 200).body(processed).build();
              })
              .build();
    }

    @Override
    public String getBaseUrl() {
      return endpoint;
    }

    @Override
    public String getName() {
      return "Local image JVM fixture";
    }

    @Override
    public String getLang() {
      return "en";
    }

    @Override
    public long getId() {
      return 42;
    }

    @Override
    public boolean getSupportsLatest() {
      return false;
    }

    @Override
    public OkHttpClient getClient() {
      return client;
    }

    @Override
    protected Headers.Builder headersBuilder() {
      return new Headers.Builder().add("Referer", "source-fixture");
    }

    @Override
    public Object getImageUrl(Page page, Continuation<? super String> continuation) {
      check(page == expected);
      resolutions++;
      new Thread(() -> continuation.resumeWith(endpoint)).start();
      return kotlin.coroutines.intrinsics.IntrinsicsKt.getCOROUTINE_SUSPENDED();
    }

    @Override
    protected Request imageRequest(Page page) {
      check(page == expected && page instanceof OriginalPage);
      imageRequests++;
      return new Request.Builder()
          .url(page.getImageUrl())
          .headers(getHeaders())
          .header("X-Original-Page", ((OriginalPage) page).secret)
          .build();
    }
  }

  static final class Sink implements SourceImages.Sink {
    final Buffer output = new Buffer();
    final FixtureSource source;
    int writes, opens, closes, cancels, maximum;
    IOException writeFailure, closeFailure;

    Sink(FixtureSource source) {
      this.source = source;
    }

    public String open() {
      opens++;
      return "fixture-handle";
    }

    public void write(String handle, byte[] bytes) throws IOException {
      check(handle.equals("fixture-handle"));
      check(bytes.length > 0 && bytes.length <= 65536);
      writes++;
      maximum = Math.max(maximum, bytes.length);
      if (writeFailure != null) throw writeFailure;
      output.write(bytes);
    }

    public String close(String handle) throws IOException {
      check(source.processed.closed);
      closes++;
      if (closeFailure != null) throw closeFailure;
      return "{\"resourceId\":\"fixture\",\"generation\":\"fixture\",\"mimeType\":\"image/png\",\"byteLength\":"
          + output.size()
          + ",\"width\":1,\"height\":1}";
    }

    public void cancel(String handle) {
      check(handle.equals("fixture-handle"));
      cancels++;
    }
  }

  static void sessions(FixtureSource owner) throws Exception {
    PageSessions store = new PageSessions();
    OriginalPage page = new OriginalPage(900);
    List<Page> upstream = new ArrayList<>(List.of(page, new OriginalPage(900)));
    PageSessions.Session session = store.open(owner, upstream);
    check(session.id.matches("[a-f0-9-]{36}"));
    upstream.clear();
    PageSessions.Lease lease = store.acquire(owner, "42", session.id, "p-0");
    check(lease.page() == page && session.pages.size() == 2);
    for (String key : List.of("p-01", "p--1", "p-2", "p-99999", "https://arbitrary.invalid"))
      fails(
          () -> store.acquire(owner, "42", session.id, key),
          IllegalArgumentException.class,
          "page key");
    fails(
        () -> store.acquire(owner, "43", session.id, "p-0"),
        IllegalArgumentException.class,
        "different Source");
    FixtureSource duplicateId = new FixtureSource(owner.endpoint, null);
    fails(
        () -> store.acquire(duplicateId, "42", session.id, "p-0"),
        IllegalArgumentException.class,
        "different Source");
    PageSessions.Session second = store.open(owner, List.of(page));
    check(!second.id.equals(session.id));
    fails(() -> store.open(owner, List.of(page)), IllegalStateException.class, "Close an existing");
    store.close(session.id);
    check(lease.page() == page && !session.pages.isEmpty());
    fails(
        () -> store.acquire(owner, "42", session.id, "p-0"),
        IllegalArgumentException.class,
        "expired");
    fails(() -> store.open(owner, List.of(page)), IllegalStateException.class, "Close an existing");
    lease.close();
    lease.close();
    check(session.pages.isEmpty());
    fails(lease::page, IllegalStateException.class, "closed");
    store.open(owner, List.of(page));
    store.clear();
    store.close("already-closed");
    fails(
        () -> store.open(owner, Collections.nCopies(PageSessions.MAX_PAGES + 1, page)),
        IllegalArgumentException.class,
        "2048");
    fails(
        () -> store.open(owner, Arrays.asList(page, null)),
        NullPointerException.class,
        "null Page");
    PageSessions.Session afterFailure = store.open(owner, List.of(page));
    store.close(afterFailure.id);
    check(afterFailure.pages.isEmpty());
  }

  static void bodyLimits() throws Exception {
    SourceImages.Sink discard =
        new SourceImages.Sink() {
          public String open() {
            return "unused";
          }

          public void write(String handle, byte[] bytes) {
            check(bytes.length <= 65536);
          }

          public String close(String handle) {
            return "{}";
          }

          public void cancel(String handle) {}
        };
    fails(
        () -> SourceImages.pump(new Buffer().write(new byte[] {1}), 2, discard, "unused"),
        IOException.class,
        "length mismatch");
    fails(
        () -> SourceImages.pump(new Buffer().write(new byte[] {1, 2}), 1, discard, "unused"),
        IOException.class,
        "length limit");
    fails(
        () -> SourceImages.pump(new Buffer(), -1, discard, "unused"),
        IOException.class,
        "empty image");
    BufferedSource excessive =
        Okio.buffer(
            new okio.Source() {
              long remaining = HttpBodySource.MAX_RESPONSE + 1;

              public long read(Buffer sink, long maximum) {
                if (remaining == 0) return -1;
                int count = (int) Math.min(remaining, maximum);
                sink.write(new byte[count]);
                remaining -= count;
                return count;
              }

              public Timeout timeout() {
                return Timeout.NONE;
              }

              public void close() {}
            });
    try (excessive) {
      fails(
          () -> SourceImages.pump(excessive, -1, discard, "unused"),
          IOException.class,
          "length limit");
    }
  }

  public static void main(String[] ignored) throws Exception {
    Path directory = Files.createTempDirectory("karuyomi-image-jvm-");
    HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    byte[] expected = new byte[131079];
    new Random(7).nextBytes(expected);
    byte[] unicode = "漫画\u0000ÿ".getBytes(StandardCharsets.UTF_8);
    System.arraycopy(unicode, 0, expected, 17, unicode.length);
    expected[0] = 0;
    expected[1] = (byte) 255;
    byte[] encrypted = expected.clone();
    for (int index = 0; index < encrypted.length; index++) encrypted[index] ^= (byte) 0xa5;
    AtomicInteger requests = new AtomicInteger(),
        cookies = new AtomicInteger(),
        originalHeaders = new AtomicInteger();
    server.createContext(
        "/image",
        exchange -> {
          requests.incrementAndGet();
          if ("session=source-cookie".equals(exchange.getRequestHeaders().getFirst("Cookie")))
            cookies.incrementAndGet();
          if ("source-fixture".equals(exchange.getRequestHeaders().getFirst("Referer"))
              && "original-instance"
                  .equals(exchange.getRequestHeaders().getFirst("X-Original-Page")))
            originalHeaders.incrementAndGet();
          exchange.getResponseHeaders().set("Content-Type", "application/octet-stream");
          exchange.getResponseHeaders().set("Cache-Control", "public, max-age=3600");
          exchange.getResponseHeaders().set("Set-Cookie", "session=source-cookie; Path=/");
          exchange.sendResponseHeaders(200, encrypted.length);
          try (OutputStream body = exchange.getResponseBody()) {
            body.write(encrypted);
          }
        });
    server.start();
    Cache cache = new Cache(directory.toFile(), 1024 * 1024);
    try {
      FixtureSource source =
          new FixtureSource("http://127.0.0.1:" + server.getAddress().getPort() + "/image", cache);
      sessions(source);
      bodyLimits();
      OriginalPage page = new OriginalPage(31);
      source.expected = page;
      Sink first = new Sink(source);
      String descriptor = SourceImages.acquire(source, page, first);
      check(descriptor.contains("\"byteLength\":131079"));
      check(Arrays.equals(first.output.readByteArray(), expected));
      check(first.opens == 1 && first.closes == 1 && first.cancels == 0 && first.maximum <= 65536);
      check(source.resolutions == 1 && source.imageRequests == 1 && source.processed.closed);
      check(page.updates > 0 && page.completed);
      check(source.processed.contentTypeReads == 0);
      Sink second = new Sink(source);
      SourceImages.acquire(source, page, second);
      check(source.resolutions == 1 && source.imageRequests == 2);
      check(requests.get() == 2 && cookies.get() == 1 && originalHeaders.get() == 2);
      check(source.client.cache() == cache && cache.requestCount() == 0);
      source.failRead = true;
      Sink readFailure = new Sink(source);
      fails(
          () -> SourceImages.acquire(source, page, readFailure),
          IOException.class,
          "processed read failed");
      check(
          readFailure.writes == 1
              && readFailure.closes == 0
              && readFailure.cancels == 1
              && source.processed.closed);
      source.failRead = false;
      Sink cancelled = new Sink(source);
      cancelled.writeFailure = new InterruptedIOException("cancelled fixture");
      fails(
          () -> SourceImages.acquire(source, page, cancelled),
          InterruptedIOException.class,
          "cancelled fixture");
      check(cancelled.closes == 0 && cancelled.cancels == 1 && source.processed.closed);
      Sink sealFailure = new Sink(source);
      sealFailure.closeFailure = new IOException("seal failed");
      fails(
          () -> SourceImages.acquire(source, page, sealFailure), IOException.class, "seal failed");
      check(sealFailure.closes == 1 && sealFailure.cancels == 1 && source.processed.closed);
      IOException requestFailure =
          new IOException("request failed", new IOException("original cause"));
      Bridge.failNextRequest(requestFailure);
      try {
        SourceImages.acquire(source, page, new Sink(source));
        throw new AssertionError("Expected the original request IOException");
      } catch (IOException error) {
        check(error == requestFailure);
        check(error.getCause() == requestFailure.getCause());
      }
      source.failStatus = true;
      Sink statusFailure = new Sink(source);
      fails(
          () -> SourceImages.acquire(source, page, statusFailure),
          eu.kanade.tachiyomi.network.HttpException.class,
          "503");
      check(statusFailure.opens == 0 && source.processed.closed);
      System.out.println(
          "Source-image JVM fixture passed: "
              + assertions
              + " assertions; original Page, suspend URL, cacheless/progress, processed binary"
              + " body, limits and cleanup. No real Source/decoder/device gate.");
    } finally {
      server.stop(0);
      cache.close();
      Bridge.closeTransport();
      try (var paths = Files.walk(directory)) {
        for (Path file : paths.sorted(Comparator.reverseOrder()).toList())
          Files.deleteIfExists(file);
      }
    }
  }
}
