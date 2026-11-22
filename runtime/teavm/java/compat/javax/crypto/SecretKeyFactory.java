package javax.crypto;

import java.nio.ByteBuffer;
import java.nio.CharBuffer;
import java.nio.charset.StandardCharsets;
import java.security.NoSuchAlgorithmException;
import java.security.spec.InvalidKeySpecException;
import java.security.spec.KeySpec;
import java.util.Arrays;
import java.util.Locale;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;
import org.teavm.jso.JSBody;
import org.teavm.jso.JSObject;
import org.teavm.jso.JSProperty;
import org.teavm.jso.core.JSArray;
import org.teavm.jso.core.JSObjects;
import org.teavm.jso.core.JSPromise;
import org.teavm.jso.core.JSString;
import org.teavm.jso.typedarrays.ArrayBuffer;
import org.teavm.jso.typedarrays.Uint8Array;

/** Password-based key derivation through the Worker platform's WebCrypto provider. */
public class SecretKeyFactory {
  private static final int MAX_INPUT = 65536;
  private static final int MAX_KEY_BYTES = 1024;
  private static final int MAX_PRF_CALLS = 1_000_000;

  private final String algorithm;
  private final String hash;
  private final int hashBytes;

  private SecretKeyFactory(String algorithm, String hash, int hashBytes) {
    this.algorithm = algorithm;
    this.hash = hash;
    this.hashBytes = hashBytes;
  }

  public static SecretKeyFactory getInstance(String algorithm) throws NoSuchAlgorithmException {
    return switch (algorithm.toUpperCase(Locale.ROOT)) {
      case "PBKDF2WITHHMACSHA256" -> new SecretKeyFactory("PBKDF2WithHmacSHA256", "SHA-256", 32);
      case "PBKDF2WITHHMACSHA512" -> new SecretKeyFactory("PBKDF2WithHmacSHA512", "SHA-512", 64);
      default -> throw new NoSuchAlgorithmException(algorithm);
    };
  }

  public final SecretKey generateSecret(KeySpec spec) throws InvalidKeySpecException {
    if (!(spec instanceof PBEKeySpec pbe)) throw new InvalidKeySpecException("PBEKeySpec required");
    byte[] salt = pbe.getSalt();
    int size = pbe.getKeyLength() / Byte.SIZE;
    int iterations = pbe.getIterationCount();
    if (salt == null
        || salt.length > MAX_INPUT
        || size < 1
        || size > MAX_KEY_BYTES
        || iterations < 1)
      throw new InvalidKeySpecException("Missing or oversized PBKDF2 parameters");
    long calls = (long) iterations * ((size + hashBytes - 1) / hashBytes);
    if (calls > MAX_PRF_CALLS) throw new InvalidKeySpecException("PBKDF2 work limit exceeded");

    char[] password = pbe.getPassword();
    try {
      if (password.length > MAX_INPUT) throw new InvalidKeySpecException("Password is too long");
      return derive(password, salt, iterations, size);
    } finally {
      Arrays.fill(password, '\0');
    }
  }

  private SecretKey derive(char[] password, byte[] salt, int iterations, int size)
      throws InvalidKeySpecException {
    ByteBuffer encoded = StandardCharsets.UTF_8.encode(CharBuffer.wrap(password));
    Uint8Array keyData = new Uint8Array(encoded.remaining());
    byte[] key = new byte[size];
    try {
      for (int i = 0; encoded.hasRemaining(); i++) keyData.set(i, (short) (encoded.get() & 255));
      Uint8Array saltData = new Uint8Array(salt.length);
      for (int i = 0; i < salt.length; i++) saltData.set(i, (short) (salt[i] & 255));
      SubtleCrypto subtle = crypto().getSubtle();
      JSArray<JSString> usages = new JSArray<>();
      usages.push(JSString.valueOf("deriveBits"));
      JSObject handle = subtle.importKey("raw", keyData, "PBKDF2", false, usages).await();
      Pbkdf2Parameters parameters = JSObjects.create();
      parameters.setName("PBKDF2");
      parameters.setSalt(saltData);
      parameters.setIterations(iterations);
      parameters.setHash(hash);
      Uint8Array derived =
          new Uint8Array(subtle.deriveBits(parameters, handle, size * Byte.SIZE).await());
      if (derived.getByteLength() != size)
        throw new InvalidKeySpecException("Unexpected PBKDF2 output size");
      for (int i = 0; i < size; i++) {
        key[i] = (byte) derived.get(i);
        derived.set(i, (short) 0);
      }
      return new SecretKeySpec(key, algorithm);
    } catch (RuntimeException error) {
      throw new InvalidKeySpecException("WebCrypto PBKDF2 failed", error);
    } finally {
      Arrays.fill(key, (byte) 0);
      for (int i = 0; i < keyData.getByteLength(); i++) keyData.set(i, (short) 0);
      encoded.clear();
      while (encoded.hasRemaining()) encoded.put((byte) 0);
    }
  }

  @JSBody(script = "return globalThis.crypto;")
  private static native CryptoProvider crypto();

  private interface CryptoProvider extends JSObject {
    @JSProperty
    SubtleCrypto getSubtle();
  }

  private interface SubtleCrypto extends JSObject {
    JSPromise<JSObject> importKey(
        String format,
        Uint8Array key,
        String algorithm,
        boolean extractable,
        JSArray<JSString> usages);

    JSPromise<ArrayBuffer> deriveBits(Pbkdf2Parameters parameters, JSObject key, int length);
  }

  private interface Pbkdf2Parameters extends JSObject {
    @JSProperty
    void setName(String name);

    @JSProperty
    void setSalt(Uint8Array salt);

    @JSProperty
    void setIterations(int iterations);

    @JSProperty
    void setHash(String hash);
  }
}
