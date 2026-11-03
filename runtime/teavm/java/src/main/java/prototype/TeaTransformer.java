package prototype;
import org.teavm.model.*;import org.teavm.model.instructions.*;
/** Supply absent JCL entry points in TeaVM IR; never rewrites the extension input JAR. */
public class TeaTransformer implements ClassHolderTransformer{
 public void transformClass(ClassHolder cls,ClassHolderTransformerContext context){
 if(cls.getName().equals("java.io.File")){
  String sourceName="prototype.jcl.FileMethods";
  ClassHolder copy=org.teavm.model.util.ModelUtils.copyClass(context.getHierarchy().getClassSource().get(sourceName));
  copy=new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(),n->n.equals(sourceName)?cls.getName():n).rename(copy);
  MethodDescriptor descriptor=new MethodDescriptor("mkdirs",ValueType.BOOLEAN);
  cls.getMethod(descriptor).setProgram(org.teavm.model.util.ModelUtils.copyMethod(copy.getMethod(descriptor)).getProgram());
 }
 if(cls.getName().equals("java.io.RandomAccessFile")){
  String sourceName="prototype.jcl.RandomAccessFileMethods";
  ClassHolder copy=org.teavm.model.util.ModelUtils.copyClass(context.getHierarchy().getClassSource().get(sourceName));
  copy=new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(),n->n.equals(sourceName)?cls.getName():n).rename(copy);
  MethodDescriptor descriptor=new MethodDescriptor("close",ValueType.VOID);
  MethodHolder target=cls.getMethod(descriptor);
  if(target==null)throw new IllegalStateException("Unexpected TeaVM RandomAccessFile.close ABI");
  target.setProgram(org.teavm.model.util.ModelUtils.copyMethod(copy.getMethod(descriptor)).getProgram());
  for(MethodHolder method:cls.getMethods())if(method.getName().equals("<init>")&&method.parameterCount()==2&&method.parameterType(0).equals(ValueType.object("java.io.File"))){
   Program p=method.getProgram();
   for(int i=0;i<p.basicBlockCount();i++)for(Instruction instruction:p.basicBlockAt(i))if(instruction instanceof InvokeInstruction){
    InvokeInstruction invoke=(InvokeInstruction)instruction;
    if(invoke.getMethod().getClassName().equals("java.io.File")&&invoke.getMethod().getName().equals("findVirtualFile")){
     InvokeInstruction prepare=new InvokeInstruction();prepare.setType(InvocationType.SPECIAL);
     prepare.setArguments(invoke.getInstance(),p.variableAt(2));
     prepare.setMethod(new MethodReference("prototype.jcl.FileMethods","prepareRandomAccessFile",ValueType.object("java.io.File"),ValueType.object("java.lang.String"),ValueType.VOID));invoke.insertPrevious(prepare);
    }
   }
  }
 }
 if(cls.getName().equals("java.net.URL")){
  String sourceName="prototype.jcl.UrlMethods";
  ClassHolder copy=org.teavm.model.util.ModelUtils.copyClass(context.getHierarchy().getClassSource().get(sourceName));
  copy=new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(),n->n.equals(sourceName)?cls.getName():n).rename(copy);
  ValueType string=ValueType.object("java.lang.String");
  MethodDescriptor descriptor=new MethodDescriptor("set",string,string,ValueType.INTEGER,string,string,string,string,string,ValueType.VOID);
  MethodHolder target=cls.getMethod(descriptor);
  if(target==null)throw new IllegalStateException("Unexpected TeaVM URL.set ABI");
  target.setProgram(org.teavm.model.util.ModelUtils.copyMethod(copy.getMethod(descriptor)).getProgram());
 }
 if(cls.getName().equals("java.util.regex.Matcher")){
  String sourceName="org.teavm.classlib.java.util.regex.MatcherFindMethods";
  ClassHolder copy=org.teavm.model.util.ModelUtils.copyClass(context.getHierarchy().getClassSource().get(sourceName));
  copy=new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(),n->n.equals(sourceName)?cls.getName():regexType(n)).rename(copy);
  MethodDescriptor descriptor=new MethodDescriptor("findAt",ValueType.INTEGER,ValueType.INTEGER);
  cls.getMethod(descriptor).setProgram(org.teavm.model.util.ModelUtils.copyMethod(copy.getMethod(descriptor)).getProgram());
 }
 if(cls.getName().equals("java.lang.Object")){
  ClassReader source=context.getHierarchy().getClassSource().get("org.teavm.classlib.java.lang.WaitObjectMethods");
  ClassHolder copy=org.teavm.model.util.ModelUtils.copyClass(source);
  copy=new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(),n->n.equals("org.teavm.classlib.java.lang.WaitObjectMethods")?"java.lang.Object":standardType(n)).rename(copy);
  MethodHolder replacement=copy.getMethod(new MethodDescriptor("waitSupport",ValueType.LONG,ValueType.INTEGER,ValueType.object("org.teavm.interop.AsyncCallback"),ValueType.VOID));
  MethodHolder target=cls.getMethod(new MethodDescriptor("waitImpl",ValueType.LONG,ValueType.INTEGER,ValueType.object("org.teavm.interop.AsyncCallback"),ValueType.VOID));
  if(target==null)throw new IllegalStateException("Unexpected TeaVM Object.wait ABI");
  target.setProgram(org.teavm.model.util.ModelUtils.copyMethod(replacement).getProgram());
 }
 if(java.util.Set.of("java.util.regex.Pattern","java.util.regex.Lexer","java.util.regex.UnicodeCategory","java.util.regex.UnicodeCategoryScope","java.util.regex.UCISequenceSet","java.util.regex.EOLSet","java.util.regex.UEOLSet","java.util.regex.MultiLineEOLSet","java.util.regex.UMultiLineEOLSet","java.util.regex.SOLSet","java.util.regex.RelCompositeGroupQuantifierSet").contains(cls.getName())){
  String type=cls.getName().substring("java.util.regex.".length());
  ClassReader source=context.getHierarchy().getClassSource().get("org.teavm.classlib.java.util.regex.Patched"+type);
  ClassHolder copy=org.teavm.model.util.ModelUtils.copyClass(source);
  copy=new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(),TeaTransformer::regexType).rename(copy);
  cls.removeAllMethods();cls.removeAllFields();org.teavm.model.util.ModelUtils.copyClass(copy,cls);return;
 }
 if(java.util.Set.of("org.teavm.classlib.java.util.regex.LineBreakSet","org.teavm.classlib.java.util.regex.CasedLetterProperty","org.teavm.classlib.java.util.regex.SingleCharLookBehind").contains(cls.getName())){
  ClassHolder copy=org.teavm.model.util.ModelUtils.copyClass(cls);
  copy=new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(),TeaTransformer::regexType).rename(copy);
  cls.removeAllMethods();cls.removeAllFields();org.teavm.model.util.ModelUtils.copyClass(copy,cls);return;
 }
 if(cls.getName().startsWith("org.teavm.classlib.java.lang.WaitInterruptSupport")){
  ClassHolder copy=org.teavm.model.util.ModelUtils.copyClass(cls);
  copy=new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(),TeaTransformer::standardType).rename(copy);
  cls.removeAllMethods();cls.removeAllFields();org.teavm.model.util.ModelUtils.copyClass(copy,cls);return;
 }
 if(cls.getName().equals("java.lang.Object$NotifyListenerImpl")){
  ClassReader source=context.getHierarchy().getClassSource().get("prototype.jcl.WaitListenerMethods");
  ClassHolder copy=org.teavm.model.util.ModelUtils.copyClass(source);
  copy=new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(),n->n.equals("prototype.jcl.WaitListenerMethods")?cls.getName():standardType(n)).rename(copy);
  for(MethodHolder method:cls.getMethods())if(method.getName().startsWith("lambda$interrupted$"))method.setProgram(org.teavm.model.util.ModelUtils.copyMethod(copy.getMethod(new MethodDescriptor("resumeInterrupted",ValueType.VOID))).getProgram());
  MethodHolder interrupted=cls.getMethod(new MethodDescriptor("interrupted",ValueType.VOID));Program program=interrupted.getProgram();
  for(int i=0;i<program.basicBlockCount();i++)for(Instruction instruction:program.basicBlockAt(i))if(instruction instanceof PutFieldInstruction){PutFieldInstruction put=(PutFieldInstruction)instruction;if(put.getField().getFieldName().equals("performed")){PutFieldInstruction expire=new PutFieldInstruction();expire.setInstance(put.getInstance());expire.setValue(put.getValue());expire.setFieldType(ValueType.BOOLEAN);expire.setField(new FieldReference(cls.getName(),"expired"));put.insertNext(expire);}}
 }
 if(cls.getName().equals("java.util.Locale")){
  ClassReader source=context.getHierarchy().getClassSource().get("prototype.jcl.LocaleMethods");
  ClassHolder copy=org.teavm.model.util.ModelUtils.copyClass(source);
  copy=new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(),n->n.equals("prototype.jcl.LocaleMethods")?"java.util.Locale":n).rename(copy);
  for(MethodHolder method:new java.util.ArrayList<>(copy.getMethods()))if(!method.getName().equals("<init>")){
   MethodHolder old=cls.getMethod(method.getDescriptor());if(old!=null)cls.removeMethod(old);
   copy.removeMethod(method);cls.addMethod(method);
  }
 }
 if(cls.getName().equals("java.util.regex.ReluctantGroupQuantifierSet")){
  ClassReader source=context.getHierarchy().getClassSource().get("org.teavm.classlib.java.util.regex.PatchedReluctantGroupQuantifierSet");
  if(source==null)throw new IllegalStateException("Missing reluctant regex patch");
  ClassHolder copy=org.teavm.model.util.ModelUtils.copyClass(source);
  copy=new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(),n->n.equals("org.teavm.classlib.java.util.regex.PatchedReluctantGroupQuantifierSet")?"java.util.regex.ReluctantGroupQuantifierSet":n.startsWith("org.teavm.classlib.java.util.regex.T")?"java.util.regex."+n.substring("org.teavm.classlib.java.util.regex.T".length()):n).rename(copy);
  cls.removeAllMethods();cls.removeAllFields();org.teavm.model.util.ModelUtils.copyClass(copy,cls);return;
 }
 if(cls.getName().equals("java.util.regex.GroupQuantifierSet")){
  ClassReader source=context.getHierarchy().getClassSource().get("org.teavm.classlib.java.util.regex.PatchedGroupQuantifierSet");
  if(source==null)throw new IllegalStateException("Missing regex patch");
  ClassHolder copy=org.teavm.model.util.ModelUtils.copyClass(source);
  copy=new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(),n->n.equals("org.teavm.classlib.java.util.regex.PatchedGroupQuantifierSet")?"java.util.regex.GroupQuantifierSet":n.startsWith("org.teavm.classlib.java.util.regex.T")?"java.util.regex."+n.substring("org.teavm.classlib.java.util.regex.T".length()):n).rename(copy);
  cls.removeAllMethods();cls.removeAllFields();org.teavm.model.util.ModelUtils.copyClass(copy,cls);return;
 }
 if(cls.getName().equals("java.util.Base64")||cls.getName().startsWith("java.util.Base64$")){
  String replacement="prototype.jcl.Base64"+cls.getName().substring("java.util.Base64".length());
  ClassReader source=context.getHierarchy().getClassSource().get(replacement);
  if(source==null)throw new IllegalStateException("Missing Base64 patch "+replacement);
  ClassHolder copy=org.teavm.model.util.ModelUtils.copyClass(source);
  copy=new org.teavm.parsing.ClassRefsRenamer(new ReferenceCache(),n->n.startsWith("prototype.jcl.Base64")?"java.util.Base64"+n.substring("prototype.jcl.Base64".length()):n).rename(copy);
  cls.removeAllMethods();cls.removeAllFields();org.teavm.model.util.ModelUtils.copyClass(copy,cls);return;
 }
