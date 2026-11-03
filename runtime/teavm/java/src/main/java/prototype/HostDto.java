package prototype;

import com.google.gson.*;
import com.google.gson.stream.JsonReader;
import com.google.gson.stream.JsonToken;
import eu.kanade.tachiyomi.source.model.*;
import java.io.IOException;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Boundary DTOs retain all list items and source metadata. No URL rewriting. */
public final class HostDto {
  private static final int MAX_MEMO_BYTES = 64 * 1024;

  private HostDto() {}

  private static String memoJson(String json) {
    if (json.getBytes(StandardCharsets.UTF_8).length > MAX_MEMO_BYTES)
      throw new IllegalArgumentException("memoJson exceeds 64 KiB UTF-8");
    JsonReader reader = new JsonReader(new StringReader(json));
    reader.setStrictness(Strictness.STRICT);
    try {
      JsonElement memo = JsonParser.parseReader(reader);
      if (!memo.isJsonObject() || reader.peek() != JsonToken.END_DOCUMENT)
        throw new IllegalArgumentException("memoJson must contain one JSON object");
      return memo.toString();
    } catch (JsonParseException | IOException error) {
      throw new IllegalArgumentException("memoJson must contain one JSON object", error);
    }
  }

  private static kotlinx.serialization.json.JsonObject memo(JsonObject value) {
    JsonElement field = value.get("memoJson");
    if (!field.isJsonPrimitive() || !field.getAsJsonPrimitive().isString())
      throw new IllegalArgumentException("memoJson must be a JSON string");
    return (kotlinx.serialization.json.JsonObject)
        kotlinx.serialization.json.Json.Default.parseToJsonElement(memoJson(field.getAsString()));
  }

  public static int page(JsonObject args) {
    if (!args.has("page")) return 1;
    String value = args.get("page").getAsString();
    if (!value.matches("[1-9][0-9]*") || value.length() > 10)
      throw new IllegalArgumentException("page must be a positive integer");
    return Integer.parseInt(value);
  }

  public static String string(JsonObject object, String name, String fallback) {
    return object.has(name) && !object.get(name).isJsonNull()
        ? object.get(name).getAsString()
        : fallback;
  }

  private static String required(JsonObject object, String key) {
    if (object == null) throw new IllegalArgumentException("Explicit reference is required");
    String value = string(object, key, null);
    if (value == null || value.isEmpty()) throw new IllegalArgumentException(key + " is required");
    return value;
  }

  public static SManga manga(JsonObject value) {
    SManga manga = SManga.Companion.create();
    manga.setUrl(required(value, "url"));
    manga.setTitle(string(value, "title", ""));
    manga.setAuthor(string(value, "author", null));
    manga.setArtist(string(value, "artist", null));
    manga.setDescription(string(value, "description", null));
    manga.setGenre(string(value, "genre", null));
    manga.setThumbnail_url(string(value, "thumbnailUrl", null));
    if (value.has("status")) manga.setStatus(value.get("status").getAsInt());
    if (value.has("initialized")) manga.setInitialized(value.get("initialized").getAsBoolean());
    if (value.has("updateStrategy"))
      manga.setUpdate_strategy(UpdateStrategy.valueOf(value.get("updateStrategy").getAsString()));
    if (value.has("memoJson")) manga.setMemo(memo(value));
    return manga;
  }

  public static SChapter chapter(JsonObject value) {
    SChapter chapter = SChapter.Companion.create();
    chapter.setUrl(required(value, "url"));
    chapter.setName(string(value, "name", ""));
    chapter.setScanlator(string(value, "scanlator", null));
    if (value.has("dateUpload") && !value.get("dateUpload").isJsonNull())
      chapter.setDate_upload(Long.parseLong(value.get("dateUpload").getAsString()));
    if (value.has("chapterNumber") && !value.get("chapterNumber").isJsonNull())
      chapter.setChapter_number(value.get("chapterNumber").getAsFloat());
    if (value.has("memoJson")) chapter.setMemo(memo(value));
    return chapter;
  }

  public static JsonObject manga(SManga manga) {
    JsonObject dto = new JsonObject();
    dto.addProperty("url", manga.getUrl());
    dto.addProperty("title", manga.getTitle());
    dto.addProperty("author", manga.getAuthor());
    dto.addProperty("artist", manga.getArtist());
    dto.addProperty("description", manga.getDescription());
    dto.addProperty("genre", manga.getGenre());
    JsonArray genres = new JsonArray();
    if (manga.getGenres() != null) for (String genre : manga.getGenres()) genres.add(genre);
    dto.add("genres", genres);
    dto.addProperty("status", manga.getStatus());
    dto.addProperty("thumbnailUrl", manga.getThumbnail_url());
    dto.addProperty("initialized", manga.getInitialized());
    dto.addProperty("updateStrategy", manga.getUpdate_strategy().toString());
    dto.addProperty("memoJson", memoJson(manga.getMemo().toString()));
    return dto;
  }

  public static JsonObject mangasPage(MangasPage page) {
    JsonObject dto = new JsonObject();
    JsonArray mangas = new JsonArray();
    for (SManga manga : page.getMangas()) mangas.add(manga(manga));
    dto.add("mangas", mangas);
    dto.addProperty("hasNextPage", page.getHasNextPage());
    return dto;
  }

  public static JsonObject chapters(List<SChapter> chapters) {
    JsonObject dto = new JsonObject();
    JsonArray items = new JsonArray();
    for (int index = 0; index < chapters.size(); index++) {
      SChapter chapter = chapters.get(index);
      JsonObject item = new JsonObject();
      item.addProperty("url", chapter.getUrl());
      item.addProperty("name", chapter.getName());
      float number = chapter.getChapter_number();
      item.add(
          "chapterNumber",
          Float.isFinite(number) && number >= 0 ? new JsonPrimitive(number) : JsonNull.INSTANCE);
      item.addProperty("scanlator", chapter.getScanlator());
      item.addProperty("dateUpload", Long.toString(chapter.getDate_upload()));
      item.addProperty("sourceOrder", index);
      item.addProperty("memoJson", memoJson(chapter.getMemo().toString()));
      items.add(item);
    }
    dto.add("chapters", items);
    return dto;
  }

  public static JsonObject pages(String pageSessionId, List<Page> pages) {
    JsonObject dto = new JsonObject();
    dto.addProperty("pageSessionId", pageSessionId);
    JsonArray items = new JsonArray();
    for (int index = 0; index < pages.size(); index++) {
      Page page = pages.get(index);
      JsonObject item = new JsonObject();
      item.addProperty("pageKey", "p-" + index);
      item.addProperty("index", index);
      item.addProperty("sourceIndex", page.getIndex());
      item.addProperty("url", page.getUrl());
      item.addProperty("imageUrl", page.getImageUrl());
      items.add(item);
    }
    dto.add("pages", items);
    return dto;
  }
}
