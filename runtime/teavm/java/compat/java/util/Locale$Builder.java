package java.util;

/** Locale.Builder binary ABI absent from TeaVM 0.16; BCP-47 state is owned by LocaleState. */
public final class Locale$Builder {
  private String language = "", script = "", region = "", variant = "";
  private final SortedMap<Character, String> extensions = new TreeMap<>();

  public Locale$Builder() {}

  public Locale$Builder setLanguage(String value) {
    Objects.requireNonNull(value);
    if (!value.isEmpty() && (value.length() < 2 || value.length() > 8 || !alpha(value)))
      invalid(value);
    language = value;
    return this;
  }

  public Locale$Builder setScript(String value) {
    Objects.requireNonNull(value);
    if (!value.isEmpty() && (value.length() != 4 || !alpha(value))) invalid(value);
    script = value;
    return this;
  }

  public Locale$Builder setRegion(String value) {
    Objects.requireNonNull(value);
    if (!value.isEmpty()
        && !(value.length() == 2 && alpha(value) || value.length() == 3 && digits(value)))
      invalid(value);
    region = value;
    return this;
  }

  public Locale$Builder setVariant(String value) {
    Objects.requireNonNull(value);
    for (String part : value.isEmpty() ? new String[0] : value.replace('_', '-').split("-", -1)) {
      if (!(alnum(part)
          && (part.length() >= 5 && part.length() <= 8
              || part.length() == 4 && Character.isDigit(part.charAt(0))))) invalid(value);
    }
    variant = value.replace('_', '-');
    return this;
  }

  public Locale$Builder setLocale(Locale locale) {
    clear();
    setLanguage(locale.getLanguage());
    setScript(locale.getScript());
    setRegion(locale.getCountry());
    setVariant(locale.getVariant());
    for (Character key : locale.getExtensionKeys()) extensions.put(key, locale.getExtension(key));
    return this;
  }

  public Locale$Builder setLanguageTag(String tag) {
    throw new UnsupportedOperationException(
        "Locale.Builder.setLanguageTag requires a strict BCP-47 parser");
  }

  public Locale$Builder setExtension(char key, String value) {
    if (!Character.isLetterOrDigit(key)) invalid(String.valueOf(key));
    key = Character.toLowerCase(key);
    Objects.requireNonNull(value);
    if (value.isEmpty()) extensions.remove(key);
    else {
      value = value.replace('_', '-');
      for (String part : value.split("-", -1))
        if (!alnum(part) || part.length() > 8 || part.length() < (key == 'x' ? 1 : 2))
          invalid(value);
      extensions.put(key, value);
    }
    return this;
  }

  public Locale$Builder clearExtensions() {
    extensions.clear();
    return this;
  }

  public Locale$Builder clear() {
    language = script = region = variant = "";
    return clearExtensions();
  }

  public Locale build() {
    StringBuilder tag = new StringBuilder(language.isEmpty() ? "und" : language);
    if (!script.isEmpty()) tag.append('-').append(script);
    if (!region.isEmpty()) tag.append('-').append(region);
    if (!variant.isEmpty()) tag.append('-').append(variant);
    for (Map.Entry<Character, String> item : extensions.entrySet())
      if (item.getKey() != 'x')
        tag.append('-').append(item.getKey()).append('-').append(item.getValue());
    if (extensions.containsKey('x')) tag.append("-x-").append(extensions.get('x'));
    return Locale.forLanguageTag(tag.toString());
  }

  private static boolean alpha(String value) {
    for (int i = 0; i < value.length(); i++) {
      char c = value.charAt(i);
      if (!(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z')) return false;
    }
    return !value.isEmpty();
  }

  private static boolean digits(String value) {
    for (int i = 0; i < value.length(); i++)
      if (value.charAt(i) < '0' || value.charAt(i) > '9') return false;
    return !value.isEmpty();
  }

  private static boolean alnum(String value) {
    for (int i = 0; i < value.length(); i++) {
      char c = value.charAt(i);
      if (!(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9')) return false;
    }
    return !value.isEmpty();
  }

  private static void invalid(String value) {
    throw new IllformedLocaleException("Ill-formed locale field: " + value);
  }
}
