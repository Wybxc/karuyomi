package javax.crypto.spec;

import java.security.spec.KeySpec;
import java.util.Arrays;
import java.util.Objects;

public class PBEKeySpec implements KeySpec {
  private char[] password;
  private final byte[] salt;
  private final int iterations;
  private final int keyLength;

  public PBEKeySpec(char[] password) {
    this.password = password == null ? new char[0] : password.clone();
    salt = null;
    iterations = 0;
    keyLength = 0;
  }

  public PBEKeySpec(char[] password, byte[] salt, int iterations) {
    this(password, salt, iterations, 0, false);
  }

  public PBEKeySpec(char[] password, byte[] salt, int iterations, int keyLength) {
    this(password, salt, iterations, keyLength, true);
  }

  private PBEKeySpec(
      char[] password, byte[] salt, int iterations, int keyLength, boolean hasKeyLength) {
    Objects.requireNonNull(salt);
    if (salt.length == 0 || iterations <= 0 || (hasKeyLength && keyLength <= 0))
      throw new IllegalArgumentException("Invalid PBE parameters");
    this.password = password == null ? new char[0] : password.clone();
    this.salt = salt.clone();
    this.iterations = iterations;
    this.keyLength = keyLength;
  }

  public final void clearPassword() {
    if (password != null) {
      Arrays.fill(password, '\0');
      password = null;
    }
  }

  public final char[] getPassword() {
    if (password == null) throw new IllegalStateException("Password has been cleared");
    return password.clone();
  }

  public final byte[] getSalt() {
    return salt == null ? null : salt.clone();
  }

  public final int getIterationCount() {
    return iterations;
  }

  public final int getKeyLength() {
    return keyLength;
  }
}
