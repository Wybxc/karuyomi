package prototype;

import com.google.gson.*;
import eu.kanade.tachiyomi.source.Source;
import eu.kanade.tachiyomi.source.model.*;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Ephemeral descriptions keep the original Source filter instances and their concrete subclasses. */
public final class HostFilters {
  static final int MAX_DEPTH = 8;
  static final int MAX_NODES = 256;
  static final int MAX_CHOICES = 256;
  static final int MAX_LABEL = 512;
  static final int MAX_TEXT = 4096;
  static final int MAX_DESCRIPTION_BYTES = 256 * 1024;
  static final int MAX_REQUEST_BYTES = 128 * 1024;
  private Snapshot draft;
  private Snapshot retained;
  private String generation;
  private long revision;
  private long sequence;

  public synchronized void clear() {
    draft = null;
    retained = null;
    generation = null;
    revision++;
  }

  public synchronized void observeGeneration(String value) {
    if (value == null || value.isEmpty()) throw invalid("Missing filter generation");
    if (!value.equals(generation)) {
      clear();
      generation = value;
    }
  }

  /** The candidate is not published until the operation's background HTTP has drained. */
  public Candidate capture(Source owner, String currentGeneration, JsonObject request) {
    checkRequest(HostJson.write(request));
    fields(request, "retainedSnapshotId");
    Snapshot pin;
    long expectedRevision;
    String id;
    synchronized (this) {
      observeGeneration(currentGeneration);
      pin =
          request.has("retainedSnapshotId")
              ? find(owner, currentGeneration, identifier(request.get("retainedSnapshotId")))
              : null;
      expectedRevision = revision;
      id = "filters-" + ++sequence;
    }
    FilterList filters = owner.getFilterList();
    if (filters == null) throw invalid("Source returned a null FilterList");
    List<Node> nodes = new ArrayList<>();
    IdentityHashMap<Filter<?>, Boolean> seen = new IdentityHashMap<>();
    JsonArray descriptions = describe(filters, nodes, seen, 1);
    JsonObject description = new JsonObject();
    description.addProperty("snapshotId", id);
    description.add("nodes", descriptions);
    if (HostJson.write(description).getBytes(StandardCharsets.UTF_8).length > MAX_DESCRIPTION_BYTES)
      throw invalid("Filter description exceeds 256 KiB");
    Snapshot snapshot = new Snapshot(id, owner, currentGeneration, filters, nodes);
    return new Candidate(this, expectedRevision, pin, snapshot, description);
  }

  /** Called only after successful description serialization and operation drain. */
  public synchronized void commit(Candidate candidate) {
    if (candidate.registry != this
        || candidate.revision != revision
        || !candidate.snapshot.generation.equals(generation))
      throw invalid("Filter candidate expired");
    validateLayout(candidate.snapshot.filters, candidate.snapshot.nodes);
    retained = candidate.pin;
    draft = candidate.snapshot;
    revision++;
  }

  /** Validate every leaf before changing any state. Searches never change snapshot ownership. */
  public synchronized FilterList apply(
      Source owner, String currentGeneration, JsonObject selection) {
    checkRequest(HostJson.write(selection));
    observeGeneration(currentGeneration);
    fields(selection, "snapshotId", "updates");
    Snapshot snapshot = find(owner, currentGeneration, identifier(selection.get("snapshotId")));
    validateLayout(snapshot.filters, snapshot.nodes);
    JsonArray updates =
        selection.has("updates")
            ? array(selection.get("updates"), "Filter updates")
            : new JsonArray();
    List<Node> editable = new ArrayList<>();
    collectEditable(snapshot.nodes, editable);
    if (updates.size() != editable.size())
      throw invalid("Supply every editable filter exactly once");
    Set<Node> seen = Collections.newSetFromMap(new IdentityHashMap<>());
    List<Runnable> assignments = new ArrayList<>();
    for (JsonElement item : updates) {
      JsonObject update = object(item, "Filter update");
      fields(update, "path", "text", "checkBox", "triState", "select", "sort");
      JsonArray path = array(update.get("path"), "Filter path");
      if (path.isEmpty() || path.size() > MAX_DEPTH) throw invalid("Invalid filter path depth");
      List<Node> level = snapshot.nodes;
      Node node = null;
      for (int depth = 0; depth < path.size(); depth++) {
        int index = integer(path.get(depth), "Filter path index");
        if (index < 0 || index >= level.size()) throw invalid("Filter path is out of bounds");
        node = level.get(index);
        if (depth + 1 < path.size()) {
          if (!node.kind.equals("group")) throw invalid("Filter path crosses a leaf");
          level = node.children;
        }
      }
      if (node == null || !node.editable() || !seen.add(node))
        throw invalid("Filter path is not a unique editable leaf");
      if (update.size() != 2 || !update.has(node.kind))
        throw invalid("Filter state does not match its original kind");
      assignments.add(assignment(node, update.get(node.kind)));
    }
    for (Runnable assignment : assignments) assignment.run();
    return snapshot.filters;
  }

