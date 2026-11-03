package androidx.preference;
import android.content.Context;
/** Settings metadata only, consistent with the other browser preference adapters. */
public abstract class TwoStatePreference extends Preference {
  private boolean checked, disableDependentsState;
  private CharSequence summaryOn, summaryOff;
  public TwoStatePreference(Context context) { super(context); }
  public void setChecked(boolean checked) { this.checked = checked; }
  public boolean isChecked() { return checked; }
  public void setSummaryOn(CharSequence summary) { summaryOn = summary; }
  public CharSequence getSummaryOn() { return summaryOn; }
  public void setSummaryOff(CharSequence summary) { summaryOff = summary; }
  public CharSequence getSummaryOff() { return summaryOff; }
  public void setDisableDependentsState(boolean value) { disableDependentsState = value; }
  public boolean getDisableDependentsState() { return disableDependentsState; }
  @Override public CharSequence getSummary() {
    CharSequence current = checked ? summaryOn : summaryOff;
    return current != null ? current : super.getSummary();
  }
}
