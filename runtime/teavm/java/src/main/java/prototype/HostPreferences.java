package prototype;

import android.content.Context;
import android.content.SharedPreferences;
import android.text.method.PasswordTransformationMethod;
import android.widget.EditText;
import androidx.preference.*;
import com.google.gson.*;
import eu.kanade.tachiyomi.source.ConfigurableSource;
import eu.kanade.tachiyomi.source.Source;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Original Preference objects and callbacks, backed by the seed's Source SharedPreferences. */
public final class HostPreferences {
  static final int MAX_DEPTH = 8, MAX_NODES = 256, MAX_OPTIONS = 256;
  static final int MAX_KEY = 200, MAX_LABEL = 512, MAX_SUMMARY = 2048, MAX_TEXT = 4096;
  static final int MAX_ENTRIES = 128, MAX_ENTRY_BYTES = 32 * 1024;
  static final int MAX_BOOTSTRAP_BYTES = 128 * 1024,
      MAX_BOOTSTRAP_ENTRY_BYTES = 64 * 1024,
      MAX_SNAPSHOT_BYTES = 256 * 1024;
  static final int MAX_REQUEST_BYTES = 128 * 1024;
  static final String SESSION = "PREFERENCE_SYNC_SCOPE_CLIENT_SESSION";
  static final String ACCOUNT = "PREFERENCE_SYNC_SCOPE_ACCOUNT";
  private final List<Rule> rules = new ArrayList<>();
  private Snapshot snapshot;
  private String generation;
  private long revision, sequence;

  public synchronized void clear() {
    snapshot = null;
    generation = null;
    revision++;
  }

  public synchronized void observeGeneration(String value) {
    if (value == null || value.isEmpty()) throw invalid("Missing preference generation");
    if (!value.equals(generation)) {
      clear();
      generation = value;
    }
  }

  /** Validate the complete input before writing anything; called before constructing Generated. */
  public synchronized void configure(Context context, String json) {
    bounded(json, MAX_REQUEST_BYTES, "Preference host configuration");
    JsonObject config = object(JsonParser.parseString(json));
    fields(config, "bootstrap", "syncRules");
    List<Rule> approved = new ArrayList<>();
    Set<String> identities = new HashSet<>();
    for (JsonElement item : array(config, "syncRules")) {
      JsonObject rule = object(item);
      fields(rule, "key", "kind", "sourceId");
      String key = key(rule.get("key"));
      String kind = string(rule.get("kind"), 100);
      if (!Set.of("BOOLEAN", "TEXT", "INTEGER", "LONG_INTEGER", "DECIMAL", "STRINGS")
              .contains(kind.replace("PREFERENCE_VALUE_KIND_", ""))
          || !kind.startsWith("PREFERENCE_VALUE_KIND_"))
        throw invalid("Unknown preference rule kind");
      String sourceId = rule.has("sourceId") ? sourceId(rule.get("sourceId")) : null;
      if (!identities.add(String.valueOf(sourceId) + "\n" + key))
        throw invalid("Duplicate preference rule");
      approved.add(new Rule(sourceId, key, kind));
      if (approved.size() > MAX_ENTRIES) throw invalid("Too many preference rules");
    }
    List<Bootstrap> bootstraps = new ArrayList<>();
    if (config.has("bootstrap")) {
      JsonObject bootstrap = object(config.get("bootstrap"));
      bounded(HostJson.write(bootstrap), MAX_BOOTSTRAP_BYTES, "Preference bootstrap");
      fields(bootstrap, "packageName", "sources");
      key(bootstrap.get("packageName"));
      Set<String> sources = new HashSet<>();
      int totalBytes = 0;
      for (JsonElement item : array(bootstrap, "sources")) {
        JsonObject source = object(item);
        fields(source, "sourceId", "entries");
        String id = sourceId(source.get("sourceId"));
        if (!sources.add(id) || sources.size() > 64)
          throw invalid("Duplicate or too many preference sources");
        JsonArray sourceEntries = array(source, "entries");
        Map<String, Object> values = entries(sourceEntries);
        totalBytes += HostJson.write(sourceEntries).getBytes(StandardCharsets.UTF_8).length;
        if (totalBytes > MAX_BOOTSTRAP_ENTRY_BYTES)
          throw invalid("Preference bootstrap entries exceed 64 KiB");
        bootstraps.add(new Bootstrap(id, values));
      }
    }
    clear();
    rules.clear();
    rules.addAll(approved);
    for (Bootstrap bootstrap : bootstraps) {
      SharedPreferences.Editor editor =
          context.getSharedPreferences("source_" + bootstrap.id, Context.MODE_PRIVATE).edit();
      for (Map.Entry<String, Object> entry : bootstrap.values.entrySet())
        put(editor, entry.getKey(), entry.getValue());
      editor.apply();
    }
  }

