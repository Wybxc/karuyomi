package java.security.spec;

import java.security.GeneralSecurityException;

public class InvalidParameterSpecException extends GeneralSecurityException {
  public InvalidParameterSpecException(String message) {
    super(message);
  }
}
