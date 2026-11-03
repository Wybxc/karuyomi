package eu.kanade.tachiyomi.source.online;

import eu.kanade.tachiyomi.source.*;
import eu.kanade.tachiyomi.source.model.*;
import eu.kanade.tachiyomi.network.NetworkHelper;
import okhttp3.*;
import kotlin.*;
import kotlin.coroutines.*;
import java.util.*;

public abstract class HttpSource implements Source {
  private final Lazy<Headers> headers$delegate = LazyKt.lazy(() -> headersBuilder().build());

  protected final NetworkHelper getNetwork() {
    return prototype.TeaHost.network;
  }

  public abstract String getBaseUrl();

  public String getHomeUrl() {
    return getBaseUrl();
  }

  public int getVersionId() {
    return 1;
  }

  public long getId() {
    return generateId(getName(), getLang(), getVersionId());
  }

  protected final long generateId(String name, String lang, int version) {
    try {
      byte[] b =
          java.security.MessageDigest.getInstance("MD5")
              .digest(
                  (name.toLowerCase(java.util.Locale.ROOT) + "/" + lang + "/" + version)
                      .getBytes(java.nio.charset.StandardCharsets.UTF_8));
      long id = 0;
      for (int i = 0; i < 8; i++) id = (id << 8) | (b[i] & 255L);
      return id & Long.MAX_VALUE;
    } catch (java.security.NoSuchAlgorithmException e) {
      throw new IllegalStateException(e);
    }
  }

  public final Headers getHeaders() {
    return headers$delegate.getValue();
  }

  public OkHttpClient getClient() {
    return getNetwork().getClient();
  }

  protected Headers.Builder headersBuilder() {
    return new Headers.Builder().add("User-Agent", getNetwork().defaultUserAgentProvider());
  }

  public FilterList getFilterList() {
    return new FilterList();
  }

  public String getMangaUrl(SManga m) {
    return getBaseUrl() + m.getUrl();
  }

  public String getChapterUrl(SChapter c) {
    return getBaseUrl() + c.getUrl();
  }

  public final void setUrlWithoutDomain(SManga m, String u) {
    m.setUrl(path(u));
  }

  public final void setUrlWithoutDomain(SChapter c, String u) {
    c.setUrl(path(u));
  }

  private String path(String u) {
    try {
      java.net.URI uri = new java.net.URI(u.replace(" ", "%20"));
      String path = uri.getPath();
      if (uri.getQuery() != null) path = path + "?" + uri.getQuery();
      if (uri.getFragment() != null) path = path + "#" + uri.getFragment();
      return java.util.Objects.requireNonNull(path);
    } catch (java.net.URISyntaxException e) {
      return u;
    }
  }

  public rx.Observable<String> fetchImageUrl(Page p) {
    return rx.Observable.fromCallable(() -> {
      try (Response r = getClient().newCall(imageUrlRequest(p)).execute()) {
        if (!r.isSuccessful()) throw new java.io.IOException("HTTP " + r.code());
        return imageUrlParse(r);
      }
    });
  }

  public Object getImageUrl(Page p, Continuation<? super String> c) {
    return fetchImageUrl(p).toBlocking().single();
  }

  protected Request imageUrlRequest(Page p) {
    return new Request.Builder().url(p.getUrl()).headers(getHeaders()).build();
  }

  protected String imageUrlParse(Response response) {
    throw new UnsupportedOperationException("imageUrlParse");
  }

  public final Object getImage(Page p, Continuation<? super Response> c)
      throws java.io.IOException {
    return eu.kanade.tachiyomi.network.OkHttpExtensionsKt.awaitSuccess(
        eu.kanade.tachiyomi.network.OkHttpExtensionsKt.newCachelessCallWithProgress(
            getClient(), imageRequest(p), p),
        c);
  }

  protected Request imageRequest(Page p) {
    return new Request.Builder().url(p.getImageUrl()).headers(getHeaders()).build();
  }
}
