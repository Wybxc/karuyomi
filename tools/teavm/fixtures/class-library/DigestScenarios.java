package prototype;

import java.io.ByteArrayOutputStream;
import java.security.InvalidParameterException;
import java.security.MessageDigest;
import java.security.MessageDigestSpi;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;

final class DigestScenarios {
  private static int checks;

  static void run() throws NoSuchAlgorithmException {
    MessageDigest fixture = new FixtureDigest();
    require(fixture instanceof MessageDigestSpi, "a digest retains its provider SPI type");
    require(fixture.getAlgorithm().equals("Fixture"), "the constructor retains the provider name");
    fixture.update((byte) 1);
    fixture.update(new byte[] {9, 2, 3, 9}, 1, 2);
    require(
        Arrays.equals(fixture.digest(new byte[] {4}), new byte[] {1, 2, 3, 4}),
        "public update and digest calls reach the provider hooks");
    require(fixture.digest().length == 0, "the provider can reset on digest");
    fixture.update((byte) 7);
    fixture.reset();
    require(fixture.digest().length == 0, "reset reaches the provider hook");
    try {
      new FixtureDigest("unknown");
      throw new AssertionError("invalid provider parameter was accepted");
    } catch (IllegalArgumentException expected) {
      require(
          expected instanceof InvalidParameterException && "unknown".equals(expected.getMessage()),
          "the provider can signal an invalid parameter");
    }

    checkBuiltIn("MD5", "900150983cd24fb0d6963f7d28e17f72", "d41d8cd98f00b204e9800998ecf8427e");
    checkBuiltIn(
        "SHA-256",
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    System.out.println("DIGEST_SCENARIOS_PASS " + checks);
  }

  private static void checkBuiltIn(String algorithm, String abc, String empty)
      throws NoSuchAlgorithmException {
    MessageDigest digest = MessageDigest.getInstance(algorithm);
    digest.update((byte) 'a');
    digest.update(new byte[] {'x', 'b', 'c', 'x'}, 1, 2);
    require(hex(digest.digest()).equals(abc), algorithm + " keeps its standard digest");
    require(hex(digest.digest()).equals(empty), algorithm + " resets its buffered input");
  }

  static String hex(byte[] bytes) {
    StringBuilder result = new StringBuilder();
    for (byte value : bytes) {
      result.append(Character.forDigit((value >>> 4) & 15, 16));
      result.append(Character.forDigit(value & 15, 16));
    }
    return result.toString();
  }

  private static void require(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
    checks++;
  }

  private static final class FixtureDigest extends MessageDigest {
    private final ByteArrayOutputStream data = new ByteArrayOutputStream();

    FixtureDigest() {
      this("Fixture");
    }

    FixtureDigest(String name) {
      super(name);
      if (!"Fixture".equals(name)) throw new InvalidParameterException(name);
    }

    protected void engineUpdate(byte value) {
      data.write(value);
    }

    protected void engineUpdate(byte[] values, int offset, int length) {
      data.write(values, offset, length);
    }

    protected byte[] engineDigest() {
      byte[] result = data.toByteArray();
      engineReset();
      return result;
    }

    protected void engineReset() {
      data.reset();
    }
  }
}
