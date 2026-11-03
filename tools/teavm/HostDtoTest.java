package prototype;

import com.google.gson.*;
import eu.kanade.tachiyomi.source.model.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** JVM contract oracle for product DTOs, independent of websites and TeaVM. */
public final class HostDtoTest {
  private static final String MEMO =
      "{\"extension.key\":\"retained\",\"large\":9007199254740993,"
          + "\"max\":9223372036854775807,\"decimal\":123.4500,\"exponent\":1e+1000,"
          + "\"nested\":{\"items\":[null,true,\"漫画😀\",-9223372036854775808]}}";

  private static void check(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
  }

  private static JsonObject reference(String memoJson) {
    JsonObject input = new JsonObject();
    input.addProperty("url", "/explicit-reference");
    input.addProperty("title", "Title");
    input.addProperty("memoJson", memoJson);
    return input;
  }

  private static void rejected(JsonObject input) {
    for (boolean chapter : List.of(false, true)) {
      boolean rejected = false;
      try {
        if (chapter) HostDto.chapter(input);
        else HostDto.manga(input);
      } catch (IllegalArgumentException expected) {
        rejected = true;
      }
      check(rejected, "Invalid memoJson accepted for " + (chapter ? "chapter" : "manga"));
    }
  }

  private static void memoBoundary() {
    JsonObject input = reference(MEMO);
    JsonObject manga = HostDto.manga(HostDto.manga(input));
    JsonObject chapter =
        HostDto.chapters(List.of(HostDto.chapter(input)))
            .getAsJsonArray("chapters")
            .get(0)
            .getAsJsonObject();
    for (JsonObject dto : List.of(manga, chapter)) {
      check(!dto.has("memo"), "Old memo field was emitted");
      check(dto.get("memoJson").getAsString().equals(MEMO), "Memo numeric lexemes changed");
      JsonObject wire = JsonParser.parseString(HostJson.write(dto)).getAsJsonObject();
      check(wire.get("memoJson").getAsString().equals(MEMO), "Outer JSON changed opaque memo");
      check(
          HostDto.manga(HostDto.manga(wire)).get("memoJson").getAsString().equals(MEMO),
          "Manga wire round trip changed memo");
      check(
          HostDto.chapters(List.of(HostDto.chapter(wire)))
              .getAsJsonArray("chapters")
              .get(0)
              .getAsJsonObject()
              .get("memoJson")
              .getAsString()
              .equals(MEMO),
          "Chapter wire round trip changed memo");
    }
    JsonObject absent = reference("{}");
    absent.remove("memoJson");
    JsonObject defaultManga = HostDto.manga(HostDto.manga(absent));
    check(defaultManga.get("memoJson").getAsString().equals("{}"), "Default memo changed");
    check(
        !JsonParser.parseString(HostJson.write(defaultManga)).getAsJsonObject().has("author"),
        "Nullable field omission changed");
    absent.add("memo", JsonParser.parseString(MEMO));
    check(
        HostDto.manga(HostDto.manga(absent)).get("memoJson").getAsString().equals("{}"),
        "Old memo field was accepted as a fallback");

    for (String invalid :
        List.of("", "{", "[]", "null", "1", "\"text\"", "{} {}", "{unquoted:1}", "{\"a\":NaN}"))
      rejected(reference(invalid));
    for (JsonElement invalid :
        List.of(
            JsonNull.INSTANCE, new JsonPrimitive(1), new JsonPrimitive(false), new JsonObject())) {
      JsonObject value = reference("{}");
      value.add("memoJson", invalid);
      rejected(value);
    }

    String boundary = "{\"v\":\"" + "é".repeat(32764) + "\"}";
    check(boundary.getBytes(StandardCharsets.UTF_8).length == 65536, "Fixture size changed");
    check(
        HostDto.manga(HostDto.manga(reference(boundary)))
            .get("memoJson")
            .getAsString()
            .equals(boundary),
        "64 KiB UTF-8 object was rejected");
    String oversized = "{\"v\":\"" + "é".repeat(32764) + "a\"}";
    check(oversized.getBytes(StandardCharsets.UTF_8).length == 65537, "Fixture size changed");
    rejected(reference(oversized));

    kotlinx.serialization.json.JsonObject largeMemo =
        (kotlinx.serialization.json.JsonObject)
            kotlinx.serialization.json.Json.Default.parseToJsonElement(oversized);
    SManga sourceManga = HostDto.manga(absent);
    sourceManga.setMemo(largeMemo);
    boolean rejectedOutput = false;
    try {
      HostDto.manga(sourceManga);
    } catch (IllegalArgumentException expected) {
      rejectedOutput = true;
    }
    check(rejectedOutput, "Source-generated oversized manga memo escaped the boundary");
    SChapter sourceChapter = HostDto.chapter(absent);
    sourceChapter.setMemo(largeMemo);
    rejectedOutput = false;
    try {
      HostDto.chapters(List.of(sourceChapter));
    } catch (IllegalArgumentException expected) {
      rejectedOutput = true;
    }
    check(rejectedOutput, "Source-generated oversized chapter memo escaped the boundary");
  }

