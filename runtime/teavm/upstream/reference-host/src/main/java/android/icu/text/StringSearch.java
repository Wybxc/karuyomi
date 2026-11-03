package android.icu.text;
import java.text.CharacterIterator;

public final class StringSearch extends SearchIterator {
  public StringSearch(String pattern, CharacterIterator target, RuleBasedCollator collator) {
    super(new com.ibm.icu.text.StringSearch(pattern, target, (com.ibm.icu.text.RuleBasedCollator)collator.delegate));
  }
  public void setPattern(String value) { ((com.ibm.icu.text.StringSearch)delegate).setPattern(value); }
  public String getPattern() { return ((com.ibm.icu.text.StringSearch)delegate).getPattern(); }
}
