package prototype;

import com.google.gson.*;
import eu.kanade.tachiyomi.source.*;
import eu.kanade.tachiyomi.source.model.*;
import java.util.*;
import kotlin.coroutines.*;
import org.teavm.jso.*;

public class TeaHost {
  public static eu.kanade.tachiyomi.network.NetworkHelper network;
  static List<Source> sources;
  static Source source;
  static SManga manga;
  static List<SChapter> chapters;
  static List<Page> pages;
  static final PageSessions pageSessions = new PageSessions();

  public static void main(String[] args) {}

  @FunctionalInterface
  private interface HostOperation {
    String run() throws Throwable;
  }

  private static void startOperation(
      String requestId, String generation, String token, HostOperation action, Runnable cleanup) {
    BrowserCall.Operation owner;
    try {
      // Register before TeaVM schedules the host thread with setTimeout.
      owner = BrowserCall.beginOperation(requestId, generation, token);
    } catch (Throwable error) {
      fail(describe(error), true);
      return;
    }
    try {
      new Thread(
              () -> {
                owner.enter();
                try {
                  String result = action.run();
                  owner.drain();
                  done(result);
                } catch (Throwable error) {
                  boolean unfinishedCallbacks = owner.hasPending();
                  owner.close();
                  try {
                    cleanup.run();
                  } catch (Throwable cleanupError) {
                    Bridge.trace("Host operation cleanup failed: " + cleanupError);
                  }
                  // Cancelling HTTP cannot stop arbitrary plugin callback code.
                  // Discard this Worker whenever background work did not finish.
                  fail(describe(error), unfinishedCallbacks);
                } finally {
                  owner.close();
                  owner.leave();
                }
              })
          .start();
    } catch (Throwable error) {
      owner.close();
      fail(describe(error), true);
    }
  }

  @JSExport
  public static void hostInit(String userAgent, String requestId, String generation, String token) {
    startOperation(
        requestId,
        generation,
        token,
        () -> new JsonPrimitive(init(userAgent)).toString(),
        () -> {});
  }

  @JSExport
  public static void hostLoad(String requestId, String generation, String token) {
    startOperation(
        requestId,
        generation,
        token,
        () -> {
          load();
          return sourceInfo();
        },
        () -> {});
  }

  @JSExport
  public static void hostSelect(String id, String requestId, String generation, String token) {
    startOperation(
        requestId, generation, token, () -> new JsonPrimitive(select(id)).toString(), () -> {});
  }

  @JSExport
  public static void callbackInvoke(
      String requestId, String instance, String name, String method, String args) {
    Bridge.callbackInvoke(requestId, instance, name, method, args);
  }

  public static String init(String userAgent) {
    pageSessions.clear();
    PersistentFileSystem.install();
    System.setProperty("http.agent", userAgent);
    android.app.Application app = new android.app.Application();
    network = new eu.kanade.tachiyomi.network.NetworkHelper(app);
    uy.kohesive.injekt.InjektKt.getInjekt().addSingleton(() -> android.content.Context.class, app);
    uy.kohesive.injekt.InjektKt.getInjekt()
        .addSingleton(() -> eu.kanade.tachiyomi.network.NetworkHelper.class, network);
    uy.kohesive.injekt.InjektKt.getInjekt()
        .addSingleton(
            () -> kotlinx.serialization.protobuf.ProtoBuf.class,
            kotlinx.serialization.protobuf.ProtoBuf.Default);
    uy.kohesive.injekt.InjektKt.getInjekt().addSingleton(() -> android.app.Application.class, app);
    uy.kohesive.injekt.InjektKt.getInjekt()
        .addSingleton(
            () -> kotlinx.serialization.json.Json.class,
            kotlinx.serialization.json.JsonKt.Json(
                kotlinx.serialization.json.Json.Default,
                b -> {
                  b.setIgnoreUnknownKeys(true);
                  b.setExplicitNulls(false);
                  return kotlin.Unit.INSTANCE;
                }));
    return "TeaVM host ready";
  }

