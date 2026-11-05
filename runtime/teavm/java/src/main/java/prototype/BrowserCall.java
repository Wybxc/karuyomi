package prototype;

import okhttp3.*;
import okio.BufferedSink;
import okio.Okio;
import okio.Timeout;
import com.google.gson.*;
import java.util.*;
import java.io.IOException;
import java.io.InterruptedIOException;

/** Replaces only OkHttpClient.newCall; plugin interceptors still execute as JVM bytecode. */
public final class BrowserCall implements Call {
  private static final ThreadLocal<Operation> threadOperation = new ThreadLocal<>();
  private static Operation activeOperation;

  /** One exported host entry owns foreground HTTP and all callbacks it schedules. */
  static final class Operation implements AutoCloseable {
    private static final int MAX_BACKGROUND_CALLS = 64;
    private static final long DRAIN_TIMEOUT_MS = 30000;
    final String requestId;
    final String generation;
    final String token;
    private final Set<BrowserCall> pending = new HashSet<>();
    private boolean closed;
    private Throwable callbackFailure;

    Operation(String requestId, String generation, String token) {
      this.requestId = requestId;
      this.generation = generation;
      this.token = token;
    }

    void enter() {
      threadOperation.set(this);
    }

    void leave() {
      threadOperation.remove();
    }

    synchronized void checkOpen() throws InterruptedIOException {
      if (closed) throw new InterruptedIOException("Source operation expired or was cancelled");
    }

    synchronized void register(BrowserCall call) {
      if (closed) throw new IllegalStateException("Source operation has ended");
      if (pending.size() >= MAX_BACKGROUND_CALLS)
        throw new IllegalStateException("Too many background HTTP callbacks");
      pending.add(call);
    }

    synchronized void finished(BrowserCall call, Throwable failure) {
      pending.remove(call);
      if (failure != null && callbackFailure == null) callbackFailure = failure;
      notifyAll();
    }

    void drain() throws Throwable {
      drain(DRAIN_TIMEOUT_MS);
    }

    synchronized void drain(long timeoutMs) throws Throwable {
      if (timeoutMs < 1 || timeoutMs > DRAIN_TIMEOUT_MS)
        throw new IllegalArgumentException("HTTP callback drain deadline must be 1..30000 ms");
      long deadline = System.nanoTime() + timeoutMs * 1000000;
      while (!pending.isEmpty()) {
        if (callbackFailure != null) throw callbackFailure;
        long remaining = deadline - System.nanoTime();
        if (remaining <= 0)
          throw new InterruptedIOException("Background HTTP callbacks exceeded drain deadline");
        try {
          wait(Math.max(1, remaining / 1000000));
        } catch (InterruptedException error) {
          Thread.currentThread().interrupt();
          throw new InterruptedIOException("Interrupted while draining HTTP callbacks");
        }
      }
      if (callbackFailure != null) throw callbackFailure;
      closed = true;
    }

    synchronized boolean hasPending() {
      return !pending.isEmpty();
    }

    public void close() {
      List<BrowserCall> calls;
      synchronized (this) {
        closed = true;
        calls = new ArrayList<>(pending);
        pending.clear();
        notifyAll();
      }
      for (BrowserCall call : calls) call.cancel();
      synchronized (BrowserCall.class) {
        if (activeOperation == this) activeOperation = null;
      }
    }
  }

  static synchronized Operation beginOperation(String requestId, String generation, String token) {
    if (requestId == null
        || requestId.isEmpty()
        || generation == null
        || generation.isEmpty()
        || token == null
        || token.isEmpty()) throw new IllegalArgumentException("Missing Source operation owner");
    if (activeOperation != null) throw new IllegalStateException("Concurrent Source operation");
    activeOperation = new Operation(requestId, generation, token);
    return activeOperation;
  }

  private static Operation currentOperation() {
    return threadOperation.get();
  }

  /** Capture before scheduling; an expired child must never adopt another entry. */
  public static Runnable bindOperation(Runnable action) {
    Operation owner = currentOperation();
    return () -> {
      Operation previous = currentOperation();
      if (owner == null) threadOperation.remove();
      else owner.enter();
      try {
        if (owner != null) {
          try {
            owner.checkOpen();
          } catch (InterruptedIOException error) {
            throw new IllegalStateException(error);
          }
        }
        action.run();
      } finally {
        if (previous == null) threadOperation.remove();
        else previous.enter();
      }
    };
  }

  private final OkHttpClient client;
  private final Request request;
  private Operation owner;
  private volatile boolean executed;
  private volatile boolean cancelled;
  private final Set<String> httpHandles = new HashSet<>();
  private Call proxy;

