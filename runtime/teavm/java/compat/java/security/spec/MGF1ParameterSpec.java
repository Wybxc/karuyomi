package java.security.spec;

import java.util.Objects;

public class MGF1ParameterSpec implements AlgorithmParameterSpec {
  public static final MGF1ParameterSpec SHA1 = new MGF1ParameterSpec("SHA-1");
  public static final MGF1ParameterSpec SHA256 = new MGF1ParameterSpec("SHA-256");
  private final String digestAlgorithm;

  public MGF1ParameterSpec(String digestAlgorithm) {
    this.digestAlgorithm = Objects.requireNonNull(digestAlgorithm);
  }

  public String getDigestAlgorithm() {
    return digestAlgorithm;
  }
}