  private Snapshot find(Source owner, String currentGeneration, String id) {
    Snapshot snapshot =
        draft != null && draft.id.equals(id)
            ? draft
            : retained != null && retained.id.equals(id) ? retained : null;
    if (snapshot == null
        || snapshot.owner != owner
        || snapshot.sourceId != owner.getId()
        || !snapshot.generation.equals(currentGeneration))
      throw invalid("Filter snapshot is unavailable for this Source and generation");
    return snapshot;
  }

  public static void checkRequest(String json) {
    if (json.getBytes(StandardCharsets.UTF_8).length > MAX_REQUEST_BYTES)
      throw invalid("Source filter request exceeds 128 KiB");
  }

  public static final class Candidate {
    private final HostFilters registry;
    private final long revision;
    private final Snapshot pin;
    private final Snapshot snapshot;
    private final JsonObject description;

    private Candidate(
        HostFilters registry,
        long revision,
        Snapshot pin,
        Snapshot snapshot,
        JsonObject description) {
      this.registry = registry;
      this.revision = revision;
      this.pin = pin;
      this.snapshot = snapshot;
      this.description = description;
    }

    public JsonObject description() {
      return description;
    }
  }

  private static final class Snapshot {
    final String id;
    final Source owner;
    final long sourceId;
    final String generation;
    final FilterList filters;
    final List<Node> nodes;

    Snapshot(String id, Source owner, String generation, FilterList filters, List<Node> nodes) {
      this.id = id;
      this.owner = owner;
      this.sourceId = owner.getId();
      this.generation = generation;
      this.filters = filters;
      this.nodes = nodes;
    }
  }

  private static final class Node {
    final Filter<?> filter;
    final String kind;
    final List<Node> children = new ArrayList<>();
    final List<String> options = new ArrayList<>();

    Node(Filter<?> filter, String kind) {
      this.filter = filter;
      this.kind = kind;
    }

    boolean editable() {
      return !kind.equals("header") && !kind.equals("separator") && !kind.equals("group");
    }
  }

