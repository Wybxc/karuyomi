package java.net;

public class IDN {
  public static final int USE_STD3_ASCII_RULES = 2;

  @org.teavm.jso.JSBody(params = "s", script = "return new URL('https://'+s).hostname;")
  public static native String toASCII(String s);

  public static String toASCII(String s, int f) {
    return toASCII(s);
  }

  public static String toUnicode(String s) {
    return s;
  }
}
