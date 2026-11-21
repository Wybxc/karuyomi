package java.security;

import java.math.BigInteger;
import java.security.interfaces.ECPublicKey;
import java.security.spec.*;
import java.util.Arrays;
import org.teavm.jso.JSBody;
import org.teavm.jso.JSObject;
import org.teavm.jso.JSProperty;
import org.teavm.jso.core.JSArray;
import org.teavm.jso.core.JSBoolean;
import org.teavm.jso.core.JSObjects;
import org.teavm.jso.core.JSPromise;
import org.teavm.jso.core.JSString;
import org.teavm.jso.typedarrays.ArrayBuffer;
import org.teavm.jso.typedarrays.Uint8Array;

/** P-256 operations are performed by the Worker's WebCrypto provider. */
final class EcCrypto {
  static final int COORDINATE_BYTES = 32;
  private static final int MAX_ENCODED_KEY_BYTES = 1024;
  private static final String WEB_ALGORITHM = "ECDSA";
  private static final BigInteger PRIME =
      integer("FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF");

  static final ECParameterSpec PARAMETERS =
      new ECParameterSpec(
          new EllipticCurve(
              new ECFieldFp(PRIME),
              PRIME.subtract(BigInteger.valueOf(3)),
              integer("5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B")),
          new ECPoint(
              integer("6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296"),
              integer("4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5")),
          integer("FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551"),
          1);

  private EcCrypto() {}

  private static BigInteger integer(String value) {
    return new BigInteger(value, 16);
  }

  static boolean supports(AlgorithmParameterSpec spec) {
    if (spec instanceof ECGenParameterSpec named) {
      String name = named.getName();
      return name.equalsIgnoreCase("secp256r1")
          || name.equalsIgnoreCase("NIST P-256")
          || name.equals("1.2.840.10045.3.1.7");
    }
    return spec instanceof ECParameterSpec explicit
        && PARAMETERS.getCurve().equals(explicit.getCurve())
        && PARAMETERS.getGenerator().equals(explicit.getGenerator())
        && PARAMETERS.getOrder().equals(explicit.getOrder())
        && PARAMETERS.getCofactor() == explicit.getCofactor();
  }

  static KeyPair generateKeyPair() {
    SubtleCrypto subtle = crypto().getSubtle();
    CryptoKeyPair pair =
        subtle.generateKey(keyParameters(), true, usages("sign", "verify")).await();
    byte[] encoded = exportKey(subtle, "pkcs8", pair.getPrivateKey());
    return new KeyPair(
        publicKey(subtle, pair.getPublicKey()), new P256PrivateKey(pair.getPrivateKey(), encoded));
  }

  static PublicKey publicKey(KeySpec spec) throws InvalidKeySpecException {
    byte[] encoded;
    String format;
    if (spec instanceof X509EncodedKeySpec x509) {
      encoded = x509.getEncoded();
      format = "spki";
      checkEncodedLength(encoded);
    } else if (spec instanceof ECPublicKeySpec ec && supports(ec.getParams())) {
      encoded = new byte[1 + 2 * COORDINATE_BYTES];
      encoded[0] = 4;
      putCoordinate(ec.getW().getAffineX(), encoded, 1);
      putCoordinate(ec.getW().getAffineY(), encoded, 1 + COORDINATE_BYTES);
      format = "raw";
    } else {
      throw new InvalidKeySpecException("Expected an X.509 or P-256 public key");
    }
    try {
      SubtleCrypto subtle = crypto().getSubtle();
      CryptoKey key =
          subtle.importKey(format, toJs(encoded), keyParameters(), true, usages("verify")).await();
      return publicKey(subtle, key);
    } catch (RuntimeException error) {
      throw new InvalidKeySpecException("WebCrypto rejected the P-256 public key", error);
    }
  }

  static PrivateKey privateKey(KeySpec spec) throws InvalidKeySpecException {
    if (!(spec instanceof PKCS8EncodedKeySpec pkcs8))
      throw new InvalidKeySpecException("Expected a PKCS#8 private key");
    byte[] encoded = pkcs8.getEncoded();
    checkEncodedLength(encoded);
    Uint8Array keyData = toJs(encoded);
    try {
      CryptoKey key =
          crypto()
              .getSubtle()
              .importKey("pkcs8", keyData, keyParameters(), false, usages("sign"))
              .await();
      return new P256PrivateKey(key, encoded.clone());
    } catch (RuntimeException error) {
      throw new InvalidKeySpecException("WebCrypto rejected the P-256 private key", error);
    } finally {
      Arrays.fill(encoded, (byte) 0);
      for (int i = 0; i < keyData.getByteLength(); i++) keyData.set(i, (short) 0);
    }
  }

  static CryptoKey signingKey(PrivateKey key) throws InvalidKeyException {
    if (key instanceof P256PrivateKey ec) return ec.handle;
    throw new InvalidKeyException("Expected a P-256 private key");
  }

  static CryptoKey verificationKey(PublicKey key) throws InvalidKeyException {
    if (key instanceof P256PublicKey ec) return ec.handle;
    throw new InvalidKeyException("Expected a P-256 public key");
  }

  static byte[] sign(CryptoKey key, byte[] message) {
    return toJava(crypto().getSubtle().sign(signatureParameters(), key, toJs(message)).await());
  }

  static boolean verify(CryptoKey key, byte[] message, byte[] rawSignature) {
    return crypto()
        .getSubtle()
        .verify(signatureParameters(), key, toJs(rawSignature), toJs(message))
        .await()
        .booleanValue();
  }

