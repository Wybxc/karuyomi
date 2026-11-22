package javax.crypto.spec;

import java.security.spec.AlgorithmParameterSpec;
import java.security.spec.MGF1ParameterSpec;
import java.util.Objects;

public class OAEPParameterSpec implements AlgorithmParameterSpec {
  public static final OAEPParameterSpec DEFAULT =
      new OAEPParameterSpec("SHA-1", "MGF1", MGF1ParameterSpec.SHA1, PSource.PSpecified.DEFAULT);

  private final String digestAlgorithm;
  private final String mgfAlgorithm;
  private final AlgorithmParameterSpec mgfParameters;
  private final PSource pSource;

  public OAEPParameterSpec(
      String digestAlgorithm,
      String mgfAlgorithm,
      AlgorithmParameterSpec mgfParameters,
      PSource pSource) {
    this.digestAlgorithm = Objects.requireNonNull(digestAlgorithm);
    this.mgfAlgorithm = Objects.requireNonNull(mgfAlgorithm);
    this.mgfParameters = mgfParameters;
    this.pSource = Objects.requireNonNull(pSource);
  }

  public String getDigestAlgorithm() {
    return digestAlgorithm;
  }

  public String getMGFAlgorithm() {
    return mgfAlgorithm;
  }

  public AlgorithmParameterSpec getMGFParameters() {
    return mgfParameters;
  }

  public PSource getPSource() {
    return pSource;
  }
}
