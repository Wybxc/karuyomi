package prototype;

import com.google.gson.*;
import eu.kanade.tachiyomi.source.Source;
import eu.kanade.tachiyomi.source.model.*;
import java.util.*;
import kotlin.coroutines.Continuation;

/** Real seed types and Source-specific subclasses; no network or AOT compatibility claim. */
public final class HostFiltersTest {
  private static int assertions;

  private static void check(boolean condition, String message) {
    assertions++;
    if (!condition) throw new AssertionError(message);
  }

  private static void rejected(Runnable action, String message) {
    boolean failed = false;
    try {
      action.run();
    } catch (IllegalArgumentException | UnsupportedOperationException expected) {
      failed = true;
    }
    check(failed, message);
  }

  private static JsonObject json(String value) {
    return JsonParser.parseString(value).getAsJsonObject();
  }

  private static final class Input extends Filter.Text {
    Input(String name, String state) {
      super(name, state);
    }
  }

  private static final class TagCheckBox extends Filter.CheckBox {
    TagCheckBox(String name) {
      super(name, false);
    }
  }

  private static final class Tri extends Filter.TriState {
    Tri() {
      super("Tri", 0);
    }
  }

  private interface QueryFilter {
    String selectedValue();
  }

  private static final class Choice extends Filter.Select<String> implements QueryFilter {
    Choice(String[] values) {
      super("Select", values, 0);
    }

    public String selectedValue() {
      return getValues()[getState()];
    }
  }

  private static final class Sort extends Filter.Sort {
    Sort(String[] values) {
      super("Sort", values, null);
    }
  }

  private static final class TagGroup extends Filter.Group<Filter<?>> {
    TagGroup(List<Filter<?>> children) {
      super("Tags", children);
    }
  }

  private static final class Fixture {
    final Input text = new Input("Text", "original");
    final TagCheckBox checkBox = new TagCheckBox("Checked");
    final Tri tri = new Tri();
    final Choice select = new Choice(new String[] {"First", "Second"});
    final Sort sort = new Sort(new String[] {"Name", "Date"});
    final TagCheckBox tag = new TagCheckBox("Tag");
    final Input nested = new Input("Nested", "deep-original");
    final TagGroup group =
        new TagGroup(new ArrayList<>(List.of(tag, new TagGroup(List.of(nested)))));
    final FilterList filters =
        new FilterList(
            new Filter.Header("Heading"),
            new Filter.Separator(""),
            text,
            checkBox,
            tri,
            select,
            sort,
            group);

    void original() {
      check(text.getState().equals("original"), "Invalid tail changed the earlier text");
      check(
          !checkBox.getState() && tri.getState() == 0 && select.getState() == 0,
          "Invalid selection partially mutated earlier leaves");
      check(
          sort.getState() == null && !tag.getState() && nested.getState().equals("deep-original"),
          "Invalid selection partially mutated later leaves");
    }
  }

  private static final class FixtureSource implements Source {
    long id = 17;
    FilterList filters;
    int captures;
    int searches;
    boolean failCapture;
    boolean failSearch;
    String query;
    int page;
    FilterList searchedFilters;

    FixtureSource(FilterList filters) {
      this.filters = filters;
    }

    public long getId() {
      return id;
    }

    public String getName() {
      return "Fixture";
    }

    public boolean getSupportsLatest() {
      return true;
    }

    public FilterList getFilterList() {
      captures++;
      if (failCapture) throw new IllegalArgumentException("Dynamic filter fetch failed");
      return filters;
    }

    public Object getPopularManga(int page, Continuation<? super MangasPage> continuation) {
      throw new UnsupportedOperationException();
    }

    public Object getLatestUpdates(int page, Continuation<? super MangasPage> continuation) {
      throw new UnsupportedOperationException();
    }

    public Object getSearchManga(
        int page, String query, FilterList filters, Continuation<? super MangasPage> continuation) {
      searches++;
      this.page = page;
      this.query = query;
      searchedFilters = filters;
      if (failSearch) throw new IllegalArgumentException("Search failed");
      return new MangasPage(List.of(), false);
    }

