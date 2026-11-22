package prototype;

import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.AlgorithmParameters;
import java.security.GeneralSecurityException;
import java.security.InvalidKeyException;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Signature;
import java.security.SignatureException;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECFieldFp;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.ECParameterSpec;
import java.security.spec.ECPoint;
import java.security.spec.ECPublicKeySpec;
import java.security.spec.InvalidKeySpecException;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Arrays;
import javax.crypto.KeyAgreement;

final class EcScenarios {
  private static final String EC = "EC";
  private static final String ECDSA = "SHA256withECDSA";
  private static final ECGenParameterSpec CURVE = new ECGenParameterSpec("secp256r1");
  private static final byte[] MESSAGE =
      "cross-runtime signature fixture".getBytes(StandardCharsets.UTF_8);
  private static int checks;

  static void run() throws GeneralSecurityException {
    KeyFactory keys = KeyFactory.getInstance(EC);
    AlgorithmParameters parameters = AlgorithmParameters.getInstance(EC);
    parameters.init(CURVE);
    ECParameterSpec spec = parameters.getParameterSpec(ECParameterSpec.class);
    require(spec.getCofactor() == 1 && spec.getOrder().bitLength() == 256, "P-256 domain order");
    require(((ECFieldFp) spec.getCurve().getField()).getP().bitLength() == 256, "prime field size");

    // RFC 6979 Appendix A.2.5, P-256 with SHA-256, using only the public key and signature.
    ECPoint point =
        new ECPoint(
            new BigInteger("60FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6", 16),
            new BigInteger("7903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299", 16));
    var publicKey = (ECPublicKey) keys.generatePublic(new ECPublicKeySpec(point, spec));
    require(publicKey.getW().equals(point), "public point round trip");
    var verifier = Signature.getInstance(ECDSA);
    verifier.initVerify(publicKey);
    verifier.update("sample".getBytes(StandardCharsets.UTF_8));
    require(
        verifier.verify(
            decode(
                "3046022100EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716"
                    + "022100F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8")),
        "published ECDSA vector");

    KeyPair pair = keyPair();
    require("PKCS#8".equals(pair.getPrivate().getFormat()), "private encoding format");
    require("X.509".equals(pair.getPublic().getFormat()), "public encoding format");
    var privateSpec = new PKCS8EncodedKeySpec(pair.getPrivate().getEncoded());
    byte[] copy = privateSpec.getEncoded();
    copy[0] ^= 1;
    require(copy[0] != privateSpec.getEncoded()[0], "encoded key specs copy bytes");
    var signer = Signature.getInstance(ECDSA);
    signer.initSign(keys.generatePrivate(privateSpec));
    signer.update(MESSAGE[0]);
    signer.update(MESSAGE, 1, MESSAGE.length - 1);
    byte[] signed = signer.sign();
    verifier.initVerify(keys.generatePublic(new X509EncodedKeySpec(pair.getPublic().getEncoded())));
    verifier.update(MESSAGE);
    require(verifier.verify(signed), "encoded key restoration and split signature input");
    verifier.update((byte) 0);
    require(!verifier.verify(signed), "verification rejects a different message");
    verifier.update(MESSAGE);
    require(verifier.verify(signed), "verify resets the previous message");
    try {
      verifier.verify(new byte[] {0x30, 1, 0});
      throw new AssertionError("Malformed DER was accepted");
    } catch (SignatureException expected) {
      checks++;
    }
    try {
      keys.generatePrivate(new PKCS8EncodedKeySpec(new byte[] {0x30, 1, 0}));
      throw new AssertionError("Malformed PKCS#8 was accepted");
    } catch (InvalidKeySpecException expected) {
      checks++;
    }
    agreement(keys, spec);
    System.out.println("EC_SCENARIOS_PASS " + checks);
  }

  private static void agreement(KeyFactory keys, ECParameterSpec spec)
      throws GeneralSecurityException {
    // RFC 5903 Section 8.1 publishes both test keys and the expected shared secret.
    var localKey =
        keys.generatePrivate(
            new PKCS8EncodedKeySpec(
                decode(
                    "3041020100301306072A8648CE3D020106082A8648CE3D030107042730250201010420"
                        + "C88F01F510D9AC3F70A292DAA2316DE544E9AAB8AFE84049C62A9C57862D1433")));
    var peerPoint =
        new ECPoint(
            new BigInteger("D12DFB5289C8D4F81208B70270398C342296970A0BCCB74C736FC7554494BF63", 16),
            new BigInteger("56FBF3CA366CC23E8157854C13C58D6AAC23F046ADA30F8353E74F33039872AB", 16));
    var peerKey = keys.generatePublic(new ECPublicKeySpec(peerPoint, spec));
    byte[] expected = decode("D6840F6B42F6EDAFD13116E0E12565202FEF8E9ECE7DCE03812464D04B9442DE");

    var agreement = KeyAgreement.getInstance("ECDH");
    agreement.init(localKey);
    try {
      agreement.doPhase(localKey, true);
      throw new AssertionError("An ECDH peer private key was accepted");
    } catch (InvalidKeyException rejected) {
      checks++;
    }
    try {
      agreement.doPhase(peerKey, false);
      throw new AssertionError("An intermediate ECDH phase was accepted");
    } catch (IllegalStateException rejected) {
      checks++;
    }
    require(agreement.doPhase(peerKey, true) == null, "the final phase emits no key");
    require(Arrays.equals(agreement.generateSecret(), expected), "published ECDH vector");
    try {
      agreement.generateSecret();
      throw new AssertionError("ECDH peer phase was reused");
    } catch (IllegalStateException reset) {
      checks++;
    }
    agreement.doPhase(peerKey, true);
    require(
        Arrays.equals(agreement.generateSecret(), expected),
        "an initialized ECDH key can be reused");
  }

  static void interop(String[] args) throws GeneralSecurityException {
    var signer = Signature.getInstance(ECDSA);
    if (args.length == 1 && "emit-ec-signature".equals(args[0])) {
      KeyPair pair = keyPair();
      signer.initSign(pair.getPrivate());
      signer.update(MESSAGE);
      System.out.println(
          "EC_INTEROP "
              + DigestScenarios.hex(pair.getPublic().getEncoded())
              + " "
              + DigestScenarios.hex(signer.sign()));
      return;
    }
    if (args.length == 3 && "verify-ec-signature".equals(args[0])) {
      var publicKey =
          KeyFactory.getInstance(EC).generatePublic(new X509EncodedKeySpec(decode(args[1])));
      signer.initVerify(publicKey);
      signer.update(MESSAGE);
      require(signer.verify(decode(args[2])), "independent runtime accepts the signature");
      System.out.println("EC_INTEROP_VERIFIED");
      return;
    }
    throw new IllegalArgumentException("Unknown EC fixture invocation");
  }

  private static KeyPair keyPair() throws GeneralSecurityException {
    var generator = KeyPairGenerator.getInstance(EC);
    generator.initialize(CURVE);
    return generator.generateKeyPair();
  }

  private static byte[] decode(String hex) {
    byte[] bytes = new byte[hex.length() / 2];
    for (int i = 0; i < bytes.length; i++)
      bytes[i] = (byte) Integer.parseInt(hex.substring(2 * i, 2 * i + 2), 16);
    return bytes;
  }

  private static void require(boolean condition, String message) {
    if (!condition) throw new AssertionError(message);
    checks++;
  }
}
