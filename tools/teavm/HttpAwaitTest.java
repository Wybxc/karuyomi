package prototype;

import com.sun.net.httpserver.HttpServer;
import eu.kanade.tachiyomi.network.HttpException;
import eu.kanade.tachiyomi.network.OkHttpExtensionsKt;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import kotlin.coroutines.CoroutineContext;
import kotlin.coroutines.EmptyCoroutineContext;
import kotlin.jvm.functions.Function0;
import kotlin.reflect.KClass;
import kotlinx.coroutines.BuildersKt;
import kotlinx.coroutines.CoroutineDispatcher;
import kotlinx.coroutines.CoroutineStart;
import kotlinx.coroutines.Deferred;
import kotlinx.coroutines.GlobalScope;
import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.EventListener;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Protocol;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.ResponseBody;
import okio.Buffer;
import okio.BufferedSource;
import okio.ForwardingSource;
import okio.Okio;
import okio.Timeout;

/** JVM oracle for the actual seed await callbacks and the product HTTP body owner. */
public final class HttpAwaitTest {
  private static int assertions;

  private static synchronized void check(boolean value, String message) {
    assertions++;
    if (!value) throw new AssertionError("HTTP await assertion " + assertions + ": " + message);
  }

  private static void await(CountDownLatch latch) throws IOException {
    try {
      if (!latch.await(3, TimeUnit.SECONDS)) throw new IOException("Fixture latch timed out");
    } catch (InterruptedException error) {
      Thread.currentThread().interrupt();
      throw new InterruptedIOException("Fixture interrupted");
    }
  }

  private static final class QueuedDispatcher extends CoroutineDispatcher {
    private final ArrayDeque<Runnable> queued = new ArrayDeque<>();

    public void dispatch(CoroutineContext context, Runnable block) {
      synchronized (queued) {
        queued.add(block);
      }
    }

    void step() {
      Runnable next;
      synchronized (queued) {
        next = queued.poll();
      }
      if (next == null) throw new AssertionError("No queued coroutine");
      next.run();
    }

    void drain() {
      for (int index = 0; index < 100; index++) {
        Runnable next;
        synchronized (queued) {
          next = queued.poll();
        }
        if (next == null) return;
        next.run();
      }
      throw new AssertionError("Coroutine queue did not settle");
    }
  }

  /** execute is deliberately unusable: only the seed enqueue path can pass this oracle. */
  private static final class GuardCall implements Call {
    private final Call delegate;
    final CountDownLatch returned = new CountDownLatch(1);
    final AtomicInteger enqueues = new AtomicInteger();
    final AtomicInteger cancels = new AtomicInteger();
    final AtomicInteger responses = new AtomicInteger();
    final AtomicInteger failures = new AtomicInteger();

    GuardCall(Call delegate) {
      this.delegate = delegate;
    }

    public Response execute() {
      throw new AssertionError("Seed await must never call execute");
    }

    public void enqueue(Callback callback) {
      enqueues.incrementAndGet();
      delegate.enqueue(
          new Callback() {
            public void onFailure(Call call, IOException error) {
              failures.incrementAndGet();
              try {
                callback.onFailure(GuardCall.this, error);
              } finally {
                returned.countDown();
              }
            }

            public void onResponse(Call call, Response response) throws IOException {
              responses.incrementAndGet();
              try {
                callback.onResponse(GuardCall.this, response);
              } finally {
                returned.countDown();
              }
            }
          });
    }

    public void cancel() {
      cancels.incrementAndGet();
      delegate.cancel();
    }

    public Request request() {
      return delegate.request();
    }

    public boolean isExecuted() {
      return delegate.isExecuted();
    }

    public boolean isCanceled() {
      return delegate.isCanceled();
    }

    public Timeout timeout() {
      return delegate.timeout();
    }

    public void addEventListener(EventListener listener) {
      delegate.addEventListener(listener);
    }

    public <T> T tag(KClass<T> type) {
      return delegate.tag(type);
    }