  private BrowserCall(OkHttpClient c, Request r) {
    client = c;
    request = r;
  }

  public static Call create(OkHttpClient c, Request r) {
    BrowserCall b = new BrowserCall(c, r);
    b.proxy = b;
    return b;
  }

  public Request request() {
    return request;
  }

  public void enqueue(Callback c) {
    Objects.requireNonNull(c, "callback");
    startExecution();
    Operation operation = owner;
    if (operation != null) operation.register(this);
    try {
      new Thread(
              () -> {
                if (operation != null) operation.enter();
                Throwable failure = null;
                try {
                  Response response;
                  try {
                    response = executeOnce();
                  } catch (IOException error) {
                    if (operation != null) operation.checkOpen();
                    c.onFailure(this, error);
                    return;
                  }
                  try (Response closeAfterCallback = response) {
                    if (operation != null) operation.checkOpen();
                    c.onResponse(this, response);
                  }
                } catch (Throwable error) {
                  failure = error;
                  if (operation == null) Bridge.trace("HTTP callback failed: " + error);
                } finally {
                  // Close leaked handles even if an interceptor replaced the body.
                  try {
                    closeHandles();
                  } catch (Throwable error) {
                    if (failure == null) failure = error;
                  }
                  if (operation != null) {
                    operation.finished(this, failure);
                    operation.leave();
                  }
                }
              })
          .start();
    } catch (Throwable error) {
      if (operation != null) operation.finished(this, error);
      throw error;
    }
  }

  private void closeHandles() {
    List<String> handles;
    synchronized (this) {
      handles = new ArrayList<>(httpHandles);
      httpHandles.clear();
    }
    for (String handle : handles) cancelHandle(handle);
  }

  public void cancel() {
    List<String> handles;
    synchronized (this) {
      cancelled = true;
      handles = new ArrayList<>(httpHandles);
      httpHandles.clear();
    }
    for (String handle : handles) cancelHandle(handle);
  }

  public boolean isExecuted() {
    return executed;
  }

  public boolean isCanceled() {
    return cancelled;
  }

  public Timeout timeout() {
    return new Timeout();
  }

  public Call clone() {
    return create(client, request);
  }

  public void addEventListener(okhttp3.EventListener e) {
    throw new UnsupportedOperationException("event listener");
  }

  public <T> T tag(kotlin.reflect.KClass<T> c) {
    return null;
  }

  public <T> T tag(Class<? extends T> c) {
    return null;
  }

  public <T> T tag(kotlin.reflect.KClass<T> c, kotlin.jvm.functions.Function0<? extends T> f) {
    return f.invoke();
  }

  public <T> T tag(Class<T> c, kotlin.jvm.functions.Function0<? extends T> f) {
    return f.invoke();
  }

  public Response execute() throws IOException {
    startExecution();
    return executeOnce();
  }

  private synchronized void startExecution() {
    if (executed) throw new IllegalStateException("Already executed");
    executed = true;
    owner = currentOperation();
  }

  private Response executeOnce() throws IOException {
    if (owner != null) owner.checkOpen();
    Bridge.trace("execute " + request.url());
    List<Interceptor> list = new ArrayList<>(client.interceptors());
    list.add(this::follow);
    list.add(this::bridgeRequest);
    list.add(new okhttp3.internal.cache.CacheInterceptor());
    list.addAll(client.networkInterceptors());
    return proceed(list, 0, request);
  }

  private Response proceed(List<Interceptor> list, int index, Request r) throws IOException {
    return proceed(
        list,
        index,
        r,
        client.connectTimeoutMillis(),
        client.readTimeoutMillis(),
        client.writeTimeoutMillis(),
        client.cache());
  }

  private Response proceed(
      List<Interceptor> list,
      int index,
      Request r,
      int connectMs,
      int readMs,
      int writeMs,
      Cache cache)
      throws IOException {
    if (cancelled) throw new IOException("Cancelled");
    if (index == list.size()) return transport(r, readMs);
    return list.get(index).intercept(chain(list, index, r, connectMs, readMs, writeMs, cache));
  }

