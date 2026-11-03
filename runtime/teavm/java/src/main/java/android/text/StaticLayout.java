package android.text;

/** Legacy Android constructor used by unchanged TextInterceptor libraries. */
public class StaticLayout extends Layout {
  public StaticLayout(
      CharSequence source,
      TextPaint paint,
      int width,
      Alignment alignment,
      float spacingMult,
      float spacingAdd,
      boolean includePad) {
    super(source, paint, width, alignment, spacingMult, spacingAdd);
    generate(includePad);
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
    super(source, paint, width, alignment, spacingMult, spacingAdd);
    generate(start, end, includePad);
  }
}