for(MethodHolder m:cls.getMethods()){Program p=m.getProgram();if(p==null)continue;for(int i=0;i<p.basicBlockCount();i++)for(Instruction ins:p.basicBlockAt(i))if(ins instanceof InvokeInstruction){InvokeInstruction invoke=(InvokeInstruction)ins;MethodReference ref=invoke.getMethod();
if(ref.getClassName().equals("org.teavm.runtime.reflect.ClassReflectionInfo")&&ref.getName().equals("innerClassCount")){InvokeInstruction prepare=new InvokeInstruction();prepare.setType(InvocationType.SPECIAL);prepare.setArguments(invoke.getInstance());prepare.setMethod(new MethodReference("prototype.ReflectionSupport","prepareInnerClasses",ValueType.object(ref.getClassName()),ValueType.VOID));invoke.insertPrevious(prepare);}
// Boolean is final. Use direct dispatch: TeaVM 0.16 can omit the virtual slot through generic Map callbacks.
if(ref.getClassName().equals("java.lang.Boolean")&&ref.getName().equals("booleanValue")&&invoke.getType()==InvocationType.VIRTUAL)invoke.setType(InvocationType.SPECIAL);
if(ref.getClassName().equals("java.util.Collections")&&(ref.getName().equals("unmodifiableSortedMap")||ref.getName().equals("unmodifiableSortedSet")))invoke.setMethod(new MethodReference("prototype.SortedViews",ref.getName(),ref.getSignature()));
if(ref.getClassName().equals("java.lang.Character")&&ref.getName().equals("toString")&&ref.parameterCount()==1&&ref.parameterType(0).equals(ValueType.INTEGER))invoke.setMethod(new MethodReference("prototype.PlatformSupport","characterToString",ref.getSignature()));
if(ref.getClassName().equals("okhttp3.OkHttpClient$Builder")&&ref.getName().endsWith("-LRDsOJo")){String name=ref.getName().substring(0,ref.getName().indexOf('-'));if(name.equals("connectTimeout")||name.equals("readTimeout")||name.equals("writeTimeout"))invoke.setMethod(new MethodReference(ref.getClassName(),name+"Duration",ref.getSignature()));}if(ref.getClassName().equals("java.util.Locale")&&ref.getName().equals("forLanguageTag"))invoke.setMethod(new MethodReference("prototype.PlatformSupport","localeForTag",ref.getSignature()));}}}
 private static String standardType(String name){String prefix="org.teavm.classlib.java.lang.T";return name.startsWith(prefix)?"java.lang."+name.substring(prefix.length()):name;}
 private static String regexType(String name){String prefix="org.teavm.classlib.java.util.regex.";if(name.startsWith(prefix+"Patched"))return "java.util.regex."+name.substring((prefix+"Patched").length());return name.startsWith(prefix+"T")?"java.util.regex."+name.substring((prefix+"T").length()):name;}
}