    public <T> T tag(Class<? extends T> type) {
      return delegate.tag(type);
    }

    public <T> T tag(KClass<T> type, Function0<? extends T> create) {
      return delegate.tag(type, create);
    }

    public <T> T tag(Class<T> type, Function0<? extends T> create) {
      return delegate.tag(type, create);
    }

    public Call clone() {
      return new GuardCall(delegate.clone());
    }
  }

  private interface CheckedAction {
    void run() throws Throwable;
  }

  private static final class Worker {
    final CompletableFuture<Void> finished = new CompletableFuture<>();
    final Thread thread;

    Worker(String name, CheckedAction action) {
      thread =
          new Thread(
              () -> {
                try {
                  action.run();
                  finished.complete(null);
                } catch (Throwable error) {
                  finished.completeExceptionally(error);
                }
              },
              name);
      // A failing oracle must not leave the runner held by a fixture gate.
      thread.setDaemon(true);
      thread.start();
    }

    void join() throws Exception {
      finished.get(3, TimeUnit.SECONDS);
      thread.join(3000);
      check(!thread.isAlive(), "fixture worker settled");
    }
  }

  private static Call call(OkHttpClient client, String endpoint) {
    return BrowserCall.create(
        client,
        new Request.Builder()
            .url(endpoint)
            .post(RequestBody.create(MediaType.get("text/plain"), "once"))
            .build());
  }

  private static GuardCall guarded(OkHttpClient client, String endpoint) {
    return new GuardCall(call(client, endpoint));
  }

  private static Deferred<Response> start(
      QueuedDispatcher queue, GuardCall request, boolean requireSuccess) {
    return BuildersKt.async(
        GlobalScope.INSTANCE,
        queue,
        CoroutineStart.DEFAULT,
        (scope, continuation) ->
            requireSuccess
                ? OkHttpExtensionsKt.awaitSuccess(request, continuation)
                : OkHttpExtensionsKt.await(request, continuation));
  }

  private static <T> T value(Deferred<T> deferred) throws InterruptedException {
    check(deferred.isCompleted(), "reading an already completed Deferred");
    return BuildersKt.runBlocking(
        HostCoroutines.entryContext(EmptyCoroutineContext.INSTANCE),
        (scope, continuation) -> deferred.await(continuation));
  }

  private static BrowserCall.Operation begin(String name) {
    BrowserCall.Operation owner =
        BrowserCall.beginOperation(name, "http-await-generation", name + "-token");
    owner.enter();
    return owner;
  }

  private static void delayedConsumer(String endpoint) throws Throwable {
    BrowserCall.Operation owner = begin("delayed-consumer");
    try {
      QueuedDispatcher queue = new QueuedDispatcher();
      GuardCall request = guarded(new OkHttpClient.Builder().build(), endpoint);
      Deferred<Response> task = start(queue, request, true);
      queue.step();
      await(request.returned);
      check(request.enqueues.get() == 1, "exactly one enqueue after await suspended");
      check(!task.isCompleted(), "callback returned before the consumer is resumed");
      check(Bridge.openHandles() == 1, "callback hands the live body to the consumer");
      check(owner.hasPending(), "suspended official coroutine retains its operation lease");
      queue.drain();
      try (Response response = value(task)) {
        check(response.body().string().equals("encoded bytes"), "delayed consumer reads full body");
      }
      check(Bridge.openHandles() == 0, "consumer close releases the transport handle");
      owner.drain();
      check(!owner.hasPending(), "successful consumer leaves no coroutine or callback lease");
    } finally {
      owner.close();
      owner.leave();
    }
  }

