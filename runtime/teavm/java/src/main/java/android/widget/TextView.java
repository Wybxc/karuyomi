package android.widget;

import android.content.Context;
import android.text.method.TransformationMethod;
import android.util.AttributeSet;
import android.view.View;

/** Metadata-only input for an original Preference bind callback; no Android UI is created. */
public class TextView extends View {
  private int inputType = 1;
  private TransformationMethod transformation;
  private CharSequence text = "";
  private CharSequence hint;

  public TextView(Context context) {
    super(context);
  }

  public TextView(Context context, AttributeSet attrs) {
    this(context);
  }

  public TextView(Context context, AttributeSet attrs, int style) {
    this(context);
  }

  public void setInputType(int inputType) {
    this.inputType = inputType;
  }

  public void setRawInputType(int inputType) {
    this.inputType = inputType;
  }

  public int getInputType() {
    return inputType;
  }

  public final TransformationMethod getTransformationMethod() {
    return transformation;
  }

  public final void setTransformationMethod(TransformationMethod transformation) {
    this.transformation = transformation;
  }

  public CharSequence getText() {
    return text;
  }

  public final void setText(CharSequence text) {
    this.text = text == null ? "" : text;
  }

  public final void setHint(CharSequence hint) {
    this.hint = hint;
  }

  public CharSequence getHint() {
    return hint;
  }

  public void setHorizontallyScrolling(boolean value) {}

  public void setSingleLine() {}

  public void setSingleLine(boolean value) {}

  public void setSelectAllOnFocus(boolean value) {}

  public enum BufferType {
    NORMAL,
    SPANNABLE,
    EDITABLE
  }
}
