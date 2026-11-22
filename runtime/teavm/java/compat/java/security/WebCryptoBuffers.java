package java.security;

import org.teavm.jso.typedarrays.ArrayBuffer;
import org.teavm.jso.typedarrays.Uint8Array;

final class WebCryptoBuffers {
  private WebCryptoBuffers() {}

  static Uint8Array toJs(byte[] value) {
    Uint8Array array = new Uint8Array(value.length);
    for (int i = 0; i < value.length; i++) array.set(i, (short) (value[i] & 255));
    return array;
  }

  static byte[] toJava(ArrayBuffer buffer) {
    Uint8Array view = new Uint8Array(buffer);
    byte[] result = new byte[view.getByteLength()];
    for (int i = 0; i < result.length; i++) result[i] = (byte) view.get(i);
    return result;
  }
}
