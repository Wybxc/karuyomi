package prototype;

import java.io.File;
import java.nio.file.Files;
import java.util.Comparator;

/** Actual original JVM filesystem; no project filesystem/Bridge is installed here. */
public final class FileTest {
  public static void main(String[] args) throws Exception {
    File root = Files.createTempDirectory("karuyomi-file-oracle-").toFile();
    try {
      System.out.println(FileScenarios.run(root));
      if (root.list().length != 0) throw new AssertionError("File oracle left temporary files");
    } finally {
      try (var paths = Files.walk(root.toPath())) {
        for (var path : paths.sorted(Comparator.reverseOrder()).toList()) Files.delete(path);
      }
    }
  }
}
