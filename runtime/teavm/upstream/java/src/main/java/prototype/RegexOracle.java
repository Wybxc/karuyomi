package prototype;
import java.util.*;import java.util.regex.*;import java.nio.charset.StandardCharsets;
/** Deterministic JVM / TeaVM differential checks, including UTF-16 edge cases. */
public final class RegexOracle{
 public static int cases;private static int seed;private static int next(int max){seed=seed*1664525+1013904223;return (seed>>>1)%max;}
 public static String transcript(){
  String[] patterns={"(\\S*)x","(\\S+)x","(\\S+)x\\1","(\\s+)x","([^ ]+)end","([\\s\\S]+)end","(\\D+)x","(\\W*)x","(\\S+)\\s+(\\S+)","(\\S+?)x","(\\S++)x","([a-z😀]+)end"};
  List<String> samples=new ArrayList<>(List.of("","x","abcxabc","😀x😀","abc end","αβx","😀 end","a\ud800x","\udc00x","\r\n x","prefixsuffix"));seed=918;
  String[] atoms={"a","b","x"," ","\r","\n","😀","α","end"};for(int i=0;i<40;i++){StringBuilder b=new StringBuilder();for(int j=next(24);j>0;j--)b.append(atoms[next(atoms.length)]);samples.add(b.toString());}
  StringBuilder transcript=new StringBuilder();cases=0;
  for(String regex:patterns)for(int flags:new int[]{0,Pattern.CASE_INSENSITIVE})for(String sample:samples){cases++;Matcher m=Pattern.compile(regex,flags).matcher(sample);transcript.append(cases).append(':');while(m.find()){transcript.append(m.start()).append(',').append(m.end()).append(':');for(int i=0;i<=m.groupCount();i++){String g=m.group(i);transcript.append(g==null?-1:g.length()).append(':').append(g).append('|');}}transcript.append(';');}
  return transcript.toString();
 }
 public static String digest()throws Exception{byte[] hash=java.security.MessageDigest.getInstance("SHA-256").digest(transcript().getBytes(StandardCharsets.UTF_8));StringBuilder out=new StringBuilder();for(byte b:hash){String h=Integer.toHexString(b&255);if(h.length()<2)out.append('0');out.append(h);}return out.toString();}
 public static void main(String[] args)throws Exception{String digest=digest();System.out.println("{\"cases\":"+cases+",\"sha256\":\""+digest+"\"}");}
}