  @JSExport
  public static String sourceInfo() {
    JsonArray a = new JsonArray();
    for (Source s : sources) {
      JsonObject x = new JsonObject();
      x.addProperty("id", Long.toString(s.getId()));
      x.addProperty("name", s.getName());
      x.addProperty("lang", s.getLang());
      x.addProperty("supportsLatest", s.getSupportsLatest());
      if (s instanceof eu.kanade.tachiyomi.source.online.HttpSource)
        x.addProperty("baseUrl", ((eu.kanade.tachiyomi.source.online.HttpSource) s).getBaseUrl());
      a.add(x);
    }
    return a.toString();
  }

  public static int load() {
    Object entry = new keiyoushi.source.Generated();
    sources =
        entry instanceof SourceFactory
            ? ((SourceFactory) entry).createSources()
            : List.of((Source) entry);
    source = sources.get(0);
    return sources.size();
  }

  public static String select(String id) {
    source =
        sources.stream()
            .filter(s -> Long.toString(s.getId()).equals(id))
            .findFirst()
            .orElseThrow(() -> new IllegalArgumentException("Unknown Source " + id));
    manga = null;
    chapters = null;
    pages = null;
    return source.getName();
  }

  /** Product RPC: explicit references and complete DTOs; no hidden selected manga. */
  @JSExport
  public static void hostInvoke(
      String sourceId,
      String operation,
      String argsJson,
      String requestId,
      String generation,
      String token) {
    String[] createdPageSession = new String[1];
    startOperation(
        requestId,
        generation,
        token,
        () -> {
          Source selected =
              sources.stream()
                  .filter(s -> Long.toString(s.getId()).equals(sourceId))
                  .findFirst()
                  .orElseThrow(() -> new IllegalArgumentException("Unknown Source " + sourceId));
          JsonObject args = JsonParser.parseString(argsJson).getAsJsonObject();
          Object result =
              GreenCoroutines.block(
                  (scope, continuation) -> {
                    switch (operation) {
                      case "popular":
                        return selected.getPopularManga(HostDto.page(args), continuation);
                      case "latest":
                        if (!selected.getSupportsLatest())
                          throw new UnsupportedOperationException("Source does not support latest");
                        return selected.getLatestUpdates(HostDto.page(args), continuation);
                      case "search":
                        if (args.has("filters") && !args.getAsJsonArray("filters").isEmpty())
                          throw new UnsupportedOperationException(
                              "Typed filter mapping is not implemented");
                        return selected.getSearchManga(
                            HostDto.page(args),
                            HostDto.string(args, "query", ""),
                            selected.getFilterList(),
                            continuation);
                      case "details":
                      case "chapters":
                        return selected.getMangaUpdate(
                            HostDto.manga(args.getAsJsonObject("manga")),
                            List.of(),
                            operation.equals("details"),
                            operation.equals("chapters"),
                            continuation);
                      case "pages":
                        return selected.getPageList(
                            HostDto.chapter(args.getAsJsonObject("chapter")), continuation);
                      default:
                        throw new UnsupportedOperationException(
                            "Unsupported Source operation " + operation);
                    }
                  },
                  kotlinx.coroutines.Dispatchers.getDefault());
          JsonElement dto;
          if (result instanceof MangasPage) dto = HostDto.mangasPage((MangasPage) result);
          else if (result instanceof SMangaUpdate) {
            SMangaUpdate update = (SMangaUpdate) result;
            if (operation.equals("chapters")) dto = HostDto.chapters(update.getChapters());
            else {
              SManga stored = HostDto.manga(args.getAsJsonObject("manga"));
              mergeManga(stored, update.getManga());
              dto = HostDto.manga(stored);
            }
          } else if (operation.equals("pages") && result instanceof List) {
            PageSessions.Session session = pageSessions.open(selected, (List<Page>) result);
            createdPageSession[0] = session.id;
            dto = HostDto.pages(session.id, session.pages);
          } else throw new IllegalStateException("Unexpected result for " + operation);
          String json = HostJson.write(dto);
          if (createdPageSession[0] != null
              && json.getBytes(java.nio.charset.StandardCharsets.UTF_8).length
                  > PageSessions.MAX_DTO_BYTES)
            throw new IllegalArgumentException("Page metadata exceeds 2 MiB");
          return json;
        },
        () -> {
          if (createdPageSession[0] != null) pageSessions.close(createdPageSession[0]);
        });
  }

