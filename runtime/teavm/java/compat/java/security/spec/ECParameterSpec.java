package java.security.spec;

import java.math.BigInteger;
import java.util.Objects;

public class ECParameterSpec implements AlgorithmParameterSpec {
  private final EllipticCurve curve;
  private final ECPoint generator;
  private final BigInteger order;
  private final int cofactor;

  public ECParameterSpec(EllipticCurve curve, ECPoint generator, BigInteger order, int cofactor) {
    this.curve = Objects.requireNonNull(curve);
    this.generator = Objects.requireNonNull(generator);
    this.order = Objects.requireNonNull(order);
    if (order.signum() <= 0 || cofactor <= 0)
      throw new IllegalArgumentException("Nonpositive EC order or cofactor");
    this.cofactor = cofactor;
  }

  public EllipticCurve getCurve() {
    return curve;
  }

  public ECPoint getGenerator() {
    return generator;
  }

  public BigInteger getOrder() {
    return order;
  }

  public int getCofactor() {
    return cofactor;
  }
}
