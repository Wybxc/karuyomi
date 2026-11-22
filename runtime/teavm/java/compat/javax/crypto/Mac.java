package javax.crypto;

import java.security.InvalidKeyException;
import java.security.Key;
import java.security.NoSuchAlgorithmException;
import java.util.Objects;
import org.bouncycastle.crypto.Digest;
import org.bouncycastle.crypto.digests.SHA256Digest;
import org.bouncycastle.crypto.digests.SHA512Digest;
import org.bouncycastle.crypto.macs.HMac;
import org.bouncycastle.crypto.params.KeyParameter;

public class Mac {
  private final String algorithm;
  private final HMac mac;
  private boolean initialized;

  private Mac(String algorithm, Digest digest) {
    this.algorithm = algorithm;
    mac = new HMac(digest);
  }

  public static Mac getInstance(String algorithm) throws NoSuchAlgorithmException {
    if ("HmacSHA256".equalsIgnoreCase(algorithm)) return new Mac("HmacSHA256", new SHA256Digest());
    if ("HmacSHA512".equalsIgnoreCase(algorithm)) return new Mac("HmacSHA512", new SHA512Digest());
    throw new NoSuchAlgorithmException(algorithm);
  }

  public String getAlgorithm() {
    return algorithm;
  }

  public int getMacLength() {
    return mac.getMacSize();
  }

  public void init(Key key) throws InvalidKeyException {
    byte[] raw = key == null ? null : key.getEncoded();
    if (raw == null || raw.length == 0) throw new InvalidKeyException("RAW key required");
    mac.init(new KeyParameter(raw));
    initialized = true;
  }

  public void reset() {
    if (initialized) mac.reset();
  }

  public void update(byte[] input) {
    update(input, 0, input.length);
  }

  public void update(byte input) {
    requireInitialized();
    mac.update(input);
  }

  public void update(byte[] input, int offset, int length) {
    requireInitialized();
    Objects.checkFromIndexSize(offset, length, input.length);
    mac.update(input, offset, length);
  }

  public byte[] doFinal(byte[] bytes) {
    update(bytes);
    return doFinal();
  }

  public byte[] doFinal() {
    requireInitialized();
    byte[] output = new byte[getMacLength()];
    mac.doFinal(output, 0);
    return output;
  }

  private void requireInitialized() {
    if (!initialized) throw new IllegalStateException("Mac not initialized");
  }
}