  /** Setup may launch owned background work; finishRead is called only after owner.drain. */
  public synchronized Read beginRead(Source owner, Context context, String currentGeneration) {
    observeGeneration(currentGeneration);
    PreferenceScreen screen = new PreferenceScreen(context);
    SharedPreferences storage =
        owner instanceof ConfigurableSource configurable
            ? configurable.getSourcePreferences()
            : context.getSharedPreferences("source_" + owner.getId(), Context.MODE_PRIVATE);
    screen.hostAttach(storage, null);
    if (owner instanceof ConfigurableSource configurable)
      configurable.setupPreferenceScreen(screen);
    Snapshot next =
        new Snapshot("preferences-" + ++sequence, owner, currentGeneration, screen, storage);
    List<Preference> ordered = new ArrayList<>();
    collect(screen, storage, ordered, new IdentityHashMap<>(), 1);
    Map<String, Object> values = stored(storage);
    for (Preference preference : ordered)
      next.nodes.put(preference, node(preference, values, true));
    next.layout.addAll(ordered);
    return new Read(this, owner, currentGeneration, revision, next);
  }

  public synchronized JsonObject finishRead(Read read) {
    current(read.registry, read.generation, read.revision);
    JsonObject result = describe(read.snapshot);
    snapshot = read.snapshot;
    return result;
  }

  /** Each validated command invokes its original callback once. No automatic replay is allowed. */
  public synchronized Edit beginEdit(Source owner, String currentGeneration, JsonObject request) {
    checkRequest(HostJson.write(request));
    fields(request, "snapshotId", "path", "change", "click");
    observeGeneration(currentGeneration);
    String id = string(request.get("snapshotId"), MAX_KEY);
    Snapshot selected = snapshot;
    if (selected == null
        || !selected.id.equals(id)
        || selected.owner != owner
        || selected.sourceId != owner.getId()
        || !selected.generation.equals(currentGeneration))
      throw invalid("Preference snapshot expired or belongs to another Source");
    // Recheck the original layout and dependencies before invoking a callback.
    describe(selected);
    Preference target = at(selected.screen, requiredArray(request, "path"));
    Node node = selected.nodes.get(target);
    if (node == null || !target.isEnabled() || !visible(target) || !target.isSelectable())
      throw invalid("Preference is unavailable");
    boolean change = request.has("change"), click = request.has("click");
    if (change == click) throw invalid("Exactly one preference command is required");
    Object value = change ? value(request.get("change")) : null;
    if (change) validateChange(node, value);
    else {
      fields(object(request.get("click")));
      if (!node.kind.equals("action") || target.getOnPreferenceClickListener() == null)
        throw invalid("Preference does not support a click action");
    }
    // Bound and validate the entire real storage before an irreversible callback.
    stored(selected.storage);
    boolean accepted = false, handled = false;
    if (change) {
      accepted = acceptsTextProposal(node, value) && target.callChangeListener(value);
      if (accepted) {
        assign(target, value);
        if (target.isPersistent() && target.hasKey()) {
          SharedPreferences.Editor editor = selected.storage.edit();
          put(editor, target.getKey(), value);
          editor.apply();
        }
      }
    } else handled = target.getOnPreferenceClickListener().onPreferenceClick(target);
    return new Edit(this, currentGeneration, revision, selected, accepted, handled);
  }

