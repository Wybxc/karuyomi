import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import java.util.zip.ZipOutputStream;
import org.objectweb.asm.ClassReader;
import org.objectweb.asm.ClassVisitor;
import org.objectweb.asm.ClassWriter;
import org.objectweb.asm.MethodVisitor;
import org.objectweb.asm.Opcodes;

public final class PatchLibrariesTest {
  private static final String THREAD = "java/lang/Thread";
  private static final String WORKER = "kotlinx/coroutines/scheduling/CoroutineScheduler$Worker";
  private static final String SETTER = "setContextClassLoader";
  private static final String DESCRIPTOR = "(Ljava/lang/ClassLoader;)V";

  private record Invocation(int opcode, String owner, String name, String descriptor) {}

  private record Example(
      String label, String owner, String name, String descriptor, boolean adapted) {}

  private static void require(boolean value, String message) {
    if (!value) throw new AssertionError(message);
  }

  private static Invocation target() {
    return new Invocation(
        Opcodes.INVOKESTATIC,
        "prototype/PlatformSupport",
        "contextLoader",
        "(Ljava/lang/Thread;Ljava/lang/ClassLoader;)V");
  }

  private static byte[] fixture(List<Example> examples) {
    ClassWriter writer = new ClassWriter(ClassWriter.COMPUTE_MAXS);
    writer.visit(
        Opcodes.V17, Opcodes.ACC_PUBLIC, "fixtures/LoaderCalls", null, "java/lang/Object", null);
    for (Example example : examples) {
      MethodVisitor method =
          writer.visitMethod(
              Opcodes.ACC_PUBLIC | Opcodes.ACC_STATIC,
              example.label,
              "(L" + example.owner + ";" + example.descriptor.substring(1),
              null,
              null);
      method.visitCode();
      method.visitVarInsn(Opcodes.ALOAD, 0);
      method.visitVarInsn(Opcodes.ALOAD, 1);
      method.visitMethodInsn(
          Opcodes.INVOKEVIRTUAL, example.owner, example.name, example.descriptor, false);
      method.visitInsn(Opcodes.RETURN);
      method.visitMaxs(0, 0);
      method.visitEnd();
    }
    writer.visitEnd();
    return writer.toByteArray();
  }

  private static Map<String, List<Invocation>> calls(byte[] bytes) {
    Map<String, List<Invocation>> calls = new LinkedHashMap<>();
    new ClassReader(bytes)
        .accept(
            new ClassVisitor(Opcodes.ASM9) {
              public MethodVisitor visitMethod(
                  int access, String name, String desc, String signature, String[] exceptions) {
                List<Invocation> method = calls.computeIfAbsent(name, ignored -> new ArrayList<>());
                return new MethodVisitor(Opcodes.ASM9) {
                  public void visitMethodInsn(
                      int opcode, String owner, String name, String desc, boolean itf) {
                    method.add(new Invocation(opcode, owner, name, desc));
                  }
                };
              }
            },
            0);
    return calls;
  }

  private static byte[] read(Path archive, String name) throws IOException {
    try (ZipFile jar = new ZipFile(archive.toFile())) {
      ZipEntry entry = jar.getEntry(name);
      if (entry == null) throw new AssertionError("Missing entry: " + name);
      try (var input = jar.getInputStream(entry)) {
        return input.readAllBytes();
      }
    }
  }

  private static long count(Map<String, List<Invocation>> methods, Invocation expected) {
    return methods.values().stream().flatMap(List::stream).filter(expected::equals).count();
  }

  public static void main(String[] args) throws Exception {
    Path originalCore = Path.of(args[0]);
    Path work = Path.of(args[1]);
    Path fixture = work.resolve("loader-calls.jar");
    Path copiedCore = work.resolve("official-coroutines-copy.jar");
    List<Example> examples =
        List.of(
            new Example("thread", THREAD, SETTER, DESCRIPTOR, true),
            new Example("worker", WORKER, SETTER, DESCRIPTOR, true),
            new Example("unrelatedOwner", "fixtures/OtherWorker", SETTER, DESCRIPTOR, false),
            new Example(
                "similarOwner",
                "kotlinx/coroutines/scheduling/CoroutineScheduler$OtherWorker",
                SETTER,
                DESCRIPTOR,
                false),
            new Example("threadOtherSignature", THREAD, SETTER, "(Ljava/lang/Object;)V", false),
            new Example("workerOtherSignature", WORKER, SETTER, "(Ljava/lang/Object;)V", false),
            new Example("threadOtherName", THREAD, "setOtherClassLoader", DESCRIPTOR, false),
            new Example("workerOtherName", WORKER, "setOtherClassLoader", DESCRIPTOR, false));
    byte[] resource = "keep non-class resources".getBytes(StandardCharsets.UTF_8);
    try (ZipOutputStream output = new ZipOutputStream(Files.newOutputStream(fixture))) {
      output.putNextEntry(new ZipEntry("fixtures/LoaderCalls.class"));
      output.write(fixture(examples));
      output.closeEntry();
      output.putNextEntry(new ZipEntry("fixture.txt"));
      output.write(resource);
      output.closeEntry();
    }
    Invocation inherited = new Invocation(Opcodes.INVOKEVIRTUAL, WORKER, SETTER, DESCRIPTOR);
    String workerClass = WORKER + ".class";
    byte[] originalWorker = read(originalCore, workerClass);
    Map<String, List<Invocation>> originalCalls = calls(originalWorker);
    long inheritedCalls = count(originalCalls, inherited);
    require(inheritedCalls > 0, "Locked core must exercise the actual inherited Worker invocation");
    require(count(originalCalls, target()) == 0, "Original official core must remain unadapted");
    Files.copy(originalCore, copiedCore);
    PatchLibraries.main(new String[] {fixture.toString(), copiedCore.toString()});

    Map<String, List<Invocation>> adapted = calls(read(fixture, "fixtures/LoaderCalls.class"));
    for (Example example : examples) {
      Invocation expected =
          example.adapted
              ? target()
              : new Invocation(
                  Opcodes.INVOKEVIRTUAL, example.owner, example.name, example.descriptor);
      require(
          List.of(expected).equals(adapted.get(example.label)),
          "Unexpected adaptation: " + example.label);
    }
    require(Arrays.equals(resource, read(fixture, "fixture.txt")), "Non-class resource changed");
    Map<String, List<Invocation>> transformedCore = calls(read(copiedCore, workerClass));
    require(count(transformedCore, inherited) == 0, "Inherited Worker call was not adapted");
    require(
        count(transformedCore, target()) == inheritedCalls,
        "Unexpected official Worker rewrite count");
    require(
        Arrays.equals(originalWorker, read(originalCore, workerClass)),
        "Original official core changed");
    System.out.println(
        "PatchLibraries: 8 invocation cases and the official inherited Worker call passed");
  }
}