  private static void cancellationAfterDelivery(String endpoint) throws Throwable {
    BrowserCall.Operation owner = begin("cancel-delivered");
    try {
      QueuedDispatcher queue = new QueuedDispatcher();
      GuardCall request = guarded(new OkHttpClient.Builder().build(), endpoint);
      Deferred<Response> task = start(queue, request, true);
      queue.step();
      await(request.returned);
      check(
          Bridge.openHandles() == 1 && !task.isCompleted(),
          "cancellation gate is after onResponse");
      task.cancel(null);
      queue.drain();
      check(
          task.isCompleted() && task.isCancelled(), "official cancellation completes the Deferred");
      check(
          request.enqueues.get() == 1 && request.cancels.get() == 1,
          "seed cancels the same Call once");
      check(Bridge.openHandles() == 0, "undelivered resumed response is closed on cancellation");
      owner.drain();
    } finally {
      owner.close();
      owner.leave();
    }
  }

  private static void cancellationBeforeDelivery(String endpoint) throws Throwable {
    BrowserCall.Operation owner = begin("cancel-before-delivery");
    CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
    GuardCall request = null;
    try {
      OkHttpClient client =
          new OkHttpClient.Builder()
              .addInterceptor(chain -> {
                entered.countDown();
                await(release);
                return chain.proceed(chain.request());
              })
              .build();
      QueuedDispatcher queue = new QueuedDispatcher();
      request = guarded(client, endpoint);
      Deferred<Response> task = start(queue, request, true);
      queue.step();
      await(entered);
      task.cancel(null);
      queue.drain();
      check(
          task.isCompleted() && task.isCancelled(), "cancellation completes before HTTP delivery");
      check(request.cancels.get() == 1, "seed cancels a pending enqueue once");
      release.countDown();
      await(request.returned);
      owner.drain();
      check(Bridge.openHandles() == 0, "late HTTP completion cannot leak a cancelled response");
    } finally {
      release.countDown();
      if (request != null) await(request.returned);
      owner.close();
      owner.leave();
    }
  }

  private static void failureAndNon2xx(String endpoint) throws Throwable {
    BrowserCall.Operation owner = begin("non-success");
    try {
      QueuedDispatcher queue = new QueuedDispatcher();
      GuardCall request =
          guarded(new OkHttpClient.Builder().build(), endpoint.replace("/ok", "/missing"));
      Deferred<Response> task = start(queue, request, true);
      queue.step();
      await(request.returned);
      check(Bridge.openHandles() == 1, "non-2xx body is held until awaitSuccess resumes");
      queue.drain();
      try {
        value(task);
        throw new AssertionError("awaitSuccess accepted a non-2xx response");
      } catch (HttpException expected) {
        check(request.enqueues.get() == 1, "non-2xx uses the seed enqueue path");
      }
      check(Bridge.openHandles() == 0, "awaitSuccess closes the rejected response");
      owner.drain();
    } finally {
      owner.close();
      owner.leave();
    }

    owner = begin("io-failure");
    try {
      IOException expected = new IOException("exact seed await IO failure");
      Bridge.failNextRequest(expected);
      QueuedDispatcher queue = new QueuedDispatcher();
      GuardCall request = guarded(new OkHttpClient.Builder().build(), endpoint);
      Deferred<Response> task = start(queue, request, false);
      queue.step();
      await(request.returned);
      queue.drain();
      try {
        value(task);
        throw new AssertionError("await swallowed an IOException");
      } catch (Throwable actual) {
        check(actual == expected, "seed await preserves the original IOException");
      }
      check(
          request.enqueues.get() == 1 && Bridge.openHandles() == 0,
          "failed request has no retry or handle leak");
      owner.drain();
    } finally {
      owner.close();
      owner.leave();
    }
  }

  private static OkHttpClient throwingClient(Throwable failure, AtomicInteger attempts) {
    return new OkHttpClient.Builder()
        .addInterceptor(chain -> {
          attempts.incrementAndGet();
          if (failure instanceof RuntimeException error) throw error;
          if (failure instanceof Error error) throw error;
          throw new AssertionError("Expected a non-IO fixture failure", failure);
        })
        .build();
  }

