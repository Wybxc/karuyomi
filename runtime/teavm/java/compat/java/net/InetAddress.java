package java.net;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonParser;
import java.io.IOException;
import java.io.Serializable;
import java.util.Arrays;
import java.util.StringJoiner;
import prototype.Bridge;

/** Address values used by OkHttp's DNS contract in the TeaVM Source host. */
public class InetAddress implements Serializable {
  private final String host;
  private final byte[] address;

  InetAddress(String host, byte[] address) {
    this.host = host;
    this.address = address.clone();
  }

  public static InetAddress getByName(String host) throws UnknownHostException {
    return getAllByName(host)[0];
  }

  public static InetAddress[] getAllByName(String host) throws UnknownHostException {
    if (host == null || host.isEmpty()) return new InetAddress[] {getLoopbackAddress()};
    try {
      JsonArray result = JsonParser.parseString(Bridge.resolveDns(host)).getAsJsonArray();
      if (result.size() == 0 || result.size() > 16)
        throw new IOException("Invalid DNS result size");
      InetAddress[] addresses = new InetAddress[result.size()];
      int index = 0;
      for (JsonElement value : result) {
        JsonArray octets = value.getAsJsonArray();
        if (octets.size() != 4 && octets.size() != 16)
          throw new IOException("Invalid DNS address length");
        byte[] bytes = new byte[octets.size()];
        for (int byteIndex = 0; byteIndex < bytes.length; byteIndex++) {
          int octet = octets.get(byteIndex).getAsInt();
          if (octet < 0 || octet > 255) throw new IOException("Invalid DNS address byte");
          bytes[byteIndex] = (byte) octet;
        }
        addresses[index++] = getByAddress(host, bytes);
      }
      return addresses;
    } catch (IOException | RuntimeException failure) {
      UnknownHostException error = new UnknownHostException(host);
      error.initCause(failure);
      throw error;
    }
  }

  public static InetAddress getByAddress(byte[] address) throws UnknownHostException {
    return getByAddress(null, address);
  }

  public static InetAddress getByAddress(String host, byte[] address) throws UnknownHostException {
    if (address != null && address.length == 4) return new Inet4Address(host, address);
    if (address != null && address.length == 16) {
      boolean mapped = address[10] == (byte) 255 && address[11] == (byte) 255;
      for (int i = 0; mapped && i < 10; i++) mapped = address[i] == 0;
      if (mapped) return new Inet4Address(host, Arrays.copyOfRange(address, 12, 16));
      return new Inet6Address(host, address);
    }
    throw new UnknownHostException("Invalid IP address length");
  }

  public static InetAddress getLoopbackAddress() {
    return new Inet4Address("localhost", new byte[] {127, 0, 0, 1});
  }

  public byte[] getAddress() {
    return address.clone();
  }

  public String getHostAddress() {
    if (address.length == 4) {
      StringJoiner result = new StringJoiner(".");
      for (byte octet : address) result.add(Integer.toString(octet & 255));
      return result.toString();
    }
    StringJoiner result = new StringJoiner(":");
    for (int i = 0; i < address.length; i += 2)
      result.add(Integer.toHexString((address[i] & 255) << 8 | (address[i + 1] & 255)));
    return result.toString();
  }

  public String getHostName() {
    return host == null ? getHostAddress() : host;
  }

  @Override
  public boolean equals(Object other) {
    return other instanceof InetAddress value && Arrays.equals(address, value.address);
  }

  @Override
  public int hashCode() {
    return Arrays.hashCode(address);
  }

  @Override
  public String toString() {
    return (host == null ? "" : host) + "/" + getHostAddress();
  }
}
