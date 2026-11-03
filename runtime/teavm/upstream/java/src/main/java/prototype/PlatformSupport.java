package prototype;public class PlatformSupport{
 public static java.util.Locale localeForTag(String tag){return prototype.jcl.LocaleState.forLanguageTag(tag);}
 public static Class<?> loadClass(ClassLoader loader,String name)throws ClassNotFoundException{java.util.Objects.requireNonNull(loader);return Class.forName(name,false,loader);}
 public static void dumpStack(){new Exception("Stack trace").printStackTrace();}
 public static String characterToString(int codePoint){return new String(Character.toChars(codePoint));}
 /** ICU's private helper only reads immutable resource files; a read-only snapshot suffices. */
 public static java.nio.ByteBuffer mapIcuFile(java.io.File file){try(java.io.FileInputStream input=new java.io.FileInputStream(file)){return java.nio.ByteBuffer.wrap(input.readAllBytes()).asReadOnlyBuffer();}catch(java.io.IOException error){System.err.println(error);return null;}}
 public static boolean charsetSupported(String s){try{java.nio.charset.Charset.forName(s);return true;}catch(Exception e){return false;}}
 public static void contextLoader(Thread t,ClassLoader l){}
 public static java.util.Enumeration<java.net.URL> resources(ClassLoader l,String s){return java.util.Collections.emptyEnumeration();}
}