  private static void ownerFailure(BrowserCall.Operation owner, Throwable expected)
      throws Throwable {
    try {
      owner.drain(1000);
      throw new AssertionError("Owner swallowed an execution or callback failure");
    } catch (Throwable actual) {
      check(actual == expected, "owner drain preserves the original failure");
    }
    check(!owner.hasPending(), "failed call and coroutine leave no pending owner work");
    check(Bridge.openHandles() == 0, "failed execution leaves no HTTP handle");
  }

  private static void nonIoExecutionFailures(String endpoint) throws Throwable {
    for (boolean requireSuccess : new boolean[] {false, true}) {
      for (Throwable expected :
          new Throwable[] {
            new IllegalStateException("interceptor runtime failure"),
            new AssertionError("interceptor error")
          }) {
        BrowserCall.Operation owner = begin("non-io-await");
        try {
          AtomicInteger attempts = new AtomicInteger();
          QueuedDispatcher queue = new QueuedDispatcher();
          GuardCall request = guarded(throwingClient(expected, attempts), endpoint);
          Deferred<Response> task = start(queue, request, requireSuccess);
          queue.step();
          await(request.returned);
          queue.drain();
          check(task.isCompleted(), "non-IO failure resumes the actual seed await immediately");
          try {
            value(task);
            throw new AssertionError("Seed await swallowed a non-IO execution failure");
          } catch (Throwable actual) {
            check(
                actual instanceof IOException && actual.getCause() == expected,
                "await failure retains the interceptor cause");
          }
          ownerFailure(owner, expected);
          check(
              attempts.get() == 1
                  && request.enqueues.get() == 1
                  && request.failures.get() == 1
                  && request.responses.get() == 0,
              "await receives exactly one failure without a retry or response");
          check(request.isCanceled(), "fatal execution cancels its call");
        } finally {
          owner.close();
          owner.leave();
        }
      }
    }

    for (boolean throwFromCallback : new boolean[] {false, true}) {
      for (Throwable expected :
          new Throwable[] {
            new IllegalStateException("direct interceptor runtime failure"),
            new AssertionError("direct interceptor error")
          }) {
        BrowserCall.Operation owner = begin("non-io-enqueue");
        try {
          AtomicInteger attempts = new AtomicInteger(), responses = new AtomicInteger();
          AtomicInteger failures = new AtomicInteger();
          AtomicReference<IOException> delivered = new AtomicReference<>();
          CountDownLatch returned = new CountDownLatch(1);
          AssertionError callbackFailure = new AssertionError("failure callback error");
          Call request = call(throwingClient(expected, attempts), endpoint);
          request.enqueue(
              new Callback() {
                public void onFailure(Call call, IOException error) {
                  failures.incrementAndGet();
                  delivered.set(error);
                  returned.countDown();
                  if (throwFromCallback) throw callbackFailure;
                }

                public void onResponse(Call call, Response response) {
                  responses.incrementAndGet();
                  returned.countDown();
                }
              });
          await(returned);
          ownerFailure(owner, expected);
          check(
              delivered.get() != null && delivered.get().getCause() == expected,
              "direct enqueue retains the original interceptor cause");
          check(
              attempts.get() == 1 && failures.get() == 1 && responses.get() == 0,
              "direct enqueue receives at most one terminal callback");
          check(request.isCanceled(), "direct execution failure cancels its call");
          if (throwFromCallback)
            check(
                expected.getSuppressed().length == 1
                    && expected.getSuppressed()[0] == callbackFailure,
                "callback failure is retained without replacing the execution failure");
        } finally {
          owner.close();
          owner.leave();
        }
      }
    }
  }

