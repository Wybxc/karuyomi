package java.security;

public class SignatureException extends GeneralSecurityException {
  public SignatureException(String message) {
    super(message);
  }

  public SignatureException(String message, Throwable cause) {
    super(message, cause);
  }
}
