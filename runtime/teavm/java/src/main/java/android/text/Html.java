package android.text;

import org.jsoup.Jsoup;
import org.jsoup.nodes.Element;
import org.jsoup.nodes.Node;
import org.jsoup.nodes.TextNode;
import org.jsoup.select.NodeTraversor;
import org.jsoup.select.NodeVisitor;

/** Bounded plain-string projection used by TextInterceptor; styled spans are unsupported. */
public class Html {
  public static final int FROM_HTML_MODE_LEGACY = 0;
  public static final int FROM_HTML_SEPARATOR_LINE_BREAK_PARAGRAPH = 1;
  public static final int FROM_HTML_SEPARATOR_LINE_BREAK_HEADING = 2;
  public static final int FROM_HTML_SEPARATOR_LINE_BREAK_LIST_ITEM = 4;
  public static final int FROM_HTML_SEPARATOR_LINE_BREAK_LIST = 8;
  public static final int FROM_HTML_SEPARATOR_LINE_BREAK_DIV = 16;
  public static final int FROM_HTML_SEPARATOR_LINE_BREAK_BLOCKQUOTE = 32;
  public static final int FROM_HTML_MODE_COMPACT = 63;
  public static final int FROM_HTML_OPTION_USE_CSS_COLORS = 256;

  public static Spanned fromHtml(String source) {
    return fromHtml(source, FROM_HTML_MODE_LEGACY);
  }

  public static Spanned fromHtml(String source, int flags) {
    java.util.Objects.requireNonNull(source);
    if (source.length() > 32768)
      throw new IllegalArgumentException("HTML exceeds 32768 UTF-16 units");
    StringBuilder output = new StringBuilder();
    NodeTraversor.traverse(
        new NodeVisitor() {
          private void bounded() {
            if (output.length() > 8192)
              throw new IllegalArgumentException("HTML text exceeds 8192 UTF-16 units");
          }

          private int margin(Node node) {
            if (!(node instanceof Element)) return 0;
            int flag =
                switch (node.normalName()) {
                  case "p" -> FROM_HTML_SEPARATOR_LINE_BREAK_PARAGRAPH;
                  case "h1", "h2", "h3", "h4", "h5", "h6" -> FROM_HTML_SEPARATOR_LINE_BREAK_HEADING;
                  case "li" -> FROM_HTML_SEPARATOR_LINE_BREAK_LIST_ITEM;
                  case "ul" -> FROM_HTML_SEPARATOR_LINE_BREAK_LIST;
                  case "div" -> FROM_HTML_SEPARATOR_LINE_BREAK_DIV;
                  case "blockquote" -> FROM_HTML_SEPARATOR_LINE_BREAK_BLOCKQUOTE;
                  default -> 0;
                };
            return flag == 0 ? 0 : (flags & flag) != 0 ? 1 : 2;
          }

          private void separate(int count) {
            if (count == 0 || output.length() == 0) return;
            int existing = 0;
            for (int i = output.length() - 1; i >= 0 && output.charAt(i) == '\n'; i--) existing++;
            while (existing++ < count) output.append('\n');
            bounded();
          }

          public void head(Node node, int depth) {
            if (depth > 64) throw new IllegalArgumentException("HTML exceeds 64 nested elements");
            separate(margin(node));
            if (node instanceof TextNode text) {
              // Jsoup handles HTML parsing/entities. Android's
              // string projection folds ASCII spaces/newlines while retaining tabs.
              String value = text.getWholeText();
              for (int i = 0; i < value.length(); i++) {
                char c = value.charAt(i);
                char previous = output.length() == 0 ? '\n' : output.charAt(output.length() - 1);
                if (c == ' ' || c == '\n') {
                  if (previous != ' ' && previous != '\n') output.append(' ');
                } else output.append(c);
                bounded();
              }
            } else if (node.normalName().equals("br")) output.append('\n');
            else if (node.normalName().equals("img")) output.append('\uFFFC');
            bounded();
          }

          public void tail(Node node, int depth) {
            separate(margin(node));
          }
        },
        Jsoup.parseBodyFragment(source.replace("\r\n", "\n").replace('\r', '\n')).body());
    String text = output.toString();
    return new Spanned() {
      public int length() {
        return text.length();
      }

      public char charAt(int index) {
        return text.charAt(index);
      }

      public CharSequence subSequence(int start, int end) {
        return text.subSequence(start, end);
      }

      public String toString() {
        return text;
      }

      public <T> T[] getSpans(int start, int end, Class<T> type) {
        throw new UnsupportedOperationException("HTML spans are unsupported");
      }

      public int getSpanStart(Object span) {
        return -1;
      }

      public int getSpanEnd(Object span) {
        return -1;
      }

      public int getSpanFlags(Object span) {
        return 0;
      }

      public int nextSpanTransition(int start, int limit, Class type) {
        return limit;
      }
    };
  }
}
