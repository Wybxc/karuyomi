package prototype;

import java.net.URL;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TimeZone;
import org.teavm.model.*;
import org.teavm.model.emit.ProgramEmitter;
import org.teavm.model.instructions.*;
import prototype.jcl.PackagedResources;

/** Apply compatibility transformations to TeaVM IR and leave the input JAR intact. */
public class TeaTransformer implements ClassHolderTransformer {
  private static final MethodDescriptor SOURCE_INPUT =
      new MethodDescriptor(
          "askInput",
          ValueType.object("java.lang.String"),
          ValueType.object("java.lang.String"),
          ValueType.object("java.lang.String"),
          ValueType.object("java.lang.String"),
          ValueType.BOOLEAN,
          ValueType.BOOLEAN,
          ValueType.object("kotlin.coroutines.Continuation"),
          ValueType.object("java.lang.Object"));
  private static final ValueType OKHTTP_BUILDER = ValueType.object("okhttp3.OkHttpClient$Builder");
  private static final MethodDescriptor CONFIGURE_CLIENT =
      new MethodDescriptor("configureClient", OKHTTP_BUILDER, OKHTTP_BUILDER);
  private static final MethodReference OKHTTP_PROTOCOLS =
      new MethodReference(
          "okhttp3.OkHttpClient$Builder",
          new MethodDescriptor("protocols", ValueType.object("java.util.List"), OKHTTP_BUILDER));
  private static final MethodDescriptor WEBSITE_VERIFICATION =
      new MethodDescriptor(
          "getTurnstileToken-x2RqbK4",
          ValueType.object("java.lang.String"),
          ValueType.object("java.lang.String"),
          ValueType.object("java.lang.String"),
          ValueType.object("java.lang.String"),
          ValueType.object("java.lang.String"),
          ValueType.LONG,
          ValueType.object("kotlin.coroutines.Continuation"),
          ValueType.object("java.lang.Object"));
  private static final MethodDescriptor SPYFAKKU_VERIFY =
      new MethodDescriptor(
          "resolveInWebView",
          ValueType.object("okhttp3.Request"),
          ValueType.object("okhttp3.Call"),
          ValueType.BOOLEAN);
  private static final MethodDescriptor TOONLIVRE_VERIFY =
      new MethodDescriptor(
          "openVerificationWebView",
          ValueType.object("java.lang.String"),
          ValueType.object("java.lang.String"),
          ValueType.object("java.lang.String"),
          ValueType.object("kotlin.coroutines.Continuation"),
          ValueType.object("java.lang.Object"));

