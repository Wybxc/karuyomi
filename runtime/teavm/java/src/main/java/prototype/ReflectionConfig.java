package prototype;
import org.teavm.extension.spi.reflection.SimpleReflectionPolicy;
public class ReflectionConfig extends SimpleReflectionPolicy{
 protected void setup(){selectClass("eu.kanade.tachiyomi.source.online.HttpSource").reflectableFields(named("headers$delegate"));
  allClasses().reflectableMethods(withAnnotation("android.webkit.JavascriptInterface"));
  // ICU discovers these original implementations by name and invokes their constructors.
  for(String name:new String[]{"com.ibm.icu.text.CollatorServiceShim","com.ibm.icu.text.BreakIteratorFactory"})selectClass(name).foundByName().reflectableMethods(named("<init>"));
  proxyGroup("android.content.SharedPreferences");proxyGroup("android.content.SharedPreferences$Editor");}
}
