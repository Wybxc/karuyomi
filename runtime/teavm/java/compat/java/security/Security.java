package java.security;

import java.util.Objects;

/** Security properties set by the Worker host for its fixed providers. */
public final class Security {
  private Security() {}

  public static String getProperty(String name) {
    return switch (Objects.requireNonNull(name)) {
      case "org.bouncycastle.rsa.allow_unsafe_mod", "org.bouncycastle.pkcs1.not_strict" -> "false";
      case "include" -> throw new IllegalArgumentException("Reserved security property");
      default -> null;
    };
  }
}
