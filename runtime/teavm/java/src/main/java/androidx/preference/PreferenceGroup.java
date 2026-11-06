package androidx.preference;

import android.content.Context;
import java.util.ArrayList;
import java.util.List;

/** Ordered groups retain the original Preference instances and their callbacks. */
public class PreferenceGroup extends Preference {
  private final List<Preference> children = new ArrayList<>();

  public PreferenceGroup(Context context) {
    super(context);
  }

  public boolean addPreference(Preference preference) {
    if (preference == null || preference == this || preference.getParent() != null)
      throw new IllegalArgumentException("Preference already attached or cyclic");
    for (PreferenceGroup parent = getParent(); parent != null; parent = parent.getParent())
      if (parent == preference) throw new IllegalArgumentException("Cyclic preference group");
    children.add(preference);
    preference.hostAttach(getSharedPreferences(), this);
    return true;
  }

  public int getPreferenceCount() {
    return children.size();
  }

  public Preference getPreference(int index) {
    return children.get(index);
  }

  public boolean removePreference(Preference preference) {
    if (!children.remove(preference)) return false;
    preference.hostAttach(null, null);
    return true;
  }

  public void removeAll() {
    for (Preference child : children) child.hostAttach(null, null);
    children.clear();
  }

  @SuppressWarnings("unchecked")
  public <T extends Preference> T findPreference(CharSequence key) {
    if (key == null) return null;
    if (key.toString().equals(getKey())) return (T) this;
    for (Preference child : children) {
      if (key.toString().equals(child.getKey())) return (T) child;
      if (child instanceof PreferenceGroup group) {
        T match = group.findPreference(key);
        if (match != null) return match;
      }
    }
    return null;
  }
}
