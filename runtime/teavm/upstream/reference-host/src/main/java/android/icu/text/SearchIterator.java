package android.icu.text;
import java.text.CharacterIterator;

public abstract class SearchIterator {
  public static final int DONE = -1;
  final com.ibm.icu.text.SearchIterator delegate;
  SearchIterator(com.ibm.icu.text.SearchIterator delegate) { this.delegate = delegate; }
  public void setOverlapping(boolean value) { delegate.setOverlapping(value); }
  public boolean isOverlapping() { return delegate.isOverlapping(); }
  public void setTarget(CharacterIterator value) { delegate.setTarget(value); }
  public CharacterIterator getTarget() { return delegate.getTarget(); }
  public String getMatchedText() { return delegate.getMatchedText(); }
  public int first() { return delegate.first(); }
  public int next() { return delegate.next(); }
}