  @JSExport
  public static void hostAcquireImage(
      String sourceId,
      String pageSessionId,
      String pageKey,
      String requestId,
      String generation,
      String token) {
    startOperation(
        requestId,
        generation,
        token,
        () -> {
          Source selected =
              sources.stream()
                  .filter(s -> Long.toString(s.getId()).equals(sourceId))
                  .findFirst()
                  .orElseThrow(() -> new IllegalArgumentException("Unknown Source " + sourceId));
          if (!(selected instanceof eu.kanade.tachiyomi.source.online.HttpSource))
            throw new UnsupportedOperationException("Image acquisition requires an HttpSource");
          try (PageSessions.Lease lease =
              pageSessions.acquire(selected, sourceId, pageSessionId, pageKey)) {
            String resource =
                SourceImages.acquire(
                    (eu.kanade.tachiyomi.source.online.HttpSource) selected,
                    lease.page(),
                    new SourceImages.Sink() {
                      public String open() throws java.io.IOException {
                        return Bridge.imageOpen();
                      }

                      public void write(String handle, byte[] bytes) throws java.io.IOException {
                        Bridge.imageWrite(handle, bytes);
                      }

                      public String close(String handle) throws java.io.IOException {
                        return Bridge.imageClose(handle);
                      }

                      public void cancel(String handle) throws java.io.IOException {
                        Bridge.imageCancel(handle);
                      }
                    });
            return resource;
          }
        },
        () -> {});
  }

  @JSExport
  public static void hostClosePageSession(
      String pageSessionId, String requestId, String generation, String token) {
    startOperation(
        requestId,
        generation,
        token,
        () -> {
          pageSessions.close(pageSessionId);
          return "{\"closed\":true}";
        },
        () -> {});
  }

  static void mergeManga(SManga stored, SManga update) {
    if (stored == update) return;
    try {
      stored.setTitle(update.getTitle());
    } catch (kotlin.UninitializedPropertyAccessException ignored) {
    }
    if (update.getArtist() != null) stored.setArtist(update.getArtist());
    if (update.getAuthor() != null) stored.setAuthor(update.getAuthor());
    if (update.getDescription() != null) stored.setDescription(update.getDescription());
    if (update.getGenre() != null) stored.setGenre(update.getGenre());
    if (update.getThumbnail_url() != null) stored.setThumbnail_url(update.getThumbnail_url());
    stored.setStatus(update.getStatus());
    stored.setUpdate_strategy(update.getUpdate_strategy());
    stored.setInitialized(stored.getInitialized() || update.getInitialized());
    java.util.Map<String, kotlinx.serialization.json.JsonElement> memo =
        new java.util.LinkedHashMap<>(stored.getMemo());
    memo.putAll(update.getMemo());
    stored.setMemo(new kotlinx.serialization.json.JsonObject(memo));
  }

  static String hex(byte[] bytes) {
    StringBuilder s = new StringBuilder();
    for (byte b : bytes) {
      String h = Integer.toHexString(b & 255);
      if (h.length() < 2) s.append('0');
      s.append(h);
    }
    return s.toString();
  }

  static String describe(Throwable t) {
    StringBuilder s = new StringBuilder();
    java.util.Set<Throwable> seen =
        java.util.Collections.newSetFromMap(new java.util.IdentityHashMap<>());
    for (int depth = 0; t != null && depth < 16 && seen.add(t); depth++, t = t.getCause()) {
      if (depth > 0) s.append("\nCaused by: ");
      s.append(t.toString());
      org.teavm.jso.JSObject js = org.teavm.jso.JSExceptions.getJSException(t);
      if (js != null) s.append("\n").append(jsStack(js));
      for (StackTraceElement e : t.getStackTrace()) s.append("\n").append(e);
    }
    return s.toString();
  }

  @JSBody(params = "error", script = "return error&&error.stack?String(error.stack):'';")
  static native String jsStack(JSObject error);

  @JSBody(params = "value", script = "self.teaDone(value);")
  static native void done(String value);

  @JSBody(
      params = {"error", "discardRuntime"},
      script = "self.teaFail(error,discardRuntime);")
  static native void fail(String error, boolean discardRuntime);
}
