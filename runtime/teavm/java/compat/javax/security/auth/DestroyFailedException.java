package javax.security.auth;

public class DestroyFailedException extends Exception {
  public DestroyFailedException() {}

  public DestroyFailedException(String message) {
    super(message);
  }
}
