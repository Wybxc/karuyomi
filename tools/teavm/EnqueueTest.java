package prototype;

import com.sun.net.httpserver.HttpServer;
import java.io.*;
import java.net.InetSocketAddress;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import okhttp3.*;
import okio.*;

/** JVM oracle for the product BrowserCall owner, callback and body lifecycle. */
public final class EnqueueTest {
  static int assertions;

  static synchronized void check(boolean value) {
    assertions++;
    if (!value) throw new AssertionError("enqueue assertion " + assertions);
  }

  static void await(CountDownLatch latch) throws IOException {
    try {
      if (!latch.await(3, TimeUnit.SECONDS)) throw new IOException("Fixture latch timed out");
    } catch (InterruptedException error) {
      Thread.currentThread().interrupt();
      throw new InterruptedIOException("Fixture interrupted");
    }
  }

  static Call call(OkHttpClient client, String endpoint) {
    return BrowserCall.create(
        client,
        new Request.Builder()
            .url(endpoint)
            .post(RequestBody.create(MediaType.get("text/plain"), "one view"))
            .build());
  }

  static Callback callback(AtomicInteger completed) {
    return new Callback() {
      public void onResponse(Call call, Response response) {
        completed.incrementAndGet();
      }

      public void onFailure(Call call, IOException error) {
        throw new AssertionError(error);
      }
    };
  }

  static void nestedBeforeDelivery(String endpoint, AtomicInteger posts) throws Throwable {
    OkHttpClient client = new OkHttpClient.Builder().build();
    BrowserCall.Operation owner = BrowserCall.beginOperation("rpc", "generation", "token-1");
    CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
    AtomicInteger completed = new AtomicInteger();
    CompletableFuture<Void> delivered = new CompletableFuture<>();
    owner.enter();
    try {
      call(client, endpoint)
          .enqueue(
              new Callback() {
                public void onResponse(Call first, Response response) throws IOException {
                  check(Bridge.openHandles() == 1);
                  entered.countDown();
                  await(release);
                  call(client, endpoint).enqueue(callback(completed));
                  completed.incrementAndGet();
                  // Intentionally leave the response unread and unclosed.
                }

                public void onFailure(Call first, IOException error) {
                  throw new AssertionError(error);
                }
              });
      await(entered);
      check(owner.hasPending());
      Thread draining =
          new Thread(() -> {
            try {
              owner.drain();
              delivered.complete(null);
            } catch (Throwable error) {
              delivered.completeExceptionally(error);
            }
          });
      draining.start();
      check(!delivered.isDone());
      release.countDown();
      delivered.get(3, TimeUnit.SECONDS);
      draining.join(3000);
      check(!draining.isAlive());
      check(completed.get() == 2);
      check(posts.get() == 2); // Side-effect POSTs run once each, never retried.
      check(Bridge.openHandles() == 0);
      check(!owner.hasPending());
    } finally {
      release.countDown();
      owner.close();
      owner.leave();
    }
  }

  static void callbackFailureClosesBody() throws Throwable {
    AtomicBoolean closed = new AtomicBoolean();
    AtomicInteger failures = new AtomicInteger();
    OkHttpClient client =
        new OkHttpClient.Builder()
            .addInterceptor(chain -> {
              BufferedSource source =
                  Okio.buffer(
                      new ForwardingSource(new Buffer().writeUtf8("opaque")) {
                        public void close() throws IOException {
                          closed.set(true);
                          super.close();
                        }
                      });
              return new Response.Builder()
                  .request(chain.request())
                  .protocol(Protocol.HTTP_1_1)
                  .code(200)
                  .message("fixture")
                  .body(ResponseBody.create(null, 6, source))
                  .build();
            })
            .build();
    BrowserCall.Operation owner = BrowserCall.beginOperation("failure", "generation", "token-2");
    owner.enter();
    try {
      call(client, "https://fixture.invalid/")
          .enqueue(
              new Callback() {
                public void onResponse(Call call, Response response) throws IOException {
                  throw new IOException("callback failed");
                }

                public void onFailure(Call call, IOException error) {
                  failures.incrementAndGet();
                }
              });
      try {
        owner.drain();
        throw new AssertionError("Expected callback failure");
      } catch (IOException expected) {
        check(expected.getMessage().equals("callback failed"));
      }
      check(closed.get());
      check(failures.get() == 0); // onResponse failure must not deliver a second callback.
      check(!owner.hasPending());
    } finally {
      owner.close();
      owner.leave();
    }
  }

  static void postFailureIsDeliveredOnce(String endpoint, AtomicInteger posts) throws Throwable {
    OkHttpClient client = new OkHttpClient.Builder().retryOnConnectionFailure(true).build();
    BrowserCall.Operation owner =
        BrowserCall.beginOperation("failed-post", "generation", "post-token");
    AtomicInteger responses = new AtomicInteger(), failures = new AtomicInteger();
    owner.enter();
    try {
      Bridge.failNextRequest(new Bridge.NetworkFailure("before response headers"));
      call(client, endpoint)
          .enqueue(
              new Callback() {
                public void onResponse(Call call, Response response) {
                  responses.incrementAndGet();
                }

                public void onFailure(Call call, IOException error) {
                  check(error instanceof Bridge.NetworkFailure);
                  failures.incrementAndGet();
                }
              });
      owner.drain();
      check(responses.get() == 0);
      check(failures.get() == 1);
      check(posts.get() == 2); // A retried request would reach the server.
      check(Bridge.openHandles() == 0);
    } finally {
      owner.close();
      owner.leave();
    }
  }

