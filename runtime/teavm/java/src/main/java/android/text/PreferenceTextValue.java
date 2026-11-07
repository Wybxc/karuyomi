package android.text;

/** Read-only proposed text for Source preference validation; no Android spans or IME. */
public record PreferenceTextValue(String value) implements Editable {
  @Override
  public String toString() {
    return value;
  }

  @Override
  public int length() {
    return value.length();
  }

  @Override
  public char charAt(int index) {
    return value.charAt(index);
  }

  @Override
  public CharSequence subSequence(int start, int end) {
    return value.subSequence(start, end);
  }

  @Override
  public void getChars(int start, int end, char[] dest, int offset) {
    value.getChars(start, end, dest, offset);
  }

  private static UnsupportedOperationException unsupported() {
    return new UnsupportedOperationException("Android editable mutation and spans are unsupported");
  }

  @Override
  public Editable replace(int start, int end, CharSequence text, int textStart, int textEnd) {
    throw unsupported();
  }

  @Override
  public Editable replace(int start, int end, CharSequence text) {
    throw unsupported();
  }

  @Override
  public Editable insert(int where, CharSequence text, int start, int end) {
    throw unsupported();
  }

  @Override
  public Editable insert(int where, CharSequence text) {
    throw unsupported();
  }

  @Override
  public Editable delete(int start, int end) {
    throw unsupported();
  }

  @Override
  public Editable append(CharSequence text) {
    throw unsupported();
  }

  @Override
  public Editable append(CharSequence text, int start, int end) {
    throw unsupported();
  }

  @Override
  public Editable append(char c) {
    throw unsupported();
  }

  @Override
  public void clear() {
    throw unsupported();
  }

  @Override
  public void clearSpans() {
    throw unsupported();
  }

  @Override
  public void setFilters(InputFilter[] filters) {
    throw unsupported();
  }

  @Override
  public InputFilter[] getFilters() {
    throw unsupported();
  }

  @Override
  public void setSpan(Object span, int start, int end, int flags) {
    throw unsupported();
  }

  @Override
  public void removeSpan(Object span) {
    throw unsupported();
  }

  @Override
  public <T> T[] getSpans(int start, int end, Class<T> kind) {
    throw unsupported();
  }

  @Override
  public int getSpanStart(Object span) {
    throw unsupported();
  }

  @Override
  public int getSpanEnd(Object span) {
    throw unsupported();
  }

  @Override
  public int getSpanFlags(Object span) {
    throw unsupported();
  }

  @Override
  public int nextSpanTransition(int start, int limit, Class kind) {
    throw unsupported();
  }
}