  /** Re-read after background callbacks settle, including aliases and dynamic enabled/summary fields. */
  public synchronized JsonObject finishEdit(Edit edit) {
    current(edit.registry, edit.generation, edit.revision);
    if (snapshot != edit.snapshot) throw invalid("Preference edit expired");
    JsonObject result = new JsonObject();
    result.addProperty("accepted", edit.accepted);
    result.addProperty("clickHandled", edit.handled);
    result.add("snapshot", describe(edit.snapshot));
    bounded(HostJson.write(result), MAX_SNAPSHOT_BYTES, "Preference edit result");
    return result;
  }

  private void current(HostPreferences registry, String value, long expectedRevision) {
    if (registry != this || revision != expectedRevision || !Objects.equals(generation, value))
      throw invalid("Preference operation expired");
  }

  private JsonObject describe(Snapshot selected) {
    Map<String, Object> stored = stored(selected.storage);
    List<Preference> ordered = new ArrayList<>();
    collect(selected.screen, selected.storage, ordered, new IdentityHashMap<>(), 1);
    Set<String> secrets = new HashSet<>();
    if (ordered.size() != selected.layout.size())
      throw invalid("Preference layout changed during operation");
    for (int i = 0; i < ordered.size(); i++)
      if (ordered.get(i) != selected.layout.get(i))
        throw invalid("Preference layout changed during operation");
    for (Preference preference : ordered) {
      Node previous = selected.nodes.get(preference);
      if (previous == null) throw invalid("Preference layout changed during operation");
      Node node = node(preference, stored, false);
      node.secret = previous.secret;
      node.inputType = previous.inputType;
      node.hint = previous.hint;
      node.selectAllOnOpen = previous.selectAllOnOpen;
      node.textInput = previous.textInput;
      if (previous.kind.equals("unsupported")) {
        node.kind = previous.kind;
        node.reason = previous.reason;
      }
      selected.nodes.put(preference, node);
      if (node.secret && preference.hasKey()) secrets.add(preference.getKey());
      preference.hostDependencyMet(true);
    }
    Map<String, Preference> byKey = new HashMap<>();
    for (Preference preference : ordered)
      if (preference.hasKey() && byKey.put(preference.getKey(), preference) != null)
        throw invalid("Duplicate preference key");
    for (Preference preference : ordered) dependencies(preference, byKey, new IdentityHashMap<>());
    JsonObject description = new JsonObject();
    description.addProperty("snapshotId", selected.id);
    description.add("nodes", children(selected.screen, selected, secrets));
    JsonArray sync = new JsonArray(), session = new JsonArray();
    for (Map.Entry<String, Object> entry : stored.entrySet()) {
      JsonObject item = entry(entry.getKey(), entry.getValue());
      (approved(selected.sourceId, entry.getKey(), entry.getValue(), secrets) ? sync : session)
          .add(item);
    }
    description.add("syncValues", sync);
    description.add("sessionValues", session);
    bounded(HostJson.write(description), MAX_SNAPSHOT_BYTES, "Preference snapshot");
    return description;
  }

  private static void collect(
      PreferenceGroup group,
      SharedPreferences storage,
      List<Preference> ordered,
      IdentityHashMap<Preference, Boolean> seen,
      int depth) {
    if (depth > MAX_DEPTH) throw invalid("Preference group depth exceeds 8");
    for (int i = 0; i < group.getPreferenceCount(); i++) {
      Preference preference = group.getPreference(i);
      if (preference == null || seen.put(preference, true) != null)
        throw invalid("Repeated or cyclic preference");
      if (ordered.size() >= MAX_NODES) throw invalid("Preference nodes exceed 256");
      preference.hostAttach(storage, group);
      ordered.add(preference);
      if (preference instanceof PreferenceGroup children && children.getPreferenceCount() > 0)
        collect(children, storage, ordered, seen, depth + 1);
    }
  }

