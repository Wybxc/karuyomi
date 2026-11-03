package prototype;

import com.google.gson.*;
import eu.kanade.tachiyomi.source.model.*;
import java.util.*;

/** JVM contract oracle for product DTOs, independent of websites and TeaVM. */
public final class HostDtoTest {
    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    public static void main(String[] ignored) {
        List<SManga> mangas = new ArrayList<>();
        for (int index = 0; index < 31; index++) {
            JsonObject input = JsonParser.parseString("{\"url\":\"/manga/" + index
                + "?a=1&b=2\",\"title\":\"Title " + index
                + "\",\"author\":\"Author\",\"artist\":\"Artist\","
                + "\"genre\":\"Fantasy, Drama\",\"description\":\"full text\","
                + "\"thumbnailUrl\":\"https://example.invalid/cover\","
                + "\"status\":2,\"initialized\":true,\"updateStrategy\":\"ONLY_FETCH_ONCE\","
                + "\"memo\":{\"extension.key\":\"retained\"}}").getAsJsonObject();
            mangas.add(HostDto.manga(input));
        }
        JsonObject page = HostDto.mangasPage(new MangasPage(mangas, true));
        check(page.getAsJsonArray("mangas").size() == 31, "List was truncated");
        check(page.get("hasNextPage").getAsBoolean(), "Pagination flag lost");
        JsonObject manga = page.getAsJsonArray("mangas").get(30).getAsJsonObject();
        check(manga.get("url").getAsString().equals("/manga/30?a=1&b=2"), "URL changed");
        check(manga.get("author").getAsString().equals("Author"), "Author lost");
        check(manga.getAsJsonArray("genres").size() == 2, "Genres lost");
        check(manga.get("updateStrategy").getAsString().equals("ONLY_FETCH_ONCE"), "Snapshot metadata lost");
        check(manga.getAsJsonObject("memo").get("extension.key").getAsString().equals("retained"), "Memo lost");

        List<SChapter> chapters = new ArrayList<>();
        List<Page> pages = new ArrayList<>();
        for (int index = 0; index < 43; index++) {
            JsonObject input = JsonParser.parseString("{\"url\":\"/chapter/" + index
                + "\",\"name\":\"Chapter " + index + "\",\"scanlator\":\"Group\","
                + "\"dateUpload\":\"9007199254740993\",\"chapterNumber\":1.5}").getAsJsonObject();
            chapters.add(HostDto.chapter(input));
            pages.add(new Page(100 + index, "/page/" + index, null, null));
        }
        JsonArray chapterDtos = HostDto.chapters(chapters).getAsJsonArray("chapters");
        check(chapterDtos.size() == 43, "Chapters were truncated");
        check(chapterDtos.get(42).getAsJsonObject().get("dateUpload").getAsString().equals("9007199254740993"), "Long precision lost");
        check(chapterDtos.get(42).getAsJsonObject().get("sourceOrder").getAsInt() == 42, "Source ordering lost");
        JsonArray pageDtos = HostDto.pages(pages).getAsJsonArray("pages");
        check(pageDtos.size() == 43, "Pages were truncated");
        check(pageDtos.get(42).getAsJsonObject().get("index").getAsInt() == 42, "Logical page ordering changed");
        check(pageDtos.get(42).getAsJsonObject().get("sourceIndex").getAsInt() == 142, "Original index lost");
        check(pageDtos.get(0).getAsJsonObject().get("imageUrl").isJsonNull(), "Unresolved image URL changed");

        check(HostDto.page(new JsonObject()) == 1, "Initial page changed");
        check(HostDto.page(JsonParser.parseString("{\"page\":7}").getAsJsonObject()) == 7, "Page ignored");
        for (String number : List.of("0", "-1", "1.5", "2147483648")) {
            boolean rejected = false;
            try { HostDto.page(JsonParser.parseString("{\"page\":" + number + "}").getAsJsonObject()); }
            catch (IllegalArgumentException expected) { rejected = true; }
            check(rejected, "Invalid page accepted: " + number);
        }
        boolean rejected = false;
        try { HostDto.manga(new JsonObject()); }
        catch (IllegalArgumentException expected) { rejected = true; }
        check(rejected, "Implicit manga reference accepted");
        System.out.println("Host DTO JVM oracle passed: complete lists, metadata, explicit refs, ordering and page validation");
    }
}