    public Object getMangaUpdate(
        SManga manga,
        List<? extends SChapter> chapters,
        boolean details,
        boolean chapterList,
        Continuation<? super SMangaUpdate> continuation) {
      throw new UnsupportedOperationException();
    }

    public Object getPageList(
        SChapter chapter, Continuation<? super List<? extends Page>> continuation) {
      throw new UnsupportedOperationException();
    }
  }

  private static HostFilters.Candidate publish(
      HostFilters registry, FixtureSource source, String pin) {
    JsonObject request = new JsonObject();
    if (pin != null) request.addProperty("retainedSnapshotId", pin);
    HostFilters.Candidate candidate = registry.capture(source, "g1", request);
    registry.commit(candidate);
    return candidate;
  }

  private static String id(HostFilters.Candidate candidate) {
    return candidate.description().get("snapshotId").getAsString();
  }

  private static JsonObject selection(String id) {
    JsonObject selection =
        json(
            "{\"updates\":["
                + "{\"path\":[2],\"text\":\"changed\"},"
                + "{\"path\":[3],\"checkBox\":true},"
                + "{\"path\":[4],\"triState\":2},"
                + "{\"path\":[5],\"select\":1},"
                + "{\"path\":[6],\"sort\":{\"selection\":{\"index\":1,\"ascending\":true}}},"
                + "{\"path\":[7,0],\"checkBox\":true},"
                + "{\"path\":[7,1,0],\"text\":\"deep-changed\"}]}");
    selection.addProperty("snapshotId", id);
    return selection;
  }

  private static JsonObject only(String id, String update) {
    JsonObject selection = json("{\"updates\":[" + update + "]}");
    selection.addProperty("snapshotId", id);
    return selection;
  }

  private static JsonObject update(JsonObject selection, int index) {
    return selection.getAsJsonArray("updates").get(index).getAsJsonObject();
  }

  private static void descriptionsAndOriginalObjects() {
    Fixture fixture = new Fixture();
    FixtureSource source = new FixtureSource(fixture.filters);
    HostFilters registry = new HostFilters();
    HostFilters.Candidate candidate = publish(registry, source, null);
    JsonArray nodes = candidate.description().getAsJsonArray("nodes");
    check(nodes.size() == 8, "Eight standard filter kinds were not described");
    for (int index = 0; index < 8; index++)
      check(
          nodes
              .get(index)
              .getAsJsonObject()
              .has(
                  List.of(
                          "header",
                          "separator",
                          "text",
                          "checkBox",
                          "triState",
                          "select",
                          "sort",
                          "group")
                      .get(index)),
          "Wrong filter kind");
    check(
        nodes.get(6).getAsJsonObject().getAsJsonObject("sort").getAsJsonObject("state").isEmpty(),
        "Nullable sort did not retain its explicit state wrapper");
    check(
        nodes.get(7).getAsJsonObject().getAsJsonObject("group").getAsJsonArray("nodes").size() == 2,
        "Group children disappeared");
    FilterList original = registry.apply(source, "g1", selection(id(candidate)));
    check(original == fixture.filters, "Original FilterList was replaced");
    check(
        original.get(7) == fixture.group && fixture.group.getState().get(0) instanceof TagCheckBox,
        "Source-specific Group/CheckBox subclasses were erased");
    check(
        fixture.text.getState().equals("changed")
            && fixture.checkBox.getState()
            && fixture.tri.getState() == 2,
        "Scalar state did not reach the original instances");
    check(
        fixture.select.getState() == 1
            && fixture.sort.getState().getIndex() == 1
            && fixture.sort.getState().getAscending(),
        "Select/sort state changed");
    check(
        fixture.tag.getState() && fixture.nested.getState().equals("deep-changed"),
        "Nested state was not applied");
    check(
        original.stream()
            .filter(filter -> filter instanceof QueryFilter)
            .map(filter -> ((QueryFilter) filter).selectedValue())
            .toList()
            .equals(List.of("Second")),
        "Source-specific marker interface could not read original Select state");
    source.getSearchManga(1, "", original, null);
    check(
        source.query.isEmpty() && source.page == 1 && source.searchedFilters == fixture.filters,
        "Empty-query search did not preserve the Source's original FilterList");
    JsonObject secondPage = selection(id(candidate));
    update(secondPage, 4).add("sort", new JsonObject());
    registry.apply(source, "g1", secondPage);
    check(fixture.sort.getState() == null, "Explicit empty sort did not clear selection");
    update(secondPage, 4).add("sort", json("{\"selection\":{}}"));
    source.getSearchManga(2, "", registry.apply(source, "g1", secondPage), null);
    check(
        fixture.sort.getState().getIndex() == 0 && !fixture.sort.getState().getAscending(),
        "ProtoJSON default index/direction was rejected");
    check(source.page == 2, "Filtered pagination changed pages");
  }

