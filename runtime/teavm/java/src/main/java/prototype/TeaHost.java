package prototype;

import eu.kanade.tachiyomi.source.*;
import eu.kanade.tachiyomi.source.model.*;
import org.teavm.jso.*;
import java.util.*;
import kotlin.coroutines.*;
import com.google.gson.*;

public class TeaHost {
  public static eu.kanade.tachiyomi.network.NetworkHelper network;
  static List<Source> sources;
  static Source source;
  static SManga manga;
  static List<SChapter> chapters;
  static List<Page> pages;

  public static void main(String[] args) {}

  @JSExport
  public static void hostInit(String userAgent) {
    new Thread(
            () -> {
              try {
                done(new JsonPrimitive(init(userAgent)).toString());
              } catch (Throwable t) {
                fail(describe(t));
              }
            })
        .start();
  }

  @JSExport
  public static void hostLoad() {
    new Thread(
            () -> {
              try {
                if (load() >= 0) done(sourceInfo());
              } catch (Throwable t) {
                fail(describe(t));
              }
            })
        .start();
  }

  @JSExport
  public static void hostSelect(String id) {
    new Thread(
            () -> {
              try {
                done(new JsonPrimitive(select(id)).toString());
              } catch (Throwable t) {
                fail(describe(t));
              }
            })
        .start();
  }

  @JSExport
  public static void callbackInvoke(
      String requestId, String instance, String name, String method, String args) {
    Bridge.callbackInvoke(requestId, instance, name, method, args);
  }

  public static String init(String userAgent) {
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
    try {
      Object entry = new keiyoushi.source.Generated();
      sources =
          entry instanceof SourceFactory
              ? ((SourceFactory) entry).createSources()
              : List.of((Source) entry);
      source = sources.get(0);
      return sources.size();
    } catch (Throwable t) {
      StringBuilder b = new StringBuilder(t.toString());
      for (StackTraceElement e : t.getStackTrace()) b.append("\n").append(e);
      fail(b.toString());
      return -1;
    }
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
  public static void hostInvoke(String sourceId, String operation, String argsJson) {
    new Thread(
            () -> {
              try {
                Source selected =
                    sources.stream()
                        .filter(s -> Long.toString(s.getId()).equals(sourceId))
                        .findFirst()
                        .orElseThrow(
                            () -> new IllegalArgumentException("Unknown Source " + sourceId));
                JsonObject args = JsonParser.parseString(argsJson).getAsJsonObject();
                Object result =
                    GreenCoroutines.block(
                        (scope, continuation) -> {
                          switch (operation) {
                            case "popular":
                              return selected.getPopularManga(HostDto.page(args), continuation);
                            case "latest":
                              if (!selected.getSupportsLatest())
                                throw new UnsupportedOperationException(
                                    "Source does not support latest");
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
                } else if (operation.equals("pages") && result instanceof List)
                  dto = HostDto.pages((List<Page>) result);
                else throw new IllegalStateException("Unexpected result for " + operation);
                done(HostJson.write(dto));
              } catch (Throwable t) {
                fail(describe(t));
              }
            })
        .start();
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

  @JSBody(params = "error", script = "self.teaFail(error);")
  static native void fail(String error);
}
