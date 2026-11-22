package java.security;

import java.security.spec.AlgorithmParameterSpec;
import java.util.Objects;

public class KeyPairGenerator {
  private final boolean rsa;
  private int rsaBits = RsaCrypto.DEFAULT_BITS;

  private KeyPairGenerator(boolean rsa) {
    this.rsa = rsa;
  }

  public static KeyPairGenerator getInstance(String algorithm) throws NoSuchAlgorithmException {
    Objects.requireNonNull(algorithm);
    if (algorithm.equalsIgnoreCase("EC")) return new KeyPairGenerator(false);
    if (algorithm.equalsIgnoreCase("RSA")) return new KeyPairGenerator(true);
    throw new NoSuchAlgorithmException(algorithm);
  }

  public void initialize(int keySize) {
    if (rsa) {
      if (!RsaCrypto.supportsSize(keySize))
        throw new InvalidParameterException("Expected 2048 or 3072 or 4096 RSA bits");
      rsaBits = keySize;
      return;
    }
    if (keySize != EcCrypto.COORDINATE_BYTES * Byte.SIZE)
      throw new InvalidParameterException("Expected the P-256 key size");
  }

  public void initialize(AlgorithmParameterSpec params) throws InvalidAlgorithmParameterException {
    if (rsa) throw new InvalidAlgorithmParameterException("Initialize RSA with the key size");
    if (!EcCrypto.supports(params))
      throw new InvalidAlgorithmParameterException("Expected P-256 parameters");
  }

  public KeyPair generateKeyPair() {
    return rsa ? RsaCrypto.generateKeyPair(rsaBits) : EcCrypto.generateKeyPair();
  }
}
