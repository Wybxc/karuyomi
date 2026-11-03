package android.icu.text;

public class Collator {
  public static final int PRIMARY = 0;
  public static final int NO_DECOMPOSITION = 16;
  final com.ibm.icu.text.Collator delegate;
  Collator(com.ibm.icu.text.Collator delegate) { this.delegate = delegate; }
  public static Collator getInstance() { return new RuleBasedCollator((com.ibm.icu.text.RuleBasedCollator)com.ibm.icu.text.Collator.getInstance()); }
  public void setStrength(int value) { delegate.setStrength(value); }
  public int getStrength() { return delegate.getStrength(); }
  public void setDecomposition(int value) { delegate.setDecomposition(value); }
  public int getDecomposition() { return delegate.getDecomposition(); }
}
