package java.security;

import static java.security.WebCryptoBuffers.toJava;
import static java.security.WebCryptoBuffers.toJs;

import javax.crypto.BadPaddingException;
import org.teavm.jso.JSBody;
import org.teavm.jso.JSObject;
import org.teavm.jso.JSProperty;
import org.teavm.jso.core.JSPromise;
import org.teavm.jso.typedarrays.ArrayBuffer;
import org.teavm.jso.typedarrays.Uint8Array;

/** RSA-OAEP operations use the Worker's WebCrypto provider. */
public final class RsaCrypto {
  static final int DEFAULT_BITS = 2048;
  private static final int SHA256_BYTES = 32;

  private RsaCrypto() {}

  static boolean supportsSize(int bits) {
    return bits == 2048 || bits == 3072 || bits == 4096;
  }

  static KeyPair generateKeyPair(int bits) {
    CryptoKeyPair pair = generate(bits).await();
    int modulusBytes = bits / Byte.SIZE;
    return new KeyPair(
        new RsaPublicKey(pair.getPublicKey(), modulusBytes),
        new RsaPrivateKey(pair.getPrivateKey(), modulusBytes));
  }

  public static OaepKey oaepKey(Key key, boolean encrypt) throws InvalidKeyException {
    if (!(key instanceof GeneratedKey rsa)
        || !(encrypt ? key instanceof PublicKey : key instanceof PrivateKey))
      throw new InvalidKeyException(
          encrypt ? "RSA public key required" : "RSA private key required");
    return new OaepKey(rsa, encrypt);
  }

  public static final class OaepKey {
    private final GeneratedKey key;
    private final boolean encrypt;

    private OaepKey(GeneratedKey key, boolean encrypt) {
      this.key = key;
      this.encrypt = encrypt;
    }

    public int modulusBytes() {
      return key.modulusBytes;
    }

    public int inputLimit() {
      return encrypt ? modulusBytes() - 2 * SHA256_BYTES - 2 : modulusBytes();
    }

    public byte[] process(byte[] input, byte[] label) throws BadPaddingException {
      if (!encrypt && input.length != modulusBytes())
        throw new BadPaddingException("Invalid RSA-OAEP ciphertext size");
      try {
        return toJava(oaep(key.handle, encrypt, toJs(input), toJs(label)).await());
      } catch (RuntimeException error) {
        BadPaddingException failure = new BadPaddingException("WebCrypto rejected RSA-OAEP input");
        failure.initCause(error);
        throw failure;
      }
    }
  }

  @JSBody(
      params = "bits",
      script =
          "return globalThis.crypto.subtle.generateKey({name: 'RSA-OAEP', modulusLength: bits,"
              + " publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256'},"
              + " true, ['encrypt', 'decrypt']);")
  private static native JSPromise<CryptoKeyPair> generate(int bits);

  @JSBody(
      params = {"format", "key"},
      script = "return globalThis.crypto.subtle.exportKey(format, key);")
  private static native JSPromise<ArrayBuffer> export(String format, CryptoKey key);

  @JSBody(
      params = {"key", "encrypt", "input", "label"},
      script =
          "const algorithm = {name: 'RSA-OAEP', label};"
              + " const subtle = globalThis.crypto.subtle;"
              + " return encrypt ? subtle.encrypt(algorithm, key, input)"
              + " : subtle.decrypt(algorithm, key, input);")
  private static native JSPromise<ArrayBuffer> oaep(
      CryptoKey key, boolean encrypt, Uint8Array input, Uint8Array label);

  private interface CryptoKey extends JSObject {}

  private interface CryptoKeyPair extends JSObject {
    @JSProperty
    CryptoKey getPublicKey();

    @JSProperty
    CryptoKey getPrivateKey();
  }

  private abstract static class GeneratedKey implements Key {
    private final CryptoKey handle;
    private final int modulusBytes;

    GeneratedKey(CryptoKey handle, int modulusBytes) {
      this.handle = handle;
      this.modulusBytes = modulusBytes;
    }

    @Override
    public final String getAlgorithm() {
      return "RSA";
    }

    byte[] exportEncoded(String format) {
      return toJava(export(format, handle).await());
    }
  }

  private static final class RsaPublicKey extends GeneratedKey implements PublicKey {
    RsaPublicKey(CryptoKey handle, int modulusBytes) {
      super(handle, modulusBytes);
    }

    @Override
    public String getFormat() {
      return "X.509";
    }

    @Override
    public byte[] getEncoded() {
      return exportEncoded("spki");
    }
  }

  private static final class RsaPrivateKey extends GeneratedKey implements PrivateKey {
    RsaPrivateKey(CryptoKey handle, int modulusBytes) {
      super(handle, modulusBytes);
    }

    @Override
    public String getFormat() {
      return "PKCS#8";
    }

    @Override
    public byte[] getEncoded() {
      return exportEncoded("pkcs8");
    }
  }
}
