package java.text;

public class Normalizer {
  public enum Form {
    NFC,
    NFD,
    NFKC,
    NFKD
  }

  @org.teavm.jso.JSBody(
      params = {"s", "f"},
      script = "return s.normalize(f);")
  private static native String norm(String s, String f);

  public static String normalize(CharSequence s, Form f) {
    return norm(s.toString(), f.name());
  }

  public static boolean isNormalized(CharSequence s, Form f) {
    return normalize(s, f).equals(s.toString());
  }
}
