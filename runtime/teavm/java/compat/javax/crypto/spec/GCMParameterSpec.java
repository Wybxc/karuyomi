package javax.crypto.spec;

import java.util.*;

public class GCMParameterSpec implements java.security.spec.AlgorithmParameterSpec {
  private final byte[] iv;
  private final int bits;

  public GCMParameterSpec(int bits, byte[] iv) {
    this(bits, iv, 0, iv == null ? 0 : iv.length);
  }

  public GCMParameterSpec(int bits, byte[] iv, int offset, int len) {
    if (bits < 0 || iv == null) throw new IllegalArgumentException("GCM parameters");
    Objects.checkFromIndexSize(offset, len, iv.length);
    this.bits = bits;
    this.iv = Arrays.copyOfRange(iv, offset, offset + len);
  }

  public int getTLen() {
    return bits;
  }

  public byte[] getIV() {
    return iv.clone();
  }
}
