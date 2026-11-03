package javax.crypto;

import java.security.*;
import java.security.spec.*;
import javax.crypto.spec.*;
import java.util.*;
import com.google.gson.*;
import prototype.Bridge;

/** The supported provider is intentionally bounded to browser WebCrypto AES. */
public class Cipher {
  public static final int ENCRYPT_MODE = 1, DECRYPT_MODE = 2, WRAP_MODE = 3, UNWRAP_MODE = 4;
  private final String transformation;
  private byte[] key, iv, aad = new byte[0];
  private int mode, tag = 128;
  private final java.io.ByteArrayOutputStream pending = new java.io.ByteArrayOutputStream();

  private Cipher(String t) {
    transformation = t;
  }

  public static Cipher getInstance(String t)
      throws NoSuchAlgorithmException, NoSuchPaddingException {
    if (t == null) throw new NullPointerException();
    if (!t.equalsIgnoreCase("AES/CBC/PKCS5Padding")
        && !t.equalsIgnoreCase("AES/CBC/PKCS7Padding")
        && !t.equalsIgnoreCase("AES/GCM/NoPadding")) throw new NoSuchAlgorithmException(t);
    return new Cipher(t);
  }

  public String getAlgorithm() {
    return transformation;
  }

  public int getBlockSize() {
    return 16;
  }

  public byte[] getIV() {
    return iv == null ? null : iv.clone();
  }

  public void init(int mode, Key key, AlgorithmParameterSpec params)
      throws InvalidKeyException, InvalidAlgorithmParameterException {
    this.key = null;
    if (mode != 1 && mode != 2) throw new IllegalArgumentException("Unsupported cipher mode");
    if (key == null || !"AES".equalsIgnoreCase(key.getAlgorithm()) || key.getEncoded() == null)
      throw new InvalidKeyException("RAW AES key required");
    byte[] bytes = key.getEncoded();
    if (bytes.length != 16 && bytes.length != 24 && bytes.length != 32)
      throw new InvalidKeyException("AES key length");
    byte[] nonce;
    int bits = 128;
    if (transformation.toUpperCase(Locale.ROOT).contains("GCM")) {
      if (!(params instanceof GCMParameterSpec))
        throw new InvalidAlgorithmParameterException("GCM parameters required");
      GCMParameterSpec p = (GCMParameterSpec) params;
      bits = p.getTLen();
      nonce = p.getIV();
      if (nonce.length == 0
          || !(bits == 32
              || bits == 64
              || bits == 96
              || bits == 104
              || bits == 112
              || bits == 120
              || bits == 128)) throw new InvalidAlgorithmParameterException("GCM IV/tag length");
    } else {
      if (!(params instanceof IvParameterSpec))
        throw new InvalidAlgorithmParameterException("CBC IV required");
      nonce = ((IvParameterSpec) params).getIV();
      if (nonce.length != 16) throw new InvalidAlgorithmParameterException("CBC IV length");
    }
    this.key = bytes.clone();
    iv = nonce.clone();
    tag = bits;
    this.mode = mode;
    aad = new byte[0];
    pending.reset();
  }

  public void updateAAD(byte[] bytes) {
    if (key == null) throw new IllegalStateException("Cipher not initialized");
    byte[] n = Arrays.copyOf(aad, aad.length + bytes.length);
    System.arraycopy(bytes, 0, n, aad.length, bytes.length);
    aad = n;
  }

  public byte[] doFinal(byte[] input) throws IllegalBlockSizeException, BadPaddingException {
    return doFinal(input, 0, input.length);
  }

  public int getOutputSize(int len) {
    if (key == null) throw new IllegalStateException("Cipher not initialized");
    if (len < 0) throw new IllegalArgumentException();
    int total = Math.addExact(pending.size(), len);
    boolean gcm = transformation.toUpperCase(Locale.ROOT).contains("GCM");
    return mode == DECRYPT_MODE
        ? (gcm ? Math.max(0, total - tag / 8) : total)
        : (gcm ? total + tag / 8 : (total / 16 + 1) * 16);
  }

  public int update(byte[] in, int offset, int len, byte[] out, int outOffset)
      throws ShortBufferException {
    if (key == null) throw new IllegalStateException("Cipher not initialized");
    Objects.checkFromIndexSize(offset, len, in.length);
    if (outOffset < 0 || outOffset > out.length) throw new ShortBufferException("Output offset");
    pending.write(in, offset, len);
    return 0;
  }

  public int doFinal(byte[] out, int offset)
      throws IllegalBlockSizeException, BadPaddingException, ShortBufferException {
    if (offset < 0 || offset > out.length) throw new ShortBufferException("Output offset");
    byte[] buffered = pending.toByteArray();
    byte[] result = doFinal(new byte[0]);
    if (result.length > out.length - offset) {
      pending.write(buffered, 0, buffered.length);
      throw new ShortBufferException("Output too small");
    }
    System.arraycopy(result, 0, out, offset, result.length);
    return result.length;
  }

  public byte[] doFinal(byte[] input, int offset, int len)
      throws IllegalBlockSizeException, BadPaddingException {
    if (key == null) throw new IllegalStateException("Cipher not initialized");
    Objects.checkFromIndexSize(offset, len, input.length);
    if (pending.size() > 0) {
      pending.write(input, offset, len);
      input = pending.toByteArray();
      offset = 0;
      len = input.length;
    }
    boolean gcm = transformation.toUpperCase(Locale.ROOT).contains("GCM");
    if (mode == DECRYPT_MODE && !gcm && (len == 0 || len % 16 != 0))
      throw new IllegalBlockSizeException("CBC ciphertext length");
    JsonObject r = new JsonObject();
    r.addProperty("algorithm", gcm ? "AES-GCM" : "AES-CBC");
    r.addProperty("operation", mode == 1 ? "encrypt" : "decrypt");
    r.addProperty("key", b64(key));
    r.addProperty("iv", b64(iv));
    r.addProperty("tagLength", tag);
    r.addProperty("aad", b64(aad));
    r.addProperty("body", b64(Arrays.copyOfRange(input, offset, offset + len)));
    JsonObject out = JsonParser.parseString(Bridge.crypto(r.toString())).getAsJsonObject();
    if (out.has("error")) {
      if (gcm) throw new AEADBadTagException(out.get("error").getAsString());
      throw new BadPaddingException(out.get("error").getAsString());
    }
    aad = new byte[0];
    pending.reset();
    return Base64.getDecoder().decode(out.get("body").getAsString());
  }

  static String b64(byte[] b) {
    return Base64.getEncoder().encodeToString(b);
  }
}
