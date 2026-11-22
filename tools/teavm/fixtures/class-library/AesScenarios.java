package prototype;

import java.security.GeneralSecurityException;
import java.security.InvalidKeyException;
import java.security.InvalidAlgorithmParameterException;
import java.util.Arrays;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.IllegalBlockSizeException;
import javax.crypto.ShortBufferException;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;

final class AesScenarios {
  private static int checks;

  static void run() throws GeneralSecurityException {
    var decoder = Base64.getDecoder();
    byte[] plaintext = decoder.decode("ABEiM0RVZneImaq7zN3u/w==");
    var encrypt = Cipher.getInstance("AES/ECB/NoPadding");
    var decrypt = Cipher.getInstance("AES/ECB/NoPadding");
    // Known-answer vectors for the same single block with 128-, 192-, and 256-bit keys.
    for (String[] vector :
        new String[][] {
          {"AAECAwQFBgcICQoLDA0ODw==", "acTg2Gp7BDDYzbeAcLTFWg=="},
          {"AAECAwQFBgcICQoLDA0ODxAREhMUFRYX", "3al8pIZM3+Bur3Cg7A1xkQ=="},
          {"AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8=", "jqK3ylFnRb/q/EmQS0lgiQ=="}
        }) {
      var key = new SecretKeySpec(decoder.decode(vector[0]), "AES");
      byte[] ciphertext = decoder.decode(vector[1]);
      encrypt.init(Cipher.ENCRYPT_MODE, key);
      decrypt.init(Cipher.DECRYPT_MODE, key);
      check(encrypt.getBlockSize() == 16 && encrypt.getIV() == null, "No IV for either mode");
      check(decrypt.getIV() == null, "Decryption needs no IV");
      check(encrypt.getOutputSize(16) == 16, "No padding block in output");
      check(Arrays.equals(encrypt.doFinal(plaintext), ciphertext), "Known ciphertext");
      check(Arrays.equals(decrypt.doFinal(ciphertext), plaintext), "Known plaintext");

      byte[] out = new byte[32];
      check(decrypt.update(ciphertext, 0, 7, out, 0) == 0, "Retain a partial input block");
      check(decrypt.getOutputSize(9) == 16, "Count the partial block in final output size");
      check(Arrays.equals(decrypt.doFinal(ciphertext, 7, 9), plaintext), "Finish a split block");
      check(decrypt.doFinal(out, out.length) == 0, "An empty final call has no padding");

      byte[] inPlace = new byte[48];
      System.arraycopy(ciphertext, 0, inPlace, 0, 16);
      System.arraycopy(ciphertext, 0, inPlace, 16, 16);
      try {
        decrypt.update(inPlace, 0, 32, new byte[31], 0);
        throw new AssertionError("Short output accepted");
      } catch (ShortBufferException expected) {
        checks++;
      }
      check(decrypt.update(inPlace, 0, 32, inPlace, 8) == 32, "Overlapping input/output");
      check(Arrays.equals(Arrays.copyOfRange(inPlace, 8, 24), plaintext), "First in-place block");
      check(Arrays.equals(Arrays.copyOfRange(inPlace, 24, 40), plaintext), "Second in-place block");
      check(decrypt.doFinal(out, 0) == 0, "A complete update leaves no buffered bytes");
    }

    try {
      decrypt.doFinal(new byte[15]);
      throw new AssertionError("Partial final block accepted");
    } catch (IllegalBlockSizeException expected) {
      checks++;
    }
    var key = new SecretKeySpec(new byte[16], "AES");
    try {
      decrypt.init(Cipher.DECRYPT_MODE, key, new IvParameterSpec(new byte[16]));
      throw new AssertionError("An IV was accepted for ECB");
    } catch (InvalidAlgorithmParameterException expected) {
      checks++;
    }
    try {
      decrypt.init(Cipher.DECRYPT_MODE, new SecretKeySpec(new byte[15], "AES"));
      throw new AssertionError("Invalid key length accepted");
    } catch (InvalidKeyException expected) {
      checks++;
    }
    System.out.println("AES_ECB_SCENARIOS_PASS " + checks);
  }

  private static void check(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
    checks++;
  }
}
