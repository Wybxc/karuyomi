package android.widget;

import android.content.Context;
import android.text.Editable;
import android.text.PreferenceTextValue;
import android.text.TextWatcher;
import android.util.AttributeSet;
import android.view.View;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/** Limited Android text binding for a Source preference; no Android dialog is created. */
public class EditText extends TextView {
  private static final int MAX_POSTS = 16, MAX_WATCHERS = 16;
  private PreferenceBinding binding;

  public EditText(Context context) {
    super(context);
  }

  public EditText(Context context, AttributeSet attrs) {
    super(context, attrs);
  }

  public EditText(Context context, AttributeSet attrs, int style) {
    super(context, attrs, style);
  }

  public static EditText hostPreferenceInput(Context context, String value) {
    EditText input = new EditText(context);
    input.binding = new PreferenceBinding(context);
    input.setText(value);
    return input;
  }

  public void hostFinishBinding() {
    PreferenceBinding state = binding();
    if (!state.binding) throw unsupported();
    try {
      while (!state.posts.isEmpty()) state.posts.removeFirst().run();
    } finally {
      state.binding = false;
      state.posts.clear();
    }
  }

  public boolean hostValidateProposal(String previous, String proposal) {
    PreferenceBinding state = binding();
    if (state.binding) throw unsupported();
    if (state.watchers.isEmpty()) return true;
    Editable before = new PreferenceTextValue(previous == null ? "" : previous);
    Editable after = new PreferenceTextValue(proposal);
    state.confirm.setEnabled(true);
    state.error = null;
    setText(before);
    try {
      for (TextWatcher watcher : state.watchers)
        watcher.beforeTextChanged(before, 0, before.length(), after.length());
      setText(after);
      for (TextWatcher watcher : state.watchers)
        watcher.onTextChanged(after, 0, before.length(), after.length());
      for (TextWatcher watcher : state.watchers) watcher.afterTextChanged(after);
      return state.error == null
          && state.confirm.isEnabled()
          && proposal.equals(super.getText().toString());
    } finally {
      setText(before);
      state.error = null;
      state.confirm.setEnabled(true);
    }
  }

  public boolean hostSelectAllOnOpen() {
    return binding().selectAll;
  }

  public boolean post(Runnable action) {
    PreferenceBinding state = binding();
    if (!state.binding || state.postCount >= MAX_POSTS) throw unsupported();
    state.posts.addLast(Objects.requireNonNull(action));
    state.postCount++;
    return true;
  }

  public void addTextChangedListener(TextWatcher watcher) {
    PreferenceBinding state = binding();
    if (!state.binding || state.watchers.size() >= MAX_WATCHERS) throw unsupported();
    state.watchers.add(Objects.requireNonNull(watcher));
  }

  public CharSequence getError() {
    return binding().error;
  }

  public void setError(CharSequence error) {
    binding().error = error;
  }

  @Override
  public View getRootView() {
    return binding().root;
  }

  @Override
  public Editable getText() {
    binding();
    CharSequence text = super.getText();
    return text instanceof PreferenceTextValue proposed
        ? proposed
        : new PreferenceTextValue(text.toString());
  }

  public void selectAll() {
    setSelectAllOnFocus(true);
  }

  @Override
  public void setSelectAllOnFocus(boolean value) {
    PreferenceBinding state = binding();
    if (!state.binding) throw unsupported();
    state.selectAll = value;
  }

  public void setSelection(int index) {
    setSelection(index, index);
  }

  public void setSelection(int start, int end) {
    int length = getText().length();
    if (start == length && end == length) setSelectAllOnFocus(false);
    else if (start == 0 && end == length) selectAll();
    else throw unsupported();
  }

  private PreferenceBinding binding() {
    if (binding == null) throw unsupported();
    return binding;
  }

  private static UnsupportedOperationException unsupported() {
    return new UnsupportedOperationException("Android edit widget behavior is unsupported");
  }

  private static final class PreferenceBinding {
    final Button confirm;
    final View root;
    final ArrayDeque<Runnable> posts = new ArrayDeque<>();
    final List<TextWatcher> watchers = new ArrayList<>();
    CharSequence error;
    boolean binding = true, selectAll;
    int postCount;

    PreferenceBinding(Context context) {
      confirm = new Button(context);
      root =
          new View(context) {
            @Override
            protected View findViewTraversal(int id) {
              if (id != android.R.id.button1) throw unsupported();
              return confirm;
            }
          };
    }
  }
}
