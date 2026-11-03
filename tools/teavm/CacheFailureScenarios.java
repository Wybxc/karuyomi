package prototype;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import java.io.File;
import java.io.IOException;
import java.util.Arrays;
import java.util.concurrent.TimeUnit;
import okhttp3.*;
import okio.Buffer;

/** Original JVM/TeaVM shared scenarios; the controlled origin owns framing and holds the tail. */
public final class CacheFailureScenarios {
  public static final int PREFIX = 8192;
  private static int checks;

  private static void check(boolean value, String message) {
    if (!value) throw new AssertionError(message);
    checks++;
  }

  private static Request request(String url, String mode, CacheControl policy) {
    Request.Builder builder = new Request.Builder().url(url).header("X-Fixture-Mode", mode);
    if (policy != null) builder.cacheControl(policy);
    return builder.build();
  }

  public static JsonObject run(String origin, File directory) throws Exception {
    checks = 0;
    JsonArray cases = new JsonArray();
    byte[] expected = CacheScenarios.body();
    for (String mode : new String[] {"truncate", "cancel"}) {
      for (boolean seeded : new boolean[] {false, true}) {
        String name = mode + (seeded ? "-replacement" : "-empty");
        String url = origin + "/failure/" + name;
        File storage = new File(directory, name);
        Cache cache = new Cache(storage, 1048576);
        OkHttpClient client = new OkHttpClient.Builder().cache(cache).build();
        JsonObject result = new JsonObject();
        result.addProperty("name", name);
        try {
          if (seeded) {
            try (Response seed = client.newCall(request(url, "complete", null)).execute()) {
              check(seed.networkResponse() != null, name + " seed uses network");
              check(Arrays.equals(seed.body().bytes(), expected), name + " seed complete bytes");
            }
          }
          Call call = client.newCall(request(url, mode, CacheControl.FORCE_NETWORK));
          String failure = null;
          try (Response partial = call.execute()) {
            check(partial.networkResponse() != null, name + " failed replacement uses network");
            check(
                partial.body().contentLength() == expected.length,
                name + " real advertised length");
            byte[] prefix = partial.body().source().readByteArray(PREFIX);
            check(Arrays.equals(prefix, Arrays.copyOf(expected, PREFIX)), name + " exact prefix");
            if (mode.equals("cancel")) {
              call.cancel();
              check(call.isCanceled(), name + " cancel is observed by Call");
            } else {
              // The origin closes only after this Java consumer has read the exact prefix.
              OkHttpClient control = new OkHttpClient.Builder().build();
              try (Response acknowledged =
                  control
                      .newCall(
                          new Request.Builder()
                              .url(origin + "/fixture-control/truncate/" + name)
                              .build())
                      .execute()) {
                check(
                    acknowledged.code() == 204, name + " origin acknowledged prefix-read barrier");
                acknowledged.body().bytes();
              }
            }
            try {
              partial.body().source().readAll(new Buffer());
            } catch (IOException error) {
              failure = error.getClass().getName() + ": " + error.getMessage();
            }
            check(failure != null, name + " body error is not a clean EOF");
          }
          check(cache.writeAbortCount() == 1, name + " failed writer aborted exactly once");
          cache.close();
          cache = new Cache(storage, 1048576);
          client = client.newBuilder().cache(cache).build();
          CacheControl onlyCache =
              new CacheControl.Builder()
                  .onlyIfCached()
                  .maxStale(Integer.MAX_VALUE, TimeUnit.SECONDS)
                  .build();
          try (Response saved = client.newCall(request(url, "complete", onlyCache)).execute()) {
            if (seeded) {
              check(
                  saved.code() == 200
                      && saved.cacheResponse() != null
                      && saved.networkResponse() == null,
                  name + " reopen keeps old complete entry");
              check(
                  Arrays.equals(saved.body().bytes(), expected),
                  name + " old complete bytes survive");
            } else {
              check(
                  saved.code() == 504 && saved.networkResponse() == null,
                  name + " partial entry is absent after reopen");
            }
          }
          try (Response recovered =
              client.newCall(request(url, "complete", CacheControl.FORCE_NETWORK)).execute()) {
            check(recovered.networkResponse() != null, name + " recovery uses network");
            check(
                Arrays.equals(recovered.body().bytes(), expected),
                name + " recovery complete bytes");
          }
          try (Response warm = client.newCall(request(url, "complete", null)).execute()) {
            check(
                warm.networkResponse() == null && warm.cacheResponse() != null,
                name + " recovered entry becomes warm");
            check(
                Arrays.equals(warm.body().bytes(), expected),
                name + " recovered cache exact bytes");
          }
          result.addProperty("bodyFailure", failure);
          result.addProperty("prefixBytes", PREFIX);
          result.addProperty("preservedOldCompleteEntry", seeded);
          result.addProperty("passed", true);
          cases.add(result);
        } finally {
          cache.close();
        }
      }
    }
    JsonObject result = new JsonObject();
    result.addProperty("passed", true);
    result.addProperty("checks", checks);
    result.add("cases", cases);
    return result;
  }
}
