package android.text;

public class Html {
  public static Spanned fromHtml(String s) {
    return fromHtml(s, 0);
  }

  public static Spanned fromHtml(String s, int flags) {
    String text = org.jsoup.Jsoup.parse(s).text();
    return new Spanned() {
      public int length() {
        return text.length();
      }

      public char charAt(int i) {
        return text.charAt(i);
      }

      public CharSequence subSequence(int a, int b) {
        return text.subSequence(a, b);
      }

      public String toString() {
        return text;
      }

      public <T> T[] getSpans(int a, int b, Class<T> c) {
        throw new UnsupportedOperationException();
      }

      public int getSpanStart(Object o) {
        return -1;
      }

      public int getSpanEnd(Object o) {
        return -1;
      }

      public int getSpanFlags(Object o) {
        return 0;
      }

      public int nextSpanTransition(int a, int b, Class c) {
        return b;
      }
    };
  }
}
