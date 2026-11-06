package android.widget;

import android.content.Context;
import android.text.Editable;
import android.util.AttributeSet;

/** Input metadata is supported; arbitrary Android text widgets are explicitly unsupported. */
public class EditText extends TextView {
  public EditText(Context context) {
    super(context);
  }

  public EditText(Context context, AttributeSet attrs) {
    super(context, attrs);
  }

  public EditText(Context context, AttributeSet attrs, int style) {
    super(context, attrs, style);
  }

  public Editable getText() {
    throw new UnsupportedOperationException("Android editable widgets are unsupported");
  }

  public void selectAll() {}

  public void setSelection(int index) {}

  public void setSelection(int start, int end) {}
}
