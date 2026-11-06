package androidx.preference;

import android.content.Context;

public class PreferenceScreen extends PreferenceGroup {
  public PreferenceScreen() {
    this(new Context());
  }

  public PreferenceScreen(Context context) {
    super(context);
  }
}