  private static void atomicValidation() {
    Fixture fixture = new Fixture();
    FixtureSource source = new FixtureSource(fixture.filters);
    HostFilters registry = new HostFilters();
    String id = id(publish(registry, source, null));
    List<JsonObject> invalid = new ArrayList<>();
    JsonObject missing = selection(id);
    missing.getAsJsonArray("updates").remove(6);
    invalid.add(missing);
    JsonObject duplicate = selection(id);
    duplicate.getAsJsonArray("updates").set(6, update(duplicate, 0).deepCopy());
    invalid.add(duplicate);
    for (String path :
        List.of(
            "[]",
            "[99]",
            "[7,0,0]",
            "[7,99]",
            "[7]",
            "[0]",
            "[1.5]",
            "[\"2\"]",
            "[true]",
            "[-1]",
            "[4294967296]")) {
      JsonObject value = selection(id);
      update(value, 6).add("path", JsonParser.parseString(path));
      invalid.add(value);
    }
    for (JsonElement wrong :
        List.of(
            new JsonPrimitive(1), new JsonPrimitive(true), JsonNull.INSTANCE, new JsonObject())) {
      JsonObject value = selection(id);
      update(value, 6).add("text", wrong);
      invalid.add(value);
    }
    for (String state : List.of("1.5", "\"1\"", "true", "-1", "3", "4294967296")) {
      JsonObject value = selection(id);
      update(value, 2).add("triState", JsonParser.parseString(state));
      invalid.add(value);
    }
    for (String state : List.of("1.5", "\"1\"", "false", "-1", "2")) {
      JsonObject value = selection(id);
      update(value, 3).add("select", JsonParser.parseString(state));
      invalid.add(value);
    }
    for (String state : List.of("\"true\"", "0", "null")) {
      JsonObject value = selection(id);
      update(value, 5).add("checkBox", JsonParser.parseString(state));
      invalid.add(value);
    }
    for (String state :
        List.of(
            "null",
            "{\"selection\":null}",
            "{\"selection\":{\"index\":2}}",
            "{\"selection\":{\"index\":1.5}}",
            "{\"selection\":{\"index\":\"1\"}}",
            "{\"selection\":{\"ascending\":\"true\"}}",
            "{\"unknown\":1}")) {
      JsonObject value = selection(id);
      update(value, 4).add("sort", JsonParser.parseString(state));
      invalid.add(value);
    }
    JsonObject wrongKind = selection(id);
    update(wrongKind, 6).remove("text");
    update(wrongKind, 6).addProperty("checkBox", true);
    invalid.add(wrongKind);
    JsonObject twoKinds = selection(id);
    update(twoKinds, 6).addProperty("checkBox", true);
    invalid.add(twoKinds);
    JsonObject unknown = selection(id);
    update(unknown, 6).addProperty("unknown", true);
    invalid.add(unknown);
    JsonObject tooLong = selection(id);
    update(tooLong, 6).addProperty("text", "a".repeat(4097));
    invalid.add(tooLong);
    for (JsonObject value : invalid) {
      rejected(
          () -> registry.apply(source, "g1", value), "Invalid full selection accepted: " + value);
      fixture.original();
    }
    JsonObject defaults = selection(id);
    update(defaults, 0).addProperty("text", "");
    update(defaults, 1).addProperty("checkBox", false);
    update(defaults, 2).addProperty("triState", 0);
    update(defaults, 3).addProperty("select", 0);
    update(defaults, 4).add("sort", new JsonObject());
    registry.apply(source, "g1", defaults);
    check(
        fixture.text.getState().isEmpty()
            && !fixture.checkBox.getState()
            && fixture.sort.getState() == null,
        "False/zero/empty explicit updates were lost");
  }

