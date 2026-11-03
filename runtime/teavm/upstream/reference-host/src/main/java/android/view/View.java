package android.view;

import android.content.Context;

/** Context and type identity for the browser DOM adapter; no Android layout implementation. */
public class View {
    private final Context context;
    public View(Context context) { this.context = context; }
    public Context getContext() { return context; }
    public android.view.ViewParent getParent() { return null; }
}
