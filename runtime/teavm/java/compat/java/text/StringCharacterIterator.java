package java.text;

/** UTF-16 cursor with the same half-open range and DONE handling as the JDK. */
public final class StringCharacterIterator implements CharacterIterator {
  private String text;
  private int begin, end, pos;

  public StringCharacterIterator(String text) {
    this(text, 0);
  }

  public StringCharacterIterator(String text, int pos) {
    this(text, 0, text.length(), pos);
  }

  public StringCharacterIterator(String text, int begin, int end, int pos) {
    if (begin < 0 || begin > end || end > text.length() || pos < begin || pos > end)
      throw new IllegalArgumentException("Invalid iterator range");
    this.text = text;
    this.begin = begin;
    this.end = end;
    this.pos = pos;
  }

  public void setText(String value) {
    text = java.util.Objects.requireNonNull(value);
    begin = pos = 0;
    end = text.length();
  }

  public char first() {
    pos = begin;
    return current();
  }

  public char last() {
    pos = end == begin ? end : end - 1;
    return current();
  }

  public char current() {
    return pos >= begin && pos < end ? text.charAt(pos) : DONE;
  }

  public char next() {
    if (pos < end - 1) {
      pos++;
      return text.charAt(pos);
    }
    pos = end;
    return DONE;
  }

  public char previous() {
    if (pos > begin) {
      pos--;
      return text.charAt(pos);
    }
    return DONE;
  }

  public char setIndex(int position) {
    if (position < begin || position > end) throw new IllegalArgumentException("Invalid position");
    pos = position;
    return current();
  }

  public int getBeginIndex() {
    return begin;
  }

  public int getEndIndex() {
    return end;
  }

  public int getIndex() {
    return pos;
  }

  public Object clone() {
    return new StringCharacterIterator(text, begin, end, pos);
  }

  public boolean equals(Object other) {
    if (other == this) return true;
    if (!(other instanceof StringCharacterIterator)) return false;
    StringCharacterIterator that = (StringCharacterIterator) other;
    return begin == that.begin && end == that.end && pos == that.pos && text.equals(that.text);
  }

  public int hashCode() {
    return text.hashCode() ^ pos ^ begin ^ end;
  }
}
