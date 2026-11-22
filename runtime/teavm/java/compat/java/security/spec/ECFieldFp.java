package java.security.spec;

import java.math.BigInteger;

public class ECFieldFp implements ECField {
  private final BigInteger prime;

  public ECFieldFp(BigInteger prime) {
    if (prime.signum() <= 0) throw new IllegalArgumentException("Nonpositive field size");
    this.prime = prime;
  }

  public BigInteger getP() {
    return prime;
  }

  @Override
  public int getFieldSize() {
    return prime.bitLength();
  }

  @Override
  public boolean equals(Object other) {
    return other instanceof ECFieldFp field && prime.equals(field.prime);
  }

  @Override
  public int hashCode() {
    return prime.hashCode();
  }
}
