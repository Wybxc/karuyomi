/*
 *  Copyright 2023 ihromant.
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */
package prototype.jcl;

import java.util.*;
import java.nio.charset.StandardCharsets;
import java.io.ByteArrayOutputStream;

/** Patch: JDK-compatible padding/validation plus MIME decoding. */
public final class Base64 {
  private Base64() {}

  public static Encoder getEncoder() {
    return new Encoder(false, true);
  }

  public static Encoder getUrlEncoder() {
    return new Encoder(true, true);
  }

  public static Decoder getDecoder() {
    return new Decoder(false, false);
  }

  public static Decoder getUrlDecoder() {
    return new Decoder(true, false);
  }

  public static Decoder getMimeDecoder() {
    return new Decoder(false, true);
  }

  public static class Encoder {
    final boolean url, padding;

    private Encoder(boolean u, boolean p) {
      url = u;
      padding = p;
    }

    public Encoder withoutPadding() {
      return new Encoder(url, false);
    }

    public String encodeToString(byte[] b) {
      String a =
          url
              ? "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
              : "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
      StringBuilder out = new StringBuilder();
      for (int i = 0; i < b.length; i += 3) {
        int n = (b[i] & 255) << 16;
        boolean second = i + 1 < b.length, third = i + 2 < b.length;
        if (second) n |= (b[i + 1] & 255) << 8;
        if (third) n |= b[i + 2] & 255;
        out.append(a.charAt(n >>> 18)).append(a.charAt((n >>> 12) & 63));
        if (second) out.append(a.charAt((n >>> 6) & 63));
        else if (padding) out.append('=');
        if (third) out.append(a.charAt(n & 63));
        else if (padding) out.append('=');
      }
      return out.toString();
    }

    public byte[] encode(byte[] b) {
      return encodeToString(b).getBytes(StandardCharsets.ISO_8859_1);
    }
  }

  public static class Decoder {
    final boolean url, mime;

    private Decoder(boolean u, boolean m) {
      url = u;
      mime = m;
    }

    int value(int c) {
      if (c >= 'A' && c <= 'Z') return c - 'A';
      if (c >= 'a' && c <= 'z') return c - 'a' + 26;
      if (c >= '0' && c <= '9') return c - '0' + 52;
      if (c == (url ? '-' : '+')) return 62;
      if (c == (url ? '_' : '/')) return 63;
      return -1;
    }

    public byte[] decode(byte[] b) {
      return decode(new String(b, StandardCharsets.ISO_8859_1));
    }

    public byte[] decode(String s) {
      ByteArrayOutputStream out = new ByteArrayOutputStream();
      int bits = 0, n = 0;
      boolean padded = false;
      for (int i = 0; i < s.length(); i++) {
        int c = s.charAt(i), v = value(c);
        if (padded) {
          if (mime && v < 0) continue;
          throw new IllegalArgumentException("Trailing Base64 data");
        }
        if (v >= 0) {
          n = (n << 6) | v;
          bits += 6;
          if (bits >= 8) {
            bits -= 8;
            out.write((n >>> bits) & 255);
          }
        } else if (c == '=') {
          // bits=4 means two sextets, bits=2 means three. A second pad must be adjacent.
          if (bits == 4) {
            if (++i >= s.length() || s.charAt(i) != '=')
              throw new IllegalArgumentException("Missing Base64 padding");
          } else if (bits != 2) throw new IllegalArgumentException("Unexpected Base64 padding");
          padded = true;
        } else if (!mime) throw new IllegalArgumentException("Illegal Base64 character");
      }
      if (!padded && bits == 6) throw new IllegalArgumentException("Incomplete Base64 unit");
      return out.toByteArray();
    }
  }
}
