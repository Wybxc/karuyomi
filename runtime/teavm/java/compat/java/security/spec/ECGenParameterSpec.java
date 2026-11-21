package java.security.spec;

import java.util.Objects;

public class ECGenParameterSpec implements AlgorithmParameterSpec {
  private final String name;

  public ECGenParameterSpec(String name) {
    this.name = Objects.requireNonNull(name);
  }

  public String getName() {
    return name;
  }
}
