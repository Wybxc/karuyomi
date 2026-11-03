package android.graphics;
import java.io.*;import java.util.*;import com.google.gson.*;import prototype.Graphics;
public class BitmapFactory {
 public static class Options{public boolean inMutable,inJustDecodeBounds,inScaled=true,inPremultiplied=true,inDither,inPurgeable,inInputShareable;public int inSampleSize=1,inDensity,inTargetDensity,inScreenDensity,outWidth=-1,outHeight=-1;public String outMimeType;public Bitmap.Config inPreferredConfig=Bitmap.Config.ARGB_8888;}
 public static Bitmap decodeByteArray(byte[] bytes,int offset,int length){return decodeByteArray(bytes,offset,length,null);}
 public static Bitmap decodeByteArray(byte[] bytes,int offset,int length,Options opts){
  Objects.checkFromIndexSize(offset,length,bytes.length);if(opts!=null){opts.outWidth=-1;opts.outHeight=-1;opts.outMimeType=null;}
  Bitmap.Config config=opts==null||opts.inPreferredConfig==null?Bitmap.Config.ARGB_8888:opts.inPreferredConfig;
  if(opts==null||!opts.inJustDecodeBounds){if(config!=Bitmap.Config.ARGB_8888&&config!=Bitmap.Config.RGBA_F16)throw new UnsupportedOperationException("Bitmap config "+config);if(opts!=null&&!opts.inPremultiplied)throw new UnsupportedOperationException("Unpremultiplied bitmap storage");}
  JsonObject a=Graphics.args();a.addProperty("body",Base64.getEncoder().encodeToString(Arrays.copyOfRange(bytes,offset,offset+length)));a.addProperty("sample",opts==null?1:Math.max(1,Integer.highestOneBit(Math.max(1,opts.inSampleSize))));a.addProperty("bounds",opts!=null&&opts.inJustDecodeBounds);a.addProperty("f16",config==Bitmap.Config.RGBA_F16);
  float scale=opts!=null&&opts.inScaled&&opts.inDensity>0&&opts.inTargetDensity>0&&opts.inDensity!=opts.inScreenDensity?(float)opts.inTargetDensity/opts.inDensity:1; a.addProperty("densityScale",scale);
  JsonObject r=Graphics.async("decode",a);if(!r.get("ok").getAsBoolean())return null;
  boolean bounds=opts!=null&&opts.inJustDecodeBounds;if(opts!=null){opts.outWidth=r.get(bounds?"originalWidth":"width").getAsInt();opts.outHeight=r.get(bounds?"originalHeight":"height").getAsInt();opts.outMimeType=r.get("mime").getAsString();}
  if(bounds)return null;Bitmap b=Bitmap.wrap(r,config,opts!=null&&opts.inMutable);if(opts!=null&&opts.inDensity!=0)b.setDensity(scale!=1?opts.inTargetDensity:opts.inDensity);return b;
 }
 public static Bitmap decodeStream(InputStream in){return decodeStream(in,null,null);}public static Bitmap decodeStream(InputStream in,Rect padding,Options opts){if(in==null)return null;try{byte[] data=in.readAllBytes();return decodeByteArray(data,0,data.length,opts);}catch(IOException e){return null;}}
 public static Bitmap decodeFile(String path){return decodeFile(path,null);}public static Bitmap decodeFile(String path,Options opts){try(InputStream in=new FileInputStream(path)){return decodeStream(in,null,opts);}catch(IOException e){return null;}}
}