  private static void repeatedBodySourceFailure(String endpoint) throws Throwable {
    for (boolean requireSuccess : new boolean[] {false, true}) {
      for (Throwable expected :
          new Throwable[] {
            new IllegalStateException("repeated body source runtime failure"),
            new AssertionError("repeated body source error")
          }) {
        BrowserCall.Operation owner = begin("repeated-body-source");
        try {
          AtomicInteger attempts = new AtomicInteger(), sources = new AtomicInteger();
          OkHttpClient client =
              new OkHttpClient.Builder()
                  .addInterceptor(chain -> {
                    attempts.incrementAndGet();
                    return synthetic(
                        chain.request(),
                        new ResponseBody() {
                          public MediaType contentType() {
                            return null;
                          }

                          public long contentLength() {
                            return 0;
                          }

                          public BufferedSource source() {
                            sources.incrementAndGet();
                            if (expected instanceof RuntimeException error) throw error;
                            throw (Error) expected;
                          }
                        });
                  })
                  .build();
          QueuedDispatcher queue = new QueuedDispatcher();
          GuardCall request = guarded(client, endpoint);
          Deferred<Response> task = start(queue, request, requireSuccess);
          queue.step();
          await(request.returned);
          queue.drain();
          try {
            value(task);
            throw new AssertionError("Seed await swallowed a body source failure");
          } catch (Throwable actual) {
            check(
                actual instanceof IOException && actual.getCause() == expected,
                "body source failure survives identical cleanup failure as the await cause");
          }
          ownerFailure(owner, expected);
          check(
              attempts.get() == 1
                  && request.enqueues.get() == 1
                  && request.failures.get() == 1
                  && request.responses.get() == 0,
              "body source failure delivers one terminal failure without retry");
          check(
              sources.get() == 2,
              "body wrapping and cleanup both encounter the same source failure");
          check(
              expected.getSuppressed().length == 0,
              "identical cleanup failure is not self-suppressed");
          check(request.isCanceled(), "body source failure cancels its call");
        } finally {
          owner.close();
          owner.leave();
        }
      }
    }
  }

  private static void nonIoResponseCallbackFailures(String endpoint) throws Throwable {
    for (Throwable expected :
        new Throwable[] {
          new IllegalStateException("response callback runtime failure"),
          new AssertionError("response callback error")
        }) {
      BrowserCall.Operation owner = begin("non-io-response-callback");
      AtomicInteger closes = new AtomicInteger(), responses = new AtomicInteger();
      AtomicInteger failures = new AtomicInteger();
      try {
        OkHttpClient client =
            new OkHttpClient.Builder()
                .addInterceptor(chain ->
                    synthetic(
                        chain.request(),
                        ResponseBody.create(
                            null,
                            6,
                            Okio.buffer(
                                new ForwardingSource(new Buffer().writeUtf8("opaque")) {
                                  public void close() throws IOException {
                                    closes.incrementAndGet();
                                    super.close();
                                  }
                                }))))
                .build();
        call(client, endpoint)
            .enqueue(
                new Callback() {
                  public void onFailure(Call call, IOException error) {
                    failures.incrementAndGet();
                  }

                  public void onResponse(Call call, Response response) {
                    responses.incrementAndGet();
                    if (expected instanceof RuntimeException error) throw error;
                    throw (Error) expected;
                  }
                });
        ownerFailure(owner, expected);
        check(
            responses.get() == 1 && failures.get() == 0,
            "a throwing response callback never receives a second failure callback");
        check(closes.get() == 1, "a throwing response callback closes its body exactly once");
      } finally {
        owner.close();
        owner.leave();
      }
    }
  }

