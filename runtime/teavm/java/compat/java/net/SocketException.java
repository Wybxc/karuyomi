package java.net;

/** Java socket exception type retained for unchanged plugin catch clauses. */
public class SocketException extends java.io.IOException {
  public SocketException() {}

  public SocketException(String message) {
    super(message);
  }
}
