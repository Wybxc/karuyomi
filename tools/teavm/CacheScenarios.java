package prototype;

import com.google.gson.JsonObject;
import java.io.File;
import java.security.MessageDigest;
import java.util.Arrays;
import okhttp3.*;
import okio.Buffer;

/** Shared original-JVM/TeaVM CacheInterceptor scenarios. The origin is supplied by the platform. */
public final class CacheScenarios {
  private static void check(boolean value, String message) {
    if (!value) throw new AssertionError(message);
  }

  public static byte[] body() {
    byte[] bytes = new byte[131079];
    for (int index = 0; index < bytes.length; index++) bytes[index] = (byte) index;
    return bytes;
  }

  private static String digest(byte[] bytes) throws Exception {
    byte[] hash = MessageDigest.getInstance("SHA-256").digest(bytes);
    StringBuilder result = new StringBuilder();
    for (byte value : hash) result.append(String.format("%02x", value & 255));
    return result.toString();
  }

  private static Response get(OkHttpClient client, String url, String cookie) throws Exception {
    Request.Builder request = new Request.Builder().url(url);
    if (cookie != null) request.header("Cookie", cookie);
    return client.newCall(request.build()).execute();
  }

  public static JsonObject run(String origin, File directory) throws Exception {
    Cache cache = new Cache(directory, 1048576);
    OkHttpClient client = new OkHttpClient.Builder().cache(cache).build();
    JsonObject result = new JsonObject();
    String expected = digest(body());
    try {
      try (Response cold = get(client, origin + "/fresh", null)) {
        check(cold.networkResponse() != null && cold.cacheResponse() == null, "cold network");
        check(digest(cold.body().bytes()).equals(expected), "cold bytes");
      }
      try (Response warm = get(client, origin + "/fresh", null)) {
        check(warm.networkResponse() == null && warm.cacheResponse() != null, "warm cache");
        check(digest(warm.body().bytes()).equals(expected), "warm bytes");
      }
      try (Response first = get(client, origin + "/etag", null)) {
        check(digest(first.body().bytes()).equals(expected), "etag seed bytes");
      }
      try (Response validated = get(client, origin + "/etag", null)) {
        check(validated.code() == 200 && validated.networkResponse().code() == 304, "304 merge");
        check(validated.cacheResponse() != null, "304 cache response");
        check("yes".equals(validated.header("X-Revalidated")), "304 merged header");
        check(digest(validated.body().bytes()).equals(expected), "304 keeps body");
      }
      for (int index = 0; index < 2; index++) {
        try (Response noStore = get(client, origin + "/no-store", null)) {
          check(
              noStore.networkResponse() != null && noStore.cacheResponse() == null,
              "no-store network");
          noStore.body().bytes();
        }
      }
      try (Response first = get(client, origin + "/no-cache", null)) {
        check(first.networkResponse() != null, "no-cache seed network");
        check(digest(first.body().bytes()).equals(expected), "no-cache seed bytes");
      }
      try (Response validated = get(client, origin + "/no-cache", null)) {
        check(
            validated.code() == 200
                && validated.networkResponse() != null
                && validated.networkResponse().code() == 304,
            "no-cache always revalidates");
        check(validated.cacheResponse() != null, "no-cache keeps stored response");
        check("yes".equals(validated.header("X-Revalidated")), "no-cache merged header");
        check(digest(validated.body().bytes()).equals(expected), "no-cache keeps body");
      }
      try (Response seed = get(client, origin + "/invalidate", null)) {
        check(seed.networkResponse() != null, "invalidation seed network");
        check(digest(seed.body().bytes()).equals(expected), "invalidation seed bytes");
      }
      try (Response warm = get(client, origin + "/invalidate", null)) {
        check(
            warm.networkResponse() == null && warm.cacheResponse() != null,
            "invalidation seed is warm");
        check(digest(warm.body().bytes()).equals(expected), "invalidation warm bytes");
      }
      Request mutation =
          new Request.Builder()
              .url(origin + "/invalidate")
              .post(RequestBody.create("mutation", MediaType.parse("text/plain")))
              .build();
      try (Response changed = client.newCall(mutation).execute()) {
        check(
            changed.networkResponse() != null && changed.cacheResponse() == null,
            "POST uses network");
        check(changed.body().string().equals("mutation"), "POST request bytes reach origin");
      }
      try (Response invalidated = get(client, origin + "/invalidate", null)) {
        check(
            invalidated.networkResponse() != null && invalidated.cacheResponse() == null,
            "POST invalidates cached GET");
        check(digest(invalidated.body().bytes()).equals(expected), "invalidated network bytes");
      }
      try (Response warm = get(client, origin + "/invalidate", null)) {
        check(
            warm.networkResponse() == null && warm.cacheResponse() != null,
            "GET after invalidation is cached again");
        check(digest(warm.body().bytes()).equals(expected), "replacement warm bytes");
      }
      try (Response varied = get(client, origin + "/vary", "mode=a")) {
        check(varied.body().string().equals("mode=a"), "vary seed");
      }
      try (Response same = get(client, origin + "/vary", "mode=a")) {
        check(same.cacheResponse() != null && same.networkResponse() == null, "vary hit");
        check(same.body().string().equals("mode=a"), "vary hit body");
      }
      try (Response different = get(client, origin + "/vary", "mode=b")) {
        check(different.networkResponse() != null, "vary miss");
        check(different.body().string().equals("mode=b"), "vary miss body");
      }
      Response snapshot = get(client, origin + "/fresh", null);
      Buffer bytes = new Buffer();
      check(snapshot.body().source().read(bytes, 3) == 3, "snapshot prefix");
      cache.evictAll();
      snapshot.body().source().readAll(bytes);
      snapshot.close();
      check(Arrays.equals(bytes.readByteArray(), body()), "open snapshot survives evictAll");
      try (Response afterEviction = get(client, origin + "/fresh", null)) {
        check(afterEviction.networkResponse() != null, "evictAll keeps cache open");
        afterEviction.body().bytes();
      }
      result.addProperty("bodySha256", expected);
      result.addProperty("requestCount", cache.requestCount());
      result.addProperty("networkCount", cache.networkCount());
      result.addProperty("hitCount", cache.hitCount());
      result.addProperty("writeSuccessCount", cache.writeSuccessCount());
      result.addProperty("passed", true);
      return result;
    } finally {
      cache.close();
    }
  }
}