  private static JsonArray describe(
      List<?> filters, List<Node> nodes, IdentityHashMap<Filter<?>, Boolean> seen, int depth) {
    JsonArray descriptions = new JsonArray();
    for (Object value : filters) {
      if (depth > MAX_DEPTH) throw invalid("Filter tree exceeds depth 8");
      if (!(value instanceof Filter<?>)) throw invalid("Group contains a non-filter value");
      Filter<?> filter = (Filter<?>) value;
      if (seen.put(filter, Boolean.TRUE) != null)
        throw invalid("Filter tree contains aliases or cycles");
      if (seen.size() > MAX_NODES) throw invalid("Filter tree exceeds 256 nodes");
      JsonObject node = new JsonObject();
      node.addProperty("name", bounded(filter.getName(), MAX_LABEL, "Filter name"));
      JsonObject state = new JsonObject();
      String kind;
      if (filter instanceof Filter.Header) kind = "header";
      else if (filter instanceof Filter.Separator) kind = "separator";
      else if (filter instanceof Filter.Text) {
        kind = "text";
        state.addProperty(
            "state", bounded(((Filter.Text) filter).getState(), MAX_TEXT, "Filter text"));
      } else if (filter instanceof Filter.CheckBox) {
        kind = "checkBox";
        Boolean checked = ((Filter.CheckBox) filter).getState();
        if (checked == null) throw invalid("Null checkbox state");
        state.addProperty("state", checked);
      } else if (filter instanceof Filter.TriState) {
        kind = "triState";
        Integer selected = ((Filter.TriState) filter).getState();
        if (selected == null || selected < 0 || selected > 2)
          throw invalid("Invalid tri-state state");
        state.addProperty("state", selected);
      } else if (filter instanceof Filter.Select<?>) {
        kind = "select";
        Filter.Select<?> select = (Filter.Select<?>) filter;
        List<String> options = options(select.getDisplayValues());
        Integer selected = select.getState();
        if (selected == null || selected < 0 || selected >= options.size())
          throw invalid("Invalid select state");
        state.add("options", strings(options));
        state.addProperty("state", selected);
      } else if (filter instanceof Filter.Sort) {
        kind = "sort";
        Filter.Sort sort = (Filter.Sort) filter;
        List<String> options = options(Arrays.asList(sort.getValues()));
        state.add("options", strings(options));
        state.add("state", sortState(sort.getState(), options.size()));
      } else if (filter instanceof Filter.Group<?>) kind = "group";
      else
        throw new UnsupportedOperationException(
            "Unsupported Source filter " + filter.getClass().getName());
      Node stored = new Node(filter, kind);
      if (kind.equals("select"))
        stored.options.addAll(((Filter.Select<?>) filter).getDisplayValues());
      else if (kind.equals("sort"))
        stored.options.addAll(Arrays.asList(((Filter.Sort) filter).getValues()));
      else if (kind.equals("group")) {
        List<?> children = ((Filter.Group<?>) filter).getState();
        if (children == null) throw invalid("Null filter group");
        state.add("nodes", describe(children, stored.children, seen, depth + 1));
      }
      nodes.add(stored);
      node.add(kind, state);
      descriptions.add(node);
    }
    return descriptions;
  }

  private static List<String> options(List<String> values) {
    if (values.isEmpty() || values.size() > MAX_CHOICES)
      throw invalid("Filter options must contain 1..256 choices");
    List<String> copy = new ArrayList<>();
    for (String value : values) copy.add(bounded(value, MAX_LABEL, "Filter option"));
    return copy;
  }

  private static JsonArray strings(List<String> values) {
    JsonArray array = new JsonArray();
    for (String value : values) array.add(value);
    return array;
  }

  private static JsonObject sortState(Filter.Sort.Selection selection, int choices) {
    JsonObject state = new JsonObject();
    if (selection != null) {
      if (selection.getIndex() < 0 || selection.getIndex() >= choices)
        throw invalid("Invalid sort selection");
      JsonObject value = new JsonObject();
      value.addProperty("index", selection.getIndex());
      value.addProperty("ascending", selection.getAscending());
      state.add("selection", value);
    }
    return state;
  }

  private static void collectEditable(List<Node> nodes, List<Node> output) {
    for (Node node : nodes) {
      if (node.editable()) output.add(node);
      else if (node.kind.equals("group")) collectEditable(node.children, output);
    }
  }

  private static void validateLayout(List<?> filters, List<Node> nodes) {
    if (filters.size() != nodes.size())
      throw invalid("Filter tree changed; reload its description");
    for (int index = 0; index < filters.size(); index++) {
      Node node = nodes.get(index);
      if (filters.get(index) != node.filter)
        throw invalid("Filter tree changed; reload its description");
      if (node.kind.equals("group")) {
        List<?> children = ((Filter.Group<?>) node.filter).getState();
        if (children == null) throw invalid("Filter group changed; reload its description");
        validateLayout(children, node.children);
      } else if (node.kind.equals("select")) {
        if (!node.options.equals(((Filter.Select<?>) node.filter).getDisplayValues()))
          throw invalid("Filter options changed; reload their description");
      } else if (node.kind.equals("sort")) {
        if (!node.options.equals(Arrays.asList(((Filter.Sort) node.filter).getValues())))
          throw invalid("Filter options changed; reload their description");
      }
    }
  }

