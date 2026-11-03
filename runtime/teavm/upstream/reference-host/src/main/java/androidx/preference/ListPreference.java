package androidx.preference;
import android.content.Context;
public class ListPreference extends DialogPreference {
  private CharSequence[] entries = new CharSequence[0], entryValues = new CharSequence[0];
  private String value;
  public ListPreference(Context context) { super(context); }
  public void setEntries(CharSequence[] entries) { this.entries = entries.clone(); }
  public CharSequence[] getEntries() { return entries.clone(); }
  public void setEntryValues(CharSequence[] values) { entryValues = values.clone(); }
  public CharSequence[] getEntryValues() { return entryValues.clone(); }
  public void setValue(String value) { this.value = value; }
  public String getValue() { return value; }
  public void setValueIndex(int index) { setValue(entryValues[index].toString()); }
  public int findIndexOfValue(String value) {
    for (int i = entryValues.length - 1; i >= 0; i--) if (entryValues[i].toString().equals(value)) return i;
    return -1;
  }
  public CharSequence getEntry() { int index = findIndexOfValue(value); return index < 0 ? null : entries[index]; }
}
