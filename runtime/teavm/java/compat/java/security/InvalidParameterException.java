package java.security;

public class InvalidParameterException extends IllegalArgumentException {
  public InvalidParameterException() {}

  public InvalidParameterException(String message) {
    super(message);
  }

  public InvalidParameterException(String message, Throwable cause) {
    super(message, cause);
  }

  public InvalidParameterException(Throwable cause) {
    super(cause);
  }
}
