package android.text;

import java.lang.reflect.Array;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;

/** Immutable text with mutable spans for Source-authored Android presentation. */
public final class SpannableString implements Spannable, GetChars {
  private final String text;
  private final List<Span> spans = new ArrayList<>();

  public SpannableString(CharSequence source) {
    this(source, 0, source.length());
  }

  private SpannableString(CharSequence source, int start, int end) {
    text = source.toString().substring(start, end);
    if (source instanceof Spanned original) {
      for (Object span : original.getSpans(start, end, Object.class)) {
        setSpan(
            span,
            Math.max(original.getSpanStart(span), start) - start,
            Math.min(original.getSpanEnd(span), end) - start,
            original.getSpanFlags(span));
      }
    }
  }

  public static SpannableString valueOf(CharSequence source) {
    return source instanceof SpannableString existing ? existing : new SpannableString(source);
  }

  @Override
  public int length() {
    return text.length();
  }

  @Override
  public char charAt(int index) {
    return text.charAt(index);
  }

  @Override
  public CharSequence subSequence(int start, int end) {
    return new SpannableString(this, start, end);
  }

  @Override
  public String toString() {
    return text;
  }

  @Override
  public void getChars(int start, int end, char[] destination, int offset) {
    text.getChars(start, end, destination, offset);
  }

  @Override
  public void setSpan(Object value, int start, int end, int flags) {
    Objects.requireNonNull(value);
    Objects.checkFromToIndex(start, end, length());
    removeSpan(value);
    spans.add(new Span(value, start, end, flags));
  }

  @Override
  public void removeSpan(Object value) {
    spans.removeIf(span -> span.value == value);
  }

  @Override
  @SuppressWarnings("unchecked") // The array and every member use the caller's class.
  public <T> T[] getSpans(int start, int end, Class<T> kind) {
    Objects.checkFromToIndex(start, end, length());
    List<T> matches = new ArrayList<>();
    for (Span span : spans) {
      if (span.start > end || span.end < start) continue;
      if (span.start != span.end && start != end && (span.start == end || span.end == start))
        continue;
      if (kind.isInstance(span.value)) matches.add(kind.cast(span.value));
    }
    return matches.toArray((T[]) Array.newInstance(kind, matches.size()));
  }

  @Override
  public int getSpanStart(Object value) {
    Span span = find(value);
    return span == null ? -1 : span.start;
  }

  @Override
  public int getSpanEnd(Object value) {
    Span span = find(value);
    return span == null ? -1 : span.end;
  }

  @Override
  public int getSpanFlags(Object value) {
    Span span = find(value);
    return span == null ? 0 : span.flags;
  }

  @Override
  public int nextSpanTransition(int start, int limit, Class kind) {
    for (Span span : spans) {
      if (kind != null && !kind.isInstance(span.value)) continue;
      if (span.start > start && span.start < limit) limit = span.start;
      if (span.end > start && span.end < limit) limit = span.end;
    }
    return limit;
  }

  private Span find(Object value) {
    for (Span span : spans) if (span.value == value) return span;
    return null;
  }

  private record Span(Object value, int start, int end, int flags) {}
}
