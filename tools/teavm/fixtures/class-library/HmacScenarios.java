package prototype;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

final class HmacScenarios {
  private static int checks;

  static void run() throws GeneralSecurityException {
    // RFC 4231 cases 1 and 6, including keys longer than either digest's block.
    verify(
        "HmacSHA256",
        "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
        "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54");
    verify(
        "HmacSHA512",
        "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cde"
            + "daa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854",
        "80b24263c7c1a3ebb71493c1dd7be8b49b46d1f41b4aeec1121b013783f8f3526b"
            + "56d037e05f2598bd0fd2215d6a1e5295e64f73f63f0aec8b915a985d786598");
    try {
      Mac.getInstance("UnknownMac");
      throw new AssertionError("Unsupported algorithm accepted");
    } catch (NoSuchAlgorithmException expected) {
      checks++;
    }
    System.out.println("HMAC_SCENARIOS_PASS " + checks);
  }

  private static void verify(String algorithm, String shortExpected, String longExpected)
      throws GeneralSecurityException {
    var mac = Mac.getInstance(algorithm);
    byte[] message = "Hi There".getBytes(StandardCharsets.US_ASCII);
    check(mac.getAlgorithm().equals(algorithm), "Algorithm name changed");
    check(mac.getMacLength() == shortExpected.length() / 2, "MAC width changed");
    try {
      mac.update(message);
      throw new AssertionError("An uninitialized MAC accepted data");
    } catch (IllegalStateException expected) {
      checks++;
    }
    try {
      mac.init(null);
      throw new AssertionError("A null key was accepted");
    } catch (InvalidKeyException expected) {
      checks++;
    }
    mac.init(key(algorithm, 20, (byte) 0x0b));
    check(Arrays.equals(mac.doFinal(message), decode(shortExpected)), "Known-answer MAC");
    byte[] padded = "xHi Therey".getBytes(StandardCharsets.US_ASCII);
    mac.update(padded[1]);
    mac.update(padded, 2, 4);
    mac.update(padded, 6, 3);
    check(Arrays.equals(mac.doFinal(), decode(shortExpected)), "Segmented MAC");
    mac.update(padded);
    mac.reset();
    check(Arrays.equals(mac.doFinal(message), decode(shortExpected)), "Reset retains the key");

    mac.init(key(algorithm, 131, (byte) 0xaa));
    byte[] longMessage =
        "Test Using Larger Than Block-Size Key - Hash Key First"
            .getBytes(StandardCharsets.US_ASCII);
    check(Arrays.equals(mac.doFinal(longMessage), decode(longExpected)), "Rekey and long key");
  }

  private static SecretKeySpec key(String algorithm, int length, byte value) {
    byte[] bytes = new byte[length];
    Arrays.fill(bytes, value);
    return new SecretKeySpec(bytes, algorithm);
  }

  private static byte[] decode(String hex) {
    byte[] bytes = new byte[hex.length() / 2];
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = (byte) Integer.parseInt(hex.substring(i * 2, i * 2 + 2), 16);
    }
    return bytes;
  }

  private static void check(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
    checks++;
  }
}
