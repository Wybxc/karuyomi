package android.webkit;

/** ABI for error callback signatures, without synthesizing successful WebView operations. */
public abstract class WebResourceError {
    public abstract int getErrorCode();
    public abstract CharSequence getDescription();
}
