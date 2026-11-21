package javax.crypto;

import java.security.EcCrypto;
import java.security.EcCrypto.CryptoKey;
import java.security.InvalidKeyException;
import java.security.Key;
import java.security.NoSuchAlgorithmException;
import java.util.Objects;

/** Two-party P-256 key agreement through the Worker's WebCrypto provider. */
public class KeyAgreement {
  private CryptoKey local;
  private CryptoKey peer;

  private KeyAgreement() {}

  public static final KeyAgreement getInstance(String algorithm) throws NoSuchAlgorithmException {
    if (!"ECDH".equalsIgnoreCase(Objects.requireNonNull(algorithm))) {
      throw new NoSuchAlgorithmException(algorithm);
    }
    return new KeyAgreement();
  }

  public final void init(Key key) throws InvalidKeyException {
    local = null;
    peer = null;
    local = EcCrypto.agreementPrivateKey(key);
  }

  public final Key doPhase(Key key, boolean lastPhase) throws InvalidKeyException {
    if (local == null || peer != null) throw new IllegalStateException("ECDH phase out of order");
    if (!lastPhase) throw new IllegalStateException("ECDH requires a single peer");
    peer = EcCrypto.agreementPublicKey(key);
    return null;
  }

  public final byte[] generateSecret() {
    if (peer == null) throw new IllegalStateException("ECDH peer is required");
    byte[] secret = EcCrypto.deriveSecret(local, peer);
    peer = null;
    return secret;
  }
}
