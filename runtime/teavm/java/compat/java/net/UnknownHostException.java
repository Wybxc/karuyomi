package java.net;

/** Retains the checked DNS failure type used by Source interceptors. */
public class UnknownHostException extends java.io.IOException {
  public UnknownHostException() {}

  public UnknownHostException(String message) {
    super(message);
  }
}
