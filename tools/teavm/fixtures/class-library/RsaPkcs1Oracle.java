package prototype;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.Arrays;
import java.util.Base64;
import javax.crypto.Cipher;

/** Decrypts a locally generated fixture using the stock JDK provider. */
public final class RsaPkcs1Oracle {
  public static void main(String[] args) throws Exception {
    try (var input =
        new BufferedReader(new InputStreamReader(System.in, StandardCharsets.US_ASCII))) {
      var base64 = Base64.getDecoder();
      var spec = new PKCS8EncodedKeySpec(base64.decode(input.readLine()));
      var key = KeyFactory.getInstance("RSA").generatePrivate(spec);
      var cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding");
      cipher.init(Cipher.DECRYPT_MODE, key);
      byte[] plaintext = cipher.doFinal(base64.decode(input.readLine()));
      if (!Arrays.equals(plaintext, RsaScenarios.publicEncryptionPlaintext()))
        throw new AssertionError("JDK decrypted a different plaintext");
      System.out.print("RSA_PKCS1_INTEROP_VERIFIED");
    }
  }
}
