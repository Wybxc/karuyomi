package java.security;

import java.security.spec.AlgorithmParameterSpec;
import java.security.spec.InvalidParameterSpecException;
import java.util.Objects;

public class AlgorithmParameters {
  private boolean initialized;

  private AlgorithmParameters() {}

  public static AlgorithmParameters getInstance(String algorithm) throws NoSuchAlgorithmException {
    if (!Objects.requireNonNull(algorithm).equalsIgnoreCase("EC"))
      throw new NoSuchAlgorithmException(algorithm);
    return new AlgorithmParameters();
  }

  public final void init(AlgorithmParameterSpec params) throws InvalidParameterSpecException {
    if (initialized) throw new InvalidParameterSpecException("Parameters are already initialized");
    if (!EcCrypto.supports(params))
      throw new InvalidParameterSpecException("Expected P-256 parameters");
    initialized = true;
  }

  public final <T extends AlgorithmParameterSpec> T getParameterSpec(Class<T> type)
      throws InvalidParameterSpecException {
    if (!initialized || !type.isInstance(EcCrypto.PARAMETERS))
      throw new InvalidParameterSpecException("P-256 parameters are unavailable for this type");
    return type.cast(EcCrypto.PARAMETERS);
  }
}
