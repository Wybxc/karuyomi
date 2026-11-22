package prototype;

import java.security.GeneralSecurityException;
import java.security.InvalidKeyException;
import java.security.KeyFactory;
import java.security.KeyPairGenerator;
import java.security.spec.MGF1ParameterSpec;
import java.security.spec.InvalidKeySpecException;
import java.security.spec.X509EncodedKeySpec;
import java.util.Arrays;
import java.util.Base64;
import javax.crypto.BadPaddingException;
import javax.crypto.Cipher;
import javax.crypto.IllegalBlockSizeException;
import javax.crypto.ShortBufferException;
import javax.crypto.spec.OAEPParameterSpec;
import javax.crypto.spec.PSource;
import javax.crypto.spec.SecretKeySpec;

final class RsaScenarios {
  private static final String TRANSFORMATION = "RSA/ECB/OAEPWithSHA-256AndMGF1Padding";
  private static final String PKCS1 = "RSA/ECB/PKCS1Padding";
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
    runPublicEncryption(pair.getPublic().getEncoded());
  }

  private static void runPublicEncryption(byte[] spki) throws GeneralSecurityException {
    checks = 0;
    var factory = KeyFactory.getInstance("RSA");
    var publicKey = factory.generatePublic(new X509EncodedKeySpec(spki));
    verify(Arrays.equals(spki, publicKey.getEncoded()), "RSA X.509 import");
    var cipher = Cipher.getInstance(PKCS1);
    cipher.init(Cipher.ENCRYPT_MODE, publicKey);
    verify(cipher.getBlockSize() == 0 && cipher.getIV() == null, "RSA has no AES block or IV");
    verify(cipher.getOutputSize(245) == 256, "RSA size is determined by the modulus");
    byte[] plaintext = new byte[245];
    byte[] first = cipher.doFinal(plaintext);
    verify(first.length == 256, "PKCS#1 v1.5 exact input limit");
    verify(
        !Arrays.equals(first, cipher.doFinal(plaintext)), "RSA encryption uses fresh randomness");
    try {
      cipher.doFinal(new byte[246]);
      throw new AssertionError("Oversized PKCS#1 v1.5 plaintext was accepted");
    } catch (IllegalBlockSizeException expected) {
      checks++;
    }
    cipher.init(Cipher.ENCRYPT_MODE, publicKey);
    verify(
        cipher.doFinal(new byte[0]).length == 256, "RSA can be reinitialized after a size error");
    try {
      factory.generatePublic(new X509EncodedKeySpec(new byte[] {0x30, 0}));
      throw new AssertionError("Invalid X.509 encoding was accepted");
    } catch (InvalidKeySpecException expected) {
      checks++;
    }
    try {
      cipher.init(Cipher.ENCRYPT_MODE, new SecretKeySpec(new byte[16], "AES"));
      throw new AssertionError("A symmetric key was accepted for RSA");
    } catch (InvalidKeyException expected) {
      checks++;
    }
    var key = new SecretKeySpec(new byte[16], "AES");
    var cbc = Cipher.getInstance("AES/CBC/PKCS5Padding");
    cbc.init(Cipher.ENCRYPT_MODE, key);
    verify(cbc.getIV().length == 16, "CBC init creates a sixteen-byte IV");
    var gcm = Cipher.getInstance("AES/GCM/NoPadding");
    gcm.init(Cipher.ENCRYPT_MODE, key);
    verify(gcm.getIV().length == 12, "GCM init creates a twelve-byte nonce");
    verify(gcm.getOutputSize(0) == 16, "GCM init sets a 128-bit tag");
    try {
      cbc.init(Cipher.DECRYPT_MODE, key);
      throw new AssertionError("CBC decryption without an IV succeeded");
    } catch (InvalidKeyException expected) {
      checks++;
    }
    System.out.println("RSA_PKCS1_SCENARIOS_PASS " + checks);
  }

  static byte[] publicEncryptionPlaintext() {
    return new byte[] {17, 0, (byte) 0xa5, 31, 8};
  }

  static void emitPublicEncryption(String publicKey) throws GeneralSecurityException {
    byte[] spki = Base64.getDecoder().decode(publicKey);
    var key = KeyFactory.getInstance("RSA").generatePublic(new X509EncodedKeySpec(spki));
    var cipher = Cipher.getInstance(PKCS1);
    cipher.init(Cipher.ENCRYPT_MODE, key);
    System.out.println(
        "RSA_PKCS1_CIPHERTEXT "
            + Base64.getEncoder().encodeToString(cipher.doFinal(publicEncryptionPlaintext())));
  }

  private static void verify(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
    checks++;
  }
}
