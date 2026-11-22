package java.security;

import static java.security.WebCryptoBuffers.toJava;
import static java.security.WebCryptoBuffers.toJs;

import java.math.BigInteger;
import java.security.spec.InvalidKeySpecException;
import java.security.spec.KeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import javax.crypto.BadPaddingException;
import org.bouncycastle.crypto.InvalidCipherTextException;
import org.bouncycastle.crypto.encodings.PKCS1Encoding;
import org.bouncycastle.crypto.engines.RSAEngine;
import org.bouncycastle.crypto.params.ParametersWithRandom;
import org.bouncycastle.crypto.params.RSAKeyParameters;
import org.teavm.jso.JSBody;
import org.teavm.jso.JSObject;
import org.teavm.jso.JSProperty;
import org.teavm.jso.core.JSPromise;
import org.teavm.jso.typedarrays.ArrayBuffer;
import org.teavm.jso.typedarrays.Uint8Array;

/** RSA keys use WebCrypto. The legacy public encryption mode uses Bouncy Castle. */
public final class RsaCrypto {
  static final int DEFAULT_BITS = 2048;
  private static final int SHA256_BYTES = 32;
  private static final int MAX_PUBLIC_KEY_BYTES = 2048;
  private static final int MAX_BITS = 4096;

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

  static PublicKey publicKey(KeySpec spec) throws InvalidKeySpecException {
    if (!(spec instanceof X509EncodedKeySpec encoded))
      throw new InvalidKeySpecException("X.509 RSA public key required");
    byte[] bytes = encoded.getEncoded();
    if (bytes.length == 0 || bytes.length > MAX_PUBLIC_KEY_BYTES)
      throw new InvalidKeySpecException("RSA public key encoding length");
    try {
      CryptoKey handle = importPublicKey(toJs(bytes)).await();
      int bits = handle.getAlgorithm().getModulusLength();
      if (bits < 1024 || bits > MAX_BITS)
        throw new InvalidKeySpecException("RSA public key modulus length");
      return new RsaPublicKey(handle, (bits + Byte.SIZE - 1) / Byte.SIZE);
    } catch (RuntimeException error) {
      throw new InvalidKeySpecException("Invalid X.509 RSA public key", error);
    }
  }

  public static BlockCipher oaepKey(Key key, boolean encrypt, byte[] label)
      throws InvalidKeyException {
    if (!(key instanceof GeneratedKey rsa)
        || !(encrypt ? key instanceof PublicKey : key instanceof PrivateKey))
      throw new InvalidKeyException(
          encrypt ? "RSA public key required" : "RSA private key required");
    return new OaepKey(rsa, encrypt, label);
  }

  public static BlockCipher pkcs1Key(Key key) throws InvalidKeyException {
    if (!(key instanceof GeneratedKey rsa) || !(key instanceof PublicKey))
      throw new InvalidKeyException("RSA public key required");
    try {
      RsaJwk jwk = exportJwk(rsa.handle).await();
      Base64.Decoder base64 = Base64.getUrlDecoder();
      BigInteger modulus = new BigInteger(1, base64.decode(jwk.getN()));
      BigInteger exponent = new BigInteger(1, base64.decode(jwk.getE()));
      var parameters = new RSAKeyParameters(false, modulus, exponent);
      var cipher = new PKCS1Encoding(new RSAEngine());
      cipher.init(true, new ParametersWithRandom(parameters, new SecureRandom()));
      return new Pkcs1Key(cipher);
    } catch (RuntimeException error) {
      throw new InvalidKeyException("Invalid RSA public encryption key", error);
    }
  }

  public interface BlockCipher {
    int modulusBytes();

    int inputLimit();

    byte[] process(byte[] input) throws BadPaddingException;
  }

  private static final class OaepKey implements BlockCipher {
    private final GeneratedKey key;
    private final boolean encrypt;
    private final byte[] label;

    private OaepKey(GeneratedKey key, boolean encrypt, byte[] label) {
      this.key = key;
      this.encrypt = encrypt;
      this.label = label;
    }

    @Override
    public int modulusBytes() {
      return key.modulusBytes;
    }

    @Override
    public int inputLimit() {
      return encrypt ? modulusBytes() - 2 * SHA256_BYTES - 2 : modulusBytes();
    }

    @Override
    public byte[] process(byte[] input) throws BadPaddingException {
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

  private static final class Pkcs1Key implements BlockCipher {
    private final PKCS1Encoding cipher;

    private Pkcs1Key(PKCS1Encoding cipher) {
      this.cipher = cipher;
    }

    @Override
    public int modulusBytes() {
      return cipher.getOutputBlockSize();
    }

    @Override
    public int inputLimit() {
      return cipher.getInputBlockSize();
    }

    @Override
    public byte[] process(byte[] input) throws BadPaddingException {
      try {
        return cipher.processBlock(input, 0, input.length);
      } catch (InvalidCipherTextException error) {
        BadPaddingException failure = new BadPaddingException("RSA encryption failed");
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
      params = "der",
      script =
          "return globalThis.crypto.subtle.importKey('spki', der,"
              + " {name: 'RSA-OAEP', hash: 'SHA-256'}, true, ['encrypt']);")
  private static native JSPromise<CryptoKey> importPublicKey(Uint8Array der);

  @JSBody(
      params = {"format", "key"},
      script = "return globalThis.crypto.subtle.exportKey(format, key);")
  private static native JSPromise<ArrayBuffer> export(String format, CryptoKey key);

  @JSBody(params = "key", script = "return globalThis.crypto.subtle.exportKey('jwk', key);")
  private static native JSPromise<RsaJwk> exportJwk(CryptoKey key);

  @JSBody(
      params = {"key", "encrypt", "input", "label"},
      script =
          "const algorithm = {name: 'RSA-OAEP', label};"
              + " const subtle = globalThis.crypto.subtle;"
              + " return encrypt ? subtle.encrypt(algorithm, key, input)"
              + " : subtle.decrypt(algorithm, key, input);")
  private static native JSPromise<ArrayBuffer> oaep(
      CryptoKey key, boolean encrypt, Uint8Array input, Uint8Array label);

  private interface CryptoKey extends JSObject {
    @JSProperty
    RsaAlgorithm getAlgorithm();
  }

  private interface RsaAlgorithm extends JSObject {
    @JSProperty
    int getModulusLength();
  }

  private interface RsaJwk extends JSObject {
    @JSProperty
    String getN();

    @JSProperty
    String getE();
  }

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