  private static void retentionAndFailures() {
    HostFilters registry = new HostFilters();
    Fixture a = new Fixture(), b = new Fixture(), c = new Fixture();
    FixtureSource source = new FixtureSource(a.filters);
    String first = id(publish(registry, source, null));
    source.filters = b.filters;
    String second = id(publish(registry, source, first));
    check(
        registry.apply(source, "g1", selection(first)) == a.filters,
        "Retained snapshot was displaced by reset");
    source.filters = c.filters;
    HostFilters.Candidate pending =
        registry.capture(source, "g1", json("{\"retainedSnapshotId\":\"" + first + "\"}"));
    check(
        registry.apply(source, "g1", selection(second)) == b.filters,
        "Uncommitted candidate displaced the old draft");
    check(
        registry.apply(source, "g1", selection(first)) == a.filters,
        "Uncommitted candidate displaced the pin");
    rejected(
        () -> registry.apply(source, "g1", selection(id(pending))),
        "Undrained candidate was published");
    // An action/HTTP drain failure discards the candidate without committing either slot.
    source.failCapture = true;
    rejected(
        () -> registry.capture(source, "g1", new JsonObject()), "Failed dynamic capture succeeded");
    source.failCapture = false;
    source.filters = new FilterList(new Filter<Object>("Unknown", new Object()));
    rejected(
        () -> registry.capture(source, "g1", new JsonObject()), "Unknown filter kind was accepted");
    check(
        registry.apply(source, "g1", selection(first)) == a.filters
            && registry.apply(source, "g1", selection(second)) == b.filters,
        "Capture failure destroyed existing snapshots");
    int captures = source.captures;
    rejected(
        () -> registry.capture(source, "g1", json("{\"retainedSnapshotId\":\"missing\"}")),
        "Missing pin was accepted");
    check(captures == source.captures, "Invalid pin invoked Source getFilterList");
    source.filters = c.filters;
    String third = id(publish(registry, source, first));
    rejected(
        () -> registry.apply(source, "g1", selection(second)),
        "Unpinned older draft was kept indefinitely");
    registry.apply(source, "g1", selection(third));
    source.failSearch = true;
    rejected(
        () -> source.getSearchManga(1, "", registry.apply(source, "g1", selection(third)), null),
        "Fixture search did not fail");
    check(
        registry.apply(source, "g1", selection(first)) == a.filters,
        "Failed search displaced retained pagination");
    source.failSearch = false;
    source.getSearchManga(1, "", registry.apply(source, "g1", selection(third)), null);
    check(
        registry.apply(source, "g1", selection(first)) == a.filters,
        "Late successful search displaced retained pagination");
    source.getSearchManga(1, "defaults", source.getFilterList(), null);
    check(
        registry.apply(source, "g1", selection(first)) == a.filters,
        "Default search displaced retained pagination");
    rejected(() -> registry.commit(pending), "Stale candidate committed after a later reset");
    publish(registry, source, null);
    rejected(
        () -> registry.apply(source, "g1", selection(first)),
        "Omitted pin leaked the old retained slot");
  }

