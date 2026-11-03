package prototype.jcl;

import java.util.*;

/** Additional BCP-47 state missing from TeaVM 0.16's three-field Locale. */
public final class LocaleState {
  private static final Map<Locale, State> states = new IdentityHashMap<>();

  private static final class State {
    String script = "";
    final SortedMap<Character, String> extensions = new TreeMap<>();
  }

  private static State state(Locale locale) {
    Objects.requireNonNull(locale);
    State s = states.get(locale);
    if (s != null) return s;
    s = new State();
    if (locale.getLanguage().equals("ja")
        && locale.getCountry().equals("JP")
        && locale.getVariant().equals("JP")) s.extensions.put('u', "ca-japanese");
    if (locale.getLanguage().equals("th")
        && locale.getCountry().equals("TH")
        && locale.getVariant().equals("TH")) s.extensions.put('u', "nu-thai");
    return s;
  }

  // String.toLowerCase(Locale) itself asks for Locale.toLanguageTag in TeaVM.
  // BCP-47 syntax is ASCII; folding directly avoids that bootstrap recursion.
  private static String lower(String s) {
    StringBuilder b = new StringBuilder();
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      b.append(c >= 'A' && c <= 'Z' ? (char) (c + 32) : c);
    }
    return b.toString();
  }

  private static String upper(String s) {
    StringBuilder b = new StringBuilder();
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      b.append(c >= 'a' && c <= 'z' ? (char) (c - 32) : c);
    }
    return b.toString();
  }

  private static boolean alpha(String s) {
    if (s.isEmpty()) return false;
    for (int i = 0; i < s.length(); i++)
      if (!((s.charAt(i) >= 'a' && s.charAt(i) <= 'z')
          || (s.charAt(i) >= 'A' && s.charAt(i) <= 'Z'))) return false;
    return true;
  }

  private static boolean digit(String s) {
    if (s.isEmpty()) return false;
    for (int i = 0; i < s.length(); i++) if (s.charAt(i) < '0' || s.charAt(i) > '9') return false;
    return true;
  }

  private static boolean alnum(String s) {
    if (s.isEmpty()) return false;
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      if (!(c >= '0' && c <= '9' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z')) return false;
    }
    return true;
  }

  private static boolean variant(String s) {
    return alnum(s)
        && (s.length() >= 5 && s.length() <= 8
            || s.length() == 4 && s.charAt(0) >= '0' && s.charAt(0) <= '9');
  }

  private static String canonical(String tag) {
    switch (lower(tag)) {
      case "art-lojban":
        return "jbo";
      case "cel-gaulish":
        return "xtg-x-cel-gaulish";
      case "en-gb-oed":
        return "en-GB-x-oed";
      case "i-ami":
        return "ami";
      case "i-bnn":
        return "bnn";
      case "i-default":
        return "en-x-i-default";
      case "i-enochian":
        return "und-x-i-enochian";
      case "i-hak":
        return "hak";
      case "i-klingon":
        return "tlh";
      case "i-lux":
        return "lb";
      case "i-mingo":
        return "see-x-i-mingo";
      case "i-navajo":
        return "nv";
      case "i-pwn":
        return "pwn";
      case "i-tao":
        return "tao";
      case "i-tay":
        return "tay";
      case "i-tsu":
        return "tsu";
      case "no-bok":
        return "nb";
      case "no-nyn":
        return "nn";
      case "sgn-be-fr":
        return "sfb";
      case "sgn-be-nl":
        return "vgt";
      case "sgn-ch-de":
        return "sgg";
      case "zh-guoyu":
        return "cmn";
      case "zh-hakka":
        return "hak";
      case "zh-min":
        return "nan-x-zh-min";
      case "zh-min-nan":
        return "nan";
      case "zh-xiang":
        return "hsn";
      default:
        return tag;
    }
  }

  public static Locale forLanguageTag(String input) {
    Objects.requireNonNull(input);
    String[] p = canonical(input).split("-", -1);
    int i = 0;
    String language = "", country = "", variant = "";
    State s = new State();
    if (i < p.length && p[i].length() >= 2 && p[i].length() <= 8 && alpha(p[i])) {
      language = lower(p[i++]);
      if (language.length() <= 3) {
        int count = 0;
        while (i < p.length && p[i].length() == 3 && alpha(p[i]) && count < 3) {
          if (count++ == 0) language = lower(p[i]);
          i++;
        }
      }
    } else if (p.length == 0 || !p[0].equalsIgnoreCase("x")) return new Locale("");
    if (language.equals("und")) language = "";
    if (i < p.length && p[i].length() == 4 && alpha(p[i])) {
      String script = lower(p[i++]);
      s.script = upper(script.substring(0, 1)) + script.substring(1);
    }
    if (i < p.length && (p[i].length() == 2 && alpha(p[i]) || p[i].length() == 3 && digit(p[i])))
      country = upper(p[i++]);
    while (i < p.length && variant(p[i])) {
      if (!variant.isEmpty()) variant += "_";
      variant += p[i++];
    }
    while (i < p.length && p[i].length() == 1 && alnum(p[i])) {
      char key = Character.toLowerCase(p[i++].charAt(0));
      int start = i, min = key == 'x' ? 1 : 2;
      while (i < p.length && p[i].length() >= min && p[i].length() <= 8 && alnum(p[i])) i++;
      if (i == start) break;
      String value = String.join("-", Arrays.copyOfRange(p, start, i));
      if (key != 'x') value = lower(value);
      if (!s.extensions.containsKey(key)) s.extensions.put(key, value);
      if (key == 'x') break;
    }
    String x = s.extensions.get('x');
    if (x != null) {
      String[] privateParts = x.split("-");
      for (int j = 0; j < privateParts.length - 1; j++)
        if (privateParts[j].equalsIgnoreCase("lvariant")) {
          String extra =
              String.join("_", Arrays.copyOfRange(privateParts, j + 1, privateParts.length));
          variant = variant.isEmpty() ? extra : variant + "_" + extra;
          if (j == 0) s.extensions.remove('x');
          else
            s.extensions.put('x', lower(String.join("-", Arrays.copyOfRange(privateParts, 0, j))));
          break;
        }
    }
    if (language.equals("iw")) language = "he";
    if (language.equals("ji")) language = "yi";
    if (language.equals("in")) language = "id";
    if (s.extensions.containsKey('x')) s.extensions.put('x', lower(s.extensions.get('x')));
    Locale locale = new Locale(language, country, variant);
    State implicit = state(locale);
    for (Map.Entry<Character, String> e : implicit.extensions.entrySet())
      s.extensions.putIfAbsent(e.getKey(), e.getValue());
    states.put(locale, s);
    if (s.extensions.containsKey('u')) {
      List<String> pieces = new ArrayList<>(attributes(locale));
      for (Map.Entry<String, String> e : unicode(locale).entrySet()) {
        pieces.add(e.getKey());
        if (!e.getValue().isEmpty()) pieces.add(e.getValue());
      }
      s.extensions.put('u', String.join("-", pieces));
    }
    return locale;
  }

  public static String script(Locale locale) {
    return state(locale).script;
  }

  public static String extension(Locale locale, char key) {
    key = Character.toLowerCase(key);
    if (!alnum(String.valueOf(key))) throw new IllegalArgumentException("Invalid extension key");
    return state(locale).extensions.get(key);
  }

  public static Set<Character> extensionKeys(Locale locale) {
    return Collections.unmodifiableSet(new TreeSet<>(state(locale).extensions.keySet()));
  }

  private static SortedMap<String, String> unicode(Locale locale) {
    SortedMap<String, String> result = new TreeMap<>();
    String value = extension(locale, 'u');
    if (value == null) return result;
    String[] parts = value.split("-");
    int i = 0;
    while (i < parts.length && parts[i].length() >= 3) i++;
    while (i < parts.length) {
      String key = parts[i++];
      int start = i;
      while (i < parts.length && parts[i].length() >= 3) i++;
      if (!result.containsKey(key))
        result.put(key, String.join("-", Arrays.copyOfRange(parts, start, i)));
    }
    return result;
  }

  public static Set<String> attributes(Locale locale) {
    SortedSet<String> result = new TreeSet<>();
    String value = extension(locale, 'u');
    if (value != null)
      for (String part : value.split("-")) {
        if (part.length() < 3) break;
        result.add(part);
      }
    return Collections.unmodifiableSet(result);
  }

  public static Set<String> unicodeKeys(Locale locale) {
    return Collections.unmodifiableSet(unicode(locale).keySet());
  }

  public static String unicodeType(Locale locale, String key) {
    Objects.requireNonNull(key);
    if (key.length() != 2 || !alnum(key))
      throw new IllegalArgumentException("Invalid Unicode locale key");
    return unicode(locale).get(lower(key));
  }

  public static String tag(Locale locale) {
    State s = state(locale);
    String language = lower(locale.getLanguage());
    if (language.equals("iw")) language = "he";
    if (language.equals("ji")) language = "yi";
    if (language.equals("in")) language = "id";
    if (!alpha(language) || language.length() < 2 || language.length() > 8) language = "und";
    String country = upper(locale.getCountry());
    String variant = locale.getVariant();
    if (language.equals("no") && country.equals("NO") && variant.equals("NY")) {
      language = "nn";
      variant = "";
    }
    StringBuilder b = new StringBuilder(language);
    if (!s.script.isEmpty()) b.append('-').append(s.script);
    if (country.length() == 2 && alpha(country) || country.length() == 3 && digit(country))
      b.append('-').append(country);
    String privateVariant = "";
    String[] variants = variant.split("_");
    for (int i = 0; i < variants.length; i++) {
      String v = variants[i];
      if (variant(v) && privateVariant.isEmpty()) b.append('-').append(v);
      else {
        for (int j = i; j < variants.length; j++) {
          v = variants[j];
          if (v.length() < 1 || v.length() > 8 || !alnum(v)) break;
          privateVariant += (privateVariant.isEmpty() ? "" : "-") + v;
        }
        break;
      }
    }
    for (Map.Entry<Character, String> e : s.extensions.entrySet())
      if (e.getKey() != 'x') b.append('-').append(e.getKey()).append('-').append(e.getValue());
    String x = s.extensions.get('x');
    if (x != null || !privateVariant.isEmpty()) {
      if (language.equals("und") && b.length() == 3) b.setLength(0);
      else b.append('-');
      b.append("x-");
      if (x != null) b.append(x);
      if (!privateVariant.isEmpty()) {
        if (x != null) b.append('-');
        b.append("lvariant-").append(privateVariant);
      }
    }
    return b.toString();
  }

  public static boolean equal(Locale a, Object other) {
    if (a == other) return true;
    if (!(other instanceof Locale)) return false;
    Locale b = (Locale) other;
    State x = state(a), y = state(b);
    return a.getLanguage().equals(b.getLanguage())
        && a.getCountry().equals(b.getCountry())
        && a.getVariant().equals(b.getVariant())
        && x.script.equals(y.script)
        && x.extensions.equals(y.extensions);
  }

  public static int hash(Locale locale) {
    State s = state(locale);
    int base =
        ((locale.getLanguage().hashCode() * 31 + s.script.hashCode()) * 31
                    + locale.getCountry().hashCode())
                * 31
            + locale.getVariant().hashCode();
    return base ^ s.extensions.hashCode();
  }

  public static Object copy(Locale locale) {
    Locale result = new Locale(locale.getLanguage(), locale.getCountry(), locale.getVariant());
    State old = state(locale), s = new State();
    s.script = old.script;
    s.extensions.putAll(old.extensions);
    states.put(result, s);
    return result;
  }
}
