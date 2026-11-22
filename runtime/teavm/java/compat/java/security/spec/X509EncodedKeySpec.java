package java.security.spec;

public class X509EncodedKeySpec extends EncodedKeySpec {
  public X509EncodedKeySpec(byte[] encoded) {
    super(encoded);
  }

  public final String getFormat() {
    return "X.509";
  }
}
