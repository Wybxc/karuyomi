package androidx.preference;

import android.content.Context;
import android.content.SharedPreferences;

/** Owned headless AndroidX ABI. Values remain in the Source's original SharedPreferences. */
public class Preference {
  protected final Context context;
  private String key;
  private CharSequence title;
  private CharSequence summary;
  private Object defaultValue;
  private boolean enabled = true;
  private boolean visible = true;
  private boolean persistent = true;
  private boolean selectable = true;
  private boolean dependencyMet = true;
  private String dependency;
  private PreferenceGroup parent;
  private SharedPreferences preferences;
  private OnPreferenceChangeListener listener;
  private OnPreferenceClickListener clickListener;

  public Preference(Context context) {
    this.context = context;
  }

  public Context getContext() {
    return context;
  }

  public void setKey(String key) {
    this.key = key;
  }

  public String getKey() {
    return key;
  }

  public boolean hasKey() {
    return key != null && !key.isEmpty();
  }

  public void setTitle(CharSequence title) {
    this.title = title;
  }

  public CharSequence getTitle() {
    return title;
  }

  public void setSummary(CharSequence summary) {
    this.summary = summary;
  }

  public CharSequence getSummary() {
    return summary;
  }

  public void setEnabled(boolean enabled) {
    this.enabled = enabled;
  }

  public boolean isEnabled() {
    return enabled && dependencyMet && (parent == null || parent.isEnabled());
  }

  public void setVisible(boolean visible) {
    this.visible = visible;
  }

  public boolean isVisible() {
    return visible;
  }

  public boolean getVisible() {
    return visible;
  }

  public void setPersistent(boolean persistent) {
    this.persistent = persistent;
  }

  public boolean isPersistent() {
    return persistent;
  }

  public void setSelectable(boolean selectable) {
    this.selectable = selectable;
  }

  public boolean isSelectable() {
    return selectable;
  }

  public void setDependency(String dependency) {
    this.dependency = dependency;
  }

  public String getDependency() {
    return dependency;
  }

  public void setDefaultValue(Object defaultValue) {
    this.defaultValue = defaultValue;
  }

  protected Object getDefaultValue() {
    return defaultValue;
  }

  public final Object hostDefaultValue() {
    return getDefaultValue();
  }

  public final void hostDependencyMet(boolean value) {
    dependencyMet = value;
  }

  public final void hostAttach(SharedPreferences preferences, PreferenceGroup parent) {
    this.preferences = preferences;
    this.parent = parent;
    if (this instanceof PreferenceGroup group)
      for (int i = 0; i < group.getPreferenceCount(); i++)
        group.getPreference(i).hostAttach(preferences, group);
  }

  public SharedPreferences getSharedPreferences() {
    return preferences;
  }

  public PreferenceGroup getParent() {
    return parent;
  }

  public void setOnPreferenceChangeListener(OnPreferenceChangeListener listener) {
    this.listener = listener;
  }

  public OnPreferenceChangeListener getOnPreferenceChangeListener() {
    return listener;
  }

  public boolean callChangeListener(Object value) {
    return listener == null || listener.onPreferenceChange(this, value);
  }

  public void setOnPreferenceClickListener(OnPreferenceClickListener listener) {
    clickListener = listener;
  }

  public OnPreferenceClickListener getOnPreferenceClickListener() {
    return clickListener;
  }

  public interface OnPreferenceChangeListener {
    boolean onPreferenceChange(Preference preference, Object value);
  }

  public interface OnPreferenceClickListener {
    boolean onPreferenceClick(Preference preference);
  }
}
