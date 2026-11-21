package prototype;

import java.security.GeneralSecurityException;
import java.security.KeyPairGenerator;
import java.security.spec.MGF1ParameterSpec;
import java.util.Arrays;
import javax.crypto.BadPaddingException;
import javax.crypto.Cipher;
import javax.crypto.IllegalBlockSizeException;
import javax.crypto.ShortBufferException;
import javax.crypto.spec.OAEPParameterSpec;
import javax.crypto.spec.PSource;

final class RsaScenarios {
  private static final String TRANSFORMATION = "RSA/ECB/OAEPWithSHA-256AndMGF1Padding";
  private static int checks;

  static void run() throws GeneralSecurityException {
    var generator = KeyPairGenerator.getInstance("RSA");
    generator.initialize(2048);
    var pair = generator.generateKeyPair();
    verify("RSA".equals(pair.getPublic().getAlgorithm()), "public key algorithm");
    verify("X.509".equals(pair.getPublic().getFormat()), "public key format");
    verify("PKCS#8".equals(pair.getPrivate().getFormat()), "private key format");
    verify(pair.getPublic().getEncoded()[0] == 0x30, "public key DER sequence");
    verify(pair.getPrivate().getEncoded()[0] == 0x30, "private key DER sequence");

    byte[] labelBytes = {(byte) 0x80, 0x20, 0x04};
    var label = new PSource.PSpecified(labelBytes);
    labelBytes[0] = 0x16;
    byte[] labelCopy = label.getValue();
    verify(labelCopy[0] == (byte) 0x80, "PSource constructor copies the label");
    labelCopy[0] = 0x01;
    verify(label.getValue()[0] == (byte) 0x80, "PSource returns a copy of the label");
    var parameters = new OAEPParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA256, label);
    var encrypt = Cipher.getInstance(TRANSFORMATION);
    encrypt.init(Cipher.ENCRYPT_MODE, pair.getPublic(), parameters);
    var decrypt = Cipher.getInstance(TRANSFORMATION);
    decrypt.init(Cipher.DECRYPT_MODE, pair.getPrivate(), parameters);
    verify(encrypt.getBlockSize() == 0 && encrypt.getIV() == null, "RSA has no AES block or IV");
    byte[] plaintext = new byte[190];
    for (int i = 0; i < plaintext.length; i++) plaintext[i] = (byte) i;
    byte[] ciphertext = encrypt.doFinal(plaintext);
    verify(ciphertext.length == 256, "RSA-2048 ciphertext size");
    verify(Arrays.equals(decrypt.doFinal(ciphertext), plaintext), "full OAEP plaintext round trip");

    byte[] output = new byte[256];
    verify(decrypt.update(ciphertext, 0, ciphertext.length, output, 0) == 0, "RSA buffers update");
    try {
      decrypt.doFinal(new byte[8], 0);
      throw new AssertionError("Short RSA output buffer was accepted");
    } catch (ShortBufferException expected) {
      checks++;
    }
    int size = decrypt.doFinal(output, 0);
    verify(Arrays.equals(Arrays.copyOf(output, size), plaintext), "retry with sufficient output");

    var emptyLabel =
        new OAEPParameterSpec(
            "SHA-256", "MGF1", MGF1ParameterSpec.SHA256, PSource.PSpecified.DEFAULT);
    decrypt.init(Cipher.DECRYPT_MODE, pair.getPrivate(), emptyLabel);
    try {
      decrypt.doFinal(ciphertext);
      throw new AssertionError("RSA accepted a mismatched OAEP label");
    } catch (BadPaddingException expected) {
      checks++;
    }
    try {
      encrypt.doFinal(new byte[191]);
      throw new AssertionError("Oversized RSA-OAEP plaintext was accepted");
    } catch (IllegalBlockSizeException expected) {
      checks++;
    }
    encrypt.init(Cipher.ENCRYPT_MODE, pair.getPublic(), emptyLabel);
    byte[] shortPlaintext = {1, 0, (byte) 0xff};
    verify(
        Arrays.equals(decrypt.doFinal(encrypt.doFinal(shortPlaintext)), shortPlaintext),
        "round trip with the default empty label");
    System.out.println("RSA_OAEP_SCENARIOS_PASS " + checks);
  }

  private static void verify(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
    checks++;
  }
}
