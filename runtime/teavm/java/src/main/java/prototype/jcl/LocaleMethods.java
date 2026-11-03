package prototype.jcl;

import java.util.*;

/** These methods are copied into TeaVM's Locale class by the IR transformer. */
public class LocaleMethods {
  private Locale self() {
    return (Locale) (Object) this;
  }

  public String getScript() {
    return LocaleState.script(self());
  }

  public String getExtension(char key) {
    return LocaleState.extension(self(), key);
  }

  public Set<Character> getExtensionKeys() {
    return LocaleState.extensionKeys(self());
  }

  public boolean hasExtensions() {
    return !getExtensionKeys().isEmpty();
  }

  public Set<String> getUnicodeLocaleAttributes() {
    return LocaleState.attributes(self());
  }

  public Set<String> getUnicodeLocaleKeys() {
    return LocaleState.unicodeKeys(self());
  }

  public String getUnicodeLocaleType(String key) {
    return LocaleState.unicodeType(self(), key);
  }

  public String toLanguageTag() {
    return LocaleState.tag(self());
  }

  public boolean equals(Object other) {
    return LocaleState.equal(self(), other);
  }

  public int hashCode() {
    return LocaleState.hash(self());
  }

  public Object clone() {
    return LocaleState.copy(self());
  }
}
