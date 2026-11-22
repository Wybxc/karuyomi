package android.text.util;

import android.text.Spannable;
import android.text.Spanned;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.EnumSet;
import org.nibor.autolink.LinkExtractor;
import org.nibor.autolink.LinkType;

/** Recognizes explicit HTTP(S) links in Source-authored text for rendering by the client. */
public final class Linkify {
  public static final int WEB_URLS = 1;
  public static final int MAX_TEXT_BYTES = 2048, MAX_LINKS = 8;
  private static final LinkExtractor WEB_LINKS =
      LinkExtractor.builder().linkTypes(EnumSet.of(LinkType.URL)).build();

  private Linkify() {}

  public static boolean addLinks(Spannable text, int mask) {
    if (mask == 0) return false;
    if (mask != WEB_URLS) throw new UnsupportedOperationException("Expected Linkify.WEB_URLS");
    if (text.length() > MAX_TEXT_BYTES) return false;
    for (WebLink existing : text.getSpans(0, text.length(), WebLink.class)) {
      text.removeSpan(existing);
    }
    int count = 0;
    String value = text.toString();
    for (var span : WEB_LINKS.extractLinks(value)) {
      int start = span.getBeginIndex(), end = span.getEndIndex();
      if (!isWebLink(value.substring(start, end))) continue;
      text.setSpan(new WebLink(), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
      if (++count == MAX_LINKS) break;
    }
    return count != 0;
  }

  private static boolean isWebLink(String value) {
    try {
      URI uri = new URI(value);
      return ("https".equalsIgnoreCase(uri.getScheme()) || "http".equalsIgnoreCase(uri.getScheme()))
          && uri.getHost() != null
          && uri.getRawUserInfo() == null;
    } catch (URISyntaxException invalid) {
      return false;
    }
  }

  /** A link whose visible text is also its destination. */
  public static final class WebLink {
    private WebLink() {}
  }
}
