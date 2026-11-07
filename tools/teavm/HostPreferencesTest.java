package prototype;

import android.content.Context;
import android.content.SharedPreferences;
import android.text.Editable;
import android.text.TextWatcher;
import android.text.method.PasswordTransformationMethod;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import androidx.preference.*;
import com.google.gson.*;
import eu.kanade.tachiyomi.source.ConfigurableSource;
import eu.kanade.tachiyomi.source.model.*;
import java.util.*;
import kotlin.coroutines.Continuation;

/** The real seed storage and Preference subclasses; this oracle makes no AOT/online claim. */
public final class HostPreferencesTest {
  private static int assertions;
  private static long sequence = 1000;

  private static void check(boolean value, String message) {
    assertions++;
    if (!value) throw new AssertionError(message);
  }

  private static JsonObject json(String value) {
    return JsonParser.parseString(value).getAsJsonObject();
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

  private interface Marker {
    String marker();
  }

  private static final class SourceChoice extends ListPreference implements Marker {
    SourceChoice(Context context) {
      super(context);
    }

    public String marker() {
      return "original-subclass";
    }
  }

  private static final class CustomPreference extends Preference {
    CustomPreference(Context context) {
      super(context);
    }
  }

  private static final class Fixture implements ConfigurableSource {
    final long id;
    final Context context = new android.app.Application();
    final SharedPreferences storage;
    final boolean constructedWithBootstrap;
    SwitchPreferenceCompat toggle;
    EditTextPreference text, password, transformed, unsupportedInput, dependent;
    SourceChoice choice;
    MultiSelectListPreference multi;
    Preference action, unknown;
    PreferenceCategory group;
    int changes, binds, clicks;
    boolean reject, alias, delayed, emptyOptions, watch, excessivePosts;
    String hint = "Default host";
    final List<String> inputEvents = new ArrayList<>();
    int nestedGroups;
    String textKey = "text";

    Fixture() {
      this(++sequence);
    }

    Fixture(long id) {
      this.id = id;
      storage = context.getSharedPreferences("source_" + id, Context.MODE_PRIVATE);
      constructedWithBootstrap = storage.getBoolean("constructor", false);
    }

    public long getId() {
      return id;
    }

    public String getName() {
      return "Preferences fixture";
    }

    public boolean getSupportsLatest() {
      return false;
    }

    public SharedPreferences getSourcePreferences() {
      return storage;
    }

    public void setupPreferenceScreen(PreferenceScreen screen) {
      toggle = new SwitchPreferenceCompat(context);
      toggle.setKey("toggle");
      toggle.setTitle("Toggle");
      toggle.setDefaultValue(false);
      screen.addPreference(toggle);
      text = new EditTextPreference(context);
      text.setKey(textKey);
      text.setTitle("Text");
      text.setDefaultValue("");
      text.setOnBindEditTextListener(input -> {
        binds++;
        input.setInputType(1);
        if (watch) {
          input.setHint(hint);
          check(
              input.post(() -> {
                check(inputEvents.equals(List.of("bind")), "Post ran before binding finished");
                inputEvents.add("post");
                input.selectAll();
              }),
              "Projected post was rejected");
          input.addTextChangedListener(
              new TextWatcher() {
                @Override
                public void beforeTextChanged(CharSequence value, int start, int count, int after) {
                  check(start == 0 && count == value.length(), "Wrong prior text range");
                  check(
                      value.toString().equals(text.getText()),
                      "Previous stored text changed too soon");
                  inputEvents.add("before");
                }

                @Override
                public void onTextChanged(CharSequence value, int start, int before, int count) {
                  check(start == 0 && count == value.length(), "Wrong candidate text range");
                  inputEvents.add("on");
                }

                @Override
                public void afterTextChanged(Editable value) {
                  inputEvents.add("after");
                  check(
                      value.toString().equals(input.getText().toString()),
                      "Watcher did not receive current input");
                  Button confirm = (Button) input.getRootView().findViewById(android.R.id.button1);
                  switch (value.toString()) {
                    case "bad button" -> confirm.setEnabled(false);
                    case "bad error" -> input.setError(value);
                    case "throws" -> throw new UnsupportedOperationException(value.toString());
                    case "mutates" -> value.clear();
                    default -> {}
                  }
                }
              });
          inputEvents.add("bind");
        }
        if (excessivePosts) {
          Runnable recurring =
              new Runnable() {
                @Override
                public void run() {
                  input.post(this);
                }
              };
          input.post(recurring);
        }
      });
      text.setOnPreferenceChangeListener((original, value) -> {
        changes++;
        check(original == text, "Original text instance was replaced");
        if (alias) {
          storage.edit().putString("ALIAS", ((String) value).trim()).apply();
          text.setSummary("callback summary");
          return false;
        }
        return !reject;
      });
      screen.addPreference(text);
      choice = new SourceChoice(context);
      choice.setKey("choice");
      choice.setTitle("Choice");
      choice.setSummary("Selected: %s");
      choice.setEntries(new String[] {"Alpha", "Beta"});
      choice.setEntryValues(new String[] {"a", "b"});
      choice.setDefaultValue("a");
      choice.setOnPreferenceChangeListener((original, value) -> {
        check(
            ((Marker) original).marker().equals("original-subclass"),
            "Choice concrete subclass lost");
        return true;
      });
      screen.addPreference(choice);
      multi = new MultiSelectListPreference(context);
      multi.setKey("multi");
      multi.setEntries(new String[] {"One", "Two"});
      multi.setEntryValues(new String[] {"one", "two"});
      multi.setDefaultValue(new HashSet<>(Set.of("one")));
      screen.addPreference(multi);
      password = new EditTextPreference(context);
      password.setKey("password");
      password.setDefaultValue("");
      password.setSummary("must not expose credential summary");
      password.setOnBindEditTextListener(input -> {
        input.setInputType(0x81);
        input.setHint("Must not expose secret input hint");
      });
      screen.addPreference(password);
      transformed = new EditTextPreference(context);
      transformed.setKey("transformed");
      transformed.setOnBindEditTextListener(
          input -> input.setTransformationMethod(PasswordTransformationMethod.getInstance()));
      screen.addPreference(transformed);
      group = new PreferenceCategory(context);
      group.setTitle("Category");
      screen.addPreference(group);
      dependent = new EditTextPreference(context);
      dependent.setKey("dependent");
      dependent.setDependency("toggle");
      dependent.setDefaultValue("child");
      group.addPreference(dependent);
      action = new Preference(context);
      action.setKey("action");
      action.setTitle("Run original action");
      action.setOnPreferenceClickListener(original -> {
        clicks++;
        storage.edit().putBoolean("action_alias", true).apply();
        return true;
      });
      screen.addPreference(action);
      unknown = new CustomPreference(context);
      unknown.setKey("unknown");
      screen.addPreference(unknown);
      unsupportedInput = new EditTextPreference(context);
      unsupportedInput.setKey("android_ui");
      unsupportedInput.setOnBindEditTextListener(input -> {
        throw new UnsupportedOperationException("Android dialog is required");
      });
      screen.addPreference(unsupportedInput);
      if (emptyOptions) {
        choice.setEntries(new String[0]);
        choice.setEntryValues(new String[0]);
        multi.setEntries(new String[0]);
        multi.setEntryValues(new String[0]);
      }
      if (nestedGroups > 0) {
        screen.removeAll();
        PreferenceGroup parent = screen;
        for (int i = 0; i < nestedGroups; i++) {
          PreferenceCategory child = new PreferenceCategory(context);
          child.setKey("group" + i);
          parent.addPreference(child);
          parent = child;
        }
      }
    }

    public FilterList getFilterList() {
      return new FilterList();
    }

    public Object getPopularManga(int page, Continuation<? super MangasPage> continuation) {
      throw new UnsupportedOperationException();
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
        boolean chapterList,
        Continuation<? super SMangaUpdate> continuation) {
      throw new UnsupportedOperationException();
    }

    public Object getPageList(
        SChapter chapter, Continuation<? super List<? extends Page>> continuation) {
      throw new UnsupportedOperationException();
    }
  }

  private static JsonObject read(HostPreferences host, Fixture source) {
    return host.finishRead(host.beginRead(source, source.context, "g1"));
  }

  private static JsonObject change(String snapshot, String path, String value) {
    JsonObject request = json("{\"path\":" + path + ",\"change\":" + value + "}");
    request.addProperty("snapshotId", snapshot);
    return request;
  }

  private static JsonObject edit(
      HostPreferences host, Fixture source, JsonObject snapshot, String path, String value) {
    return host.finishEdit(
        host.beginEdit(
            source, "g1", change(snapshot.get("snapshotId").getAsString(), path, value)));
  }

  private static JsonObject node(JsonObject snapshot, int index) {
    return snapshot.getAsJsonArray("nodes").get(index).getAsJsonObject();
  }

  private static boolean contains(JsonObject snapshot, String partition, String key) {
    for (JsonElement entry : snapshot.getAsJsonArray(partition))
      if (entry.getAsJsonObject().get("key").getAsString().equals(key)) return true;
    return false;
  }

  private static JsonObject configured(HostPreferences host, Fixture source) {
    host.configure(
        source.context,
        "{\"syncRules\":["
            + "{\"key\":\"toggle\",\"kind\":\"PREFERENCE_VALUE_KIND_BOOLEAN\"},"
            + "{\"key\":\"choice\",\"kind\":\"PREFERENCE_VALUE_KIND_TEXT\"},"
            + "{\"key\":\"ALIAS\",\"kind\":\"PREFERENCE_VALUE_KIND_TEXT\",\"sourceId\":\""
            + source.id
            + "\"},"
            + "{\"key\":\"password\",\"kind\":\"PREFERENCE_VALUE_KIND_TEXT\"}]}");
    return read(host, source);
  }

  private static void bootstrap() {
    HostPreferences host = new HostPreferences();
    long id = ++sequence;
    Context context = new android.app.Application();
    host.configure(
        context,
        "{\"bootstrap\":{\"packageName\":\"fixture\",\"sources\":[{\"sourceId\":\""
            + id
            + "\",\"entries\":["
            + "{\"key\":\"constructor\",\"value\":{\"boolean\":true}},"
            + "{\"key\":\"empty\",\"value\":{\"text\":\"\"}},"
            + "{\"key\":\"int\",\"value\":{\"integer\":2147483647}},"
            + "{\"key\":\"long\",\"value\":{\"longInteger\":\"9223372036854775807\"}},"
            + "{\"key\":\"float\",\"value\":{\"decimal\":1.25}},"
            + "{\"key\":\"set\",\"value\":{\"strings\":{\"values\":[\"b\",\"a\"]}}}]}]}}");
    Fixture source = new Fixture(id);
    check(source.constructedWithBootstrap, "Constructor did not see bootstrap");
    check(source.storage.getString("empty", "missing").isEmpty(), "Explicit empty text lost");
    check(source.storage.getInt("int", 0) == Integer.MAX_VALUE, "Integer width changed");
    check(source.storage.getLong("long", 0) == Long.MAX_VALUE, "Long precision changed");
    check(source.storage.getFloat("float", 0) == 1.25f, "Float width changed");
    check(source.storage.getStringSet("set", Set.of()).equals(Set.of("a", "b")), "String set lost");
    JsonObject snapshot = read(host, source);
    check(
        snapshot.getAsJsonArray("syncValues").isEmpty(),
        "Unknown bootstrap values became syncable");
    check(snapshot.getAsJsonArray("sessionValues").size() == 6, "Actual stored bootstrap missing");
    String prefix =
        "{\"bootstrap\":{\"packageName\":\"fixture\",\"sources\":[{\"sourceId\":\""
            + id
            + "\",\"entries\":[{\"key\":\"early\",\"value\":{\"text\":\"changed\"}},";
    for (String bad :
        List.of(
            "{\"integer\":1.5}",
            "{\"integer\":\"1\"}",
            "{\"boolean\":\"true\"}",
            "{\"longInteger\":2}",
            "{\"longInteger\":\"9223372036854775808\"}",
            "{\"decimal\":1e100}",
            "{\"text\":false}",
            "{}",
            "{\"integer\":1,\"text\":\"x\"}")) {
      rejected(
          () -> host.configure(context, prefix + "{\"key\":\"tail\",\"value\":" + bad + "}]}]}}"),
          "Malformed bootstrap tail accepted: " + bad);
      check(!source.storage.contains("early"), "Invalid bootstrap partially wrote early key");
    }
  }

  private static void descriptionsAndEdits() {
    HostPreferences host = new HostPreferences();
    Fixture source = new Fixture();
    JsonObject snapshot = configured(host, source);
    check(snapshot.getAsJsonArray("nodes").size() == 10, "Nodes lost");
    check(
        !node(snapshot, 0).getAsJsonObject("toggle").get("value").getAsBoolean(),
        "Boolean default lost");
    check(
        node(snapshot, 1).getAsJsonObject("text").get("value").getAsString().isEmpty(),
        "Empty text default lost");
    check(
        node(snapshot, 2)
            .getAsJsonObject("choice")
            .getAsJsonArray("options")
            .get(1)
            .getAsJsonObject()
            .get("value")
            .getAsString()
            .equals("b"),
        "Entry values were replaced by labels");
    check(
        node(snapshot, 2).get("summary").getAsString().equals("Selected: Alpha"),
        "List summary format not projected");
    check(
        node(snapshot, 3).getAsJsonObject("multiChoice").getAsJsonArray("values").size() == 1,
        "Set default lost");
    check(
        node(snapshot, 4).getAsJsonObject("text").get("secret").getAsBoolean(),
        "Password inputType not recognized");
    check(node(snapshot, 4).get("summary").getAsString().isEmpty(), "Password summary exposed");
    check(
        node(snapshot, 4).get("syncScope").getAsString().equals(HostPreferences.SESSION),
        "Password policy override failed");
    check(
        node(snapshot, 5).getAsJsonObject("text").get("secret").getAsBoolean(),
        "Password transformation not recognized");
    check(
        !node(snapshot, 5).getAsJsonObject("text").has("value"),
        "Missing text was changed to empty");
    check(
        node(snapshot, 6).getAsJsonObject("group").getAsJsonArray("nodes").size() == 1,
        "Grouping lost");
    check(!source.dependent.isEnabled(), "Toggle dependency ignored");
    check(
        node(snapshot, 8).has("unsupported") && node(snapshot, 9).has("unsupported"),
        "Unsupported Android controls not explicit");
    check(source.binds == 1, "Bind callback repeated during finish");
    rejected(
        () -> edit(host, source, snapshot, "[6,0]", "{\"text\":\"x\"}"),
        "Disabled dependent edited");
    JsonObject result = edit(host, source, snapshot, "[0]", "{\"boolean\":true}");
    check(
        result.get("accepted").getAsBoolean() && source.storage.getBoolean("toggle", false),
        "Toggle did not persist");
    check(source.dependent.isEnabled(), "Dependency did not update after original toggle");
    check(
        contains(result.getAsJsonObject("snapshot"), "syncValues", "toggle"),
        "Approved toggle not synced");
    edit(host, source, snapshot, "[2]", "{\"text\":\"b\"}");
    check(
        source.storage.getString("choice", "").equals("b"),
        "Choice not persisted using entryValue");
    edit(host, source, snapshot, "[3]", "{\"strings\":{\"values\":[\"two\",\"one\"]}}");
    check(
        source.storage.getStringSet("multi", Set.of()).equals(Set.of("one", "two")),
        "Multi-choice not persisted");
    edit(host, source, snapshot, "[4]", "{\"text\":\"secret\"}");
    JsonObject secret =
        edit(host, source, snapshot, "[1]", "{\"text\":\"plain\"}").getAsJsonObject("snapshot");
    check(
        contains(secret, "sessionValues", "password")
            && !contains(secret, "syncValues", "password"),
        "Secret leaked into account partition");
    check(contains(secret, "sessionValues", "text"), "Unapproved text synced");
    source.reject = true;
    check(
        !edit(host, source, snapshot, "[1]", "{\"text\":\"rejected\"}")
            .get("accepted")
            .getAsBoolean(),
        "Listener rejection lost");
    check(source.storage.getString("text", "").equals("plain"), "Rejected edit persisted UI key");
    source.alias = true;
    JsonObject alias =
        edit(host, source, snapshot, "[1]", "{\"text\":\" alias \"}").getAsJsonObject("snapshot");
    check(
        source.storage.getString("ALIAS", "").equals("alias"),
        "Original alias callback not preserved");
    check(contains(alias, "syncValues", "ALIAS"), "Explicitly approved actual alias omitted");
    check(source.changes == 3 && source.binds == 1, "Original callback replayed by serialization");
    JsonObject click = json("{\"path\":[7],\"click\":{}}");
    click.addProperty("snapshotId", snapshot.get("snapshotId").getAsString());
    check(
        host.finishEdit(host.beginEdit(source, "g1", click)).get("clickHandled").getAsBoolean(),
        "Original click was not handled");
    check(
        source.clicks == 1 && source.storage.getBoolean("action_alias", false),
        "Original click callback not invoked once");
    source.text.setVisible(false);
    rejected(
        () -> edit(host, source, snapshot, "[1]", "{\"text\":\"hidden\"}"),
        "Hidden preference edited");
  }

  private static void validationAndLifecycle() {
    HostPreferences host = new HostPreferences();
    Fixture source = new Fixture();
    JsonObject snapshot = configured(host, source);
    String id = snapshot.get("snapshotId").getAsString();
    for (String path :
        List.of("[]", "[1.5]", "[\"1\"]", "[true]", "[-1]", "[99]", "[1,0]", "[0,0,0,0,0,0,0,0,0]"))
      rejected(
          () -> host.beginEdit(source, "g1", change(id, path, "{\"text\":\"bad\"}")),
          "Malformed path accepted: " + path);
    for (String value :
        List.of(
            "{\"boolean\":\"true\"}",
            "{\"integer\":1.5}",
            "{\"text\":1}",
            "{\"text\":\"x\",\"boolean\":false}",
            "{}"))
      rejected(
          () -> host.beginEdit(source, "g1", change(id, "[1]", value)),
          "Wrong typed value accepted");
    rejected(
        () -> host.beginEdit(source, "g1", change(id, "[2]", "{\"text\":\"label-not-value\"}")),
        "Invalid choice accepted");
    rejected(
        () ->
            host.beginEdit(
                source, "g1", change(id, "[3]", "{\"strings\":{\"values\":[\"invalid\"]}}")),
        "Invalid multi-choice accepted");
    rejected(
        () ->
            host.beginEdit(
                source, "g1", change(id, "[3]", "{\"strings\":{\"values\":[\"one\",\"one\"]}}")),
        "Duplicate set accepted");
    rejected(
        () -> host.beginEdit(source, "g1", change(id, "[8]", "{\"text\":\"x\"}")),
        "Unsupported control edited");
    rejected(
        () ->
            host.beginEdit(
                source, "g1", change(id, "[1]", "{\"text\":\"" + "x".repeat(4097) + "\"}")),
        "Overlong text accepted");
    check(
        source.changes == 0 && !source.storage.contains("text"),
        "Validation invoked callback or mutated storage");
    Fixture sameId = new Fixture(source.id);
    rejected(
        () -> host.beginEdit(sameId, "g1", change(id, "[1]", "{\"text\":\"x\"}")),
        "Another instance adopted snapshot");
    HostPreferences.Read candidate = host.beginRead(source, source.context, "g1");
    host.observeGeneration("g2");
    rejected(() -> host.finishRead(candidate), "Late read published into another generation");
    rejected(
        () -> host.beginEdit(source, "g2", change(id, "[1]", "{\"text\":\"x\"}")),
        "Old generation snapshot adopted");
    JsonObject current = read(host, source);
    HostPreferences.Edit edit =
        host.beginEdit(
            source,
            "g1",
            change(current.get("snapshotId").getAsString(), "[1]", "{\"text\":\"x\"}"));
    host.clear();
    rejected(() -> host.finishEdit(edit), "Late edit escaped lifecycle close");
  }

  private static void lateWritesAndBudgets() {
    HostPreferences host = new HostPreferences();
    Fixture source = new Fixture();
    HostPreferences.Read pending = host.beginRead(source, source.context, "g1");
    source.storage.edit().putString("late_read_alias", "arrived after setup").apply();
    JsonObject snapshot = host.finishRead(pending);
    check(
        contains(snapshot, "sessionValues", "late_read_alias"),
        "Final read missed post-setup alias");
    HostPreferences.Edit pendingEdit =
        host.beginEdit(
            source,
            "g1",
            change(snapshot.get("snapshotId").getAsString(), "[1]", "{\"text\":\"x\"}"));
    source.storage.edit().putString("late_edit_alias", "arrived after callback").apply();
    source.text.setSummary("after drain");
    JsonObject result = host.finishEdit(pendingEdit).getAsJsonObject("snapshot");
    check(
        contains(result, "sessionValues", "late_edit_alias"),
        "Final edit missed post-callback alias");
    check(
        node(result, 1).get("summary").getAsString().equals("after drain"),
        "Final edit returned stale summary");
    check(source.changes == 1 && source.binds == 1, "Final read replayed callbacks");
    source.storage.edit().clear().apply();
    SharedPreferences.Editor editor = source.storage.edit();
    for (int i = 0; i < 129; i++) editor.putString("key" + i, "x");
    editor.apply();
    rejected(() -> read(host, source), "Unbounded actual storage accepted");
    source.storage.edit().clear().putString("large", "x".repeat(4097)).apply();
    rejected(() -> read(host, source), "Oversized stored text accepted");
    source.storage.edit().clear().putFloat("infinite", Float.POSITIVE_INFINITY).apply();
    rejected(() -> read(host, source), "Non-finite stored decimal accepted");
    source.storage.edit().clear().apply();
    for (int i = 0; i < 9; i++)
      source.storage.edit().putString("large" + i, "x".repeat(4096)).apply();
    rejected(() -> read(host, source), "32 KiB entries budget bypassed");
    rejected(
        () -> HostPreferences.checkRequest("x".repeat(128 * 1024 + 1)),
        "Request byte budget bypassed");
  }

  private static String bootstrapMany(long firstId, int sources, int count, int textLength) {
    JsonObject config = new JsonObject(), bootstrap = new JsonObject();
    bootstrap.addProperty("packageName", "fixture");
    JsonArray all = new JsonArray();
    for (int source = 0; source < sources; source++) {
      JsonObject item = new JsonObject();
      item.addProperty("sourceId", Long.toString(firstId + source));
      JsonArray entries = new JsonArray();
      for (int entry = 0; entry < count; entry++) {
        JsonObject value = new JsonObject();
        value.addProperty("text", "x".repeat(textLength));
        JsonObject named = new JsonObject();
        named.addProperty("key", "k" + entry);
        named.add("value", value);
        entries.add(named);
      }
      item.add("entries", entries);
      all.add(item);
    }
    bootstrap.add("sources", all);
    config.add("bootstrap", bootstrap);
    return HostJson.write(config);
  }

  private static void bootstrapBudgets() {
    HostPreferences host = new HostPreferences();
    Context context = new android.app.Application();
    long first = sequence + 10000;
    host.configure(context, bootstrapMany(first, 5, 128, 0));
    check(
        context.getSharedPreferences("source_" + (first + 4), 0).getAll().size() == 128,
        "Valid bootstrap above 512 total entries rejected");
    host.configure(context, bootstrapMany(first + 100, 64, 0, 0));
    check(true, "64 source namespaces accepted");
    rejected(
        () -> host.configure(context, bootstrapMany(first + 200, 65, 0, 0)),
        "65 source namespaces accepted");
    rejected(
        () -> host.configure(context, bootstrapMany(first + 300, 1, 129, 0)),
        "129 per-source entries accepted");
    rejected(
        () -> host.configure(context, bootstrapMany(first + 400, 3, 6, 4000)),
        "Aggregate 64 KiB entries budget bypassed");
    check(
        context.getSharedPreferences("source_" + (first + 400), 0).getAll().isEmpty(),
        "Aggregate failure partially applied bootstrap");
    host.configure(context, bootstrapMany(first + 500, 2, 6, 4000));
    check(
        context.getSharedPreferences("source_" + (first + 501), 0).getAll().size() == 6,
        "Valid larger bootstrap rejected");
    String manyRules =
        "{\"syncRules\":["
            + "{\"key\":\"k\",\"kind\":\"PREFERENCE_VALUE_KIND_TEXT\"},".repeat(2000)
            + "]}";
    rejected(
        () -> host.configure(context, manyRules),
        "Complete host configuration 128 KiB budget bypassed");
  }

  private static void dependencyAndLayout() {
    HostPreferences host = new HostPreferences();
    Fixture source = new Fixture();
    JsonObject snapshot = configured(host, source);
    source.toggle.setDisableDependentsState(true);
    check(
        edit(host, source, snapshot, "[6,0]", "{\"text\":\"inverted\"}")
            .get("accepted")
            .getAsBoolean(),
        "Inverted toggle dependency ignored");
    source.group.setEnabled(false);
    rejected(
        () -> edit(host, source, snapshot, "[6,0]", "{\"text\":\"blocked\"}"),
        "Disabled parent group ignored");
    source.group.setEnabled(true);
    source.text.setDependency("choice");
    source.choice.setDependency("text");
    rejected(
        () -> edit(host, source, snapshot, "[1]", "{\"text\":\"cyclic\"}"),
        "Cyclic dependency accepted");
    source.text.setDependency(null);
    source.choice.setDependency(null);
    source.text.setPersistent(false);
    JsonObject local =
        edit(host, source, snapshot, "[1]", "{\"text\":\"memory-only\"}")
            .getAsJsonObject("snapshot");
    check(
        node(local, 1).getAsJsonObject("text").get("value").getAsString().equals("memory-only"),
        "Nonpersistent memory state reset to default");
    check(!source.storage.contains("text"), "Nonpersistent value written to storage");
    source.text.setKey("k".repeat(200));
    JsonObject boundary =
        edit(host, source, snapshot, "[1]", "{\"text\":\"x\"}").getAsJsonObject("snapshot");
    check(
        node(boundary, 1).get("key").getAsString().length() == 200,
        "200-unit preference key rejected");
    source.text.setKey("k".repeat(201));
    rejected(
        () -> edit(host, source, snapshot, "[1]", "{\"text\":\"x\"}"),
        "201-unit preference key accepted");
    source.text.setKey("text");
    source.storage.edit().putInt("ALIAS", 2).apply();
    check(
        contains(
            edit(host, source, snapshot, "[1]", "{\"text\":\"x\"}").getAsJsonObject("snapshot"),
            "sessionValues",
            "ALIAS"),
        "Wrong type for approved alias synced");
    Fixture other = new Fixture();
    other.storage.edit().putString("ALIAS", "other").apply();
    check(
        !contains(read(host, other), "syncValues", "ALIAS"),
        "Source-specific rule crossed Source boundary");
    JsonObject fixed = read(host, source);
    // Preserve identities and node count but reorder the original children under one parent.
    source.group.removePreference(source.dependent);
    EditTextPreference replacement = new EditTextPreference(source.context);
    replacement.setKey("replacement");
    source.group.addPreference(replacement);
    rejected(
        () -> edit(host, source, fixed, "[6,0]", "{\"text\":\"wrong target\"}"),
        "Changed original node identity adopted stale path");
    source.group.removePreference(replacement);
    source.group.addPreference(source.dependent);
    check(
        source.group.getSharedPreferences() == source.dependent.getSharedPreferences(),
        "Nested original store attachment lost");
    source.textKey = "";
    JsonObject noKey = read(host, source);
    check(node(noKey, 1).has("unsupported"), "Keyless editable row produced invalid wire metadata");
  }

  private static void emptyDynamicOptionsAndDepth() {
    HostPreferences host = new HostPreferences();
    Fixture source = new Fixture();
    source.emptyOptions = true;
    JsonObject snapshot = read(host, source);
    check(
        node(snapshot, 2).getAsJsonObject("choice").getAsJsonArray("options").isEmpty(),
        "Empty dynamic choice rejected");
    check(
        node(snapshot, 3).getAsJsonObject("multiChoice").getAsJsonArray("options").isEmpty(),
        "Empty dynamic multi-choice rejected");
    check(
        !node(snapshot, 2).get("enabled").getAsBoolean()
            && !node(snapshot, 3).get("enabled").getAsBoolean(),
        "Empty choices remained editable");
    rejected(() -> edit(host, source, snapshot, "[2]", "{\"text\":\"a\"}"), "Empty choice edited");
    rejected(
        () -> edit(host, source, snapshot, "[3]", "{\"strings\":{}}"),
        "Empty multi-choice edited with an empty set");
    source.nestedGroups = 8;
    JsonObject deepest = read(host, source);
    JsonObject group = node(deepest, 0);
    for (int i = 1; i < 8; i++)
      group = group.getAsJsonObject("group").getAsJsonArray("nodes").get(0).getAsJsonObject();
    check(
        group.getAsJsonObject("group").getAsJsonArray("nodes").isEmpty(),
        "Depth-eight empty group rejected");
    source.nestedGroups = 9;
    rejected(() -> read(host, source), "Depth-nine group accepted");
  }

  private static void projectedTextValidation() {
    HostPreferences host = new HostPreferences();
    Fixture source = new Fixture();
    source.watch = true;
    source.storage.edit().putString("text", "stored").apply();
    JsonObject snapshot = read(host, source);
    JsonObject projected = node(snapshot, 1).getAsJsonObject("text");
    check(projected.get("hint").getAsString().equals("Default host"), "Bound hint missing");
    check(projected.get("selectAllOnOpen").getAsBoolean(), "Posted select-all missing");
    check(source.inputEvents.equals(List.of("bind", "post")), "Reading ran a validation callback");
    check(!snapshot.toString().contains("Must not expose secret input hint"), "Secret hint leaked");
    for (String candidate : List.of("bad button", "bad error", "throws", "mutates")) {
      source.inputEvents.clear();
      JsonObject result = edit(host, source, snapshot, "[1]", "{\"text\":\"" + candidate + "\"}");
      check(!result.get("accepted").getAsBoolean(), "Rejected text was accepted");
      check(!result.toString().contains(candidate), "Rejected raw proposal or error leaked");
      check(source.inputEvents.equals(List.of("before", "on", "after")), "Watcher phases changed");
      check(source.changes == 0, "Original change callback ran for invalid text");
      check(source.storage.getString("text", "").equals("stored"), "Invalid text reached storage");
    }
    source.inputEvents.clear();
    JsonObject changed = edit(host, source, snapshot, "[1]", "{\"text\":\"valid\"}");
    check(changed.get("accepted").getAsBoolean(), "Validation did not reset after rejection");
    check(source.changes == 1, "Original callback was not invoked once");
    check(source.storage.getString("text", "").equals("valid"), "Valid input was not stored");
    source.alias = true;
    JsonObject alias = edit(host, source, snapshot, "[1]", "{\"text\":\" normalized \"}");
    check(!alias.get("accepted").getAsBoolean(), "Original false result was lost");
    check(source.changes == 2, "Original callback replayed");
    check(
        source.storage.getString("ALIAS", "").equals("normalized"),
        "Original callback write was lost");
    check(
        source.storage.getString("text", "").equals("valid"),
        "Original false default write applied");
    check(
        node(alias.getAsJsonObject("snapshot"), 1).getAsJsonObject("text").has("hint"),
        "Existing metadata was lost during re-read");

    Fixture tooLong = new Fixture();
    tooLong.watch = true;
    tooLong.hint = "字".repeat(200);
    check(
        !node(read(host, tooLong), 1).getAsJsonObject("text").has("hint"), "Oversize hint leaked");
    Fixture overflow = new Fixture();
    overflow.excessivePosts = true;
    check(node(read(host, overflow), 1).has("unsupported"), "Unbounded posted actions accepted");
    rejected(
        () -> new View(source.context).findViewById(android.R.id.button1),
        "Ordinary View gained a fake dialog");
    rejected(
        () -> new EditText(source.context).post(() -> {}), "Ordinary EditText accepted posting");
  }

  public static void main(String[] args) {
    bootstrap();
    descriptionsAndEdits();
    projectedTextValidation();
    validationAndLifecycle();
    lateWritesAndBudgets();
    bootstrapBudgets();
    dependencyAndLayout();
    emptyDynamicOptionsAndDepth();
    System.out.println("HostPreferencesTest: " + assertions + " assertions passed");
  }
}
