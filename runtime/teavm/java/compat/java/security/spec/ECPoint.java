package java.security.spec;

import java.math.BigInteger;
import java.util.Objects;

public class ECPoint {
  public static final ECPoint POINT_INFINITY = new ECPoint();

  private final BigInteger x;
  private final BigInteger y;

  private ECPoint() {
    x = null;
    y = null;
  }

  public ECPoint(BigInteger x, BigInteger y) {
    this.x = Objects.requireNonNull(x);
    this.y = Objects.requireNonNull(y);
  }

  public BigInteger getAffineX() {
    return x;
  }

  public BigInteger getAffineY() {
    return y;
  }

  @Override
  public boolean equals(Object other) {
    return other instanceof ECPoint point
        && Objects.equals(x, point.x)
        && Objects.equals(y, point.y);
  }

  @Override
  public int hashCode() {
    return Objects.hash(x, y);
  }
}
