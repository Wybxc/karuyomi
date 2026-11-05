package keiyoushi.source;

import eu.kanade.tachiyomi.source.model.*;
import eu.kanade.tachiyomi.source.online.HttpSource;
import java.io.IOException;
import java.util.List;
import java.util.concurrent.TimeUnit;
import kotlin.coroutines.Continuation;
import okhttp3.*;
import org.teavm.jso.JSBody;
import prototype.BrowserCall;

/** A controlled Source for the real TeaHost entry; no official extension is modified. */
public final class Generated extends HttpSource {
  private final OkHttpClient client =
      new OkHttpClient.Builder().retryOnConnectionFailure(true).build();
  private Call deferredForeground, deferredBackground;
  private volatile boolean lateMayRun;
  private volatile int limitEntered, limitFinished;
  private volatile boolean limitRejected;

  public long getId() {
    return 1;
  }

  public String getName() {
    return "Enqueue fixture";
  }

  public String getLang() {
    return "en";
  }

  public String getBaseUrl() {
    return "https://fixture.example.org";
  }

  public boolean getSupportsLatest() {
    return false;
  }

  @JSBody(params = "event", script = "self.enqueueFixtureMark(event);")
  private static native void mark(String event);

  private Call call(String path) {
    return call(client, path);
  }

  private Call call(OkHttpClient selectedClient, String path) {
    return selectedClient.newCall(
        new Request.Builder()
            .url(getBaseUrl() + path)
            .post(RequestBody.create(MediaType.get("text/plain"), "one view"))
            .build());
  }

  private Callback success(String event) {
    return new Callback() {
      public void onResponse(Call call, Response response) throws IOException {
        if (!response.body().string().equals("opaque encoded bytes"))
          throw new IOException("Unexpected fixture response");
        mark(event);
      }

      public void onFailure(Call call, IOException error) {
        throw new AssertionError(error);
      }
    };
  }

  public Object getPopularManga(int page, Continuation<? super MangasPage> continuation) {
    mark("entry-" + page);
    switch (page) {
      case 1:
        call("/nested-first")
            .enqueue(
                new Callback() {
                  public void onResponse(Call first, Response response) {
                    mark("nested-first");
                    call("/nested-second").enqueue(success("nested-second"));
                    // Deliberately leave the first response unread and unclosed.
                  }

                  public void onFailure(Call first, IOException error) {
                    throw new AssertionError(error);
                  }
                });
        break;
      case 2:
        call("/callback-failure")
            .enqueue(
                new Callback() {
                  public void onResponse(Call call, Response response) throws IOException {
                    mark("callback-failure");
                    throw new IOException("fixture callback failed");
                  }

                  public void onFailure(Call call, IOException error) {
                    mark("unexpected-second-callback");
                  }
                });
        break;
      case 3:
        call("/network-failure")
            .enqueue(
                new Callback() {
                  public void onResponse(Call call, Response response) {
                    throw new AssertionError("Expected network failure");
                  }

                  public void onFailure(Call call, IOException error) {
                    mark("handled-network-failure");
                  }
                });
        break;
      case 4:
        call("/cancel")
            .enqueue(
                new Callback() {
                  public void onResponse(Call call, Response response) throws IOException {
                    call.cancel();
                    try {
                      response.body().bytes();
                      throw new AssertionError("Cancelled body was readable");
                    } catch (IOException expected) {
                      mark("cancelled-body-rejected");
                    }
                    Runnable oldOwner =
                        BrowserCall.bindOperation(() -> {
                          mark("unexpected-late-action");
                          call("/unexpected-late").enqueue(success("unexpected-late-http"));
                        });
                    new Thread(
                            () -> {
                              try {
                                long deadline = System.nanoTime() + 3000000000L;
                                while (!lateMayRun && System.nanoTime() < deadline) Thread.sleep(1);
                                if (!lateMayRun)
                                  throw new AssertionError("Next entry did not release late child");
                                try {
                                  oldOwner.run();
                                  mark("unexpected-late-owner-accepted");
                                } catch (IllegalStateException expected) {
                                  mark("expired-owner-rejected");
                                }
                              } catch (Throwable error) {
                                mark("late-child-failed:" + error);
                              }
                            })
                        .start();
                  }

                  public void onFailure(Call call, IOException error) {
                    throw new AssertionError(error);
                  }
                });
        break;
      case 5:
        lateMayRun = true;
        call("/next").enqueue(success("next-callback"));
        break;
      case 6:
        deferredForeground = call("/deferred-foreground");
        deferredBackground = call("/deferred-background");
        mark("deferred-created");
        break;
      case 7:
        try (Response response = deferredForeground.execute()) {
          if (!response.body().string().equals("opaque encoded bytes"))
            throw new IOException("Unexpected deferred response");
          mark("deferred-foreground");
        } catch (IOException error) {
          throw new IllegalStateException(error);
        }
        deferredBackground.enqueue(success("deferred-background"));
        break;
      case 8:
        pendingLimit();
        break;
      case 9:
        call(client.newBuilder().readTimeout(90, TimeUnit.SECONDS).build(), "/drain-timeout")
            .enqueue(
                new Callback() {
                  public void onResponse(Call call, Response response) throws IOException {
                    mark("drain-callback-entered");
                    // The controlled endpoint sends META but never DATA/END. Its HTTP deadline
                    // exceeds the real, unchanged 30-second Java callback drain deadline.
                    response.body().bytes();
                    throw new AssertionError("Held drain body unexpectedly completed");
                  }

                  public void onFailure(Call call, IOException error) {
                    throw new AssertionError("Drain HTTP failed before its callback", error);
                  }
                });
        break;
      case 10:
        mark("healthy-rpc");
        break;
      default:
        throw new IllegalArgumentException("Unknown fixture page " + page);
    }
    mark("return-" + page);
    return new MangasPage(List.of(), false);
  }

