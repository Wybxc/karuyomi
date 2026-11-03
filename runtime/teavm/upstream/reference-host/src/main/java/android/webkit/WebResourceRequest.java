package android.webkit;

import android.net.Uri;
import java.util.Map;

/** ABI for extension WebView clients; the DOM bridge does not intercept subresources. */
public interface WebResourceRequest {
    Uri getUrl();
    boolean isForMainFrame();
    boolean isRedirect();
    boolean hasGesture();
    String getMethod();
    Map<String, String> getRequestHeaders();
}
