package okhttp3;

import java.util.*;
import java.util.concurrent.TimeUnit;

public class OkHttpClient implements Call.Factory {
  final Builder b;

  public OkHttpClient() {
    this(new Builder());
  }

  public OkHttpClient(Builder b) {
    this.b = new Builder(b);
  }

  public Builder newBuilder() {
    return new Builder(b);
  }

  public Call newCall(Request r) {
    return prototype.BrowserCall.create(this, r);
  }

  public List<Interceptor> interceptors() {
    return b.interceptors;
  }

  public List<Interceptor> networkInterceptors() {
    return b.networkInterceptors;
  }

  public CookieJar cookieJar() {
    return b.cookieJar;
  }

  public boolean followRedirects() {
    return b.followRedirects;
  }

  public boolean followSslRedirects() {
    return b.followRedirects;
  }

  public Cache cache() {
    return b.cache;
  }

  public boolean retryOnConnectionFailure() {
    return b.retry;
  }

  public int connectTimeoutMillis() {
    return b.connect;
  }

  public int readTimeoutMillis() {
    return b.read;
  }

  public int writeTimeoutMillis() {
    return b.write;
  }

  public static class Builder {
    List<Interceptor> interceptors = new ArrayList<>(), networkInterceptors = new ArrayList<>();
    Cache cache;
    CookieJar cookieJar = prototype.Cookies.INSTANCE;
    boolean followRedirects = true, retry = true;
    int connect = 10000, read = 10000, write = 10000;

    public Builder() {}

    Builder(Builder x) {
      interceptors.addAll(x.interceptors);
      networkInterceptors.addAll(x.networkInterceptors);
      cache = x.cache;
      cookieJar = x.cookieJar;
      followRedirects = x.followRedirects;
      retry = x.retry;
      connect = x.connect;
      read = x.read;
      write = x.write;
    }

    public Builder(OkHttpClient c) {
      this(c.b);
    }

    public List<Interceptor> interceptors() {
      return interceptors;
    }

    public List<Interceptor> networkInterceptors() {
      return networkInterceptors;
    }

    public Builder addInterceptor(Interceptor i) {
      interceptors.add(i);
      return this;
    }

    public Builder addNetworkInterceptor(Interceptor i) {
      networkInterceptors.add(i);
      return this;
    }

    public Builder cookieJar(CookieJar j) {
      cookieJar = j;
      return this;
    }

    public Builder followRedirects(boolean v) {
      followRedirects = v;
      return this;
    }

    public Builder followSslRedirects(boolean v) {
      if (!v) throw new UnsupportedOperationException("followSslRedirects false");
      return this;
    }

    public Builder cache(Cache cache) {
      this.cache = cache;
      return this;
    }

    public Builder connectTimeoutDuration(long encoded) {
      return connectTimeout(durationMillis(encoded), TimeUnit.MILLISECONDS);
    }

    public Builder readTimeoutDuration(long encoded) {
      return readTimeout(durationMillis(encoded), TimeUnit.MILLISECONDS);
    }

    public Builder writeTimeoutDuration(long encoded) {
      return writeTimeout(durationMillis(encoded), TimeUnit.MILLISECONDS);
    }

    // Kotlin Duration: low bit is unit tag; zero=nanos, one=millis. JDK timeout range is Int.
    static long durationMillis(long encoded) {
      if (encoded == Long.MAX_VALUE || encoded == -Long.MAX_VALUE)
        throw new IllegalArgumentException("Infinite timeout");
      long value = encoded >> 1;
      if (value < 0) throw new IllegalArgumentException("Negative timeout");
      long ms = (encoded & 1) == 0 ? value / 1000000 : value;
      if (ms > Integer.MAX_VALUE) throw new IllegalArgumentException("Timeout too large");
      if (ms == 0 && value > 0) throw new IllegalArgumentException("Timeout too small");
      return ms;
    }

    public Builder retryOnConnectionFailure(boolean v) {
      retry = v;
      return this;
    }

    public Builder connectTimeout(long v, TimeUnit u) {
      connect = (int) u.toMillis(v);
      return this;
    }

    public Builder readTimeout(long v, TimeUnit u) {
      read = (int) u.toMillis(v);
      return this;
    }

    public Builder writeTimeout(long v, TimeUnit u) {
      write = (int) u.toMillis(v);
      return this;
    }

    public OkHttpClient build() {
      return new OkHttpClient(this);
    }
  }
}
