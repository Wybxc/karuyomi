package android.webkit;

/** ABI for renderer lifecycle callback signatures; no Android renderer is created. */
public abstract class RenderProcessGoneDetail {
    public abstract boolean didCrash();
    public abstract int rendererPriorityAtExit();
}
