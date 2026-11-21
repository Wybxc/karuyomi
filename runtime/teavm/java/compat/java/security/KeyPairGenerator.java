package java.security;

import java.security.spec.AlgorithmParameterSpec;
import java.util.Objects;

public class KeyPairGenerator {
  private KeyPairGenerator() {}

  public static KeyPairGenerator getInstance(String algorithm) throws NoSuchAlgorithmException {
    if (!Objects.requireNonNull(algorithm).equalsIgnoreCase("EC"))
      throw new NoSuchAlgorithmException(algorithm);
    return new KeyPairGenerator();
  }

  public void initialize(int keySize) {
    if (keySize != EcCrypto.COORDINATE_BYTES * Byte.SIZE)
      throw new InvalidParameterException("Expected the P-256 key size");
  }

  public void initialize(AlgorithmParameterSpec params) throws InvalidAlgorithmParameterException {
    if (!EcCrypto.supports(params))
      throw new InvalidAlgorithmParameterException("Expected P-256 parameters");
  }

  public KeyPair generateKeyPair() {
    return EcCrypto.generateKeyPair();
  }
}
