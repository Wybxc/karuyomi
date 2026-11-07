package android.widget;

import android.content.Context;

/** The confirmation control of a projected preference dialog. */
public final class Button extends TextView {
  private boolean enabled = true;

  Button(Context context) {
    super(context);
  }

  public boolean isEnabled() {
    return enabled;
  }

  public void setEnabled(boolean enabled) {
    this.enabled = enabled;
  }
}
