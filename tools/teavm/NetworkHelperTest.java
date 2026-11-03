package prototype;

import android.app.Application;
import com.google.gson.JsonObject;
import eu.kanade.tachiyomi.network.NetworkHelper;
import eu.kanade.tachiyomi.network.OkHttpExtensionsKt;
import java.io.File;
import java.lang.reflect.Modifier;
import java.lang.reflect.Field;
import okhttp3.*;

/** Shared configuration checks. No upstream request or cache storage is simulated here. */
public final class NetworkHelperTest {
  private static int checks;

  private static void check(boolean value, String message) {
    checks++;
    if (!value) throw new AssertionError(message);
  }

  private static void defaults(NetworkHelper network) {
    OkHttpClient client = network.getClient();
    check(client == network.getClient(), "client is stable");
    check(client == network.getCloudflareClient(), "cloudflare client aliases regular client");
    check(client.cookieJar() == Cookies.INSTANCE, "existing cookie jar is preserved");
    check(client.interceptors().size() == 3, "three existing application interceptors");
    String[] names = {
      "UncaughtExceptionInterceptor", "UserAgentInterceptor", "CloudflareInterceptor"
    };
    for (int index = 0; index < names.length; index++)
      check(
          client
              .interceptors()
              .get(index)
              .getClass()
              .getName()
              .equals("eu.kanade.tachiyomi.network.interceptor." + names[index]),
          "interceptor order " + index);
    check(client.networkInterceptors().isEmpty(), "no new network interceptor");
    check(new OkHttpClient.Builder().build().cache() == null, "ordinary builders remain cacheless");
  }

  public static JsonObject run() throws Exception {
    checks = 0;
    Application context = new Application();
    NetworkHelper network = new NetworkHelper(context);
    defaults(network);
    OkHttpClient client = network.getClient();
    Cache cache = client.cache();
    check(cache != null, "owned default client installs cache");
    check(cache.maxSize() == 5L * 1024 * 1024, "default cache is 5 MiB");
    check(
        cache.directory().equals(new File(context.getCacheDir(), "network_cache")),
        "cache directory is derived from context");
    check(
        cache.directory().getAbsolutePath().equals("/files/cache/network_cache"),
        "stable host directory");
    NetworkHelper scoped =
        new NetworkHelper(
            new android.content.Context() {
              @Override
              public File getCacheDir() {
                return new File("/files/cache/custom-context");
              }
            });
    check(
        scoped
            .getClient()
            .cache()
            .directory()
            .equals(new File("/files/cache/custom-context/network_cache")),
        "custom context cache directory is honored");
    Cache another = new NetworkHelper(context).getClient().cache();
    check(
        another != cache && another.directory().equals(cache.directory()),
        "recreated helper retains directory");
    OkHttpClient copied = client.newBuilder().build();
    check(copied.cache() == cache, "newBuilder retains cache");
    check(copied.cookieJar() == client.cookieJar(), "newBuilder retains cookie jar");
    check(copied.interceptors().equals(client.interceptors()), "newBuilder retains interceptors");
    OkHttpClient cacheless = client.newBuilder().cache(null).build();
    check(
        cacheless.cache() == null && client.cache() == cache,
        "explicit cacheless clone is isolated");
    Cache custom = new Cache(new File("/files/cache/source_override"), 1024);
    check(
        client.newBuilder().cache(custom).build().cache() == custom && client.cache() == cache,
        "source cache override is isolated");

    String previous = System.getProperty("http.agent");
    try {
      System.clearProperty("http.agent");
      check(
          network.defaultUserAgentProvider().equals("MihonBrowserPrototype/0.1"),
          "existing UA fallback");
      System.setProperty("http.agent", "KaruyomiNetworkConfiguration/1");
      check(
          network.defaultUserAgentProvider().equals("KaruyomiNetworkConfiguration/1"),
          "UA provider reads current property");
    } finally {
      if (previous == null) System.clearProperty("http.agent");
      else System.setProperty("http.agent", previous);
    }
    JsonObject result = new JsonObject();
    result.addProperty("passed", true);
    result.addProperty("checks", checks);
    result.addProperty("cacheDirectory", cache.directory().getAbsolutePath());
    result.addProperty("cacheBytes", cache.maxSize());
    result.addProperty("scope", "configuration; no network or storage operation");
    return result;
  }

  public static void main(String[] args) throws Exception {
    if (args.length != 2)
      throw new IllegalArgumentException("seed|owned EXPECTED_CLASS_DIRECTORY_URL");
    check(
        new File(NetworkHelper.class.getProtectionDomain().getCodeSource().getLocation().toURI())
            .getCanonicalFile()
            .equals(new File(java.net.URI.create(args[1])).getCanonicalFile()),
        "actual NetworkHelper CodeSource");
    check(Modifier.isFinal(NetworkHelper.class.getModifiers()), "NetworkHelper remains final");
    for (String method :
        new String[] {"getClient", "getCloudflareClient", "defaultUserAgentProvider"})
      check(
          Modifier.isFinal(NetworkHelper.class.getDeclaredMethod(method).getModifiers()),
          "final public ABI " + method);
    if (args[0].equals("seed")) {
      NetworkHelper seed = new NetworkHelper(new Application());
      defaults(seed);
      check(seed.getClient().cache() == null, "locked seed reproduces missing default cache");
      System.out.println("Locked seed NetworkHelper: " + checks + " checks; default cache is null");
    } else if (args[0].equals("owned")) {
      check(
          new File(OkHttpClient.class.getProtectionDomain().getCodeSource().getLocation().toURI())
              .getCanonicalFile()
              .equals(new File(java.net.URI.create(args[1])).getCanonicalFile()),
          "owned OkHttpClient CodeSource");
      check(
          new File(Cache.class.getProtectionDomain().getCodeSource().getLocation().toURI())
              .getCanonicalFile()
              .equals(new File(java.net.URI.create(args[1])).getCanonicalFile()),
          "owned Cache CodeSource");
      NetworkHelper network = new NetworkHelper(new Application());
      OkHttpClient client = network.getClient();
      Request request =
          new Request.Builder()
              .url("https://fixture.example.org/configuration-only")
              .header("User-Agent", "SourceCustomUA/1")
              .build();
      Call call =
          OkHttpExtensionsKt.newCachelessCallWithProgress(
              client, request, (bytes, length, done) -> {});
      check(BrowserCall.class.isInstance(call), "actual image helper creates product BrowserCall");
      Field clientField = BrowserCall.class.getDeclaredField("client");
      clientField.setAccessible(true);
      OkHttpClient imageClient = (OkHttpClient) clientField.get(call);
      check(
          imageClient.cache() == null && client.cache() != null,
          "actual image helper is cacheless without mutating source client");
      check(
          imageClient.cookieJar() == client.cookieJar(), "actual image helper retains cookie jar");
      check(
          imageClient.interceptors().equals(client.interceptors()),
          "actual image helper retains application interceptors");
      check(
          call.request() == request
              && "SourceCustomUA/1".equals(call.request().header("User-Agent")),
          "actual image helper preserves Source request");
      int abiChecks = checks;
      JsonObject result = run();
      result.addProperty("jvmAbiChecks", abiChecks);
      System.out.println("Owned NetworkHelper configuration: " + result);
    } else throw new IllegalArgumentException("Unknown configuration mode");
  }
}
