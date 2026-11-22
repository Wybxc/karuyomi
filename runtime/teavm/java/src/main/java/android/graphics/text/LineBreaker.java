package android.graphics.text;

/** Paragraph strategies shared by Android text layout APIs. */
public final class LineBreaker {
  public static final int BREAK_STRATEGY_SIMPLE = 0;
  public static final int BREAK_STRATEGY_HIGH_QUALITY = 1;
  public static final int BREAK_STRATEGY_BALANCED = 2;

  private LineBreaker() {}
}
