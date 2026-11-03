package javax.crypto;

import java.security.*;
import java.util.*;
import com.google.gson.*;
import prototype.Bridge;

public class Mac {
  private byte[] key;
  private final java.io.ByteArrayOutputStream pending = new java.io.ByteArrayOutputStream();

  public static Mac getInstance(String algorithm) throws NoSuchAlgorithmException {
    if (!"HmacSHA256".equalsIgnoreCase(algorithm)) throw new NoSuchAlgorithmException(algorithm);
    return new Mac();
  }

  public String getAlgorithm() {
    return "HmacSHA256";
  }

  public int getMacLength() {
    return 32;
  }

  public void init(Key key) throws InvalidKeyException {
    if (key == null || key.getEncoded() == null || key.getEncoded().length == 0)
      throw new InvalidKeyException("RAW key required");
    this.key = key.getEncoded().clone();
    reset();
  }

  public void reset() {
    pending.reset();
  }

  public void update(byte[] b) {
    update(b, 0, b.length);
  }

  public void update(byte b) {
    if (key == null) throw new IllegalStateException("Mac not initialized");
    pending.write(b);
  }

  public void update(byte[] b, int off, int len) {
    if (key == null) throw new IllegalStateException("Mac not initialized");
    pending.write(b, off, len);
  }

  public byte[] doFinal(byte[] bytes) {
    update(bytes);
    return doFinal();
  }

  public byte[] doFinal() {
    if (key == null) throw new IllegalStateException("Mac not initialized");
    JsonObject r = new JsonObject();
    r.addProperty("algorithm", "HMAC");
    r.addProperty("key", Base64.getEncoder().encodeToString(key));
    r.addProperty("body", Base64.getEncoder().encodeToString(pending.toByteArray()));
    JsonObject out = JsonParser.parseString(Bridge.crypto(r.toString())).getAsJsonObject();
    if (out.has("error")) throw new IllegalStateException(out.get("error").getAsString());
    reset();
    return Base64.getDecoder().decode(out.get("body").getAsString());
  }
}