  private void pendingLimit() {
    limitEntered = 0;
    limitFinished = 0;
    limitRejected = false;
    // The callback limit is independent of the four-open-HTTP-body transport limit.
    // A real application interceptor supplies these responses without opening HTTP handles.
    OkHttpClient local =
        client
            .newBuilder()
            .addInterceptor(chain ->
                new Response.Builder()
                    .request(chain.request())
                    .protocol(Protocol.HTTP_1_1)
                    .code(200)
                    .message("fixture")
                    .body(ResponseBody.create(MediaType.get("text/plain"), "opaque encoded bytes"))
                    .build())
            .build();
    Callback held =
        new Callback() {
          public void onResponse(Call call, Response response) throws IOException {
            if (!response.body().string().equals("opaque encoded bytes"))
              throw new IOException("Unexpected limit response");
            synchronized (Generated.this) {
              limitEntered++;
              mark("limit-callback-entered");
              if (limitEntered == 64) mark("limit-all-entered");
            }
            try {
              long deadline = System.nanoTime() + 5000000000L;
              while ((!limitRejected || limitEntered != 64) && System.nanoTime() < deadline)
                Thread.sleep(1);
              if (!limitRejected || limitEntered != 64)
                throw new IOException("Limit callback barrier timed out");
            } catch (InterruptedException error) {
              Thread.currentThread().interrupt();
              throw new IOException(error);
            }
            synchronized (Generated.this) {
              limitFinished++;
              mark("limit-callback-finished");
              if (limitFinished == 64) mark("limit-all-finished");
            }
          }

          public void onFailure(Call call, IOException error) {
            throw new AssertionError(error);
          }
        };
    for (int index = 0; index < 64; index++) call(local, "/limit/" + index).enqueue(held);
    mark("limit-registered-64");
    try {
      call(local, "/limit/65")
          .enqueue(
              new Callback() {
                public void onResponse(Call call, Response response) {
                  mark("unexpected-limit-65-callback");
                }

                public void onFailure(Call call, IOException error) {
                  mark("unexpected-limit-65-callback");
                }
              });
      throw new AssertionError("65th pending callback was accepted");
    } catch (IllegalStateException expected) {
      if (!"Too many background HTTP callbacks".equals(expected.getMessage())) throw expected;
      mark("limit-rejected-65");
      limitRejected = true;
    }
  }

  public Object getLatestUpdates(int page, Continuation<? super MangasPage> continuation) {
    throw new UnsupportedOperationException();
  }

  public Object getSearchManga(
      int page, String query, FilterList filters, Continuation<? super MangasPage> continuation) {
    throw new UnsupportedOperationException();
  }

  public Object getMangaUpdate(
      SManga manga,
      List<? extends SChapter> chapters,
      boolean details,
      boolean updateChapters,
      Continuation<? super SMangaUpdate> continuation) {
    throw new UnsupportedOperationException();
  }

  public Object getPageList(
      SChapter chapter, Continuation<? super List<? extends Page>> continuation) {
    throw new UnsupportedOperationException();
  }
}
