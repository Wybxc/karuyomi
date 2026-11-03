package org.teavm.classlib.java.util.regex;

/** Java \\R: CRLF first, with the single-CR fallback required by backtracking. */
public final class LineBreakSet extends TAbstractSet {
  public int matches(int index, CharSequence text, TMatchResultImpl result) {
    int right = result.getRightBound();
    if (index >= right) {
      result.hitEnd = true;
      return -1;
    }
    char ch = text.charAt(index);
    if (ch == '\r') {
      if (index + 1 < right && text.charAt(index + 1) == '\n') {
        int match = next.matches(index + 2, text, result);
        if (match >= 0) return match;
      } else if (index + 1 >= right) result.hitEnd = true;
      return next.matches(index + 1, text, result);
    }
    if (ch == '\n'
        || ch == '\u000b'
        || ch == '\f'
        || ch == '\u0085'
        || ch == '\u2028'
        || ch == '\u2029') return next.matches(index + 1, text, result);
    return -1;
  }

  public boolean hasConsumed(TMatchResultImpl result) {
    return true;
  }

  protected String getName() {
    return "LineBreak";
  }
}