  private static void replacedBodyAndLimits(String endpoint) throws Throwable {
    BrowserCall.Operation owner = begin("response-limits");
    try {
      AtomicInteger closed = new AtomicInteger();
      OkHttpClient client =
          new OkHttpClient.Builder()
              .addInterceptor(chain -> {
                Response response = chain.proceed(chain.request());
                // Third-party interceptor intentionally leaves the original transport body open.
                BufferedSource replacement =
                    Okio.buffer(
                        new ForwardingSource(new Buffer().writeUtf8("replacement")) {
                          public void close() throws IOException {
                            closed.incrementAndGet();
                            super.close();
                          }
                        });
                return response
                    .newBuilder()
                    .body(ResponseBody.create(null, 11, replacement))
                    .build();
              })
              .build();
      for (int index = 0; index < 70; index++) {
        try (Response response = call(client, endpoint).execute()) {
          check(
              response.body().string().equals("replacement"),
              "interceptor replacement remains visible");
        }
        check(
            Bridge.openHandles() == 0,
            "replacement close immediately releases the original handle");
      }
      check(closed.get() == 70, "closed responses do not exhaust a cumulative resource budget");
      List<Response> held = new ArrayList<>();
      try {
        for (int index = 0; index < 64; index++) held.add(call(client, endpoint).execute());
        check(Bridge.openHandles() == 64, "64 concurrently held responses are permitted");
        try {
          call(client, endpoint).execute();
          throw new AssertionError("65th outstanding response must fail explicitly");
        } catch (IOException expected) {
          check(
              expected.getMessage().equals("Too many open Source HTTP responses"),
              "65th response reports its resource limit");
        }
        check(Bridge.openHandles() == 64, "rejected response releases only its own handle");
        held.remove(0).close();
        check(Bridge.openHandles() == 63, "one closed response frees a slot immediately");
        held.add(call(client, endpoint).execute());
        check(Bridge.openHandles() == 64, "freed response slot can be reused");
      } finally {
        for (Response response : held) response.close();
      }
      check(Bridge.openHandles() == 0, "all outstanding responses release their handles");
      owner.drain();
    } finally {
      owner.close();
      owner.leave();
    }
  }

  private static Response synthetic(Request request, ResponseBody body) {
    return new Response.Builder()
        .request(request)
        .protocol(Protocol.HTTP_1_1)
        .code(200)
        .message("fixture")
        .body(body)
        .build();
  }

  private abstract static class EmptyBody extends ResponseBody {
    private final Buffer source = new Buffer();

    public MediaType contentType() {
      return null;
    }

    public long contentLength() {
      return 0;
    }

    public BufferedSource source() {
      return source;
    }
  }

  private static void cleanupBeforeAck(String endpoint) throws Throwable {
    BrowserCall.Operation owner = begin("cleanup-before-ack");
    try {
      List<String> events = new ArrayList<>();
      OkHttpClient client =
          new OkHttpClient.Builder()
              .addInterceptor(chain ->
                  synthetic(
                      chain.request(),
                      new EmptyBody() {
                        public void close() {
                          events.add("close");
                        }
                      }))
              .build();
      call(client, endpoint).execute();
      check(events.isEmpty(), "abandoned response stays open until drain");
      owner.drain();
      events.add("ack");
      check(events.equals(List.of("close", "ack")), "drain closes the response before ACK");
    } finally {
      owner.close();
      owner.leave();
    }

    owner = begin("cleanup-failure");
    try {
      AtomicInteger closed = new AtomicInteger();
      IllegalStateException expected = new IllegalStateException("original close failed");
      OkHttpClient client =
          new OkHttpClient.Builder()
              .addInterceptor(chain ->
                  synthetic(
                      chain.request(),
                      new EmptyBody() {
                        public void close() {
                          closed.incrementAndGet();
                          throw expected;
                        }
                      }))
              .build();
      call(client, endpoint).execute();
      call(client, endpoint).execute();
      try {
        owner.drain();
        throw new AssertionError("Response cleanup failure must prevent ACK");
      } catch (Throwable actual) {
        check(actual == expected, "drain preserves the first close failure");
      }
      check(closed.get() == 2, "one close failure does not skip other responses");
      check(Bridge.openHandles() == 0, "failing cleanup leaves no HTTP handles");
    } finally {
      owner.close();
      owner.leave();
    }
  }

