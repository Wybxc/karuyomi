package android.text;

import java.util.Objects;

/** Plain-text layout for display on bitmaps. */
public class StaticLayout extends Layout {
  public StaticLayout(
      CharSequence source,
      TextPaint paint,
      int width,
      Alignment alignment,
      float spacingMult,
      float spacingAdd,
      boolean includePad) {
    this(source, 0, source.length(), paint, width, alignment, spacingMult, spacingAdd, includePad);
  }

  public StaticLayout(
      CharSequence source,
      int start,
      int end,
      TextPaint paint,
      int width,
      Alignment alignment,
      float spacingMult,
      float spacingAdd,
      boolean includePad) {
    this(
        source,
        start,
        end,
        paint,
        width,
        alignment,
        spacingMult,
        spacingAdd,
        includePad,
        BREAK_STRATEGY_SIMPLE,
        HYPHENATION_FREQUENCY_NONE);
  }

  private StaticLayout(
      CharSequence source,
      int start,
      int end,
      TextPaint paint,
      int width,
      Alignment alignment,
      float spacingMult,
      float spacingAdd,
      boolean includePad,
      int breakStrategy,
      int hyphenationFrequency) {
    super(source, paint, width, alignment, spacingMult, spacingAdd);
    generate(start, end, includePad, breakStrategy, hyphenationFrequency);
  }

  public static final class Builder {
    private final CharSequence text;
    private final int start, end, width;
    private final TextPaint paint;
    private Alignment alignment = Alignment.ALIGN_NORMAL;
    private float spacingMult = DEFAULT_LINESPACING_MULTIPLIER;
    private float spacingAdd = DEFAULT_LINESPACING_ADDITION;
    private boolean includePad = true;
    private int breakStrategy = BREAK_STRATEGY_SIMPLE;
    private int hyphenationFrequency = HYPHENATION_FREQUENCY_NONE;

    private Builder(CharSequence source, int start, int end, TextPaint paint, int width) {
      Objects.checkFromToIndex(start, end, source.length());
      this.text = source;
      this.start = start;
      this.end = end;
      this.paint = Objects.requireNonNull(paint);
      this.width = width;
    }

    public static Builder obtain(
        CharSequence source, int start, int end, TextPaint paint, int width) {
      return new Builder(source, start, end, paint, width);
    }

    public Builder setAlignment(Alignment alignment) {
      this.alignment = Objects.requireNonNull(alignment);
      return this;
    }

    public Builder setIncludePad(boolean includePad) {
      this.includePad = includePad;
      return this;
    }

    public Builder setLineSpacing(float spacingAdd, float spacingMult) {
      this.spacingAdd = spacingAdd;
      this.spacingMult = spacingMult;
      return this;
    }

    public Builder setBreakStrategy(int strategy) {
      if (strategy < BREAK_STRATEGY_SIMPLE || strategy > BREAK_STRATEGY_BALANCED)
        throw new IllegalArgumentException("Invalid break strategy");
      breakStrategy = strategy;
      return this;
    }

    public Builder setHyphenationFrequency(int frequency) {
      if (frequency < HYPHENATION_FREQUENCY_NONE || frequency > HYPHENATION_FREQUENCY_FULL)
        throw new IllegalArgumentException("Invalid hyphenation frequency");
      hyphenationFrequency = frequency;
      return this;
    }

    public StaticLayout build() {
      return new StaticLayout(
          text,
          start,
          end,
          paint,
          width,
          alignment,
          spacingMult,
          spacingAdd,
          includePad,
          breakStrategy,
          hyphenationFrequency);
    }
  }
}
