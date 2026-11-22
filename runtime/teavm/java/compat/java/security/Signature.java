package java.security;

import java.io.ByteArrayOutputStream;
import java.util.Arrays;
import java.util.Objects;

public class Signature {
  private static final String ALGORITHM = "SHA256withECDSA";
  private static final int MAX_MESSAGE_BYTES = 8 * 1024 * 1024;
  private static final int WIDTH = EcCrypto.COORDINATE_BYTES;
  private static final int RAW_BYTES = 2 * WIDTH;
  private static final int MAX_DER_BYTES = RAW_BYTES + 8;

  private final ByteArrayOutputStream message = new ByteArrayOutputStream();
  private EcCrypto.CryptoKey key;
  private boolean signing;

  private Signature() {}

  public static Signature getInstance(String algorithm) throws NoSuchAlgorithmException {
    if (!Objects.requireNonNull(algorithm).equalsIgnoreCase(ALGORITHM))
      throw new NoSuchAlgorithmException(algorithm);
    return new Signature();
  }

  public final String getAlgorithm() {
    return ALGORITHM;
  }

  public final void initSign(PrivateKey privateKey) throws InvalidKeyException {
    key = EcCrypto.signingKey(privateKey);
    signing = true;
    message.reset();
  }

  public final void initVerify(PublicKey publicKey) throws InvalidKeyException {
    key = EcCrypto.verificationKey(publicKey);
    signing = false;
    message.reset();
  }

  public final void update(byte value) throws SignatureException {
    checkMessageLength(1);
    message.write(value);
  }

  public final void update(byte[] value) throws SignatureException {
    update(value, 0, value.length);
  }

  public final void update(byte[] value, int offset, int length) throws SignatureException {
    Objects.checkFromIndexSize(offset, length, value.length);
    checkMessageLength(length);
    message.write(value, offset, length);
  }

  private void checkMessageLength(int length) throws SignatureException {
    if (key == null) throw new SignatureException("Signature is not initialized");
    if (length > MAX_MESSAGE_BYTES - message.size())
      throw new SignatureException("Signature message is too large");
  }

  public final byte[] sign() throws SignatureException {
    if (key == null || !signing)
      throw new SignatureException("Signature is not initialized for signing");
    try {
      return toDer(EcCrypto.sign(key, message.toByteArray()));
    } catch (RuntimeException error) {
      throw new SignatureException("WebCrypto ECDSA signing failed", error);
    } finally {
      message.reset();
    }
  }

  public final boolean verify(byte[] signature) throws SignatureException {
    if (key == null || signing)
      throw new SignatureException("Signature is not initialized for verification");
    try {
      return EcCrypto.verify(key, message.toByteArray(), fromDer(signature));
    } catch (RuntimeException error) {
      throw new SignatureException("WebCrypto ECDSA verification failed", error);
    } finally {
      message.reset();
    }
  }

  // Java uses DER ECDSA-Sig-Value while WebCrypto uses the fixed-width r || s form.
  private static byte[] toDer(byte[] raw) throws SignatureException {
    if (raw.length != RAW_BYTES) throw new SignatureException("Unexpected P-256 signature length");
    byte[] der = new byte[MAX_DER_BYTES];
    int end = writeInteger(raw, WIDTH, der, writeInteger(raw, 0, der, 2));
    der[0] = 0x30;
    der[1] = (byte) (end - 2);
    return Arrays.copyOf(der, end);
  }

  private static int writeInteger(byte[] raw, int start, byte[] der, int destination) {
    int end = start + WIDTH;
    while (start < end - 1 && raw[start] == 0) start++;
    int length = end - start;
    boolean padded = raw[start] < 0;
    der[destination++] = 2;
    der[destination++] = (byte) (length + (padded ? 1 : 0));
    if (padded) der[destination++] = 0;
    System.arraycopy(raw, start, der, destination, length);
    return destination + length;
  }

  private static byte[] fromDer(byte[] der) throws SignatureException {
    if (der.length < 8 || der.length > MAX_DER_BYTES || der[0] != 0x30 || der[1] != der.length - 2)
      throw new SignatureException("Invalid DER ECDSA signature");
    byte[] raw = new byte[RAW_BYTES];
    int end = readInteger(der, readInteger(der, 2, raw, 0), raw, WIDTH);
    if (end != der.length) throw new SignatureException("Trailing DER signature data");
    return raw;
  }

  private static int readInteger(byte[] der, int offset, byte[] raw, int destination)
      throws SignatureException {
    if (offset + 2 >= der.length || der[offset] != 2)
      throw new SignatureException("Missing DER signature integer");
    int start = offset + 2;
    int length = der[offset + 1] & 255;
    int end = start + length;
    if (length < 1 || length > WIDTH + 1 || end > der.length || der[start] < 0)
      throw new SignatureException("Invalid DER signature integer");
    if (length > 1 && der[start] == 0) {
      if (der[start + 1] >= 0) throw new SignatureException("Nonminimal DER signature integer");
      start++;
      length--;
    }
    if (length > WIDTH) throw new SignatureException("Oversized DER signature integer");
    System.arraycopy(der, start, raw, destination + WIDTH - length, length);
    return end;
  }
}
