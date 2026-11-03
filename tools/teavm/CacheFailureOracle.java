package prototype;

import java.io.File;

/** Uses only the untouched locked upstream OkHttp artifact, never seed-adapted newCall bytecode. */
public final class CacheFailureOracle {
  public static void main(String[] args) throws Exception {
    if (args.length != 2) throw new IllegalArgumentException("ORIGIN DIRECTORY required");
    for (Class<?> type : new Class<?>[] {okhttp3.Cache.class, okhttp3.OkHttpClient.class}) {
      String location = type.getProtectionDomain().getCodeSource().getLocation().toString();
      if (!location.endsWith("/okhttp-jvm-5.5.0.jar"))
        throw new AssertionError(
            "Original upstream OkHttp required: " + type + " from " + location);
    }
    System.out.println(CacheFailureScenarios.run(args[0], new File(args[1])));
  }
}
