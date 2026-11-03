package prototype;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.locks.*;
import kotlinx.coroutines.*;
/** Runtime checks for the browser-specific dependency adapters used by these extensions. */
public final class CompatibilityProbe {
 static int checks;
 static void expect(boolean condition,String name){if(!condition)throw new AssertionError(name);checks++;}
 static String md5(String s)throws Exception{byte[] digest=java.security.MessageDigest.getInstance("MD5").digest(s.getBytes(StandardCharsets.UTF_8));StringBuilder out=new StringBuilder();for(byte b:digest){String h=Integer.toHexString(b&255);if(h.length()==1)out.append('0');out.append(h);}return out.toString();}
 public static String run()throws Exception {
  checks=0;
  expect(md5("").equals("d41d8cd98f00b204e9800998ecf8427e"),"MD5 empty");
  expect(md5("abc").equals("900150983cd24fb0d6963f7d28e17f72"),"MD5 abc");
  expect(md5("abcdefghijklmnopqrstuvwxyz").equals("c3fcd3d76192e4007dfb496cca67e13b"),"MD5 alphabet");
  var psl=okhttp3.internal.publicsuffix.PublicSuffixDatabase.get();
  expect("example.co.uk".equals(psl.getEffectiveTldPlusOne("a.example.co.uk")),"PSL multipart");
  expect(psl.getEffectiveTldPlusOne("co.uk")==null,"PSL suffix");
  expect("a.b.ck".equals(psl.getEffectiveTldPlusOne("a.b.ck")),"PSL wildcard");
  expect("www.ck".equals(psl.getEffectiveTldPlusOne("a.www.ck")),"PSL exception");
  expect(java.text.Normalizer.normalize("e\u0301",java.text.Normalizer.Form.NFC).equals("é"),"Unicode normalization");
  expect(java.net.IDN.toASCII("bücher.de").equals("xn--bcher-kva.de"),"IDN");
  expect(java.text.Collator.getInstance(Locale.ENGLISH).compare("a","b")<0,"Collation");
  var pref=new android.app.Application().getSharedPreferences("compat-probe",0);pref.edit().clear().commit();
  final int[] events={0};android.content.SharedPreferences.OnSharedPreferenceChangeListener listener=(p,k)->events[0]++;
  pref.registerOnSharedPreferenceChangeListener(listener);
  expect(pref.edit().putString("name","value").putInt("n",7).commit(),"Preferences commit");
  expect(pref.getString("name","").equals("value")&&pref.getInt("n",0)==7,"Preferences read");
  expect(events[0]>=1,"Preferences listener");pref.unregisterOnSharedPreferenceChangeListener(listener);pref.edit().clear().commit();
  ReentrantLock lock=new ReentrantLock();lock.lock();lock.lock();expect(lock.getHoldCount()==2,"Lock reentrancy");lock.unlock();lock.unlock();
  String result=GreenCoroutines.block((scope,c)->{
   var first=new GreenCoroutines.Task<String>(scope,kotlin.coroutines.EmptyCoroutineContext.INSTANCE,CoroutineStart.DEFAULT,(s,cc)->{try{Thread.sleep(3);}catch(InterruptedException e){throw new RuntimeException(e);}return "a";});
   var second=new GreenCoroutines.Task<String>(scope,kotlin.coroutines.EmptyCoroutineContext.INSTANCE,CoroutineStart.LAZY,(s,cc)->"b");
   return first.value()+second.value();
  },kotlin.coroutines.EmptyCoroutineContext.INSTANCE);
  expect(result.equals("ab"),"Concurrent deferred and lazy await");
  boolean failed=false;try{GreenCoroutines.block((scope,c)->{new GreenCoroutines.Task<String>(scope,kotlin.coroutines.EmptyCoroutineContext.INSTANCE,CoroutineStart.DEFAULT,(s,cc)->{throw new IllegalArgumentException("probe failure");});return "ignored";},kotlin.coroutines.EmptyCoroutineContext.INSTANCE);}catch(IllegalArgumentException e){failed=e.getMessage().equals("probe failure");}
  expect(failed,"Structured child exception propagation");
  return "{\"pass\":true,\"checks\":"+checks+"}";
 }
}