  public static void main(String[] ignored) {
    List<SManga> mangas = new ArrayList<>();
    for (int index = 0; index < 31; index++) {
      JsonObject input =
          JsonParser.parseString(
                  "{\"url\":\"/manga/"
                      + index
                      + "?a=1&b=2\",\"title\":\"Title "
                      + index
                      + "\",\"author\":\"Author\",\"artist\":\"Artist\","
                      + "\"genre\":\"Fantasy, Drama\",\"description\":\"full text\","
                      + "\"thumbnailUrl\":\"https://example.invalid/cover\","
                      + "\"status\":2,\"initialized\":true,\"updateStrategy\":\"ONLY_FETCH_ONCE\"}")
              .getAsJsonObject();
      input.addProperty("memoJson", MEMO);
      mangas.add(HostDto.manga(input));
    }
    JsonObject page = HostDto.mangasPage(new MangasPage(mangas, true));
    check(page.getAsJsonArray("mangas").size() == 31, "List was truncated");
    check(page.get("hasNextPage").getAsBoolean(), "Pagination flag lost");
    JsonObject manga = page.getAsJsonArray("mangas").get(30).getAsJsonObject();
    check(manga.get("url").getAsString().equals("/manga/30?a=1&b=2"), "URL changed");
    check(manga.get("author").getAsString().equals("Author"), "Author lost");
    check(manga.getAsJsonArray("genres").size() == 2, "Genres lost");
    check(
        manga.get("updateStrategy").getAsString().equals("ONLY_FETCH_ONCE"),
        "Snapshot metadata lost");
    check(
        JsonParser.parseString(manga.get("memoJson").getAsString())
            .getAsJsonObject()
            .get("extension.key")
            .getAsString()
            .equals("retained"),
        "Memo lost");

    List<SChapter> chapters = new ArrayList<>();
    List<Page> pages = new ArrayList<>();
    for (int index = 0; index < 43; index++) {
      JsonObject input =
          JsonParser.parseString(
                  "{\"url\":\"/chapter/"
                      + index
                      + "\",\"name\":\"Chapter "
                      + index
                      + "\",\"scanlator\":\"Group\","
                      + "\"dateUpload\":\"9007199254740993\",\"chapterNumber\":1.5}")
              .getAsJsonObject();
      chapters.add(HostDto.chapter(input));
      pages.add(new Page(100 + index, "/page/" + index, null, null));
    }
    JsonArray chapterDtos = HostDto.chapters(chapters).getAsJsonArray("chapters");
    check(chapterDtos.size() == 43, "Chapters were truncated");
    check(
        chapterDtos
            .get(42)
            .getAsJsonObject()
            .get("dateUpload")
            .getAsString()
            .equals("9007199254740993"),
        "Long precision lost");
    check(
        chapterDtos.get(42).getAsJsonObject().get("sourceOrder").getAsInt() == 42,
        "Source ordering lost");
    JsonObject pageResult = HostDto.pages("fixture-session", pages);
    check(
        pageResult.get("pageSessionId").getAsString().equals("fixture-session"),
        "Page session lost");
    JsonArray pageDtos = pageResult.getAsJsonArray("pages");
    check(
        pageDtos.get(42).getAsJsonObject().get("pageKey").getAsString().equals("p-42"),
        "Opaque page key lost");
    check(pageDtos.size() == 43, "Pages were truncated");
    check(
        pageDtos.get(42).getAsJsonObject().get("index").getAsInt() == 42,
        "Logical page ordering changed");
    check(
        pageDtos.get(42).getAsJsonObject().get("sourceIndex").getAsInt() == 142,
        "Original index lost");
    check(
        pageDtos.get(0).getAsJsonObject().get("imageUrl").isJsonNull(),
        "Unresolved image URL changed");

    check(HostDto.page(new JsonObject()) == 1, "Initial page changed");
    check(
        HostDto.page(JsonParser.parseString("{\"page\":7}").getAsJsonObject()) == 7,
        "Page ignored");
    for (String number : List.of("0", "-1", "1.5", "2147483648")) {
      boolean rejected = false;
      try {
        HostDto.page(JsonParser.parseString("{\"page\":" + number + "}").getAsJsonObject());
      } catch (IllegalArgumentException expected) {
        rejected = true;
      }
      check(rejected, "Invalid page accepted: " + number);
    }
    boolean rejected = false;
    try {
      HostDto.manga(new JsonObject());
    } catch (IllegalArgumentException expected) {
      rejected = true;
    }
    check(rejected, "Implicit manga reference accepted");
    memoBoundary();
    System.out.println(
        "Host DTO JVM oracle passed: complete lists, metadata, explicit refs, ordering and page"
            + " validation; opaque memoJson precision and 64 KiB UTF-8 boundary");
  }
}