  private static Node node(Preference preference, Map<String, Object> stored, boolean bind) {
    Node node = new Node(preference);
    Object current =
        preference.hasKey() && stored.containsKey(preference.getKey())
            ? stored.get(preference.getKey())
            : bind ? preference.hostDefaultValue() : null;
    if (preference instanceof PreferenceGroup) node.kind = "group";
    else if (preference instanceof TwoStatePreference toggle) {
      node.kind = "toggle";
      if (current != null) {
        if (!(current instanceof Boolean)) throw invalid("Toggle value has wrong type");
        toggle.setChecked((Boolean) current);
      }
    } else if (preference instanceof EditTextPreference text) {
      node.kind = "text";
      node.inputType = 1;
      if (current != null) {
        if (!(current instanceof String)) throw invalid("Text value has wrong type");
        text.setText((String) current);
      }
      if (bind && text.getOnBindEditTextListener() != null)
        try {
          EditText input = EditText.hostPreferenceInput(preference.getContext(), text.getText());
          text.getOnBindEditTextListener().onBindEditText(input);
          input.hostFinishBinding();
          node.inputType = input.getInputType();
          int type = node.inputType & 0xf, variation = node.inputType & 0xff0;
          node.secret =
              input.getTransformationMethod() instanceof PasswordTransformationMethod
                  || type == 1 && (variation == 0x80 || variation == 0x90 || variation == 0xe0)
                  || type == 2 && variation == 0x10;
          if (!node.secret && input.getHint() != null) {
            String hint = input.getHint().toString();
            if (hint.length() <= MAX_LABEL
                && hint.getBytes(StandardCharsets.UTF_8).length <= MAX_LABEL) node.hint = hint;
          }
          node.selectAllOnOpen = input.hostSelectAllOnOpen();
          node.textInput = input;
        } catch (UnsupportedOperationException | LinkageError unsupported) {
          node.kind = "unsupported";
          node.secret = true;
          node.reason = "Android input binding requires unsupported UI capabilities";
        }
    } else if (preference instanceof ListPreference choice) {
      node.kind = "choice";
      node.options = options(choice.getEntries(), choice.getEntryValues());
      if (current != null) {
        if (!(current instanceof String)) throw invalid("Choice value has wrong type");
        choice.setValue((String) current);
      }
    } else if (preference instanceof MultiSelectListPreference multi) {
      node.kind = "multiChoice";
      node.options = options(multi.getEntries(), multi.getEntryValues());
      if (current != null) {
        Set<String> values = stringSet(current);
        multi.setValues(values);
      }
    } else if (preference.getClass() == Preference.class
        && preference.getOnPreferenceClickListener() != null) node.kind = "action";
    else {
      node.kind = "unsupported";
      node.reason = "Unsupported Android preference type or action";
    }
    if (!preference.hasKey()
        && Set.of("toggle", "text", "choice", "multiChoice").contains(node.kind)) {
      node.kind = "unsupported";
      node.reason = "Editable preference has no storage key";
    }
    return node;
  }

  private static void dependencies(
      Preference preference,
      Map<String, Preference> byKey,
      IdentityHashMap<Preference, Boolean> visiting) {
    if (visiting.put(preference, true) != null) throw invalid("Cyclic preference dependency");
    if (preference.getParent() != null && byKey.containsValue(preference.getParent()))
      dependencies(preference.getParent(), byKey, visiting);
    String dependency = preference.getDependency();
    if (dependency != null && !dependency.isEmpty()) {
      Preference required = byKey.get(dependency);
      if (required == null) throw invalid("Missing preference dependency");
      dependencies(required, byKey, visiting);
      boolean disabled = !required.isEnabled();
      if (required instanceof TwoStatePreference toggle)
        disabled |= toggle.getDisableDependentsState() ? toggle.isChecked() : !toggle.isChecked();
      else if (required instanceof EditTextPreference text)
        disabled |= text.getText() == null || text.getText().isEmpty();
      preference.hostDependencyMet(!disabled);
    }
    visiting.remove(preference);
  }