  private Interceptor.Chain chain(
      List<Interceptor> list,
      int index,
      Request r,
      int connectMs,
      int readMs,
      int writeMs,
      Cache cache) {
    return new Interceptor.Chain() {
      public okhttp3.Request request() {
        return r;
      }

      public okhttp3.Response proceed(okhttp3.Request a0) throws IOException {
        return BrowserCall.this.proceed(list, index + 1, a0, connectMs, readMs, writeMs, cache);
      }

      public okhttp3.Connection connection() {
        return null;
      }

      public okhttp3.Call call() {
        return BrowserCall.this;
      }

      public int connectTimeoutMillis() {
        return connectMs;
      }

      public okhttp3.Interceptor.Chain withConnectTimeout(
          int a0, java.util.concurrent.TimeUnit a1) {
        return chain(list, index, r, (int) a1.toMillis(a0), readMs, writeMs, cache);
      }

      public int readTimeoutMillis() {
        return readMs;
      }

      public okhttp3.Interceptor.Chain withReadTimeout(int a0, java.util.concurrent.TimeUnit a1) {
        return chain(list, index, r, connectMs, (int) a1.toMillis(a0), writeMs, cache);
      }

      public int writeTimeoutMillis() {
        return writeMs;
      }

      public okhttp3.Interceptor.Chain withWriteTimeout(int a0, java.util.concurrent.TimeUnit a1) {
        return chain(list, index, r, connectMs, readMs, (int) a1.toMillis(a0), cache);
      }

      public boolean getFollowSslRedirects() {
        return client.followSslRedirects();
      }

      public boolean getFollowRedirects() {
        return client.followRedirects();
      }

      public okhttp3.Dns getDns() {
        throw new UnsupportedOperationException("Chain.getDns");
      }

      public okhttp3.Interceptor.Chain withDns(okhttp3.Dns a0) {
        throw new UnsupportedOperationException("Chain.withDns");
      }

      public javax.net.SocketFactory getSocketFactory() {
        throw new UnsupportedOperationException("Chain.getSocketFactory");
      }

      public okhttp3.Interceptor.Chain withSocketFactory(javax.net.SocketFactory a0) {
        throw new UnsupportedOperationException("Chain.withSocketFactory");
      }

      public boolean getRetryOnConnectionFailure() {
        return client.retryOnConnectionFailure();
      }

      public okhttp3.Interceptor.Chain withRetryOnConnectionFailure(boolean a0) {
        throw new UnsupportedOperationException("Chain.withRetryOnConnectionFailure");
      }

      public okhttp3.Authenticator getAuthenticator() {
        throw new UnsupportedOperationException("Chain.getAuthenticator");
      }

      public okhttp3.Interceptor.Chain withAuthenticator(okhttp3.Authenticator a0) {
        throw new UnsupportedOperationException("Chain.withAuthenticator");
      }

      public okhttp3.CookieJar getCookieJar() {
        return client.cookieJar();
      }

      public okhttp3.Interceptor.Chain withCookieJar(okhttp3.CookieJar a0) {
        throw new UnsupportedOperationException("Chain.withCookieJar");
      }

      public okhttp3.Cache getCache() {
        return cache;
      }

      public okhttp3.Interceptor.Chain withCache(okhttp3.Cache a0) {
        return chain(list, index, r, connectMs, readMs, writeMs, a0);
      }

      public java.net.Proxy getProxy() {
        throw new UnsupportedOperationException("Chain.getProxy");
      }

      public okhttp3.Interceptor.Chain withProxy(java.net.Proxy a0) {
        throw new UnsupportedOperationException("Chain.withProxy");
      }

      public java.net.ProxySelector getProxySelector() {
        throw new UnsupportedOperationException("Chain.getProxySelector");
      }

      public okhttp3.Interceptor.Chain withProxySelector(java.net.ProxySelector a0) {
        throw new UnsupportedOperationException("Chain.withProxySelector");
      }

      public okhttp3.Authenticator getProxyAuthenticator() {
        throw new UnsupportedOperationException("Chain.getProxyAuthenticator");
      }

      public okhttp3.Interceptor.Chain withProxyAuthenticator(okhttp3.Authenticator a0) {
        throw new UnsupportedOperationException("Chain.withProxyAuthenticator");
      }

      public javax.net.ssl.SSLSocketFactory getSslSocketFactoryOrNull() {
        throw new UnsupportedOperationException("Chain.getSslSocketFactoryOrNull");
      }

      public okhttp3.Interceptor.Chain withSslSocketFactory(
          javax.net.ssl.SSLSocketFactory a0, javax.net.ssl.X509TrustManager a1) {
        throw new UnsupportedOperationException("Chain.withSslSocketFactory");
      }

      public javax.net.ssl.X509TrustManager getX509TrustManagerOrNull() {
        throw new UnsupportedOperationException("Chain.getX509TrustManagerOrNull");
      }

      public javax.net.ssl.HostnameVerifier getHostnameVerifier() {
        throw new UnsupportedOperationException("Chain.getHostnameVerifier");
      }

      public okhttp3.Interceptor.Chain withHostnameVerifier(javax.net.ssl.HostnameVerifier a0) {
        throw new UnsupportedOperationException("Chain.withHostnameVerifier");
      }

      public okhttp3.CertificatePinner getCertificatePinner() {
        throw new UnsupportedOperationException("Chain.getCertificatePinner");
      }

      public okhttp3.Interceptor.Chain withCertificatePinner(okhttp3.CertificatePinner a0) {
        throw new UnsupportedOperationException("Chain.withCertificatePinner");
      }

      public okhttp3.ConnectionPool getConnectionPool() {
        throw new UnsupportedOperationException("Chain.getConnectionPool");
      }

      public okhttp3.Interceptor.Chain withConnectionPool(okhttp3.ConnectionPool a0) {
        throw new UnsupportedOperationException("Chain.withConnectionPool");
      }

      public okhttp3.EventListener getEventListener() {
        return okhttp3.EventListener.NONE;
      }
    };
  }

