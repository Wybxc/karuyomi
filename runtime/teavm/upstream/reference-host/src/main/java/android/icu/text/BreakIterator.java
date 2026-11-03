package android.icu.text;
import java.text.CharacterIterator;

public final class BreakIterator {
  public static final int DONE = -1;
  public static final int WORD_NONE = 0;
  private final com.ibm.icu.text.BreakIterator delegate;
  private BreakIterator(com.ibm.icu.text.BreakIterator delegate) { this.delegate = delegate; }
  public static BreakIterator getCharacterInstance() { return new BreakIterator(com.ibm.icu.text.BreakIterator.getCharacterInstance()); }
  public static BreakIterator getWordInstance() { return new BreakIterator(com.ibm.icu.text.BreakIterator.getWordInstance()); }
  public void setText(CharacterIterator text) { delegate.setText(text); }
  public CharacterIterator getText() { return delegate.getText(); }
  public int first() { return delegate.first(); }
  public int next() { return delegate.next(); }
  public int getRuleStatus() { return delegate.getRuleStatus(); }
}
