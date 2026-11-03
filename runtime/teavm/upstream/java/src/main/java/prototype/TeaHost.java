package prototype;
import eu.kanade.tachiyomi.source.*;
import eu.kanade.tachiyomi.source.model.*;
import org.teavm.jso.*;
import java.util.*;
import kotlin.coroutines.*;
import com.google.gson.*;
public class TeaHost {
 public static eu.kanade.tachiyomi.network.NetworkHelper network;
 static List<Source> sources; static Source source; static SManga manga; static List<SChapter> chapters; static List<Page> pages;
 public static void main(String[] args) { }
 @JSExport public static void hostInit(String userAgent){new Thread(()->{try{done(new JsonPrimitive(init(userAgent)).toString());}catch(Throwable t){fail(describe(t));}}).start();}
 @JSExport public static void hostLoad(){new Thread(()->{try{if(load()>=0)done(sourceInfo());}catch(Throwable t){fail(describe(t));}}).start();}
 @JSExport public static void hostSelect(String id){new Thread(()->{try{done(new JsonPrimitive(select(id)).toString());}catch(Throwable t){fail(describe(t));}}).start();}
 @JSExport public static void callbackInvoke(String requestId,String instance,String name,String method,String args){Bridge.callbackInvoke(requestId,instance,name,method,args);}
 public static String init(String userAgent){PersistentFileSystem.install();System.setProperty("http.agent",userAgent);android.app.Application app=new android.app.Application(); network=new eu.kanade.tachiyomi.network.NetworkHelper(app); uy.kohesive.injekt.InjektKt.getInjekt().addSingleton(()->android.content.Context.class,app); uy.kohesive.injekt.InjektKt.getInjekt().addSingleton(()->eu.kanade.tachiyomi.network.NetworkHelper.class,network); uy.kohesive.injekt.InjektKt.getInjekt().addSingleton(()->kotlinx.serialization.protobuf.ProtoBuf.class,kotlinx.serialization.protobuf.ProtoBuf.Default); uy.kohesive.injekt.InjektKt.getInjekt().addSingleton(()->android.app.Application.class,app); uy.kohesive.injekt.InjektKt.getInjekt().addSingleton(()->kotlinx.serialization.json.Json.class,kotlinx.serialization.json.JsonKt.Json(kotlinx.serialization.json.Json.Default,b->{b.setIgnoreUnknownKeys(true);b.setExplicitNulls(false);return kotlin.Unit.INSTANCE;})); return "TeaVM host ready";}
 @JSExport public static String sourceInfo(){JsonArray a=new JsonArray();for(Source s:sources){JsonObject x=new JsonObject();x.addProperty("id",Long.toString(s.getId()));x.addProperty("name",s.getName());x.addProperty("lang",s.getLang());a.add(x);}return a.toString();}
 public static int load(){try{Object entry=new keiyoushi.source.Generated();sources=entry instanceof SourceFactory?((SourceFactory)entry).createSources():List.of((Source)entry);source=sources.get(0); return sources.size();}catch(Throwable t){StringBuilder b=new StringBuilder(t.toString());for(StackTraceElement e:t.getStackTrace())b.append("\n").append(e);fail(b.toString());return -1;}}
 public static String select(String id){source=sources.stream().filter(s->Long.toString(s.getId()).equals(id)).findFirst().orElseThrow(()->new IllegalArgumentException("Unknown Source "+id));manga=null;chapters=null;pages=null;return source.getName();}
 @JSExport public static void probes(){new Thread(()->{try{done(CompatibilityProbe.run());}catch(Throwable t){fail(describe(t));}}).start();}
 @JSExport public static void invoke(String op,String arg){new Thread(()->invokeInternal(op,arg)).start();}
 static void invokeInternal(String op,String arg){Bridge.trace("begin "+op);
  Continuation<Object> c=new Continuation<>(){
   public CoroutineContext getContext(){return kotlinx.coroutines.Dispatchers.getDefault();}
   public void resumeWith(Object value){try{kotlin.ResultKt.throwOnFailure(value);complete(op,value);}catch(Throwable t){fail(describe(t));}}
  };
  try {Object v; switch(op){
   case "popular":v=source.getPopularManga(1,c);break;
   case "search":v=source.getSearchManga(1,arg,source.getFilterList(),c);break;
   case "details":case "chapters":v=source.getMangaUpdate(manga,chapters==null?List.of():chapters,op.equals("details"),op.equals("chapters"),c);break;
   case "pages":v=source.getPageList(chapters.get(0),c);break;
   case "image":{Page page;if(arg.startsWith("{")){JsonObject a=JsonParser.parseString(arg).getAsJsonObject();page=new Page(a.has("index")?a.get("index").getAsInt():0,a.has("url")?a.get("url").getAsString():"",a.has("imageUrl")?a.get("imageUrl").getAsString():null,null);}else{if(pages==null||pages.isEmpty())throw new IllegalStateException("No pages loaded");page=pages.get(arg.isEmpty()?0:Integer.parseInt(arg));}eu.kanade.tachiyomi.source.online.HttpSource http=(eu.kanade.tachiyomi.source.online.HttpSource)source;if(page.getImageUrl()==null)page.setImageUrl(GreenCoroutines.block((scope,cc)->http.getImageUrl(page,cc),c.getContext()));v=http.getImage(page,c);break;}
   default:throw new IllegalArgumentException(op);
  } if(v!=kotlin.coroutines.intrinsics.IntrinsicsKt.getCOROUTINE_SUSPENDED())complete(op,v);
  }catch(Throwable t){fail(describe(t));}
 }
 static void complete(String op,Object v){JsonObject j=new JsonObject();
  if(v instanceof MangasPage){MangasPage p=(MangasPage)v;if(!p.getMangas().isEmpty())manga=p.getMangas().get(0);j.addProperty("count",p.getMangas().size());j.addProperty("hasNextPage",p.getHasNextPage());JsonArray a=new JsonArray();for(SManga m:p.getMangas().subList(0,Math.min(5,p.getMangas().size()))){JsonObject x=new JsonObject();x.addProperty("title",m.getTitle());x.addProperty("url",m.getUrl());a.add(x);}j.add("mangas",a);}
  else if(v instanceof SMangaUpdate){SMangaUpdate u=(SMangaUpdate)v;mergeManga(manga,u.getManga());if(op.equals("chapters")){chapters=u.getChapters();j.addProperty("count",chapters.size());JsonArray a=new JsonArray();for(SChapter c:chapters.subList(0,Math.min(3,chapters.size()))){JsonObject x=new JsonObject();x.addProperty("name",c.getName());x.addProperty("url",c.getUrl());a.add(x);}j.add("chapters",a);}else{SManga m=manga;j.addProperty("title",m.getTitle());j.addProperty("description",m.getDescription());j.addProperty("thumbnail",m.getThumbnail_url());}}
  else if(v instanceof List){List<Page> p=(List<Page>)v;pages=p;j.addProperty("count",p.size());JsonArray a=new JsonArray();for(Page page:p.subList(0,Math.min(3,p.size()))){JsonObject x=new JsonObject();x.addProperty("index",page.getIndex());x.addProperty("url",page.getUrl());x.addProperty("imageUrl",page.getImageUrl());a.add(x);}j.add("pages",a);}
  else if(v instanceof okhttp3.Response){okhttp3.Response r=(okhttp3.Response)v;try{byte[] bytes=r.body().bytes();j.addProperty("status",r.code());j.addProperty("bytes",bytes.length);j.addProperty("contentType",r.body().contentType()==null?null:r.body().contentType().toString());j.addProperty("bodySha256",hex(java.security.MessageDigest.getInstance("SHA-256").digest(bytes)));android.graphics.Bitmap image=android.graphics.BitmapFactory.decodeByteArray(bytes,0,bytes.length);if(image==null)throw new IllegalStateException("Image decode returned null");try{j.addProperty("width",image.getWidth());j.addProperty("height",image.getHeight());JsonArray samples=new JsonArray();for(int y=0;y<4;y++)for(int x=0;x<4;x++)samples.add(image.getPixel(Math.min(image.getWidth()-1,x*image.getWidth()/4),Math.min(image.getHeight()-1,y*image.getHeight()/4)));j.add("sampleArgb",samples);}finally{image.recycle();}}catch(Exception e){throw new RuntimeException(e);}finally{r.close();}}
  done(HostJson.write(j));
 }
 static void mergeManga(SManga stored,SManga update){
  if(stored==update)return;
  try{stored.setTitle(update.getTitle());}catch(kotlin.UninitializedPropertyAccessException ignored){}
  if(update.getArtist()!=null)stored.setArtist(update.getArtist());
  if(update.getAuthor()!=null)stored.setAuthor(update.getAuthor());
  if(update.getDescription()!=null)stored.setDescription(update.getDescription());
  if(update.getGenre()!=null)stored.setGenre(update.getGenre());
  if(update.getThumbnail_url()!=null)stored.setThumbnail_url(update.getThumbnail_url());
  stored.setStatus(update.getStatus());stored.setUpdate_strategy(update.getUpdate_strategy());
  stored.setInitialized(stored.getInitialized()||update.getInitialized());
  java.util.Map<String,kotlinx.serialization.json.JsonElement> memo=new java.util.LinkedHashMap<>(stored.getMemo());memo.putAll(update.getMemo());stored.setMemo(new kotlinx.serialization.json.JsonObject(memo));
 }
 static String hex(byte[] bytes){StringBuilder s=new StringBuilder();for(byte b:bytes){String h=Integer.toHexString(b&255);if(h.length()<2)s.append('0');s.append(h);}return s.toString();}
 static String describe(Throwable t){StringBuilder s=new StringBuilder();java.util.Set<Throwable> seen=java.util.Collections.newSetFromMap(new java.util.IdentityHashMap<>());for(int depth=0;t!=null&&depth<16&&seen.add(t);depth++,t=t.getCause()){if(depth>0)s.append("\nCaused by: ");s.append(t.toString());org.teavm.jso.JSObject js=org.teavm.jso.JSExceptions.getJSException(t);if(js!=null)s.append("\n").append(jsStack(js));for(StackTraceElement e:t.getStackTrace())s.append("\n").append(e);}return s.toString();}
 @JSBody(params="error",script="return error&&error.stack?String(error.stack):'';") static native String jsStack(JSObject error);
 @JSBody(params="value",script="self.teaDone(value);") static native void done(String value);
 @JSBody(params="error",script="self.teaFail(error);") static native void fail(String error);
}
