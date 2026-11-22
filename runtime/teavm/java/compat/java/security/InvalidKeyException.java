package java.security;

public class InvalidKeyException extends java.security.GeneralSecurityException {
  public InvalidKeyException() {}

  public InvalidKeyException(String s) {
    super(s);
  }

  public InvalidKeyException(String message, Throwable cause) {
    super(message, cause);
  }
}