  private static void closingConsumerMustFinishBeforeAck(String endpoint) throws Throwable {
    BrowserCall.Operation owner = begin("consumer-close-gate");
    CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
    List<String> events = Collections.synchronizedList(new ArrayList<>());
    Worker consumer = null, draining = null;
    try {
      OkHttpClient client =
          new OkHttpClient.Builder()
              .addInterceptor(chain -> {
                Response response = chain.proceed(chain.request());
                return response
                    .newBuilder()
                    .body(
                        new EmptyBody() {
                          public void close() {
                            entered.countDown();
                            try {
                              await(release);
                            } catch (IOException error) {
                              throw new IllegalStateException(error);
                            }
                            events.add("close");
                          }
                        })
                    .build();
              })
              .build();
      Response response = call(client, endpoint).execute();
      consumer = new Worker("http-await-consumer-close", response::close);
      await(entered);
      check(!owner.hasPending(), "this close is not covered by a callback or coroutine lease");
      draining =
          new Worker(
              "http-await-drain",
              () -> {
                owner.drain(2000);
                events.add("ack");
              });
      long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(1);
      boolean closed = false;
      while (System.nanoTime() < deadline) {
        try {
          owner.checkOpen();
          Thread.yield();
        } catch (InterruptedIOException expected) {
          closed = true;
          break;
        }
      }
      check(closed, "drain reached the resource cleanup phase");
      boolean waiting = false;
      deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(1);
      while (System.nanoTime() < deadline) {
        if (draining.finished.isDone()) break;
        if (draining.thread.getState() == Thread.State.TIMED_WAITING) {
          waiting = true;
          break;
        }
        Thread.yield();
      }
      check(waiting, "drain waits for the original close instead of completing early");
      check(!draining.finished.isDone() && events.isEmpty(), "an in-flight close prevents ACK");
      release.countDown();
      consumer.join();
      draining.join();
      check(events.equals(List.of("close", "ack")), "the original close finishes before ACK");
      check(Bridge.openHandles() == 0, "pending consumer close releases the original handle");
    } finally {
      release.countDown();
      if (consumer != null) consumer.join();
      if (draining != null) draining.join();
      owner.close();
      owner.leave();
    }
  }

  /**
   * The deadline bounds waiting for an already-running close, not arbitrary synchronous close code.
   */
  private static void cleanupTimeoutKeepsPendingResource(String endpoint) throws Throwable {
    BrowserCall.Operation owner = begin("consumer-close-timeout");
    CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
    AtomicInteger closed = new AtomicInteger();
    Worker consumer = null;
    try {
      OkHttpClient client =
          new OkHttpClient.Builder()
              .addInterceptor(chain -> {
                Response response = chain.proceed(chain.request());
                return response
                    .newBuilder()
                    .body(
                        new EmptyBody() {
                          public void close() {
                            entered.countDown();
                            try {
                              await(release);
                            } catch (IOException error) {
                              throw new IllegalStateException(error);
                            }
                            closed.incrementAndGet();
                          }
                        })
                    .build();
              })
              .build();
      Response response = call(client, endpoint).execute();
      consumer = new Worker("http-await-close-timeout", response::close);
      await(entered);
      check(
          !owner.hasPending(), "an open owner does not wait for retained responses as active work");
      try {
        owner.drain(25);
        throw new AssertionError("An unfinished response close must prevent ACK at the deadline");
      } catch (InterruptedIOException expected) {
        check(
            expected.getMessage().equals("HTTP response cleanup exceeded drain deadline"),
            "the original drain deadline bounds the resource cleanup wait");
      }
      check(owner.hasPending(), "cleanup timeout retains the runtime-discard signal");
      check(closed.get() == 0, "the original close remains at the gate after timeout");
      owner.close();
      check(owner.hasPending(), "owner close does not pretend an in-flight response was released");
      check(closed.get() == 0, "idempotent cancellation cannot finish another thread's close");
    } finally {
      release.countDown();
      try {
        if (consumer != null) consumer.join();
        check(Bridge.openHandles() == 0, "eventual close has no remaining transport handle");
        check(!owner.hasPending(), "actual response release clears the pending resource signal");
      } finally {
        owner.close();
        owner.leave();
      }
    }
  }