  public void transformClass(ClassHolder cls, ClassHolderTransformerContext context) {
    if (cls.getName().equals("eu.kanade.tachiyomi.extension.en.megatokyo.Megatokyo")
        && "1".equals(System.getenv("KARUYOMI_AOT_MEGATOKYO_PLATFORM_TLS"))) {
      // For this pinned helper the sole effect is to install weaker TLS settings.
      // Keep the ordinary builder so the relay can apply its platform TLS checks.
      var helper =
          cls.getMethod(new MethodDescriptor("ignoreAllSSLErrors", OKHTTP_BUILDER, OKHTTP_BUILDER));
      if (helper == null || helper.getProgram() == null)
        throw new IllegalStateException("Pinned MegaTokyo TLS helper is missing");
      ProgramEmitter emitter = ProgramEmitter.create(helper, context.getHierarchy());
      emitter.var(1, OKHTTP_BUILDER).returnValue();
    }
    if (cls.getName().equals("eu.kanade.tachiyomi.extension.en.spyfakku.SpyFakku")
        && "1".equals(System.getenv("KARUYOMI_AOT_SPYFAKKU_PLATFORM_TLS"))) {
      usePlatformTls(cls, context);
    }
    if (cls.getName().equals("eu.kanade.tachiyomi.extension.en.spyfakku.AnibusInterceptor")
        && "1".equals(System.getenv("KARUYOMI_AOT_SPYFAKKU_PLATFORM_TLS"))) {
      requireOfficialReader(
          cls,
          context,
          SPYFAKKU_VERIFY,
          "This mirror requires verification in its browser reader.");
    }
    if (cls.getName().equals("eu.kanade.tachiyomi.extension.pt.mangalivre.MangaLivre")
        && "1".equals(System.getenv("KARUYOMI_AOT_TOONLIVRE_READER_VERIFICATION"))) {
      requireOfficialReader(
          cls,
          context,
          TOONLIVRE_VERIFY,
          "Este capítulo requer verificação no leitor oficial do ToonLivre.");
    }
    if ("1".equals(System.getenv("KARUYOMI_AOT_PLATFORM_HTTP_NEGOTIATION"))
        && (cls.getName().equals("eu.kanade.tachiyomi.extension.en.reimanga.Reimanga")
            || cls.getName().equals("eu.kanade.tachiyomi.extension.zh.ikmmh.Ikmmh"))) {
      usePlatformHttpNegotiation(cls);
    }
    if (cls.getName().equals("keiyoushi.utils.TurnstileHelperKt")
        && "1".equals(System.getenv("KARUYOMI_AOT_BROWSER_VERIFICATION"))) {
      requireOfficialReader(
          cls,
          context,
          WEBSITE_VERIFICATION,
          "This website requires verification in its official browser reader.");
    }
    if (cls.getName().equals("java.lang.Class")) {
      MethodDescriptor descriptor = new MethodDescriptor("getResource", String.class, URL.class);
      if (cls.getMethod(descriptor) == null) {
        MethodHolder method = new MethodHolder(descriptor);
        method.setLevel(AccessLevel.PUBLIC);
        ProgramEmitter program = ProgramEmitter.create(method, context.getHierarchy());
        program
            .invoke(
                PackagedResources.class,
                "getResource",
                URL.class,
                program.var(0, Class.class),
                program.var(1, String.class))
            .returnValue();
        cls.addMethod(method);
      }
    }
    if (cls.getName().equals("java.util.TimeZone")) {
      MethodDescriptor descriptor = new MethodDescriptor("toZoneId", ZoneId.class);
      if (cls.getMethod(descriptor) == null) {
        MethodHolder method = new MethodHolder(descriptor);
        method.setLevel(AccessLevel.PUBLIC);
        ProgramEmitter program = ProgramEmitter.create(method, context.getHierarchy());
        program
            .invoke(
                ZoneId.class,
                "of",
                ZoneId.class,
                program.var(0, TimeZone.class).invokeVirtual("getID", String.class),
                program.getField(ZoneId.class, "SHORT_IDS", Map.class))
            .returnValue();
        cls.addMethod(method);
      }
    }
    if (cls.getName().equals("java.text.DateFormatElement$WeekdayText")) {
      replaceDateParse(
          cls,
          context,
          "org.teavm.classlib.java.text.PatchedDateFormatElement$WeekdayText",
          new MethodDescriptor(
              "parse",
              ValueType.object("java.lang.String"),
              ValueType.object("java.util.Calendar"),
              ValueType.object("java.text.ParsePosition"),
              ValueType.VOID));
    }
    if (cls.getName().equals("java.text.SimpleDateFormat")) {
      replaceDateParse(
          cls,
          context,
          "org.teavm.classlib.java.text.PatchedSimpleDateFormat",
          new MethodDescriptor(
              "parse",
              ValueType.object("java.lang.String"),
              ValueType.object("java.text.ParsePosition"),
              ValueType.object("java.util.Date")));
    }
    if (cls.getName().equals("java.io.File")) {
      String sourceName = "prototype.jcl.FileMethods";
      ClassHolder copy =
          org.teavm.model.util.ModelUtils.copyClass(
              context.getHierarchy().getClassSource().get(sourceName));
      copy =
          new org.teavm.parsing.ClassRefsRenamer(
                  new ReferenceCache(), n -> n.equals(sourceName) ? cls.getName() : n)
              .rename(copy);
      MethodDescriptor descriptor = new MethodDescriptor("mkdirs", ValueType.BOOLEAN);
      cls.getMethod(descriptor)
          .setProgram(
              org.teavm.model.util.ModelUtils.copyMethod(copy.getMethod(descriptor)).getProgram());
    }
    if (cls.getName().equals("java.io.FileInputStream")) {
      String sourceName = "prototype.jcl.FileInputStreamMethods";
      ClassHolder copy =
          org.teavm.model.util.ModelUtils.copyClass(
              context.getHierarchy().getClassSource().get(sourceName));
      copy =
          new org.teavm.parsing.ClassRefsRenamer(
                  new ReferenceCache(), n -> n.equals(sourceName) ? cls.getName() : n)
              .rename(copy);
      MethodDescriptor descriptor = new MethodDescriptor("read", ValueType.INTEGER);
      MethodHolder target = cls.getMethod(descriptor);
      if (target == null)
        throw new IllegalStateException("Unexpected TeaVM FileInputStream.read ABI");
      target.setProgram(
          org.teavm.model.util.ModelUtils.copyMethod(copy.getMethod(descriptor)).getProgram());
    }
    if (cls.getName().equals("java.io.RandomAccessFile")) {
      String sourceName = "prototype.jcl.RandomAccessFileMethods";
      ClassHolder copy =
          org.teavm.model.util.ModelUtils.copyClass(
              context.getHierarchy().getClassSource().get(sourceName));
      copy =
          new org.teavm.parsing.ClassRefsRenamer(
                  new ReferenceCache(), n -> n.equals(sourceName) ? cls.getName() : n)
              .rename(copy);
      for (MethodDescriptor descriptor :
          new MethodDescriptor[] {
            new MethodDescriptor("close", ValueType.VOID),
            new MethodDescriptor(
                "read",
                ValueType.arrayOf(ValueType.BYTE),
                ValueType.INTEGER,
                ValueType.INTEGER,
                ValueType.INTEGER)
          }) {
        MethodHolder target = cls.getMethod(descriptor);
        if (target == null)
          throw new IllegalStateException("Unexpected TeaVM RandomAccessFile ABI: " + descriptor);
        target.setProgram(
            org.teavm.model.util.ModelUtils.copyMethod(copy.getMethod(descriptor)).getProgram());
      }
      for (MethodHolder method : cls.getMethods())
        if (method.getName().equals("<init>")
            && method.parameterCount() == 2
            && method.parameterType(0).equals(ValueType.object("java.io.File"))) {
          Program p = method.getProgram();
          for (int i = 0; i < p.basicBlockCount(); i++)
            for (Instruction instruction : p.basicBlockAt(i))
              if (instruction instanceof InvokeInstruction) {
                InvokeInstruction invoke = (InvokeInstruction) instruction;
                if (invoke.getMethod().getClassName().equals("java.io.File")
                    && invoke.getMethod().getName().equals("findVirtualFile")) {
                  InvokeInstruction prepare = new InvokeInstruction();
                  prepare.setType(InvocationType.SPECIAL);
                  prepare.setArguments(invoke.getInstance(), p.variableAt(2));
                  prepare.setMethod(
                      new MethodReference(
                          "prototype.jcl.FileMethods",
                          "prepareRandomAccessFile",
                          ValueType.object("java.io.File"),
                          ValueType.object("java.lang.String"),
                          ValueType.VOID));
                  invoke.insertPrevious(prepare);
                }
              }
        }
    }
    if (cls.getName().equals("java.net.URL")) {
      String sourceName = "prototype.jcl.UrlMethods";
      ClassHolder copy =
          org.teavm.model.util.ModelUtils.copyClass(
              context.getHierarchy().getClassSource().get(sourceName));
      copy =
          new org.teavm.parsing.ClassRefsRenamer(
                  new ReferenceCache(), n -> n.equals(sourceName) ? cls.getName() : n)
              .rename(copy);
      ValueType string = ValueType.object("java.lang.String");
      MethodDescriptor descriptor =
          new MethodDescriptor(
              "set",
              string,
              string,
              ValueType.INTEGER,
              string,
              string,
              string,
              string,
              string,
              ValueType.VOID);
      MethodHolder target = cls.getMethod(descriptor);
      if (target == null) throw new IllegalStateException("Unexpected TeaVM URL.set ABI");
      target.setProgram(
          org.teavm.model.util.ModelUtils.copyMethod(copy.getMethod(descriptor)).getProgram());
    }
    if (cls.getName().equals("java.util.regex.Matcher")) {
      String sourceName = "org.teavm.classlib.java.util.regex.MatcherFindMethods";
      ClassHolder copy =
          org.teavm.model.util.ModelUtils.copyClass(
              context.getHierarchy().getClassSource().get(sourceName));
      copy =
          new org.teavm.parsing.ClassRefsRenamer(
                  new ReferenceCache(), n -> n.equals(sourceName) ? cls.getName() : regexType(n))
              .rename(copy);
      MethodDescriptor descriptor =
          new MethodDescriptor("findAt", ValueType.INTEGER, ValueType.INTEGER);
      cls.getMethod(descriptor)
          .setProgram(
              org.teavm.model.util.ModelUtils.copyMethod(copy.getMethod(descriptor)).getProgram());
    }
    if (cls.getName().equals("java.lang.Object")) {
      ClassReader source =
          context
              .getHierarchy()
              .getClassSource()
              .get("org.teavm.classlib.java.lang.WaitObjectMethods");
      ClassHolder copy = org.teavm.model.util.ModelUtils.copyClass(source);
      copy =
          new org.teavm.parsing.ClassRefsRenamer(
                  new ReferenceCache(),
                  n ->
                      n.equals("org.teavm.classlib.java.lang.WaitObjectMethods")
                          ? "java.lang.Object"
                          : standardType(n))
              .rename(copy);
      MethodHolder replacement =
          copy.getMethod(
              new MethodDescriptor(
                  "waitSupport",
                  ValueType.LONG,
                  ValueType.INTEGER,
                  ValueType.object("org.teavm.interop.AsyncCallback"),
                  ValueType.VOID));
      MethodHolder target =
          cls.getMethod(
              new MethodDescriptor(
                  "waitImpl",
                  ValueType.LONG,
                  ValueType.INTEGER,
                  ValueType.object("org.teavm.interop.AsyncCallback"),
                  ValueType.VOID));
      if (target == null) throw new IllegalStateException("Unexpected TeaVM Object.wait ABI");
      target.setProgram(org.teavm.model.util.ModelUtils.copyMethod(replacement).getProgram());
    }
    if (java.util.Set.of(
            "java.util.regex.Pattern",
            "java.util.regex.Lexer",
            "java.util.regex.UnicodeCategory",
            "java.util.regex.UnicodeCategoryScope",
            "java.util.regex.UCISequenceSet",
            "java.util.regex.EOLSet",
            "java.util.regex.UEOLSet",
            "java.util.regex.MultiLineEOLSet",
            "java.util.regex.UMultiLineEOLSet",
            "java.util.regex.SOLSet",
            "java.util.regex.RelCompositeGroupQuantifierSet")
        .contains(cls.getName())) {
      String type = cls.getName().substring("java.util.regex.".length());
      ClassReader source =
          context
              .getHierarchy()
              .getClassSource()
              .get("org.teavm.classlib.java.util.regex.Patched" + type);
      ClassHolder copy = org.teavm.model.util.ModelUtils.copyClass(source);
      copy =
          new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(), TeaTransformer::regexType)
              .rename(copy);
      cls.removeAllMethods();
      cls.removeAllFields();
      org.teavm.model.util.ModelUtils.copyClass(copy, cls);
      return;
    }
    if (java.util.Set.of(
            "org.teavm.classlib.java.util.regex.LineBreakSet",
            "org.teavm.classlib.java.util.regex.CasedLetterProperty",
            "org.teavm.classlib.java.util.regex.SingleCharLookBehind")
        .contains(cls.getName())) {
      ClassHolder copy = org.teavm.model.util.ModelUtils.copyClass(cls);
      copy =
          new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(), TeaTransformer::regexType)
              .rename(copy);
      cls.removeAllMethods();
      cls.removeAllFields();
      org.teavm.model.util.ModelUtils.copyClass(copy, cls);
      return;
    }
    if (cls.getName().startsWith("org.teavm.classlib.java.lang.WaitInterruptSupport")) {
      ClassHolder copy = org.teavm.model.util.ModelUtils.copyClass(cls);
      copy =
          new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(), TeaTransformer::standardType)
              .rename(copy);
      cls.removeAllMethods();
      cls.removeAllFields();
      org.teavm.model.util.ModelUtils.copyClass(copy, cls);
      return;
    }
    if (cls.getName().equals("java.lang.Object$NotifyListenerImpl")) {
      ClassReader source =
          context.getHierarchy().getClassSource().get("prototype.jcl.WaitListenerMethods");
      ClassHolder copy = org.teavm.model.util.ModelUtils.copyClass(source);
      copy =
          new org.teavm.parsing.ClassRefsRenamer(
                  new ReferenceCache(),
                  n ->
                      n.equals("prototype.jcl.WaitListenerMethods")
                          ? cls.getName()
                          : standardType(n))
              .rename(copy);
      for (MethodHolder method : cls.getMethods())
        if (method.getName().startsWith("lambda$interrupted$"))
          method.setProgram(
              org.teavm.model.util.ModelUtils.copyMethod(
                      copy.getMethod(new MethodDescriptor("resumeInterrupted", ValueType.VOID)))
                  .getProgram());
      MethodHolder interrupted = cls.getMethod(new MethodDescriptor("interrupted", ValueType.VOID));
      Program program = interrupted.getProgram();
      for (int i = 0; i < program.basicBlockCount(); i++)
        for (Instruction instruction : program.basicBlockAt(i))
          if (instruction instanceof PutFieldInstruction) {
            PutFieldInstruction put = (PutFieldInstruction) instruction;
            if (put.getField().getFieldName().equals("performed")) {
              PutFieldInstruction expire = new PutFieldInstruction();
              expire.setInstance(put.getInstance());
              expire.setValue(put.getValue());
              expire.setFieldType(ValueType.BOOLEAN);
              expire.setField(new FieldReference(cls.getName(), "expired"));
              put.insertNext(expire);
            }
          }
    }
    if (cls.getName().equals("java.util.Locale")) {
      ClassReader source =
          context.getHierarchy().getClassSource().get("prototype.jcl.LocaleMethods");
      ClassHolder copy = org.teavm.model.util.ModelUtils.copyClass(source);
      copy =
          new org.teavm.parsing.ClassRefsRenamer(
                  new ReferenceCache(),
                  n -> n.equals("prototype.jcl.LocaleMethods") ? "java.util.Locale" : n)
              .rename(copy);
      for (MethodHolder method : new java.util.ArrayList<>(copy.getMethods()))
        if (!method.getName().equals("<init>")) {
          MethodHolder old = cls.getMethod(method.getDescriptor());
          if (old != null) cls.removeMethod(old);
          copy.removeMethod(method);
          cls.addMethod(method);
        }
    }
    if (cls.getName().equals("java.util.regex.ReluctantGroupQuantifierSet")) {
      ClassReader source =
          context
              .getHierarchy()
              .getClassSource()
              .get("org.teavm.classlib.java.util.regex.PatchedReluctantGroupQuantifierSet");
      if (source == null) throw new IllegalStateException("Missing reluctant regex patch");
      ClassHolder copy = org.teavm.model.util.ModelUtils.copyClass(source);
      copy =
          new org.teavm.parsing.ClassRefsRenamer(
                  new ReferenceCache(),
                  n ->
                      n.equals(
                              "org.teavm.classlib.java.util.regex.PatchedReluctantGroupQuantifierSet")
                          ? "java.util.regex.ReluctantGroupQuantifierSet"
                          : n.startsWith("org.teavm.classlib.java.util.regex.T")
                              ? "java.util.regex."
                                  + n.substring("org.teavm.classlib.java.util.regex.T".length())
                              : n)
              .rename(copy);
      cls.removeAllMethods();
      cls.removeAllFields();
      org.teavm.model.util.ModelUtils.copyClass(copy, cls);
      return;
    }
    if (cls.getName().equals("java.util.regex.GroupQuantifierSet")) {
      ClassReader source =
          context
              .getHierarchy()
              .getClassSource()
              .get("org.teavm.classlib.java.util.regex.PatchedGroupQuantifierSet");
      if (source == null) throw new IllegalStateException("Missing regex patch");
      ClassHolder copy = org.teavm.model.util.ModelUtils.copyClass(source);
      copy =
          new org.teavm.parsing.ClassRefsRenamer(
                  new ReferenceCache(),
                  n ->
                      n.equals("org.teavm.classlib.java.util.regex.PatchedGroupQuantifierSet")
                          ? "java.util.regex.GroupQuantifierSet"
                          : n.startsWith("org.teavm.classlib.java.util.regex.T")
                              ? "java.util.regex."
                                  + n.substring("org.teavm.classlib.java.util.regex.T".length())
                              : n)
              .rename(copy);
      cls.removeAllMethods();
      cls.removeAllFields();
      org.teavm.model.util.ModelUtils.copyClass(copy, cls);
      return;
    }
    if (cls.getName().equals("java.util.Base64") || cls.getName().startsWith("java.util.Base64$")) {
      String replacement =
          "prototype.jcl.Base64" + cls.getName().substring("java.util.Base64".length());
      ClassReader source = context.getHierarchy().getClassSource().get(replacement);
      if (source == null) throw new IllegalStateException("Missing Base64 patch " + replacement);
      ClassHolder copy = org.teavm.model.util.ModelUtils.copyClass(source);
      copy =
          new org.teavm.parsing.ClassRefsRenamer(
                  new ReferenceCache(),
                  n ->
                      n.startsWith("prototype.jcl.Base64")
                          ? "java.util.Base64" + n.substring("prototype.jcl.Base64".length())
                          : n)
              .rename(copy);
      cls.removeAllMethods();
      cls.removeAllFields();
      org.teavm.model.util.ModelUtils.copyClass(copy, cls);
      return;
    }
    for (MethodHolder m : cls.getMethods()) {
      Program p = m.getProgram();
      if (p == null) continue;
      for (int i = 0; i < p.basicBlockCount(); i++)
        for (Instruction ins : p.basicBlockAt(i))
          if (ins instanceof InvokeInstruction) {
            InvokeInstruction invoke = (InvokeInstruction) ins;
            MethodReference ref = invoke.getMethod();
            if (ref.getClassName().equals("keiyoushi.utils.ui.DialogHelperKt")
                && ref.getDescriptor().equals(SOURCE_INPUT))
              invoke.setMethod(new MethodReference("prototype.SourceInput", SOURCE_INPUT));
            if (ref.getClassName().equals("org.teavm.runtime.reflect.ClassReflectionInfo")
                && ref.getName().equals("innerClassCount")) {
              InvokeInstruction prepare = new InvokeInstruction();
              prepare.setType(InvocationType.SPECIAL);
              prepare.setArguments(invoke.getInstance());
              prepare.setMethod(
                  new MethodReference(
                      "prototype.ReflectionSupport",
                      "prepareInnerClasses",
                      ValueType.object(ref.getClassName()),
                      ValueType.VOID));
              invoke.insertPrevious(prepare);
            }
            // Boolean is final. Use direct dispatch: TeaVM 0.16 can omit the virtual slot through
            // generic Map callbacks.
            if (ref.getClassName().equals("java.lang.Boolean")
                && ref.getName().equals("booleanValue")
                && invoke.getType() == InvocationType.VIRTUAL)
              invoke.setType(InvocationType.SPECIAL);
            if (ref.getClassName().equals("java.util.Collections")
                && (ref.getName().equals("unmodifiableSortedMap")
                    || ref.getName().equals("unmodifiableSortedSet")))
              invoke.setMethod(
                  new MethodReference("prototype.SortedViews", ref.getName(), ref.getSignature()));
            if (ref.getClassName().equals("java.lang.Character")
                && ref.getName().equals("toString")
                && ref.parameterCount() == 1
                && ref.parameterType(0).equals(ValueType.INTEGER))
              invoke.setMethod(
                  new MethodReference(
                      "prototype.PlatformSupport", "characterToString", ref.getSignature()));
            if (ref.getClassName().equals("okhttp3.OkHttpClient$Builder")
                && ref.getName().endsWith("-LRDsOJo")) {
              String name = ref.getName().substring(0, ref.getName().indexOf('-'));
              if (name.equals("callTimeout")
                  || name.equals("connectTimeout")
                  || name.equals("readTimeout")
                  || name.equals("writeTimeout"))
                invoke.setMethod(
                    new MethodReference(ref.getClassName(), name + "Duration", ref.getSignature()));
            }
            if (ref.getClassName().equals("java.util.Locale")
                && ref.getName().equals("forLanguageTag"))
              invoke.setMethod(
                  new MethodReference(
                      "prototype.PlatformSupport", "localeForTag", ref.getSignature()));
          }
    }
  }

  private static void replaceDateParse(
      ClassHolder cls,
      ClassHolderTransformerContext context,
      String sourceName,
      MethodDescriptor descriptor) {
    ClassReader source = context.getHierarchy().getClassSource().get(sourceName);
    MethodHolder target = cls.getMethod(descriptor);
    if (source == null || target == null)
      throw new IllegalStateException("Unexpected TeaVM date parser ABI: " + cls.getName());
    ClassHolder copy =
        new org.teavm.parsing.ClassRefsRenamer(
                new ReferenceCache(),
                name ->
                    name.equals(sourceName)
                        ? cls.getName()
                        : switch (name) {
                          case "org.teavm.classlib.java.text.TDateFormat" -> "java.text.DateFormat";
                          case "org.teavm.classlib.java.text.TDateFormatElement",
                              "org.teavm.classlib.java.text.PatchedDateFormatElement" ->
                              "java.text.DateFormatElement";
                          case "org.teavm.classlib.java.text.TParsePosition" ->
                              "java.text.ParsePosition";
                          case "org.teavm.classlib.java.util.TCalendar" -> "java.util.Calendar";
                          case "org.teavm.classlib.java.util.TDate" -> "java.util.Date";
                          default -> name;
                        })
            .rename(org.teavm.model.util.ModelUtils.copyClass(source));
    MethodHolder replacement = copy.getMethod(descriptor);
    if (replacement == null || replacement.getProgram() == null)
      throw new IllegalStateException("Missing TeaVM date parser donor: " + sourceName);
    target.setProgram(org.teavm.model.util.ModelUtils.copyMethod(replacement).getProgram());
  }

  private static void usePlatformTls(ClassHolder cls, ClassHolderTransformerContext context) {
    MethodHolder configure = cls.getMethod(CONFIGURE_CLIENT);
    if (configure == null || configure.getProgram() == null)
      throw new IllegalStateException("Pinned SpyFakku client configuration is missing");
    var classes = context.getHierarchy().getClassSource();
    for (BasicBlock block : configure.getProgram().getBasicBlocks()) {
      Instruction trustManager = null;
      List<String> calls = new ArrayList<>();
      for (Instruction instruction : block) {
        if (instruction instanceof ConstructInstruction construct) {
          ClassReader type = classes.get(construct.getType());
          if (type != null && type.getInterfaces().contains("javax.net.ssl.X509TrustManager"))
            trustManager = instruction;
        }
        if (trustManager == null || !(instruction instanceof InvokeInstruction invoke)) continue;
        MethodReference call = invoke.getMethod();
        String owner = call.getClassName();
        if (owner.equals("javax.net.ssl.SSLContext")
            || owner.equals("okhttp3.OkHttpClient$Builder"))
          calls.add(owner + "." + call.getName());
        if (!owner.equals("okhttp3.OkHttpClient$Builder")
            || !call.getName().equals("hostnameVerifier")) continue;
        if (!calls.equals(
            List.of(
                "javax.net.ssl.SSLContext.getInstance",
                "javax.net.ssl.SSLContext.init",
                "javax.net.ssl.SSLContext.getSocketFactory",
                "okhttp3.OkHttpClient$Builder.sslSocketFactory",
                "okhttp3.OkHttpClient$Builder.hostnameVerifier")))
          throw new IllegalStateException("Pinned SpyFakku TLS configuration changed");
        // The pinned source builds these objects only to attach its custom trust settings.
        // Both the URL interceptor before this block and the later hooks stay in the program.
        Instruction keep = instruction.getNext();
        for (Instruction current = trustManager; current != keep; ) {
          Instruction next = current.getNext();
          current.delete();
          current = next;
        }
        return;
      }
    }
    throw new IllegalStateException("Pinned SpyFakku TLS configuration is missing");
  }

  private static void usePlatformHttpNegotiation(ClassHolder cls) {
    MethodHolder configure = cls.getMethod(CONFIGURE_CLIENT);
    if (configure == null || configure.getProgram() == null)
      throw new IllegalStateException("Pinned client configuration is missing: " + cls.getName());
    for (BasicBlock block : configure.getProgram().getBasicBlocks()) {
      for (Instruction instruction : block) {
        if (!(instruction instanceof InvokeInstruction invoke)
            || !invoke.getMethod().equals(OKHTTP_PROTOCOLS)) continue;
        // The relay negotiates HTTP with the public origin. Keep the original client hooks.
        if (invoke.getReceiver() == null) {
          instruction.delete();
        } else {
          var assignment = new AssignInstruction();
          assignment.setReceiver(invoke.getReceiver());
          assignment.setAssignee(invoke.getInstance());
          instruction.replace(assignment);
        }
        return;
      }
    }
    throw new IllegalStateException("Pinned HTTP protocol setting is missing: " + cls.getName());
  }

  private static void requireOfficialReader(
      ClassHolder cls,
      ClassHolderTransformerContext context,
      MethodDescriptor descriptor,
      String message) {
    MethodHolder method = cls.getMethod(descriptor);
    if (method == null || method.getProgram() == null)
      throw new IllegalStateException(
          "Pinned reader verification method is missing: " + descriptor);
    ProgramEmitter emitter = ProgramEmitter.create(method, context.getHierarchy());
    emitter.construct(UnsupportedOperationException.class, emitter.constant(message)).raise();
  }

  private static String standardType(String name) {
    String prefix = "org.teavm.classlib.java.lang.T";
    return name.startsWith(prefix) ? "java.lang." + name.substring(prefix.length()) : name;
  }

  private static String regexType(String name) {
    String prefix = "org.teavm.classlib.java.util.regex.";
    if (name.startsWith(prefix + "Patched"))
      return "java.util.regex." + name.substring((prefix + "Patched").length());
    return name.startsWith(prefix + "T")
        ? "java.util.regex." + name.substring((prefix + "T").length())
        : name;
  }
}