  static void timeoutAndOldOwner(String endpoint, AtomicInteger posts) throws Throwable {
    OkHttpClient client = new OkHttpClient.Builder().build();
    BrowserCall.Operation old =
        BrowserCall.beginOperation("same-rpc", "same-generation", "old-token");
    CountDownLatch entered = new CountDownLatch(1),
        release = new CountDownLatch(1),
        finished = new CountDownLatch(1);
    AtomicReference<Throwable> lateFailure = new AtomicReference<>();
    old.enter();
    Runnable lateChild =
        BrowserCall.bindOperation(() -> {
          throw new AssertionError("Expired child ran");
        });
    call(client, endpoint)
        .enqueue(
            new Callback() {
              public void onResponse(Call call, Response response) throws IOException {
                entered.countDown();
                await(release);
                try {
                  EnqueueTest.call(client, endpoint).enqueue(callback(new AtomicInteger()));
                } catch (Throwable expected) {
                  lateFailure.set(expected);
                } finally {
                  finished.countDown();
                }
              }

              public void onFailure(Call call, IOException error) {
                throw new AssertionError(error);
              }
            });
    try {
      await(entered);
      long started = System.nanoTime();
      try {
        old.drain(25);
        throw new AssertionError("Expected bounded drain timeout");
      } catch (InterruptedIOException expected) {
        check(expected.getMessage().contains("drain deadline"));
      }
      check(TimeUnit.NANOSECONDS.toMillis(System.nanoTime() - started) < 1000);
      check(old.hasPending()); // TeaHost must classify this as runtime_lost.
    } finally {
      old.close();
      old.leave();
    }
    BrowserCall.Operation next =
        BrowserCall.beginOperation("same-rpc", "same-generation", "new-token");
    CountDownLatch resumedEntered = new CountDownLatch(1), resumedRelease = new CountDownLatch(1);
    AtomicInteger resumedCallbacks = new AtomicInteger();
    next.enter();
    try {
      try {
        lateChild.run();
        throw new AssertionError("Expired child adopted next operation");
      } catch (IllegalStateException expected) {
        check(expected.getCause() instanceof InterruptedIOException);
      }
      release.countDown();
      await(finished);
      check(lateFailure.get() instanceof IllegalStateException);
      check(posts.get() == 3);
      call(client, endpoint)
          .enqueue(
              new Callback() {
                public void onResponse(Call call, Response response) throws IOException {
                  resumedEntered.countDown();
                  await(resumedRelease);
                  resumedCallbacks.incrementAndGet();
                }

                public void onFailure(Call call, IOException error) {
                  throw new AssertionError(error);
                }
              });
      await(resumedEntered);
      check(next.hasPending()); // The failed bound child must restore the caller's owner.
      resumedRelease.countDown();
      next.drain();
      check(!next.hasPending());
      check(resumedCallbacks.get() == 1);
      check(posts.get() == 4);
    } finally {
      release.countDown();
      resumedRelease.countDown();
      next.close();
      next.leave();
    }
  }

  static void creationDoesNotBindExecution(String endpoint, AtomicInteger posts) throws Throwable {
    OkHttpClient client = new OkHttpClient.Builder().build();
    BrowserCall.Operation creator =
        BrowserCall.beginOperation("create", "generation", "create-token");
    Call foreground, background;
    creator.enter();
    try {
      foreground = call(client, endpoint);
      background = call(client, endpoint);
      check(!foreground.isExecuted() && !background.isExecuted());
      creator.drain();
    } finally {
      creator.close();
      creator.leave();
    }
    BrowserCall.Operation executor =
        BrowserCall.beginOperation("execute", "generation", "execute-token");
    AtomicInteger callbacks = new AtomicInteger();
    int previousPosts = posts.get();
    executor.enter();
    try {
      try (Response response = foreground.execute()) {
        check(response.code() == 200);
        check(response.body().bytes().length > 0);
      }
      background.enqueue(callback(callbacks));
      executor.drain();
      check(foreground.isExecuted() && background.isExecuted());
      check(callbacks.get() == 1);
      check(posts.get() == previousPosts + 2);
      check(Bridge.openHandles() == 0);
    } finally {
      executor.close();
      executor.leave();
    }
  }

  public static void main(String[] args) throws Throwable {
    AtomicInteger posts = new AtomicInteger();
    HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    server.createContext(
        "/view",
        exchange -> {
          check(exchange.getRequestMethod().equals("POST"));
          posts.incrementAndGet();
          exchange.getRequestBody().readAllBytes();
          byte[] body = "opaque encoded bytes".getBytes(java.nio.charset.StandardCharsets.UTF_8);
          exchange.sendResponseHeaders(200, body.length);
          exchange.getResponseBody().write(body);
          exchange.close();
        });
    server.start();
    try {
      String endpoint = "http://127.0.0.1:" + server.getAddress().getPort() + "/view";
      nestedBeforeDelivery(endpoint, posts);
      callbackFailureClosesBody();
      postFailureIsDeliveredOnce(endpoint, posts);
      timeoutAndOldOwner(endpoint, posts);
      creationDoesNotBindExecution(endpoint, posts);
      System.out.println("EnqueueTest: " + assertions + " assertions passed");
    } finally {
      Bridge.closeTransport();
      server.stop(0);
    }
  }
}
