package javax.crypto.spec;

import java.util.Objects;

public class PSource {
  private final String algorithm;

  protected PSource(String algorithm) {
    this.algorithm = Objects.requireNonNull(algorithm);
  }

  public String getAlgorithm() {
    return algorithm;
  }

  public static final class PSpecified extends PSource {
    public static final PSpecified DEFAULT = new PSpecified(new byte[0]);
    private final byte[] value;

    public PSpecified(byte[] value) {
      super("PSpecified");
      this.value = value.clone();
    }

    public byte[] getValue() {
      return value.clone();
    }
  }
}
