package prototype;

import android.graphics.GraphicsTransformTest;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.net.UnknownHostException;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.TimeZone;

public final class ClassLibraryScenarios {
  private static int checks;

  public static void main(String[] args) throws IOException, GeneralSecurityException {
    if (args.length > 0) {
      EcScenarios.interop(args);
      return;
    }
    DateFormatScenarios.main(args);
    String path = "/assets/example.txt";
    URL absolute = ClassLibraryScenarios.class.getResource(path);
    check(absolute != null, "absolute path resolves");
    check(read(absolute).equals("bundled resource\n"), "URL.openStream reads the resource");
    try (InputStream independent = absolute.openConnection().getInputStream()) {
      check(independent.read() == 'b', "reopening the URL starts a fresh stream");
    }

    URL relative = ClassLibraryScenarios[].class.getResource("cover sample #.txt");
    check(relative != null, "an array uses its component class's package");
    check(read(relative).equals("封面\n"), "spaces, hash and UTF-8 round trip");
    check(
        read(new URL(relative, "../assets/example.txt")).equals(read(absolute)),
        "relative URLs read the resolved resource");
    check(
        ClassLibraryScenarios.class.getResource("/assets/absent.txt") == null,
        "missing resources return null");
    try {
      read(new URL(absolute, "absent.txt"));
      throw new AssertionError("Opening a URL for a missing resource succeeded");
    } catch (FileNotFoundException expected) {
      checks++;
    }
    System.out.println("PACKAGED_RESOURCE_SCENARIOS_PASS " + checks);
    DigestScenarios.run();
    Pbkdf2Scenarios.run();
    timeZones();
    check(
        concat("ink", 17, true).equals("\1ink\2" + "17:true\1\2"),
        "concatenation preserves literal recipe tags and dynamic arguments");
    System.out.println("STRING_CONCAT_SCENARIO_PASS");
    EcScenarios.run();
    RsaScenarios.run();
    SequenceStreamScenarios.run();
    unknownHost();
    GraphicsTransformTest.main(args);
  }

  private static void unknownHost() throws IOException {
    String name = "synthetic.fixture.invalid";
    try {
      throwUnknownHost(name);
      throw new AssertionError("Expected a checked DNS error");
    } catch (UnknownHostException failure) {
      check(name.equals(failure.getMessage()), "DNS error preserves the message");
    }
    check(new UnknownHostException().getMessage() == null, "empty DNS error message");
    System.out.println("UNKNOWN_HOST_SCENARIO_PASS");
  }

  private static void throwUnknownHost(String message) throws IOException {
    throw new UnknownHostException(message);
  }

  private static String concat(String title, int count, boolean enabled) {
    return "\1" + title + "\2" + count + ":" + enabled + "\1\2";
  }

  private static void timeZones() {
    checks = 0;
    Instant winter = Instant.parse("2025-01-15T12:00:00Z");
    Instant summer = Instant.parse("2025-07-15T12:00:00Z");
    var utc = TimeZone.getTimeZone("UTC").toZoneId();
    check(utc.getId().equals("UTC"), "UTC zone ID");
    check(
        DateTimeFormatter.ISO_ZONED_DATE_TIME
            .withZone(utc)
            .format(winter)
            .equals("2025-01-15T12:00:00Z[UTC]"),
        "the converted UTC zone can format an instant");

    var pacific = TimeZone.getTimeZone("America/Los_Angeles").toZoneId();
    check(pacific.getId().equals("America/Los_Angeles"), "IANA zone ID");
    check(pacific.getRules().getOffset(winter).equals(ZoneOffset.ofHours(-8)), "standard time");
    check(pacific.getRules().getOffset(summer).equals(ZoneOffset.ofHours(-7)), "daylight saving");

    TimeZone custom = TimeZone.getTimeZone("GMT+05:30");
    check(
        custom.toZoneId().getRules().getOffset(winter).equals(ZoneOffset.of("+05:30")),
        "offset ID");
    custom.setID("ACT");
    check(
        custom.toZoneId().getId().equals("Australia/Darwin"),
        "short ID after changing the zone ID");
    System.out.println("TIME_ZONE_SCENARIOS_PASS " + checks);
  }

  private static String read(URL url) throws IOException {
    try (InputStream input = url.openStream()) {
      return new String(input.readAllBytes(), StandardCharsets.UTF_8);
    }
  }

  private static void check(boolean condition, String message) {
    checks++;
    if (!condition) throw new AssertionError(message);
  }
}
