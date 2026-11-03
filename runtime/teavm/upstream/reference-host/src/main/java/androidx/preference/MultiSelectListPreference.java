package androidx.preference;
import android.content.Context;
import java.util.HashSet;
import java.util.Set;
public class MultiSelectListPreference extends DialogPreference {
  private CharSequence[] entries = new CharSequence[0], entryValues = new CharSequence[0];
  private Set<String> values = new HashSet<>();
  public MultiSelectListPreference(Context context) { super(context); }
  public void setEntries(CharSequence[] entries) { this.entries = entries.clone(); }
  public CharSequence[] getEntries() { return entries.clone(); }
  public void setEntryValues(CharSequence[] entries) { entryValues = entries.clone(); }
  public CharSequence[] getEntryValues() { return entryValues.clone(); }
  public void setValues(Set<String> values) { this.values = new HashSet<>(values); }
  public Set<String> getValues() { return new HashSet<>(values); }
}