  private Response follow(Interceptor.Chain chain) throws IOException {
    Request next = chain.request();
    Response prior = null;
    for (int redirects = 0; ; redirects++) {
      Response response = chain.proceed(next);
      if (prior != null) response = response.newBuilder().priorResponse(prior).build();
      String location = response.header("Location");
      int code = response.code();
      if (!client.followRedirects()
          || location == null
          || !Arrays.asList(301, 302, 303, 307, 308).contains(code)) return response;
      if (redirects >= 10) {
        response.close();
        throw new IOException("Too many redirects");
      }
      HttpUrl target = next.url().resolve(location);
      if (target == null) {
        response.close();
        throw new IOException("Bad redirect");
      }
      Request.Builder builder = next.newBuilder().url(target);
      if (!target.host().equals(next.url().host())
          || target.port() != next.url().port()
          || !target.scheme().equals(next.url().scheme()))
        builder.removeHeader("Authorization").removeHeader("Cookie");
      if (code == 303 && !next.method().equals("HEAD")
          || ((code == 301 || code == 302) && next.method().equals("POST")))
        builder
            .get()
            .removeHeader("Content-Type")
            .removeHeader("Content-Length")
            .removeHeader("Transfer-Encoding");
      prior = okhttp3.internal.UnreadableResponseBodyKt.stripBody(response);
      response.close();
      next = builder.build();
    }
  }

  private Response bridgeRequest(Interceptor.Chain chain) throws IOException {
    Request user = chain.request();
    Headers.Builder sent = user.headers().newBuilder();
    List<Cookie> cookies = client.cookieJar().loadForRequest(user.url());
    if (user.body() != null && user.body().contentType() != null)
      sent.set("Content-Type", user.body().contentType().toString());
    if (!cookies.isEmpty()) {
      StringJoiner cookie = new StringJoiner("; ");
      for (Cookie value : cookies) cookie.add(value.name() + "=" + value.value());
      sent.set("Cookie", cookie.toString());
    }
    Response response = chain.proceed(user.newBuilder().headers(sent.build()).build());
    client
        .cookieJar()
        .saveFromResponse(user.url(), Cookie.parseAll(user.url(), response.headers()));
    return response.newBuilder().request(user).build();
  }

  private Response transport(Request r, int readMs) throws IOException {
    try {
      return transportV2(r, readMs);
    } catch (IOException error) {
      if (cancelled
          || error instanceof InterruptedIOException
          || !client.retryOnConnectionFailure()
          || !(r.method().equals("GET") || r.method().equals("HEAD"))
          || !Bridge.networkFailure(error)) throw error;
      Bridge.trace("Retry idempotent request after connection loss: " + r.url());
      return transportV2(r, readMs);
    }
  }

