package prototype;

import com.sun.net.httpserver.HttpServer;
import java.io.*;
import java.net.InetSocketAddress;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;
import kotlin.Unit;
import kotlin.coroutines.EmptyCoroutineContext;
import kotlinx.coroutines.*;
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

  static void boundBeforeRunMustDrain() throws Throwable {
    BrowserCall.Operation owner =
        BrowserCall.beginOperation("scheduled", "generation", "scheduled-token");
    AtomicBoolean completed = new AtomicBoolean();
    owner.enter();
    try {
      Runnable child = BrowserCall.bindOperation(() -> completed.set(true));
      try {
        owner.drain(25);
        throw new AssertionError("Drain completed before the bound child was even scheduled");
      } catch (InterruptedIOException expected) {
        check(expected.getMessage().contains("drain deadline"));
      }
      check(owner.hasPending());
      child.run();
      owner.drain();
      check(completed.get() && !owner.hasPending());
    } finally {
      owner.close();
      owner.leave();
    }
  }

  static CompletableFuture<Void> drainAsync(BrowserCall.Operation owner) {
    CompletableFuture<Void> result = new CompletableFuture<>();
    new Thread(
            () -> {
              try {
                owner.drain();
                result.complete(null);
              } catch (Throwable error) {
                result.completeExceptionally(error);
              }
            })
        .start();
    return result;
  }

  static void globalScopeIncludesPostHttpWork(String endpoint, AtomicInteger posts)
      throws Throwable {
    BrowserCall.Operation owner =
        BrowserCall.beginOperation("global", "generation", "global-token");
    CountDownLatch entered = new CountDownLatch(1),
        allowHttp = new CountDownLatch(1),
        writing = new CountDownLatch(1),
        allowWrite = new CountDownLatch(1);
    AtomicBoolean written = new AtomicBoolean(), completedCallback = new AtomicBoolean();
    int previousPosts = posts.get();
    owner.enter();
    try {
      Job task =
          BuildersKt.launch(
              GlobalScope.INSTANCE,
              Dispatchers.getIO(),
              CoroutineStart.DEFAULT,
              (scope, continuation) -> {
                entered.countDown();
                try {
                  await(allowHttp);
                  try (Response response =
                      call(new OkHttpClient.Builder().build(), endpoint).execute()) {
                    check(response.body().bytes().length > 0);
                  }
                  writing.countDown();
                  await(allowWrite);
                  written.set(true);
                  return Unit.INSTANCE;
                } catch (IOException error) {
                  throw GreenCoroutines.propagate(error);
                }
              });
      task.invokeOnCompletion(error -> {
        completedCallback.set(true);
        return Unit.INSTANCE;
      });
      await(entered);
      CompletableFuture<Void> delivered = drainAsync(owner);
      check(owner.hasPending() && !delivered.isDone());
      allowHttp.countDown();
      await(writing);
      check(Bridge.openHandles() == 0 && posts.get() == previousPosts + 1);
      check(!written.get() && !task.isCompleted() && owner.hasPending() && !delivered.isDone());
      allowWrite.countDown();
      delivered.get(3, TimeUnit.SECONDS);
      check(written.get() && task.isCompleted() && completedCallback.get());
      check(!owner.hasPending());
    } finally {
      allowHttp.countDown();
      allowWrite.countDown();
      owner.close();
      owner.leave();
    }
  }

  static void runningCancellationDoesNotFinishWork() throws Throwable {
    BrowserCall.Operation owner =
        BrowserCall.beginOperation("cancel-global", "generation", "cancel-token");
    CountDownLatch entered = new CountDownLatch(1), release = new CountDownLatch(1);
    AtomicBoolean finished = new AtomicBoolean();
    owner.enter();
    try {
      Job task =
          BuildersKt.launch(
              GlobalScope.INSTANCE,
              Dispatchers.getIO(),
              CoroutineStart.DEFAULT,
              (scope, continuation) -> {
                entered.countDown();
                try {
                  await(release);
                } catch (IOException error) {
                  throw GreenCoroutines.propagate(error);
                }
                finished.set(true);
                return Unit.INSTANCE;
              });
      await(entered);
      task.cancel(new CancellationException("cancelled by Source"));
      CompletableFuture<Void> delivered = drainAsync(owner);
      check(task.isCompleted() && task.isCancelled());
      check(owner.hasPending() && !delivered.isDone() && !finished.get());
      release.countDown();
      delivered.get(3, TimeUnit.SECONDS);
      check(finished.get() && !owner.hasPending());
    } finally {
      release.countDown();
      owner.close();
      owner.leave();
    }
  }

  static void lazyTaskKeepsOriginalOwner() throws Throwable {
    BrowserCall.Operation old = BrowserCall.beginOperation("lazy", "generation", "old-lazy-token");
    AtomicInteger bodies = new AtomicInteger();
    GreenCoroutines.Task<Unit> lazy;
    old.enter();
    try {
      lazy =
          new GreenCoroutines.Task<>(
              GlobalScope.INSTANCE,
              EmptyCoroutineContext.INSTANCE,
              CoroutineStart.LAZY,
              (scope, continuation) -> {
                bodies.incrementAndGet();
                return Unit.INSTANCE;
              });
      check(!old.hasPending());
      old.drain();
    } finally {
      old.close();
      old.leave();
    }
    BrowserCall.Operation next = BrowserCall.beginOperation("lazy", "generation", "new-lazy-token");
    next.enter();
    try {
      try {
        lazy.start();
        throw new AssertionError("Lazy task adopted a later Source operation");
      } catch (IllegalStateException expected) {
        check(expected.getMessage().equals("Source operation has ended"));
      }
      check(lazy.isCompleted() && !lazy.isActive() && bodies.get() == 0 && !next.hasPending());
      try {
        lazy.value();
        throw new AssertionError("Expired lazy waiter was not completed with failure");
      } catch (IllegalStateException expected) {
        check(expected.getMessage().equals("Source operation has ended"));
      }
      GreenCoroutines.Task<Unit> cancelled =
          new GreenCoroutines.Task<>(
              GlobalScope.INSTANCE,
              EmptyCoroutineContext.INSTANCE,
              CoroutineStart.LAZY,
              (scope, continuation) -> {
                throw new AssertionError("Cancelled lazy body ran");
              });
      cancelled.cancel(new CancellationException("never started"));
      check(!cancelled.start() && cancelled.isCompleted() && !next.hasPending());
      next.drain();
    } finally {
      next.close();
      next.leave();
    }
  }

  static void expiredCompletionCannotAdoptAnotherOwner(String endpoint, AtomicInteger posts)
      throws Throwable {
    BrowserCall.Operation old =
        BrowserCall.beginOperation("lazy-callback", "generation", "old-callback-token");
    AtomicInteger completionCalls = new AtomicInteger(), childCalls = new AtomicInteger();
    GreenCoroutines.Task<Unit> lazy;
    old.enter();
    try {
      lazy =
          new GreenCoroutines.Task<>(
              GlobalScope.INSTANCE,
              EmptyCoroutineContext.INSTANCE,
              CoroutineStart.LAZY,
              (scope, continuation) -> Unit.INSTANCE);
      lazy.invokeOnCompletion(error -> {
        completionCalls.incrementAndGet();
        try (Response response = call(new OkHttpClient.Builder().build(), endpoint).execute()) {
          check(response.code() == 200);
        } catch (IOException failure) {
          throw GreenCoroutines.propagate(failure);
        }
        BuildersKt.launch(
            GlobalScope.INSTANCE,
            Dispatchers.getIO(),
            CoroutineStart.DEFAULT,
            (scope, continuation) -> {
              childCalls.incrementAndGet();
              return Unit.INSTANCE;
            });
        return Unit.INSTANCE;
      });
      old.drain();
    } finally {
      old.close();
      old.leave();
    }
    BrowserCall.Operation next =
        BrowserCall.beginOperation("lazy-callback", "generation", "new-callback-token");
    int previousPosts = posts.get();
    next.enter();
    try {
      try {
        lazy.start();
        throw new AssertionError("Expired lazy task started");
      } catch (IllegalStateException expected) {
        check(lazy.isCompleted());
      }
      check(completionCalls.get() == 0 && childCalls.get() == 0 && posts.get() == previousPosts);
      check(!next.hasPending());
      try {
        lazy.invokeOnCompletion(error -> {
          completionCalls.incrementAndGet();
          return Unit.INSTANCE;
        });
        throw new AssertionError("Expired immediate completion callback ran under another owner");
      } catch (IllegalStateException expected) {
        check(expected.getCause() instanceof InterruptedIOException);
      }
      check(completionCalls.get() == 0 && !next.hasPending());
      next.drain();
    } finally {
      next.close();
      next.leave();
    }
  }

  static void workAndHttpHaveIndependentBudgets() throws Throwable {
    BrowserCall.Operation owner =
        BrowserCall.beginOperation("work-limit", "generation", "limit-token");
    java.util.List<BrowserCall.BoundOperation> work = new java.util.ArrayList<>();
    java.util.List<BrowserCall> http = new java.util.ArrayList<>();
    owner.enter();
    try {
      for (int index = 0; index < 64; index++) work.add(BrowserCall.bindOperation(() -> {}));
      try {
        BrowserCall.bindOperation(() -> {});
        throw new AssertionError("Unbounded Source work accepted");
      } catch (IllegalStateException expected) {
        check(expected.getMessage().contains("background Source tasks"));
      }
      GreenCoroutines.Task<Unit> overflow =
          new GreenCoroutines.Task<>(
              GlobalScope.INSTANCE,
              EmptyCoroutineContext.INSTANCE,
              CoroutineStart.LAZY,
              (scope, continuation) -> {
                throw new AssertionError("Unscheduled body ran");
              });
      try {
        overflow.start();
        throw new AssertionError("Over-limit task scheduled");
      } catch (IllegalStateException expected) {
        check(overflow.isCompleted());
      }
      for (int index = 0; index < 64; index++) {
        BrowserCall call =
            (BrowserCall) call(new OkHttpClient.Builder().build(), "https://fixture.invalid/");
        owner.register(call);
        http.add(call);
      }
      BrowserCall extra =
          (BrowserCall) call(new OkHttpClient.Builder().build(), "https://fixture.invalid/");
      try {
        owner.register(extra);
        throw new AssertionError("Unbounded HTTP accepted");
      } catch (IllegalStateException expected) {
        check(expected.getMessage().contains("HTTP callbacks"));
      }
      for (BrowserCall.BoundOperation child : work) child.run();
      check(owner.hasPending());
      for (BrowserCall call : http) owner.finished(call, null);
      owner.drain();
      check(!owner.hasPending());
    } finally {
      owner.close();
      owner.leave();
    }
  }

  static void singleUseAndSchedulingFailures() throws Throwable {
    BrowserCall.Operation owner =
        BrowserCall.beginOperation("schedule", "generation", "schedule-token");
    AtomicInteger runs = new AtomicInteger();
    owner.enter();
    try {
      BrowserCall.BoundOperation cancelled = BrowserCall.bindOperation(runs::incrementAndGet);
      cancelled.close();
      cancelled.close();
      check(!owner.hasPending());
      try {
        cancelled.run();
        throw new AssertionError("Cancelled reservation ran");
      } catch (IllegalStateException expected) {
        check(runs.get() == 0);
      }
      BrowserCall.BoundOperation once = BrowserCall.bindOperation(runs::incrementAndGet);
      once.run();
      try {
        once.run();
        throw new AssertionError("One-shot task ran twice");
      } catch (IllegalStateException expected) {
        check(runs.get() == 1);
      }
      once.close();
      check(!owner.hasPending());
      for (boolean failAtStart : java.util.List.of(false, true)) {
        BrowserCall.BoundOperation rejected = BrowserCall.bindOperation(runs::incrementAndGet);
        OutOfMemoryError failure = new OutOfMemoryError("fixture scheduling failure");
        try {
          BrowserCall.startBoundThread(
              rejected,
              () -> {
                if (!failAtStart) throw failure;
                return new Thread() {
                  public synchronized void start() {
                    throw failure;
                  }
                };
              });
          throw new AssertionError("Thread scheduling failure was swallowed");
        } catch (OutOfMemoryError expected) {
          check(expected == failure && !owner.hasPending() && runs.get() == 1);
        }
      }
      owner.drain();
    } finally {
      owner.close();
      owner.leave();
    }
  }

  static void closingRejectsDrainAndLateWork() throws Throwable {
    BrowserCall.Operation old = BrowserCall.beginOperation("closing", "generation", "closing-old");
    AtomicBoolean ran = new AtomicBoolean();
    BrowserCall.BoundOperation late;
    old.enter();
    try {
      late = BrowserCall.bindOperation(() -> ran.set(true));
      CompletableFuture<Void> drained = drainAsync(old);
      old.close();
      try {
        drained.get(3, TimeUnit.SECONDS);
        throw new AssertionError("Closed operation drained successfully");
      } catch (ExecutionException expected) {
        check(expected.getCause() instanceof InterruptedIOException);
      }
    } finally {
      old.close();
      old.leave();
    }
    BrowserCall.Operation next = BrowserCall.beginOperation("closing", "generation", "closing-new");
    next.enter();
    try {
      try {
        late.run();
        throw new AssertionError("Late work adopted the next operation");
      } catch (IllegalStateException expected) {
        check(expected.getCause() instanceof InterruptedIOException);
      }
      check(!ran.get() && !next.hasPending());
      BrowserCall.BoundOperation current = BrowserCall.bindOperation(() -> ran.set(true));
      check(next.hasPending());
      current.run();
      next.drain();
      check(ran.get() && !next.hasPending());
    } finally {
      next.close();
      next.leave();
    }
  }

  static void deferredFailureKeepsSourceRecovery() throws Throwable {
    BrowserCall.Operation owner =
        BrowserCall.beginOperation("deferred-error", "generation", "deferred-token");
    IOException failure = new IOException("Source-handled async error");
    owner.enter();
    try {
      GreenCoroutines.Task<Unit> task =
          new GreenCoroutines.Task<>(
              GlobalScope.INSTANCE,
              EmptyCoroutineContext.INSTANCE,
              CoroutineStart.DEFAULT,
              (scope, continuation) -> {
                throw GreenCoroutines.propagate(failure);
              });
      try {
        task.value();
        throw new AssertionError("Deferred error disappeared");
      } catch (Throwable expected) {
        check(expected == failure);
      }
      owner.drain();
      check(!owner.hasPending());
    } finally {
      owner.close();
      owner.leave();
    }
  }

  public static void main(String[] args) throws Throwable {
    boundBeforeRunMustDrain();
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
      globalScopeIncludesPostHttpWork(endpoint, posts);
      runningCancellationDoesNotFinishWork();
      lazyTaskKeepsOriginalOwner();
      expiredCompletionCannotAdoptAnotherOwner(endpoint, posts);
      workAndHttpHaveIndependentBudgets();
      singleUseAndSchedulingFailures();
      closingRejectsDrainAndLateWork();
      deferredFailureKeepsSourceRecovery();
      System.out.println("EnqueueTest: " + assertions + " assertions passed");
    } finally {
      Bridge.closeTransport();
      server.stop(0);
    }
  }
}
