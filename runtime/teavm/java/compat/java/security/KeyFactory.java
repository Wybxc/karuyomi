package java.security;

import java.security.spec.InvalidKeySpecException;
import java.security.spec.KeySpec;
import java.util.Objects;

public class KeyFactory {
  private KeyFactory() {}

  public static KeyFactory getInstance(String algorithm) throws NoSuchAlgorithmException {
    if (!Objects.requireNonNull(algorithm).equalsIgnoreCase("EC"))
      throw new NoSuchAlgorithmException(algorithm);
    return new KeyFactory();
  }

  public final PublicKey generatePublic(KeySpec keySpec) throws InvalidKeySpecException {
    return EcCrypto.publicKey(keySpec);
  }

  public final PrivateKey generatePrivate(KeySpec keySpec) throws InvalidKeySpecException {
    return EcCrypto.privateKey(keySpec);
  }
}
