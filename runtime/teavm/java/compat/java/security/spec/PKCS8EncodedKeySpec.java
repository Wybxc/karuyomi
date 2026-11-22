package java.security.spec;

public class PKCS8EncodedKeySpec extends EncodedKeySpec {
  public PKCS8EncodedKeySpec(byte[] encoded) {
    super(encoded);
  }

  public final String getFormat() {
    return "PKCS#8";
  }
}