  private static Runnable assignment(Node node, JsonElement value) {
    switch (node.kind) {
      case "text":
        {
          Filter.Text filter = (Filter.Text) node.filter;
          String text = bounded(string(value, "Filter text"), MAX_TEXT, "Filter text");
          return () -> filter.setState(text);
        }
      case "checkBox":
        {
          Filter.CheckBox filter = (Filter.CheckBox) node.filter;
          boolean checked = bool(value, "Checkbox state");
          return () -> filter.setState(checked);
        }
      case "triState":
        {
          Filter.TriState filter = (Filter.TriState) node.filter;
          int state = integer(value, "Tri-state state");
          if (state < 0 || state > 2) throw invalid("Tri-state state is out of bounds");
          return () -> filter.setState(state);
        }
      case "select":
        {
          Filter.Select<?> filter = (Filter.Select<?>) node.filter;
          int state = integer(value, "Select state");
          if (state < 0 || state >= node.options.size())
            throw invalid("Select state is out of bounds");
          return () -> filter.setState(state);
        }
      case "sort":
        {
          Filter.Sort filter = (Filter.Sort) node.filter;
          JsonObject state = object(value, "Sort state");
          fields(state, "selection");
          Filter.Sort.Selection selection = null;
          if (state.has("selection")) {
            JsonObject selected = object(state.get("selection"), "Sort selection");
            fields(selected, "index", "ascending");
            int index = selected.has("index") ? integer(selected.get("index"), "Sort index") : 0;
            boolean ascending =
                selected.has("ascending") && bool(selected.get("ascending"), "Sort direction");
            if (index < 0 || index >= node.options.size())
              throw invalid("Sort index is out of bounds");
            selection = new Filter.Sort.Selection(index, ascending);
          }
          Filter.Sort.Selection next = selection;
          return () -> filter.setState(next);
        }
      default:
        throw invalid("Filter is not editable");
    }
  }

  private static String identifier(JsonElement value) {
    String id = bounded(string(value, "Filter snapshot id"), 200, "Filter snapshot id");
    if (id.isEmpty()) throw invalid("Missing filter snapshot id");
    return id;
  }

  private static String bounded(String value, int limit, String name) {
    if (value == null || value.length() > limit)
      throw invalid(name + " exceeds its limit or is null");
    return value;
  }

  private static String string(JsonElement value, String name) {
    if (value == null || !value.isJsonPrimitive() || !value.getAsJsonPrimitive().isString())
      throw invalid(name + " must be a string");
    return value.getAsString();
  }

  private static boolean bool(JsonElement value, String name) {
    if (value == null || !value.isJsonPrimitive() || !value.getAsJsonPrimitive().isBoolean())
      throw invalid(name + " must be a boolean");
    return value.getAsBoolean();
  }

  private static int integer(JsonElement value, String name) {
    if (value == null || !value.isJsonPrimitive() || !value.getAsJsonPrimitive().isNumber())
      throw invalid(name + " must be an integer");
    try {
      return new BigDecimal(value.getAsString()).intValueExact();
    } catch (ArithmeticException | NumberFormatException error) {
      throw invalid(name + " must be a bounded integer");
    }
  }

  private static JsonObject object(JsonElement value, String name) {
    if (value == null || !value.isJsonObject()) throw invalid(name + " must be an object");
    return value.getAsJsonObject();
  }

  private static JsonArray array(JsonElement value, String name) {
    if (value == null || !value.isJsonArray()) throw invalid(name + " must be an array");
    return value.getAsJsonArray();
  }

  private static void fields(JsonObject value, String... allowed) {
    for (String key : value.keySet())
      if (!Arrays.asList(allowed).contains(key)) throw invalid("Unknown filter field " + key);
  }

  private static IllegalArgumentException invalid(String message) {
    return new IllegalArgumentException(message);
  }
}