  private JsonArray children(PreferenceGroup group, Snapshot selected, Set<String> secrets) {
    JsonArray result = new JsonArray();
    for (int i = 0; i < group.getPreferenceCount(); i++) {
      Preference preference = group.getPreference(i);
      Node node = selected.nodes.get(preference);
      JsonObject description = new JsonObject();
      description.addProperty(
          "key", preference.hasKey() ? key(new JsonPrimitive(preference.getKey())) : "");
      description.addProperty("title", label(preference.getTitle(), MAX_LABEL));
      String summary = label(preference.getSummary(), MAX_SUMMARY);
      if (preference instanceof ListPreference list && summary.contains("%s"))
        summary = summary.replace("%s", list.getEntry() == null ? "" : list.getEntry().toString());
      description.addProperty("summary", node.secret ? "" : label(summary, MAX_SUMMARY));
      description.addProperty(
          "enabled", preference.isEnabled() && (node.options == null || !node.options.isEmpty()));
      description.addProperty("visible", visible(preference));
      Object nodeValue = nodeValue(preference);
      description.addProperty(
          "syncScope",
          preference.hasKey()
                  && !node.secret
                  && approved(selected.sourceId, preference.getKey(), nodeValue, secrets)
              ? ACCOUNT
              : SESSION);
      if (preference.hostDefaultValue() != null
          && !node.secret
          && !node.kind.equals("unsupported")
          && !node.kind.equals("group")
          && !node.kind.equals("action"))
        description.add("defaultValue", encoded(preference.hostDefaultValue()));
      JsonObject state = new JsonObject();
      switch (node.kind) {
        case "group":
          state.add("nodes", children((PreferenceGroup) preference, selected, secrets));
          break;
        case "toggle":
          state.addProperty("value", ((TwoStatePreference) preference).isChecked());
          break;
        case "text":
          if (((EditTextPreference) preference).getText() != null)
            state.addProperty("value", text(((EditTextPreference) preference).getText()));
          state.addProperty("secret", node.secret);
          state.addProperty("inputType", node.inputType);
          if (node.hint != null) state.addProperty("hint", node.hint);
          state.addProperty("selectAllOnOpen", node.selectAllOnOpen);
          break;
        case "choice":
          state.add("options", node.options);
          if (((ListPreference) preference).getValue() != null)
            state.addProperty("value", text(((ListPreference) preference).getValue()));
          break;
        case "multiChoice":
          state.add("options", node.options);
          state.add("values", strings(((MultiSelectListPreference) preference).getValues()));
          break;
        case "unsupported":
          state.addProperty("reason", node.reason);
          break;
        case "action":
          break;
        default:
          throw invalid("Unknown preference kind");
      }
      description.add(node.kind, state);
      result.add(description);
    }
    return result;
  }

  private static Object nodeValue(Preference preference) {
    if (preference instanceof TwoStatePreference toggle) return toggle.isChecked();
    if (preference instanceof EditTextPreference text) return text.getText();
    if (preference instanceof ListPreference list) return list.getValue();
    if (preference instanceof MultiSelectListPreference multi) return multi.getValues();
    return null;
  }

  private boolean approved(long sourceId, String key, Object value, Set<String> secrets) {
    if (value == null || secrets.contains(key)) return false;
    String kind = kind(value);
    for (Rule rule : rules)
      if (rule.key.equals(key)
          && rule.kind.equals(kind)
          && (rule.sourceId == null || rule.sourceId.equals(Long.toString(sourceId)))) return true;
    return false;
  }

  private static boolean visible(Preference preference) {
    for (Preference current = preference; current != null; current = current.getParent())
      if (!current.isVisible()) return false;
    return true;
  }

  private static Preference at(PreferenceGroup root, JsonArray path) {
    if (path.isEmpty() || path.size() > MAX_DEPTH) throw invalid("Invalid preference path");
    Preference current = root;
    for (JsonElement element : path) {
      int index = integer(element);
      if (!(current instanceof PreferenceGroup group)
          || index < 0
          || index >= group.getPreferenceCount()) throw invalid("Preference path is out of bounds");
      current = group.getPreference(index);
    }
    return current;
  }

  private static boolean acceptsTextProposal(Node node, Object value) {
    if (node.textInput == null) return true;
    if (!(node.preference instanceof EditTextPreference text)
        || !(value instanceof String proposal)) return false;
    try {
      return node.textInput.hostValidateProposal(text.getText(), proposal);
    } catch (RuntimeException | LinkageError rejected) {
      // The validator is part of the original input. Do not commit or surface its raw exception.
      return false;
    }
  }

