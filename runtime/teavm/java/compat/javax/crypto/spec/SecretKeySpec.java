package javax.crypto.spec;

import java.util.*;
import javax.crypto.SecretKey;

public class SecretKeySpec implements SecretKey, java.security.spec.KeySpec {
  private final byte[] key;
  private final String algorithm;

  public SecretKeySpec(byte[] key, String algorithm) {
    this(key, 0, key == null ? 0 : key.length, algorithm);
  }

  public SecretKeySpec(byte[] key, int offset, int len, String algorithm) {
    if (key == null || algorithm == null || key.length == 0 || len <= 0)
      throw new IllegalArgumentException("Empty key or algorithm");
    java.util.Objects.checkFromIndexSize(offset, len, key.length);
    this.key = Arrays.copyOfRange(key, offset, offset + len);
    this.algorithm = algorithm;
  }

  public String getAlgorithm() {
    return algorithm;
  }

  public String getFormat() {
    return "RAW";
  }

  public byte[] getEncoded() {
    return key.clone();
  }

  public boolean equals(Object o) {
    return o instanceof SecretKey
        && algorithm.equalsIgnoreCase(((SecretKey) o).getAlgorithm())
        && Arrays.equals(key, ((SecretKey) o).getEncoded());
  }

  public int hashCode() {
    return Arrays.hashCode(key) ^ algorithm.toLowerCase(Locale.ROOT).hashCode();
  }
}