  private Response transportV2(Request request, int readMs) throws IOException {
    if (cancelled) throw new InterruptedIOException("Cancelled");
    if (owner != null) owner.checkOpen();
    RequestBody body = request.body();
    if (body != null && body.isDuplex()) throw new IOException("Duplex HTTP upload is unsupported");
    long bodyLength = body == null ? 0 : body.contentLength();
    if (bodyLength < -1 || bodyLength > HttpRequestSink.MAX_REQUEST)
      throw new IOException("HTTP request body exceeds 8 MiB or has an invalid length");
    JsonObject metadata = new JsonObject();
    if (owner != null) {
      metadata.addProperty("operationRequestId", owner.requestId);
      metadata.addProperty("operationGeneration", owner.generation);
      metadata.addProperty("operationToken", owner.token);
    }
    metadata.addProperty("url", request.url().toString());
    metadata.addProperty("method", request.method());
    JsonArray headers = new JsonArray();
    for (int index = 0; index < request.headers().size(); index++) {
      JsonArray pair = new JsonArray();
      pair.add(request.headers().name(index));
      pair.add(request.headers().value(index));
      headers.add(pair);
    }
    metadata.add("headers", headers);
    metadata.addProperty("hasBody", body != null);
    if (bodyLength < 0) metadata.add("bodyLength", JsonNull.INSTANCE);
    else metadata.addProperty("bodyLength", bodyLength);
    // The v2 host currently enforces one overall budget, not three separate
    // connect/read/write idle timers. A zero OkHttp timeout uses its 5-minute cap.
    metadata.addProperty("timeoutMs", readMs <= 0 ? 300000 : Math.min(readMs, 300000));
    String json = metadata.toString();
    if (json.getBytes(java.nio.charset.StandardCharsets.UTF_8).length > HttpBodySource.MAX_CHUNK)
      throw new IOException("HTTP request metadata exceeds 64 KiB");
    long sentAt = System.currentTimeMillis();
    String handle = Bridge.httpOpen(json);
    synchronized (this) {
      if (!cancelled) httpHandles.add(handle);
    }
    try {
      if (cancelled) throw new InterruptedIOException("Cancelled");
      if (body != null) {
        HttpRequestSink upload =
            new HttpRequestSink(bytes -> {
              if (cancelled) throw new InterruptedIOException("Cancelled");
              Bridge.httpWrite(handle, bytes);
            });
        BufferedSink sink = Okio.buffer(upload);
        body.writeTo(sink);
        sink.flush();
        upload.finish(bodyLength);
        sink.close();
      }
      String responseJson = Bridge.httpFinish(handle);
      if (cancelled) throw new InterruptedIOException("Cancelled");
      // The host adds one opaque handle to the already bounded wire META.
      if (responseJson == null
          || responseJson.getBytes(java.nio.charset.StandardCharsets.UTF_8).length
              > HttpBodySource.MAX_CHUNK + 256)
        throw new IOException("Invalid HTTP response metadata size");
      JsonObject result = JsonParser.parseString(responseJson).getAsJsonObject();
      if (result.has("body") || !handle.equals(result.get("handle").getAsString()))
        throw new IOException("Invalid HTTP response handle or inline body");
      int status = result.get("upstreamStatus").getAsInt();
      if (status < 100 || status > 599) throw new IOException("Invalid upstream status");
      long responseLength =
          result.get("bodyLength").isJsonNull() ? -1 : result.get("bodyLength").getAsLong();
      if (!result.get("hasBody").getAsBoolean() && responseLength != 0)
        throw new IOException("An absent response body must have zero length");
      Headers.Builder received = new Headers.Builder();
      for (JsonElement element : result.getAsJsonArray("headers")) {
        JsonArray pair = element.getAsJsonArray();
        if (pair.size() != 2) throw new IOException("Invalid HTTP response header");
        received.add(pair.get(0).getAsString(), pair.get(1).getAsString());
      }
      Headers responseHeaders = received.build();
      HttpBodySource source =
          new HttpBodySource(
              new HttpBodySource.Reader() {
                public byte[] read(int maximum) throws IOException {
                  if (cancelled) throw new InterruptedIOException("Cancelled");
                  byte[] bytes = Bridge.httpRead(handle, maximum);
                  if (cancelled) throw new InterruptedIOException("Cancelled");
                  return bytes;
                }

                public void close() throws IOException {
                  try {
                    Bridge.httpClose(handle);
                  } finally {
                    forgetHandle(handle);
                  }
                }
              },
              responseLength);
      return new Response.Builder()
          .request(request)
          .protocol(Protocol.HTTP_1_1)
          .code(status)
          .message(result.get("message").getAsString())
          .headers(responseHeaders)
          .sentRequestAtMillis(sentAt)
          .receivedResponseAtMillis(System.currentTimeMillis())
          .body(
              ResponseBody.create(
                  MediaType.parse(
                      responseHeaders.get("Content-Type") == null
                          ? "application/octet-stream"
                          : responseHeaders.get("Content-Type")),
                  responseLength,
                  Okio.buffer(source)))
          .build();
    } catch (IOException | RuntimeException error) {
      cancelHandle(handle);
      forgetHandle(handle);
      throw error;
    }
  }

  private synchronized void forgetHandle(String handle) {
    httpHandles.remove(handle);
  }

  private static void cancelHandle(String handle) {
    try {
      Bridge.httpCancel(handle);
    } catch (IOException error) {
      Bridge.trace("HTTP cancel failed: " + error.getMessage());
    }
  }
}