  private static void validateChange(Node node, Object value) {
    boolean valid =
        switch (node.kind) {
          case "toggle" -> value instanceof Boolean;
          case "text" -> value instanceof String;
          case "choice" ->
              !node.options.isEmpty()
                  && value instanceof String
                  && includes(node.options, (String) value);
          case "multiChoice" ->
              !node.options.isEmpty()
                  && value instanceof Set
                  && stringSet(value).stream().allMatch(item -> includes(node.options, item));
          default -> false;
        };
    if (!valid) throw invalid("Preference change has wrong type or unsupported value");
  }

  private static void assign(Preference preference, Object value) {
    if (preference instanceof TwoStatePreference toggle) toggle.setChecked((Boolean) value);
    else if (preference instanceof EditTextPreference text) text.setText((String) value);
    else if (preference instanceof ListPreference choice) choice.setValue((String) value);
    else if (preference instanceof MultiSelectListPreference multi)
      multi.setValues(stringSet(value));
  }

  private static boolean includes(JsonArray options, String value) {
    for (JsonElement option : options)
      if (option.getAsJsonObject().get("value").getAsString().equals(value)) return true;
    return false;
  }

  private static JsonArray options(CharSequence[] labels, CharSequence[] values) {
    if (labels == null
        || values == null
        || labels.length != values.length
        || labels.length > MAX_OPTIONS) throw invalid("Invalid preference options");
    JsonArray options = new JsonArray();
    Set<String> seen = new HashSet<>();
    for (int i = 0; i < labels.length; i++) {
      String value = text(Objects.requireNonNull(values[i]).toString());
      if (!seen.add(value)) throw invalid("Duplicate preference option value");
      JsonObject option = new JsonObject();
      option.addProperty("label", label(labels[i], MAX_LABEL));
      option.addProperty("value", value);
      options.add(option);
    }
    return options;
  }

  private static Map<String, Object> stored(SharedPreferences storage) {
    Map<String, ?> values = storage.getAll();
    if (values.size() > MAX_ENTRIES) throw invalid("Source preference entries exceed 128");
    Map<String, Object> result = new TreeMap<>();
    JsonArray encoded = new JsonArray();
    for (Map.Entry<String, ?> entry : values.entrySet()) {
      String key = key(new JsonPrimitive(entry.getKey()));
      Object value = entry.getValue();
      if (value == null) throw invalid("Stored preference value is null");
      JsonObject item = entry(key, value);
      result.put(key, value instanceof Set ? stringSet(value) : value);
      encoded.add(item);
    }
    bounded(HostJson.write(encoded), MAX_ENTRY_BYTES, "Source preference entries");
    return result;
  }

  private static Map<String, Object> entries(JsonArray entries) {
    if (entries.size() > MAX_ENTRIES) throw invalid("Source preference entries exceed 128");
    bounded(HostJson.write(entries), MAX_ENTRY_BYTES, "Source preference entries");
    Map<String, Object> result = new LinkedHashMap<>();
    for (JsonElement element : entries) {
      JsonObject entry = object(element);
      fields(entry, "key", "value");
      String key = key(entry.get("key"));
      if (result.put(key, value(entry.get("value"))) != null)
        throw invalid("Duplicate stored preference key");
    }
    return result;
  }

  private static void put(SharedPreferences.Editor editor, String key, Object value) {
    if (value instanceof Boolean item) editor.putBoolean(key, item);
    else if (value instanceof String item) editor.putString(key, item);
    else if (value instanceof Integer item) editor.putInt(key, item);
    else if (value instanceof Long item) editor.putLong(key, item);
    else if (value instanceof Float item) editor.putFloat(key, item);
    else if (value instanceof Set) editor.putStringSet(key, stringSet(value));
    else throw invalid("Unsupported preference storage type");
  }

  private static String kind(Object value) {
    if (value instanceof Boolean) return "PREFERENCE_VALUE_KIND_BOOLEAN";
    if (value instanceof String) return "PREFERENCE_VALUE_KIND_TEXT";
    if (value instanceof Integer) return "PREFERENCE_VALUE_KIND_INTEGER";
    if (value instanceof Long) return "PREFERENCE_VALUE_KIND_LONG_INTEGER";
    if (value instanceof Float) return "PREFERENCE_VALUE_KIND_DECIMAL";
    if (value instanceof Set) return "PREFERENCE_VALUE_KIND_STRINGS";
    throw invalid("Unsupported preference storage type");
  }

