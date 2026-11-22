package prototype;

import java.security.NoSuchAlgorithmException;
import java.security.spec.InvalidKeySpecException;
import javax.crypto.SecretKey;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;

final class Pbkdf2Scenarios {
  private static int checks;

  static void run() throws NoSuchAlgorithmException, InvalidKeySpecException {
    char[] password = "référence 世界 🎵".toCharArray();
    byte[] salt = {0, 32, 1, -2, 5};
    PBEKeySpec spec = new PBEKeySpec(password, salt, 2048, 130);
    password[0] = '?';
    salt[0] = 6;
    spec.getPassword()[0] = '!';
    spec.getSalt()[0] = 9;
    require(spec.getPassword()[0] == 'r' && spec.getSalt()[0] == 0, "copied PBE inputs");
    require(spec.getIterationCount() == 2048 && spec.getKeyLength() == 130, "PBE parameters");

    String sha256 = "PBKDF2WithHmacSHA256";
    String sha512 = "PBKDF2WithHmacSHA512";
    SecretKey first = SecretKeyFactory.getInstance(sha256).generateSecret(spec);
    require(first.getAlgorithm().equals(sha256) && first.getFormat().equals("RAW"), "key identity");
    byte[] available = first.getEncoded();
    require(available.length == 16, "length follows the Java provider's byte units");
    available[0] ^= 1;
    require(available[0] != first.getEncoded()[0], "the secret keeps its own encoded bytes");
    spec.clearPassword();
    try {
      spec.getPassword();
      throw new AssertionError("cleared password could still be read");
    } catch (IllegalStateException expected) {
      checks++;
    }

    PBEKeySpec empty = new PBEKeySpec(null, new byte[] {7, 8, 9}, 17, 520);
    SecretKey second = SecretKeyFactory.getInstance(sha512).generateSecret(empty);
    require(
        second.getAlgorithm().equals(sha512) && second.getEncoded().length == 65,
        "empty password and multi-block output");
    empty.clearPassword();
    try {
      SecretKeyFactory.getInstance(sha256).generateSecret(new PBEKeySpec(new char[0]));
      throw new AssertionError("a specification without salt was accepted");
    } catch (InvalidKeySpecException expected) {
      checks++;
    }
    System.out.println(
        "PBKDF2_SCENARIOS_PASS "
            + checks
            + " "
            + DigestScenarios.hex(first.getEncoded())
            + " "
            + DigestScenarios.hex(second.getEncoded()));
  }

  private static void require(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
    checks++;
  }
}
