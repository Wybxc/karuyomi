package android.icu.text;

public final class RuleBasedCollator extends Collator {
  RuleBasedCollator(com.ibm.icu.text.RuleBasedCollator delegate) { super(delegate); }
  public void setCaseLevel(boolean value) { ((com.ibm.icu.text.RuleBasedCollator)delegate).setCaseLevel(value); }
  public boolean isCaseLevel() { return ((com.ibm.icu.text.RuleBasedCollator)delegate).isCaseLevel(); }
}