  private static void identityAndMutableTrees() {
    Fixture fixture = new Fixture();
    FixtureSource source = new FixtureSource(fixture.filters);
    HostFilters registry = new HostFilters();
    String old = id(publish(registry, source, null));
    FixtureSource other = new FixtureSource(fixture.filters);
    rejected(
        () -> registry.apply(other, "g1", selection(old)),
        "Same-id different Source owner was accepted");
    source.id++;
    rejected(() -> registry.apply(source, "g1", selection(old)), "Changed Source id was accepted");
    source.id--;
    fixture.group.setState(List.of(fixture.nested));
    rejected(
        () -> registry.apply(source, "g1", selection(old)), "Changed group layout was accepted");
    fixture.group.setState(List.of(fixture.tag, new TagGroup(List.of(fixture.nested))));
    Fixture fresh = new Fixture();
    source.filters = fresh.filters;
    String current = id(publish(registry, source, null));
    fresh.select.getValues()[0] = "Replaced";
    rejected(
        () -> registry.apply(source, "g1", selection(current)),
        "Changed choices accepted a stale path");
    source.filters = new Fixture().filters;
    HostFilters.Candidate pending = registry.capture(source, "g1", new JsonObject());
    registry.observeGeneration("g2");
    rejected(() -> registry.commit(pending), "Old-generation candidate committed");
    rejected(
        () -> registry.apply(source, "g2", selection(current)),
        "Old-generation snapshot was accepted");
    HostFilters.Candidate afterGeneration = registry.capture(source, "g2", new JsonObject());
    registry.commit(afterGeneration);
    registry.clear();
    rejected(
        () -> registry.apply(source, "g2", selection(id(afterGeneration))),
        "Init/load clear retained a snapshot");
    rejected(() -> registry.commit(afterGeneration), "Cleared candidate was revived");
  }

  private static void sameTreeResetAndEmptyLists() {
    Fixture fixture = new Fixture();
    FixtureSource source = new FixtureSource(fixture.filters);
    HostFilters registry = new HostFilters();
    String first = id(publish(registry, source, null));
    JsonObject originalQuery = selection(first);
    update(originalQuery, 0).addProperty("text", "first query");
    registry.apply(source, "g1", originalQuery);
    String second = id(publish(registry, source, first));
    registry.apply(source, "g1", selection(second));
    check(fixture.text.getState().equals("changed"), "Second snapshot state was not applied");
    registry.apply(source, "g1", originalQuery);
    check(
        fixture.text.getState().equals("first query"),
        "Retained shared-tree pagination did not restore complete state");
    source.filters = new FilterList();
    String empty = id(publish(registry, source, first));
    JsonObject noUpdates = new JsonObject();
    noUpdates.addProperty("snapshotId", empty);
    check(
        registry.apply(source, "g1", noUpdates) == source.filters,
        "ProtoJSON omitted empty updates were rejected");
    source.filters = new FilterList(new Filter.Header("Defaults only"));
    String headerOnly = id(publish(registry, source, null));
    noUpdates.addProperty("snapshotId", headerOnly);
    check(
        registry.apply(source, "g1", noUpdates).size() == 1,
        "Read-only filter tree required an editable leaf");
  }

