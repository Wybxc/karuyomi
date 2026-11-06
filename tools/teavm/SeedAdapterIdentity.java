package prototype;

import java.io.IOException;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.zip.ZipFile;
import org.objectweb.asm.*;

/** The project changes one image-integration method; seed suspend code stays intact. */
public final class SeedAdapterIdentity {
  private static final String OWNER = "eu/kanade/tachiyomi/network/OkHttpExtensionsKt";
  private static final String CACHELESS =
      "(Lokhttp3/OkHttpClient;Lokhttp3/Request;Leu/kanade/tachiyomi/network/ProgressListener;)Lokhttp3/Call;";

  private static byte[] normalized(byte[] input, boolean outer) {
    ClassWriter writer = new ClassWriter(ClassWriter.COMPUTE_MAXS);
    new ClassReader(input)
        .accept(
            new ClassVisitor(Opcodes.ASM9, writer) {
              public MethodVisitor visitMethod(
                  int access,
                  String name,
                  String descriptor,
                  String signature,
                  String[] exceptions) {
                if (outer
                    && name.equals("newCachelessCallWithProgress")
                    && descriptor.equals(CACHELESS)) return null;
                return super.visitMethod(access, name, descriptor, signature, exceptions);
              }
            },
            ClassReader.SKIP_DEBUG | ClassReader.SKIP_FRAMES);
    return writer.toByteArray();
  }

  public static void main(String[] args) throws IOException {
    int matched = 0;
    try (ZipFile original = new ZipFile(Path.of(args[0]).toFile());
        ZipFile patched = new ZipFile(Path.of(args[1]).toFile())) {
      for (var entry :
          original.stream()
              .filter(e ->
                  e.getName().equals(OWNER + ".class") || e.getName().startsWith(OWNER + "$await"))
              .toList()) {
        byte[] left = original.getInputStream(entry).readAllBytes();
        byte[] right = patched.getInputStream(patched.getEntry(entry.getName())).readAllBytes();
        boolean outer = entry.getName().equals(OWNER + ".class");
        if (!Arrays.equals(normalized(left, outer), normalized(right, outer)))
          throw new AssertionError("Modified seed await implementation: " + entry.getName());
        matched++;
      }
    }
    if (matched != 5) throw new AssertionError("Unexpected seed suspend class count: " + matched);
    System.out.println("SEED_AWAIT_UNCHANGED_PASS " + matched);
  }
}
