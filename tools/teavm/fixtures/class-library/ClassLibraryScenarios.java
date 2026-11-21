package prototype;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.NoSuchAlgorithmException;

public final class ClassLibraryScenarios {
  private static int checks;

  public static void main(String[] args) throws IOException, NoSuchAlgorithmException {
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
