package android.text.method;

import android.graphics.Rect;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.View;

/** Password marker used to classify a Source preference without exposing its contents. */
public class PasswordTransformationMethod implements TransformationMethod, TextWatcher {
  private static final PasswordTransformationMethod INSTANCE = new PasswordTransformationMethod();

  public PasswordTransformationMethod() {}

  public static PasswordTransformationMethod getInstance() {
    return INSTANCE;
  }

  public CharSequence getTransformation(CharSequence source, View view) {
    return "•".repeat(source.length());
  }

  public void onFocusChanged(
      View view, CharSequence source, boolean focused, int direction, Rect previous) {}

  public void beforeTextChanged(CharSequence source, int start, int count, int after) {}

  public void onTextChanged(CharSequence source, int start, int before, int count) {}

  public void afterTextChanged(Editable editable) {}
}