  private static void budgetsAndDescriptionValidation() {
    HostFilters registry = new HostFilters();
    FixtureSource source = new FixtureSource(new FilterList());
    java.util.function.Consumer<FilterList> bad =
        filters -> {
          source.filters = filters;
          rejected(
              () -> registry.capture(source, "g1", new JsonObject()),
              "Invalid Source description was accepted");
        };
    bad.accept(new FilterList(new Input("a".repeat(513), "")));
    bad.accept(new FilterList(new Input("Text", "a".repeat(4097))));
    bad.accept(new FilterList(new Choice(new String[] {})));
    bad.accept(new FilterList(new Sort(new String[] {})));
    String[] tooMany = new String[257];
    Arrays.fill(tooMany, "x");
    bad.accept(new FilterList(new Choice(tooMany)));
    bad.accept(new FilterList(new Sort(new String[] {"a".repeat(513)})));
    Choice select = new Choice(new String[] {"Only"});
    select.setState(1);
    bad.accept(new FilterList(select));
    Sort sort = new Sort(new String[] {"Only"});
    sort.setState(new Filter.Sort.Selection(-1, true));
    bad.accept(new FilterList(sort));
    Tri tri = new Tri();
    tri.setState(3);
    bad.accept(new FilterList(tri));
    Input nullable = new Input("Text", "");
    nullable.setState(null);
    bad.accept(new FilterList(nullable));
    TagCheckBox aliased = new TagCheckBox("Same");
    bad.accept(new FilterList(aliased, aliased));
    TagGroup cycle = new TagGroup(new ArrayList<>());
    cycle.setState(List.of(cycle));
    bad.accept(new FilterList(cycle));
    Filter<?> nested = new Input("Leaf", "");
    for (int depth = 0; depth < 7; depth++) nested = new TagGroup(List.of(nested));
    source.filters = new FilterList(nested);
    String deepest = id(publish(registry, source, null));
    check(
        registry.apply(source, "g1", only(deepest, "{\"path\":[0,0,0,0,0,0,0,0],\"text\":\"ok\"}"))
            == source.filters,
        "Depth 8 boundary was rejected");
    bad.accept(new FilterList(new TagGroup(List.of(nested))));
    List<Filter<?>> many = new ArrayList<>();
    for (int index = 0; index < 256; index++) many.add(new Filter.Header(""));
    source.filters = new FilterList(many);
    check(
        publish(registry, source, null).description().getAsJsonArray("nodes").size() == 256,
        "256 node boundary was rejected");
    many.add(new Filter.Header(""));
    bad.accept(new FilterList(many));
    String[] choices = new String[256];
    Arrays.fill(choices, "a".repeat(512));
    source.filters = new FilterList(new Choice(choices));
    publish(registry, source, null);
    bad.accept(new FilterList(new Choice(choices), new Choice(choices)));
    source.filters = new FilterList(new Input("Text", "😀".repeat(2048)));
    String maxText = id(publish(registry, source, null));
    registry.apply(
        source, "g1", only(maxText, "{\"path\":[0],\"text\":\"" + "😀".repeat(2048) + "\"}"));
    check(true, "4096 UTF-16 text boundary failed");
    HostFilters.checkRequest(" ".repeat(128 * 1024));
    rejected(
        () -> HostFilters.checkRequest(" ".repeat(128 * 1024 + 1)), "Oversized request accepted");
    HostFilters.checkRequest("é".repeat(64 * 1024));
    rejected(
        () -> HostFilters.checkRequest("é".repeat(64 * 1024) + "a"),
        "Request budget counted characters instead of UTF-8");
    rejected(
        () -> registry.capture(source, "g1", json("{\"retainedSnapshotId\":true}")),
        "Boolean snapshot id accepted");
    rejected(
        () -> registry.capture(source, "g1", json("{\"unknown\":0}")),
        "Unknown getFilters field accepted");
    for (int length : List.of(200, 201)) {
      JsonObject request = new JsonObject();
      request.addProperty("retainedSnapshotId", "x".repeat(length));
      try {
        registry.capture(source, "g1", request);
        throw new AssertionError("Unknown boundary identifier accepted");
      } catch (IllegalArgumentException expected) {
        check(
            expected.getMessage().contains(length == 200 ? "unavailable" : "exceeds"),
            "Snapshot id limit differs from the 200 UTF-16 contract");
      }
    }
  }

  public static void main(String[] ignored) {
    descriptionsAndOriginalObjects();
    atomicValidation();
    retentionAndFailures();
    identityAndMutableTrees();
    sameTreeResetAndEmptyLists();
    budgetsAndDescriptionValidation();
    System.out.println(
        "HostFilters: " + assertions + " assertions passed (seed JVM; no AOT/network)");
  }
}
