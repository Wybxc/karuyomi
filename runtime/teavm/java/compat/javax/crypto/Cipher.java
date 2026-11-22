package javax.crypto;

import java.security.*;
import java.security.spec.*;
import javax.crypto.spec.*;
import java.util.*;
import com.google.gson.*;
import prototype.Bridge;

/** Java cipher calls backed by WebCrypto and Bouncy Castle's public RSA encryption. */
public class Cipher {
  public static final int ENCRYPT_MODE = 1, DECRYPT_MODE = 2, WRAP_MODE = 3, UNWRAP_MODE = 4;
  private static final String AES_GCM = "AES/GCM/NoPadding";
  private static final String RSA_OAEP = "RSA/ECB/OAEPWithSHA-256AndMGF1Padding";
  private static final String RSA_PKCS1 = "RSA/ECB/PKCS1Padding";
  private final String transformation;
  private final boolean rsa;
  private final boolean pkcs1;
  private final boolean gcm;
  private byte[] key, iv, aad = new byte[0];
  private RsaCrypto.BlockCipher rsaKey;
  private boolean rsaInputTooLong;
  private int mode, tag = 128;
  private final java.io.ByteArrayOutputStream pending = new java.io.ByteArrayOutputStream();

  private Cipher(String t) {
    transformation = t;
    pkcs1 = RSA_PKCS1.equalsIgnoreCase(t);
    rsa = pkcs1 || RSA_OAEP.equalsIgnoreCase(t);
    gcm = AES_GCM.equalsIgnoreCase(t);
  }

  public static Cipher getInstance(String t)
      throws NoSuchAlgorithmException, NoSuchPaddingException {
    if (t == null) throw new NullPointerException();
    if (!t.equalsIgnoreCase("AES/CBC/PKCS5Padding")
        && !t.equalsIgnoreCase("AES/CBC/PKCS7Padding")
        && !AES_GCM.equalsIgnoreCase(t)
        && !RSA_OAEP.equalsIgnoreCase(t)
        && !RSA_PKCS1.equalsIgnoreCase(t)) throw new NoSuchAlgorithmException(t);
    return new Cipher(t);
  }

  public String getAlgorithm() {
    return transformation;
  }

  public int getBlockSize() {
    return rsa ? 0 : 16;
  }

  public byte[] getIV() {
    return iv == null ? null : iv.clone();
  }

  public void init(int mode, Key key) throws InvalidKeyException {
    AlgorithmParameterSpec params = null;
    if (!rsa && mode == ENCRYPT_MODE) {
      byte[] nonce = new byte[gcm ? 12 : 16];
      new SecureRandom().nextBytes(nonce);
      params = gcm ? new GCMParameterSpec(128, nonce) : new IvParameterSpec(nonce);
    }
    try {
      init(mode, key, params);
    } catch (InvalidAlgorithmParameterException error) {
      throw new InvalidKeyException("Invalid cipher parameters", error);
    }
  }

  public void init(int mode, Key key, AlgorithmParameterSpec params)
      throws InvalidKeyException, InvalidAlgorithmParameterException {
    this.key = null;
    rsaKey = null;
    if (mode != ENCRYPT_MODE && mode != DECRYPT_MODE)
      throw new IllegalArgumentException("Unsupported cipher mode");
    if (rsa) {
      pending.reset();
      rsaInputTooLong = false;
      if (pkcs1) {
        if (mode != ENCRYPT_MODE)
          throw new InvalidKeyException("RSA PKCS#1 v1.5 supports public encryption");
        if (params != null)
          throw new InvalidAlgorithmParameterException("RSA PKCS#1 v1.5 uses no parameters");
        rsaKey = RsaCrypto.pkcs1Key(key);
      } else {
        rsaKey = oaepKey(mode, key, params);
      }
      return;
    }
    if (key == null || !"AES".equalsIgnoreCase(key.getAlgorithm()) || key.getEncoded() == null)
      throw new InvalidKeyException("RAW AES key required");
    byte[] bytes = key.getEncoded();
    if (bytes.length != 16 && bytes.length != 24 && bytes.length != 32)
      throw new InvalidKeyException("AES key length");
    byte[] nonce;
    int bits = 128;
    if (gcm) {
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

  private static RsaCrypto.BlockCipher oaepKey(int mode, Key key, AlgorithmParameterSpec params)
      throws InvalidKeyException, InvalidAlgorithmParameterException {
    if (!(params instanceof OAEPParameterSpec spec)
        || !"SHA-256".equalsIgnoreCase(spec.getDigestAlgorithm())
        || !"MGF1".equalsIgnoreCase(spec.getMGFAlgorithm())
        || !(spec.getMGFParameters() instanceof MGF1ParameterSpec mgf)
        || !"SHA-256".equalsIgnoreCase(mgf.getDigestAlgorithm())
        || !(spec.getPSource() instanceof PSource.PSpecified label))
      throw new InvalidAlgorithmParameterException("Expected SHA-256 for RSA-OAEP and MGF1");
    return RsaCrypto.oaepKey(key, mode == ENCRYPT_MODE, label.getValue());
  }

  private void requireInitialized() {
    if (key == null && rsaKey == null) throw new IllegalStateException("Cipher not initialized");
  }

  public void updateAAD(byte[] bytes) {
    requireInitialized();
    if (rsa) throw new UnsupportedOperationException("RSA does not use AES associated data");
    byte[] n = Arrays.copyOf(aad, aad.length + bytes.length);
    System.arraycopy(bytes, 0, n, aad.length, bytes.length);
    aad = n;
  }

  public byte[] doFinal(byte[] input) throws IllegalBlockSizeException, BadPaddingException {
    return doFinal(input, 0, input.length);
  }

  public int getOutputSize(int len) {
    requireInitialized();
    if (len < 0) throw new IllegalArgumentException();
    if (rsa) return rsaKey.modulusBytes();
    int total = Math.addExact(pending.size(), len);
    return mode == DECRYPT_MODE
        ? (gcm ? Math.max(0, total - tag / 8) : total)
        : (gcm ? total + tag / 8 : (total / 16 + 1) * 16);
  }

  public int update(byte[] in, int offset, int len, byte[] out, int outOffset)
      throws ShortBufferException {
    requireInitialized();
    Objects.checkFromIndexSize(offset, len, in.length);
    if (outOffset < 0 || outOffset > out.length) throw new ShortBufferException("Output offset");
    if (rsa && len > rsaKey.inputLimit() - pending.size()) {
      rsaInputTooLong = true;
      return 0;
    }
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
    requireInitialized();
    Objects.checkFromIndexSize(offset, len, input.length);
    if (rsa) return finishRsa(input, offset, len);
    if (pending.size() > 0) {
      pending.write(input, offset, len);
      input = pending.toByteArray();
      offset = 0;
      len = input.length;
    }
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

  private byte[] finishRsa(byte[] input, int offset, int len)
      throws IllegalBlockSizeException, BadPaddingException {
    try {
      if (rsaInputTooLong || len > rsaKey.inputLimit() - pending.size())
        throw new IllegalBlockSizeException("RSA input exceeds the block size");
      pending.write(input, offset, len);
      return rsaKey.process(pending.toByteArray());
    } finally {
      pending.reset();
      rsaInputTooLong = false;
    }
  }

  static String b64(byte[] b) {
    return Base64.getEncoder().encodeToString(b);
  }
}