  /** Unit-level cleanup context contract, not a claim that two exported entries can be active. */
  private static void cleanupKeepsOriginalOwner(String endpoint) throws Throwable {
    BrowserCall.Operation old = begin("original-cleanup-owner");
    BrowserCall.Operation caller =
        new BrowserCall.Operation("caller-context", "generation", "caller-context-token");
    AtomicInteger closeCount = new AtomicInteger();
    AtomicReference<Throwable> denied = new AtomicReference<>();
    AtomicReference<BrowserCall.Operation> observed = new AtomicReference<>();
    try {
      OkHttpClient plain = new OkHttpClient.Builder().build();
      OkHttpClient client =
          new OkHttpClient.Builder()
              .addInterceptor(chain ->
                  synthetic(
                      chain.request(),
                      new EmptyBody() {
                        public void close() {
                          closeCount.incrementAndGet();
                          observed.set(BrowserCall.currentOperation());
                          try (Response ignored = call(plain, endpoint).execute()) {
                            // An expired owner's close callback must not borrow the caller.
                          } catch (Throwable error) {
                            denied.set(error);
                          }
                        }
                      }))
              .build();
      call(client, endpoint).execute();
      old.leave();
      caller.enter();
      old.close();
      check(
          closeCount.get() == 1 && observed.get() == old,
          "cleanup enters its original owner exactly once");
      check(
          denied.get() instanceof InterruptedIOException,
          "closed-owner cleanup cannot start HTTP under the caller");
      check(BrowserCall.currentOperation() == caller, "cleanup restores the caller context");
      try (Response response = call(plain, endpoint).execute()) {
        check(
            response.body().string().equals("encoded bytes"),
            "restored caller can still execute its own HTTP");
      }
      caller.drain();
      check(Bridge.openHandles() == 0, "cleanup context test has no leftover handles");
    } finally {
      old.close();
      caller.close();
      caller.leave();
    }
  }

  private static void identities(String corePath, String hostPath) throws Exception {
    Path core = Path.of(corePath).toRealPath();
    for (Class<?> type :
        new Class<?>[] {BuildersKt.class, GlobalScope.class, CoroutineDispatcher.class}) {
      Path actual =
          Path.of(type.getProtectionDomain().getCodeSource().getLocation().toURI()).toRealPath();
      check(actual.equals(core), "official core defines " + type.getName());
    }
    Path actualHost =
        Path.of(
                OkHttpExtensionsKt.class
                    .getProtectionDomain()
                    .getCodeSource()
                    .getLocation()
                    .toURI())
            .toRealPath();
    check(
        actualHost.equals(Path.of(hostPath).toRealPath()),
        "await comes from the patched seed host JAR");
  }

  public static void main(String[] args) throws Throwable {
    identities(args[0], args[1]);
    HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    server.createContext(
        "/",
        exchange -> {
          exchange.getRequestBody().readAllBytes();
          byte[] body = "encoded bytes".getBytes(StandardCharsets.UTF_8);
          exchange.sendResponseHeaders(
              exchange.getRequestURI().getPath().equals("/missing") ? 404 : 200, body.length);
          try (java.io.OutputStream output = exchange.getResponseBody()) {
            output.write(body);
          } finally {
            exchange.close();
          }
        });
    server.start();
    try {
      String endpoint = "http://127.0.0.1:" + server.getAddress().getPort() + "/ok";
      delayedConsumer(endpoint);
      cancellationAfterDelivery(endpoint);
      cancellationBeforeDelivery(endpoint);
      failureAndNon2xx(endpoint);
      nonIoExecutionFailures(endpoint);
      repeatedBodySourceFailure(endpoint);
      nonIoResponseCallbackFailures(endpoint);
      replacedBodyAndLimits(endpoint);
      cleanupBeforeAck(endpoint);
      closingConsumerMustFinishBeforeAck(endpoint);
      cleanupTimeoutKeepsPendingResource(endpoint);
      cleanupKeepsOriginalOwner(endpoint);
      System.out.println(
          "HttpAwaitTest: " + assertions + " assertions passed; actual seed await/awaitSuccess");
    } finally {
      Bridge.closeTransport();
      server.stop(0);
    }
  }
}