  private static JsonObject entry(String key, Object value) {
    JsonObject entry = new JsonObject();
    entry.addProperty("key", key);
    entry.add("value", encoded(value));
    return entry;
  }

  private static JsonObject encoded(Object value) {
    JsonObject result = new JsonObject();
    switch (kind(value)) {
      case "PREFERENCE_VALUE_KIND_BOOLEAN":
        result.addProperty("boolean", (Boolean) value);
        break;
      case "PREFERENCE_VALUE_KIND_TEXT":
        result.addProperty("text", text((String) value));
        break;
      case "PREFERENCE_VALUE_KIND_INTEGER":
        result.addProperty("integer", (Integer) value);
        break;
      case "PREFERENCE_VALUE_KIND_LONG_INTEGER":
        result.addProperty("longInteger", Long.toString((Long) value));
        break;
      case "PREFERENCE_VALUE_KIND_DECIMAL":
        if (!Float.isFinite((Float) value)) throw invalid("Non-finite preference decimal");
        result.addProperty("decimal", (Float) value);
        break;
      case "PREFERENCE_VALUE_KIND_STRINGS":
        JsonObject set = new JsonObject();
        set.add("values", strings(value));
        result.add("strings", set);
        break;
      default:
        throw invalid("Unsupported preference storage type");
    }
    return result;
  }

  private static Object value(JsonElement element) {
    JsonObject value = object(element);
    fields(value, "boolean", "text", "integer", "longInteger", "decimal", "strings");
    if (value.size() != 1) throw invalid("Exactly one preference value is required");
    if (value.has("boolean")) {
      JsonElement item = value.get("boolean");
      if (!item.isJsonPrimitive() || !item.getAsJsonPrimitive().isBoolean())
        throw invalid("Expected preference boolean");
      return item.getAsBoolean();
    }
    if (value.has("text")) return string(value.get("text"), MAX_TEXT);
    if (value.has("integer")) return integer(value.get("integer"));
    if (value.has("longInteger")) {
      String item = string(value.get("longInteger"), 20);
      try {
        long parsed = Long.parseLong(item);
        if (!Long.toString(parsed).equals(item)) throw invalid("Noncanonical preference long");
        return parsed;
      } catch (NumberFormatException error) {
        throw invalid("Preference long is out of range");
      }
    }
    if (value.has("decimal")) {
      JsonElement item = value.get("decimal");
      if (!item.isJsonPrimitive() || !item.getAsJsonPrimitive().isNumber())
        throw invalid("Expected preference decimal");
      float result = item.getAsFloat();
      if (!Float.isFinite(result)) throw invalid("Preference decimal is out of range");
      return result;
    }
    JsonObject set = object(value.get("strings"));
    fields(set, "values");
    Set<String> result = new LinkedHashSet<>();
    JsonArray items = array(set, "values");
    if (items.size() > MAX_OPTIONS) throw invalid("Preference set exceeds 256 values");
    for (JsonElement item : items)
      if (!result.add(string(item, MAX_TEXT))) throw invalid("Duplicate preference set value");
    return result;
  }

  private static Set<String> stringSet(Object value) {
    if (!(value instanceof Set<?> items) || items.size() > MAX_OPTIONS)
      throw invalid("Expected bounded preference string set");
    Set<String> result = new TreeSet<>();
    for (Object item : items) {
      if (!(item instanceof String)) throw invalid("Expected preference string set member");
      result.add(text((String) item));
    }
    return result;
  }

  private static JsonArray strings(Object value) {
    JsonArray result = new JsonArray();
    for (String item : stringSet(value)) result.add(item);
    return result;
  }

  static void checkRequest(String json) {
    bounded(json, MAX_REQUEST_BYTES, "Preference request");
  }

  private static void bounded(String json, int limit, String name) {
    if (json == null || json.getBytes(StandardCharsets.UTF_8).length > limit)
      throw invalid(name + " exceeds byte limit");
  }

  private static JsonObject object(JsonElement value) {
    if (value == null || !value.isJsonObject()) throw invalid("Expected preference object");
    return value.getAsJsonObject();
  }

