package android.util;
public final class Base64 {
 public static final int DEFAULT=0,NO_PADDING=1,NO_WRAP=2,URL_SAFE=8;
 public static byte[] decode(String s,int f){return ((f&8)!=0?java.util.Base64.getUrlDecoder():java.util.Base64.getMimeDecoder()).decode(s);}
 public static byte[] decode(byte[] b,int f){return decode(new String(b,java.nio.charset.StandardCharsets.UTF_8),f);}
 public static String encodeToString(byte[] b,int f){java.util.Base64.Encoder e=(f&8)!=0?java.util.Base64.getUrlEncoder():java.util.Base64.getEncoder();if((f&1)!=0)e=e.withoutPadding();return e.encodeToString(b);}
}
