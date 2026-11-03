package androidx.preference;
import android.content.Context;
public abstract class DialogPreference extends Preference {
  private CharSequence dialogTitle, dialogMessage, positiveButtonText, negativeButtonText;
  public DialogPreference(Context context) { super(context); }
  public void setDialogTitle(CharSequence value) { dialogTitle=value; }
  public CharSequence getDialogTitle() { return dialogTitle; }
  public void setDialogMessage(CharSequence value) { dialogMessage=value; }
  public CharSequence getDialogMessage() { return dialogMessage; }
  public void setPositiveButtonText(CharSequence value) { positiveButtonText=value; }
  public CharSequence getPositiveButtonText() { return positiveButtonText; }
  public void setNegativeButtonText(CharSequence value) { negativeButtonText=value; }
  public CharSequence getNegativeButtonText() { return negativeButtonText; }
}