  private static JsonArray array(JsonObject value, String name) {
    return value.has(name) ? requiredArray(value, name) : new JsonArray();
  }

  private static JsonArray requiredArray(JsonObject value, String name) {
    if (!value.has(name) || !value.get(name).isJsonArray())
      throw invalid("Expected preference array");
    return value.getAsJsonArray(name);
  }

  private static void fields(JsonObject value, String... names) {
    Set<String> allowed = new HashSet<>(Arrays.asList(names));
    for (String key : value.keySet())
      if (!allowed.contains(key)) throw invalid("Unknown preference field");
  }

  private static String string(JsonElement value, int limit) {
    if (value == null || !value.isJsonPrimitive() || !value.getAsJsonPrimitive().isString())
      throw invalid("Expected preference string");
    String result = value.getAsString();
    if (result.length() > limit) throw invalid("Preference string exceeds limit");
    return result;
  }

  private static String key(JsonElement value) {
    String key = string(value, MAX_KEY);
    if (key.isEmpty()) throw invalid("Missing preference key");
    return key;
  }

  private static String sourceId(JsonElement value) {
    String id = string(value, 20);
    try {
      if (!Long.toString(Long.parseLong(id)).equals(id))
        throw invalid("Noncanonical preference Source ID");
    } catch (NumberFormatException error) {
      throw invalid("Invalid preference Source ID");
    }
    return id;
  }

  private static int integer(JsonElement value) {
    if (value == null || !value.isJsonPrimitive() || !value.getAsJsonPrimitive().isNumber())
      throw invalid("Expected preference integer");
    try {
      return new BigDecimal(value.getAsString()).intValueExact();
    } catch (ArithmeticException | NumberFormatException error) {
      throw invalid("Preference integer is out of range");
    }
  }

  private static String text(String value) {
    if (value.length() > MAX_TEXT) throw invalid("Preference text exceeds 4096 units");
    return value;
  }

  private static String label(CharSequence value, int limit) {
    String result = value == null ? "" : value.toString();
    if (result.length() > limit) throw invalid("Preference label exceeds limit");
    return result;
  }

  private static IllegalArgumentException invalid(String message) {
    return new IllegalArgumentException(message);
  }

  private record Rule(String sourceId, String key, String kind) {}

  private record Bootstrap(String id, Map<String, Object> values) {}

  private static final class Node {
    final Preference preference;
    String kind, reason, hint;
    boolean secret, selectAllOnOpen;
    EditText textInput;
    int inputType;
    JsonArray options;

    Node(Preference preference) {
      this.preference = preference;
    }
  }

  private static final class Snapshot {
    final String id, generation;
    final Source owner;
    final long sourceId;
    final PreferenceScreen screen;
    final SharedPreferences storage;
    final IdentityHashMap<Preference, Node> nodes = new IdentityHashMap<>();
    final List<Preference> layout = new ArrayList<>();

    Snapshot(
        String id,
        Source owner,
        String generation,
        PreferenceScreen screen,
        SharedPreferences storage) {
      this.id = id;
      this.owner = owner;
      this.sourceId = owner.getId();
      this.generation = generation;
      this.screen = screen;
      this.storage = storage;
    }
  }

  public static final class Read {
    final HostPreferences registry;
    final Source owner;
    final String generation;
    final long revision;
    final Snapshot snapshot;

    Read(
        HostPreferences registry,
        Source owner,
        String generation,
        long revision,
        Snapshot snapshot) {
      this.registry = registry;
      this.owner = owner;
      this.generation = generation;
      this.revision = revision;
      this.snapshot = snapshot;
    }
  }

  public static final class Edit {
    final HostPreferences registry;
    final String generation;
    final long revision;
    final Snapshot snapshot;
    final boolean accepted, handled;

    Edit(
        HostPreferences registry,
        String generation,
        long revision,
        Snapshot snapshot,
        boolean accepted,
        boolean handled) {
      this.registry = registry;
      this.generation = generation;
      this.revision = revision;
      this.snapshot = snapshot;
      this.accepted = accepted;
      this.handled = handled;
    }
  }
}
