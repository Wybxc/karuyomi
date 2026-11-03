package androidx.preference;
import android.content.Context;
import android.widget.EditText;
/** Settings metadata only; the prototype does not open Android dialogs. */
public class EditTextPreference extends DialogPreference {
  private String text;
  private OnBindEditTextListener bindListener;
  public EditTextPreference(Context context) { super(context); }
  public String getText() { return text; }
  public void setText(String text) { this.text = text; }
  public void setOnBindEditTextListener(OnBindEditTextListener listener) { bindListener = listener; }
  public OnBindEditTextListener getOnBindEditTextListener() { return bindListener; }
  public interface OnBindEditTextListener { void onBindEditText(EditText editText); }
}