  private static void checkEncodedLength(byte[] bytes) throws InvalidKeySpecException {
    if (bytes.length == 0 || bytes.length > MAX_ENCODED_KEY_BYTES)
      throw new InvalidKeySpecException("Invalid encoded EC key length");
  }

  private static void putCoordinate(BigInteger coordinate, byte[] raw, int offset)
      throws InvalidKeySpecException {
    if (coordinate.signum() < 0 || coordinate.compareTo(PRIME) >= 0)
      throw new InvalidKeySpecException("Public EC coordinate is outside the field");
    byte[] value = coordinate.toByteArray();
    int length = Math.min(value.length, COORDINATE_BYTES);
    System.arraycopy(value, value.length - length, raw, offset + COORDINATE_BYTES - length, length);
  }

  private static PublicKey publicKey(SubtleCrypto subtle, CryptoKey key) {
    byte[] raw = exportKey(subtle, "raw", key);
    if (raw.length != 1 + 2 * COORDINATE_BYTES || raw[0] != 4)
      throw new IllegalStateException("Unexpected WebCrypto public key encoding");
    ECPoint point =
        new ECPoint(
            new BigInteger(1, Arrays.copyOfRange(raw, 1, 1 + COORDINATE_BYTES)),
            new BigInteger(1, Arrays.copyOfRange(raw, 1 + COORDINATE_BYTES, raw.length)));
    return new P256PublicKey(key, exportKey(subtle, "spki", key), point);
  }

  private static byte[] exportKey(SubtleCrypto subtle, String format, CryptoKey key) {
    return toJava(subtle.exportKey(format, key).await());
  }

  private static Uint8Array toJs(byte[] value) {
    Uint8Array array = new Uint8Array(value.length);
    for (int i = 0; i < value.length; i++) array.set(i, (short) (value[i] & 255));
    return array;
  }

  private static byte[] toJava(ArrayBuffer buffer) {
    Uint8Array view = new Uint8Array(buffer);
    byte[] result = new byte[view.getByteLength()];
    for (int i = 0; i < result.length; i++) result[i] = (byte) view.get(i);
    return result;
  }

  private static JSArray<JSString> usages(String... values) {
    JSArray<JSString> usages = new JSArray<>();
    for (String use : values) usages.push(JSString.valueOf(use));
    return usages;
  }

  private static EcKeyParameters keyParameters() {
    EcKeyParameters parameters = JSObjects.create();
    parameters.setName(WEB_ALGORITHM);
    parameters.setNamedCurve("P-256");
    return parameters;
  }

  private static EcSignatureParameters signatureParameters() {
    EcSignatureParameters parameters = JSObjects.create();
    parameters.setName(WEB_ALGORITHM);
    parameters.setHash("SHA-256");
    return parameters;
  }

  @JSBody(script = "return globalThis.crypto;")
  private static native CryptoProvider crypto();

  interface CryptoKey extends JSObject {}

  private interface CryptoProvider extends JSObject {
    @JSProperty
    SubtleCrypto getSubtle();
  }

  private interface CryptoKeyPair extends JSObject {
    @JSProperty
    CryptoKey getPublicKey();

    @JSProperty
    CryptoKey getPrivateKey();
  }

  private interface SubtleCrypto extends JSObject {
    JSPromise<CryptoKeyPair> generateKey(
        EcKeyParameters parameters, boolean extractable, JSArray<JSString> usages);

    JSPromise<CryptoKey> importKey(
        String format,
        Uint8Array bytes,
        EcKeyParameters parameters,
        boolean extractable,
        JSArray<JSString> usages);

    JSPromise<ArrayBuffer> exportKey(String format, CryptoKey key);

    JSPromise<ArrayBuffer> sign(
        EcSignatureParameters parameters, CryptoKey key, Uint8Array message);

    JSPromise<JSBoolean> verify(
        EcSignatureParameters parameters, CryptoKey key, Uint8Array signature, Uint8Array message);
  }

  private interface EcKeyParameters extends JSObject {
    @JSProperty
    void setName(String name);

    @JSProperty
    void setNamedCurve(String curve);
  }

  private interface EcSignatureParameters extends JSObject {
    @JSProperty
    void setName(String name);

    @JSProperty
    void setHash(String hash);
  }

  private static final class P256PublicKey implements ECPublicKey {
    private final CryptoKey handle;
    private final byte[] encoded;
    private final ECPoint point;

    P256PublicKey(CryptoKey handle, byte[] encoded, ECPoint point) {
      this.handle = handle;
      this.encoded = encoded;
      this.point = point;
    }

    public String getAlgorithm() {
      return "EC";
    }

    public String getFormat() {
      return "X.509";
    }

    public byte[] getEncoded() {
      return encoded.clone();
    }

    public ECPoint getW() {
      return point;
    }

    public ECParameterSpec getParams() {
      return PARAMETERS;
    }
  }

  private static final class P256PrivateKey implements PrivateKey {
    private final CryptoKey handle;
    private final byte[] encoded;

    P256PrivateKey(CryptoKey handle, byte[] encoded) {
      this.handle = handle;
      this.encoded = encoded;
    }

    public String getAlgorithm() {
      return "EC";
    }

    public String getFormat() {
      return "PKCS#8";
    }

    public byte[] getEncoded() {
      return encoded.clone();
    }
  }
}
