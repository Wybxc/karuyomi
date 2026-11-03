package android.net;
import java.nio.charset.StandardCharsets;
/** The UTF-8 percent-encoding subset used by extension text-image URLs. */
public final class Uri implements Comparable<Uri> {
 private final String value;
 private Uri(String value){this.value=java.util.Objects.requireNonNull(value);}
 public static Uri parse(String value){return new Uri(value);}
 public static Uri fromFile(java.io.File file){return parse(file.toURI().toString());}
 public static Uri withAppendedPath(Uri base,String path){return base.buildUpon().appendEncodedPath(path).build();}
 private java.net.URI parsed(){return java.net.URI.create(value);}
 public String getScheme(){return parsed().getScheme();}
 public String getHost(){return parsed().getHost();}
 public int getPort(){return parsed().getPort();}
 public String getAuthority(){return parsed().getAuthority();}
 public String getEncodedAuthority(){return parsed().getRawAuthority();}
 public String getPath(){return decode(getEncodedPath());}
 public String getEncodedPath(){return parsed().getRawPath();}
 public String getQuery(){return decode(getEncodedQuery());}
 public String getEncodedQuery(){return parsed().getRawQuery();}
 public String getFragment(){return decode(parsed().getRawFragment());}
 public String getEncodedFragment(){return parsed().getRawFragment();}
 public java.util.List<String> getPathSegments(){
  var segments=new java.util.ArrayList<String>();String path=getEncodedPath();
  if(path!=null)for(String segment:path.split("/"))if(!segment.isEmpty())segments.add(decode(segment));
  return java.util.Collections.unmodifiableList(segments);
 }
 public String getLastPathSegment(){var segments=getPathSegments();return segments.isEmpty()?null:segments.get(segments.size()-1);}
 public String getQueryParameter(String key){var values=getQueryParameters(key);return values.isEmpty()?null:values.get(0);}
 public java.util.List<String> getQueryParameters(String key){
  var values=new java.util.ArrayList<String>();String query=getEncodedQuery();
  if(query!=null)for(String part:query.split("&")){String[] pair=part.split("=",2);if(decode(pair[0]).equals(key))values.add(pair.length==1?"":decode(pair[1].replace("+","%20")));}
  return java.util.Collections.unmodifiableList(values);
 }
 public java.util.Set<String> getQueryParameterNames(){var names=new java.util.LinkedHashSet<String>();String query=getEncodedQuery();if(query!=null)for(String part:query.split("&"))names.add(decode(part.split("=",2)[0]));return java.util.Collections.unmodifiableSet(names);}
 public Builder buildUpon(){return new Builder(this);}
 @Override public String toString(){return value;}
 @Override public int hashCode(){return value.hashCode();}
 @Override public boolean equals(Object other){return other instanceof Uri && value.equals(((Uri)other).value);}
 public int compareTo(Uri other){return value.compareTo(other.value);}
 public static final class Builder {
  private String scheme,authority,path="",query,fragment;
  public Builder(){}
  private Builder(Uri uri){scheme=uri.getScheme();authority=uri.getEncodedAuthority();path=uri.getEncodedPath();query=uri.getEncodedQuery();fragment=uri.getEncodedFragment();}
  public Builder scheme(String value){scheme=value;return this;}
  public Builder authority(String value){return encodedAuthority(encode(value,"@[]:"));}
  public Builder encodedAuthority(String value){authority=value;return this;}
  public Builder path(String value){return encodedPath(encode(value,"/"));}
  public Builder encodedPath(String value){path=value;return this;}
  public Builder appendPath(String value){return appendEncodedPath(encode(value));}
  public Builder appendEncodedPath(String value){path=(path==null?"":path)+(path!=null&&path.endsWith("/")?"":"/")+value;return this;}
  public Builder query(String value){return encodedQuery(encode(value,"=&"));}
  public Builder encodedQuery(String value){query=value;return this;}
  public Builder clearQuery(){query=null;return this;}
  public Builder appendQueryParameter(String key,String value){String pair=encode(key)+"="+encode(value);query=query==null||query.isEmpty()?pair:query+"&"+pair;return this;}
  public Builder fragment(String value){return encodedFragment(encode(value));}
  public Builder encodedFragment(String value){fragment=value;return this;}
  public Uri build(){return parse((scheme==null?"":scheme+":")+(authority==null?"":"//"+authority)+(path==null?"":authority!=null&&!path.isEmpty()&&!path.startsWith("/")?"/"+path:path)+(query==null?"":"?"+query)+(fragment==null?"":"#"+fragment));}
  @Override public String toString(){return build().toString();}
 }

 public static String encode(String value){return encode(value,null);}
 public static String encode(String value,String allow){
  if(value==null)return null;
  StringBuilder out=new StringBuilder();String hex="0123456789ABCDEF";
  for(byte raw:value.getBytes(StandardCharsets.UTF_8)){
   int b=raw&255;boolean safe=b>='a'&&b<='z'||b>='A'&&b<='Z'||b>='0'&&b<='9'||"_-!.~'()*".indexOf(b)>=0||b<128&&allow!=null&&allow.indexOf(b)>=0;
   if(safe)out.append((char)b);else out.append('%').append(hex.charAt(b>>4)).append(hex.charAt(b&15));
  }return out.toString();
 }
 public static String decode(String value){return value==null?null:java.net.URLDecoder.decode(value.replace("+","%2B"),StandardCharsets.UTF_8);}
}
