package java.security.spec;

import java.util.Objects;

public class ECPublicKeySpec implements KeySpec {
  private final ECPoint point;
  private final ECParameterSpec params;

  public ECPublicKeySpec(ECPoint point, ECParameterSpec params) {
    this.point = Objects.requireNonNull(point);
    this.params = Objects.requireNonNull(params);
    if (ECPoint.POINT_INFINITY.equals(point))
      throw new IllegalArgumentException("The public point must be finite");
  }

  public ECPoint getW() {
    return point;
  }

  public ECParameterSpec getParams() {
    return params;
  }
}
