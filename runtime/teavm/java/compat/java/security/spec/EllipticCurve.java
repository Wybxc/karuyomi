package java.security.spec;

import java.math.BigInteger;
import java.util.Objects;

public class EllipticCurve {
  private final ECField field;
  private final BigInteger a;
  private final BigInteger b;

  public EllipticCurve(ECField field, BigInteger a, BigInteger b) {
    this.field = Objects.requireNonNull(field);
    this.a = Objects.requireNonNull(a);
    this.b = Objects.requireNonNull(b);
    if (a.signum() < 0
        || b.signum() < 0
        || (field instanceof ECFieldFp fp
            && (a.compareTo(fp.getP()) >= 0 || b.compareTo(fp.getP()) >= 0))) {
      throw new IllegalArgumentException("Curve coefficient is outside the field");
    }
  }

  public ECField getField() {
    return field;
  }

  public BigInteger getA() {
    return a;
  }

  public BigInteger getB() {
    return b;
  }

  @Override
  public boolean equals(Object other) {
    return other instanceof EllipticCurve curve
        && field.equals(curve.field)
        && a.equals(curve.a)
        && b.equals(curve.b);
  }

  @Override
  public int hashCode() {
    return Objects.hash(field, a, b);
  }
}
