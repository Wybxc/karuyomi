package java.security;

import java.security.spec.InvalidKeySpecException;
import java.security.spec.KeySpec;
import java.util.Objects;

public class KeyFactory {
  private final boolean rsa;

  private KeyFactory(boolean rsa) {
    this.rsa = rsa;
  }

  public static KeyFactory getInstance(String algorithm) throws NoSuchAlgorithmException {
    Objects.requireNonNull(algorithm);
    if ("EC".equalsIgnoreCase(algorithm)) return new KeyFactory(false);
    if ("RSA".equalsIgnoreCase(algorithm)) return new KeyFactory(true);
    throw new NoSuchAlgorithmException(algorithm);
  }

  public final PublicKey generatePublic(KeySpec keySpec) throws InvalidKeySpecException {
    return rsa ? RsaCrypto.publicKey(keySpec) : EcCrypto.publicKey(keySpec);
  }

  public final PrivateKey generatePrivate(KeySpec keySpec) throws InvalidKeySpecException {
    if (rsa) throw new InvalidKeySpecException("RSA private key import is unavailable");
    return EcCrypto.privateKey(keySpec);
  }
}
