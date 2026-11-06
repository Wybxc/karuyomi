import java.io.*;
import java.nio.file.*;
import java.util.*;
import java.util.zip.*;
import org.objectweb.asm.*;

/** Adapt only host/dependency libraries. Extension input JAR is never rewritten. */
public class PatchLibraries {
  public static void main(String[] args) throws Exception {
    for (String arg : args) {
      Path f = Path.of(arg);
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      try (ZipInputStream in = new ZipInputStream(Files.newInputStream(f));
          ZipOutputStream z = new ZipOutputStream(out)) {
        ZipEntry e;
        while ((e = in.getNextEntry()) != null) {
          byte[] b = in.readAllBytes();
          if (e.getName().endsWith(".class")) {
            ClassReader r = new ClassReader(b);
            ClassWriter w = new ClassWriter(ClassWriter.COMPUTE_MAXS);
            r.accept(
                new ClassVisitor(Opcodes.ASM9, w) {
                  public MethodVisitor visitMethod(
                      int a, String n, String d, String s, String[] ex) {
                    if (r.getClassName().equals("android/view/ViewGroup$LayoutParams")
                        && n.equals("<init>")
                        && d.equals("(II)V")) {
                      MethodVisitor method = super.visitMethod(a, n, d, s, ex);
                      method.visitCode();
                      method.visitVarInsn(Opcodes.ALOAD, 0);
                      method.visitMethodInsn(
                          Opcodes.INVOKESPECIAL, "java/lang/Object", "<init>", "()V", false);
                      method.visitVarInsn(Opcodes.ALOAD, 0);
                      method.visitVarInsn(Opcodes.ILOAD, 1);
                      method.visitFieldInsn(Opcodes.PUTFIELD, r.getClassName(), "width", "I");
                      method.visitVarInsn(Opcodes.ALOAD, 0);
                      method.visitVarInsn(Opcodes.ILOAD, 2);
                      method.visitFieldInsn(Opcodes.PUTFIELD, r.getClassName(), "height", "I");
                      method.visitInsn(Opcodes.RETURN);
                      method.visitMaxs(2, 3);
                      method.visitEnd();
                      return null;
                    }
                    if (r.getClassName().equals("com/ibm/icu/impl/ICUBinary")
                        && n.equals("mapFile")
                        && d.equals("(Ljava/io/File;)Ljava/nio/ByteBuffer;")) {
                      MethodVisitor method = super.visitMethod(a, n, d, s, ex);
                      method.visitCode();
                      method.visitVarInsn(Opcodes.ALOAD, 0);
                      method.visitMethodInsn(
                          Opcodes.INVOKESTATIC,
                          "prototype/PlatformSupport",
                          "mapIcuFile",
                          d,
                          false);
                      method.visitInsn(Opcodes.ARETURN);
                      method.visitMaxs(1, 1);
                      method.visitEnd();
                      return null;
                    }
                    if (r.getClassName().equals("eu/kanade/tachiyomi/network/OkHttpExtensionsKt")
                        && n.equals("newCachelessCallWithProgress")
                        && d.equals(
                            "(Lokhttp3/OkHttpClient;Lokhttp3/Request;Leu/kanade/tachiyomi/network/ProgressListener;)Lokhttp3/Call;")) {
                      MethodVisitor method = super.visitMethod(a, n, d, s, ex);
                      method.visitCode();
                      method.visitVarInsn(Opcodes.ALOAD, 0);
                      method.visitVarInsn(Opcodes.ALOAD, 1);
                      method.visitVarInsn(Opcodes.ALOAD, 2);
                      method.visitMethodInsn(
                          Opcodes.INVOKESTATIC, "prototype/BrowserCall", n, d, false);
                      method.visitInsn(Opcodes.ARETURN);
                      method.visitMaxs(3, 3);
                      method.visitEnd();
                      return null;
                    }
                    boolean completionWrapper =
                        r.getClassName().equals("kotlinx/coroutines/JobSupport")
                            && n.equals("completeStateFinalization")
                            && d.equals("(Lkotlinx/coroutines/Incomplete;Ljava/lang/Object;)V");
                    return new MethodVisitor(
                        Opcodes.ASM9,
                        super.visitMethod(
                            a, completionWrapper ? "hostCompleteStateFinalization" : n, d, s, ex)) {
                      public void visitCode() {
                        super.visitCode();
                        if (r.getClassName().equals("kotlinx/coroutines/AbstractCoroutine")
                            && n.equals("<init>")
                            && d.equals("(Lkotlin/coroutines/CoroutineContext;ZZ)V")) {
                          super.visitVarInsn(Opcodes.ALOAD, 1);
                          super.visitMethodInsn(
                              Opcodes.INVOKESTATIC,
                              "prototype/HostCoroutines",
                              "capture",
                              "(Lkotlin/coroutines/CoroutineContext;)Lkotlin/coroutines/CoroutineContext;",
                              false);
                          super.visitVarInsn(Opcodes.ASTORE, 1);
                        }
                        if (r.getClassName().equals("kotlinx/coroutines/JobSupport")
                            && n.equals("startInternal")
                            && d.equals("(Ljava/lang/Object;)I")) {
                          super.visitVarInsn(Opcodes.ALOAD, 0);
                          super.visitMethodInsn(
                              Opcodes.INVOKESTATIC,
                              "prototype/HostCoroutines",
                              "beforeStart",
                              "(Lkotlinx/coroutines/Job;)V",
                              false);
                        }
                        if (r.getClassName().equals("kotlinx/coroutines/JobSupport")
                            && n.equals("invokeOnCompletion")
                            && (d.equals(
                                    "(Lkotlin/jvm/functions/Function1;)Lkotlinx/coroutines/DisposableHandle;")
                                || d.equals(
                                    "(ZZLkotlin/jvm/functions/Function1;)Lkotlinx/coroutines/DisposableHandle;"))) {
                          int parameter = d.startsWith("(ZZ") ? 3 : 1;
                          super.visitVarInsn(Opcodes.ALOAD, 0);
                          super.visitVarInsn(Opcodes.ALOAD, parameter);
                          super.visitMethodInsn(
                              Opcodes.INVOKESTATIC,
                              "prototype/HostCoroutines",
                              "captureCompletion",
                              "(Lkotlinx/coroutines/Job;Lkotlin/jvm/functions/Function1;)Lkotlin/jvm/functions/Function1;",
                              false);
                          super.visitVarInsn(Opcodes.ASTORE, parameter);
                        }
                        if (Boolean.getBoolean("trace")
                            && r.getClassName().startsWith("kotlinx/coroutines/")
                            && (n.equals("<init>") && r.getClassName().endsWith("AbstractCoroutine")
                                || n.equals("coroutineScope")
                                || n.equals("async")
                                || n.equals("newCoroutineContext")
                                || n.equals("initParentJob")
                                || n.equals("attachChild")
                                || n.equals("start")
                                || n.equals("startCoroutineCancellable")
                                || n.equals("resumeCancellableWith")
                                || n.equals("dispatchUnconfined")
                                || n.equals("processUnconfinedEvent"))) {
                          super.visitLdcInsn(r.getClassName() + "." + n);
                          super.visitMethodInsn(
                              Opcodes.INVOKESTATIC,
                              "prototype/Bridge",
                              "trace",
                              "(Ljava/lang/String;)Ljava/lang/String;",
                              false);
                          super.visitInsn(Opcodes.POP);
                        }
                      }

                      public void visitMethodInsn(
                          int op, String owner, String name, String desc, boolean itf) {
                        if (owner.equals("java/nio/charset/Charset")
                            && name.equals("isSupported")) {
                          super.visitMethodInsn(
                              Opcodes.INVOKESTATIC,
                              "prototype/PlatformSupport",
                              "charsetSupported",
                              desc,
                              false);
                          return;
                        }
                        // TLS belongs to the verified fetch transport. Only responses restored by
                        // our
                        // browser cache may omit Java's unavailable Handshake/certificate
                        // serialization.
                        if (r.getClassName().equals("okhttp3/internal/cache/CacheStrategy$Factory")
                            && n.equals("computeCandidate")
                            && owner.equals("okhttp3/Request")
                            && name.equals("isHttps")) {
                          super.visitVarInsn(Opcodes.ALOAD, 0);
                          super.visitFieldInsn(
                              Opcodes.GETFIELD,
                              r.getClassName(),
                              "cacheResponse",
                              "Lokhttp3/Response;");
                          super.visitMethodInsn(
                              Opcodes.INVOKESTATIC,
                              "okhttp3/Cache",
                              "requiresJavaHandshake",
                              "(Lokhttp3/Request;Lokhttp3/Response;)Z",
                              false);
                          return;
                        }
                        if (owner.equals("java/lang/Class")
                            && name.equals("newInstance")
                            && desc.equals("()Ljava/lang/Object;")
                            && n.equals("getShim")
                            && (r.getClassName().equals("com/ibm/icu/text/Collator")
                                || r.getClassName().equals("com/ibm/icu/text/BreakIterator"))) {
                          super.visitMethodInsn(
                              Opcodes.INVOKESTATIC,
                              "com/ibm/icu/text/AotServiceFactory",
                              "newInstance",
                              "(Ljava/lang/Class;)Ljava/lang/Object;",
                              false);
                          return;
                        }
                        if ((owner.equals("java/lang/Thread")
                                || owner.equals(
                                    "kotlinx/coroutines/scheduling/CoroutineScheduler$Worker"))
                            && name.equals("setContextClassLoader")
                            && desc.equals("(Ljava/lang/ClassLoader;)V")) {
                          super.visitMethodInsn(
                              Opcodes.INVOKESTATIC,
                              "prototype/PlatformSupport",
                              "contextLoader",
                              "(Ljava/lang/Thread;Ljava/lang/ClassLoader;)V",
                              false);
                          return;
                        }
                        if (owner.equals("java/lang/ClassLoader") && name.equals("getResources")) {
                          super.visitMethodInsn(
                              Opcodes.INVOKESTATIC,
                              "prototype/PlatformSupport",
                              "resources",
                              "(Ljava/lang/ClassLoader;Ljava/lang/String;)Ljava/util/Enumeration;",
                              false);
                          return;
                        }
                        if (owner.equals("java/lang/ClassLoader")
                            && name.equals("loadClass")
                            && desc.equals("(Ljava/lang/String;)Ljava/lang/Class;")) {
                          super.visitMethodInsn(
                              Opcodes.INVOKESTATIC,
                              "prototype/PlatformSupport",
                              "loadClass",
                              "(Ljava/lang/ClassLoader;Ljava/lang/String;)Ljava/lang/Class;",
                              false);
                          return;
                        }
                        if (owner.equals("java/lang/Thread") && name.equals("dumpStack")) {
                          super.visitMethodInsn(
                              Opcodes.INVOKESTATIC,
                              "prototype/PlatformSupport",
                              "dumpStack",
                              desc,
                              false);
                          return;
                        }
                        if (r.getClassName().equals("kotlinx/coroutines/AbstractCoroutine")
                            && n.equals("<init>")
                            && d.equals("(Lkotlin/coroutines/CoroutineContext;ZZ)V")
                            && owner.equals("kotlinx/coroutines/JobSupport")
                            && name.equals("<init>")
                            && desc.equals("(Z)V")) {
                          super.visitMethodInsn(op, owner, name, desc, itf);
                          super.visitVarInsn(Opcodes.ALOAD, 0);
                          super.visitVarInsn(Opcodes.ALOAD, 1);
                          super.visitVarInsn(Opcodes.ILOAD, 3);
                          super.visitMethodInsn(
                              Opcodes.INVOKESTATIC,
                              "prototype/HostCoroutines",
                              "created",
                              "(Lkotlinx/coroutines/Job;Lkotlin/coroutines/CoroutineContext;Z)V",
                              false);
                          return;
                        }
                        super.visitMethodInsn(op, owner, name, desc, itf);
                      }
                    };
                  }

                  public void visitEnd() {
                    if (r.getClassName().equals("kotlinx/coroutines/JobSupport")) {
                      MethodVisitor method =
                          super.visitMethod(
                              Opcodes.ACC_PRIVATE | Opcodes.ACC_FINAL,
                              "completeStateFinalization",
                              "(Lkotlinx/coroutines/Incomplete;Ljava/lang/Object;)V",
                              null,
                              null);
                      Label start = new Label(), end = new Label(), handler = new Label();
                      method.visitCode();
                      method.visitVarInsn(Opcodes.ALOAD, 0);
                      method.visitMethodInsn(
                          Opcodes.INVOKESTATIC,
                          "prototype/HostCoroutines",
                          "completing",
                          "(Lkotlinx/coroutines/Job;)Lprototype/HostCoroutines$CompletionScope;",
                          false);
                      method.visitVarInsn(Opcodes.ASTORE, 3);
                      method.visitLabel(start);
                      method.visitVarInsn(Opcodes.ALOAD, 0);
                      method.visitVarInsn(Opcodes.ALOAD, 1);
                      method.visitVarInsn(Opcodes.ALOAD, 2);
                      method.visitMethodInsn(
                          Opcodes.INVOKESPECIAL,
                          r.getClassName(),
                          "hostCompleteStateFinalization",
                          "(Lkotlinx/coroutines/Incomplete;Ljava/lang/Object;)V",
                          false);
                      method.visitLabel(end);
                      method.visitVarInsn(Opcodes.ALOAD, 3);
                      method.visitMethodInsn(
                          Opcodes.INVOKEVIRTUAL,
                          "prototype/HostCoroutines$CompletionScope",
                          "close",
                          "()V",
                          false);
                      method.visitInsn(Opcodes.RETURN);
                      method.visitLabel(handler);
                      method.visitFrame(
                          Opcodes.F_FULL,
                          4,
                          new Object[] {
                            r.getClassName(),
                            "kotlinx/coroutines/Incomplete",
                            "java/lang/Object",
                            "prototype/HostCoroutines$CompletionScope"
                          },
                          1,
                          new Object[] {"java/lang/Throwable"});
                      method.visitVarInsn(Opcodes.ASTORE, 4);
                      method.visitVarInsn(Opcodes.ALOAD, 3);
                      method.visitMethodInsn(
                          Opcodes.INVOKEVIRTUAL,
                          "prototype/HostCoroutines$CompletionScope",
                          "close",
                          "()V",
                          false);
                      method.visitVarInsn(Opcodes.ALOAD, 4);
                      method.visitInsn(Opcodes.ATHROW);
                      method.visitTryCatchBlock(start, end, handler, null);
                      method.visitMaxs(3, 5);
                      method.visitEnd();
                    }
                    super.visitEnd();
                  }
                },
                0);
            b = w.toByteArray();
          }
          z.putNextEntry(new ZipEntry(e.getName()));
          z.write(b);
          z.closeEntry();
        }
      }
      Files.write(f, out.toByteArray());
    }
  }
}
