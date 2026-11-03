package prototype;
import okhttp3.*;
import okio.Buffer;
import okio.Timeout;
import com.google.gson.*;
import java.lang.reflect.*;
import java.util.*;
import java.io.IOException;

/** Replaces only OkHttpClient.newCall; plugin interceptors still execute as JVM bytecode. */
public final class BrowserCall implements InvocationHandler {
  private final OkHttpClient client; private final Request request;
  private boolean executed,cancelled; private Call proxy;
  private static final Gson gson=new Gson();
  private BrowserCall(OkHttpClient c,Request r){client=c;request=r;}
  public static Call create(OkHttpClient c,Request r){
    BrowserCall b=new BrowserCall(c,r);b.proxy=(Call)Proxy.newProxyInstance(BrowserCall.class.getClassLoader(),new Class[]{Call.class},b);return b.proxy;
  }
  public Object invoke(Object p,Method m,Object[] a)throws Throwable {
    switch(m.getName()){
      case "request":return request;
      case "execute":return execute();
      case "enqueue":new Thread(()->{Response response;try{response=execute();}catch(Exception e){((Callback)a[0]).onFailure(proxy,e instanceof IOException?(IOException)e:new IOException(e));return;}try{((Callback)a[0]).onResponse(proxy,response);}catch(IOException e){Bridge.trace("Callback failure: "+e);}},"browser-http").start();return null;
      case "clone":return create(client,request);
      case "cancel":cancelled=true;return null;
      case "isCanceled":return cancelled;
      case "isExecuted":return executed;
      case "timeout":return new Timeout();
      case "addEventListener":return null;
      case "tag":return null;
      case "toString":return "BrowserCall("+request.url()+")";
      case "hashCode":return System.identityHashCode(this);
      case "equals":return p==a[0];
      default:throw new UnsupportedOperationException(m.toString());
    }
  }
  private Response execute()throws IOException {
    if(executed)throw new IllegalStateException("Already executed");executed=true;
    Bridge.trace("execute "+request.url());
    List<Interceptor> list=new ArrayList<>(client.interceptors());list.addAll(client.networkInterceptors());
    return proceed(list,0,request);
  }
  private Response proceed(List<Interceptor> list,int index,Request r)throws IOException {
    return proceed(list,index,r,client.connectTimeoutMillis(),client.readTimeoutMillis(),client.writeTimeoutMillis());
  }
  private Response proceed(List<Interceptor> list,int index,Request r,int connectMs,int readMs,int writeMs)throws IOException {
    if(cancelled)throw new IOException("Cancelled");
    if(index==list.size())return transport(r,0);
    return list.get(index).intercept(chain(list,index,r,connectMs,readMs,writeMs));
  }
  private Interceptor.Chain chain(List<Interceptor> list,int index,Request r,int connectMs,int readMs,int writeMs) {
    Interceptor.Chain chain=(Interceptor.Chain)Proxy.newProxyInstance(BrowserCall.class.getClassLoader(),new Class[]{Interceptor.Chain.class},(p,m,a)->{
      String n=m.getName();if(n.equals("request"))return r;if(n.equals("proceed"))return proceed(list,index+1,(Request)a[0],connectMs,readMs,writeMs);
      if(n.equals("call"))return proxy;if(n.equals("connection"))return null;
      if(n.equals("connectTimeoutMillis"))return connectMs;if(n.equals("readTimeoutMillis"))return readMs;if(n.equals("writeTimeoutMillis"))return writeMs;
      if(n.equals("withConnectTimeout")||n.equals("withReadTimeout")||n.equals("withWriteTimeout")){
        int value=(Integer)a[0];java.util.concurrent.TimeUnit unit=(java.util.concurrent.TimeUnit)a[1];
        if(value<0)throw new IllegalArgumentException("timeout < 0");long millis=unit.toMillis(value);
        if(millis>Integer.MAX_VALUE||value>0&&millis==0)throw new IllegalArgumentException("timeout out of range");
        return chain(list,index,r,n.equals("withConnectTimeout")?(int)millis:connectMs,n.equals("withReadTimeout")?(int)millis:readMs,n.equals("withWriteTimeout")?(int)millis:writeMs);
      }
      String getter=n.startsWith("get")?Character.toLowerCase(n.charAt(3))+n.substring(4):n;
      try{return client.getClass().getMethod(getter).invoke(client);}catch(ReflectiveOperationException e){throw new UnsupportedOperationException(n,e);}
    });
    Bridge.trace("interceptor "+list.get(index).getClass().getName());
    return chain;
  }
  private Response transport(Request r,int redirects)throws IOException {
    Bridge.trace("transport "+r.url());
    JsonObject j=new JsonObject();j.addProperty("url",r.url().toString());j.addProperty("method",r.method());
    Headers.Builder sent=r.headers().newBuilder();List<Cookie> cookies=client.cookieJar().loadForRequest(r.url());
    // OkHttp's internal BridgeInterceptor normally derives this from RequestBody.
    if(r.body()!=null&&r.body().contentType()!=null)sent.set("Content-Type",r.body().contentType().toString());
    if(!cookies.isEmpty()){StringJoiner s=new StringJoiner("; ");for(Cookie c:cookies)s.add(c.name()+"="+c.value());sent.set("Cookie",s.toString());}
    JsonArray headers=new JsonArray();Headers h=sent.build();for(int i=0;i<h.size();i++){JsonArray a=new JsonArray();a.add(h.name(i));a.add(h.value(i));headers.add(a);}j.add("headers",headers);
    if(r.body()!=null){Buffer b=new Buffer();r.body().writeTo(b);j.addProperty("body",Base64.getEncoder().encodeToString(b.readByteArray()));}
    String payload=gson.toJson(j);
    JsonObject result=JsonParser.parseString(Bridge.http(payload)).getAsJsonObject();
    if(cancelled)throw new IOException("Cancelled");
    if(result.has("error") && client.retryOnConnectionFailure() && (r.method().equals("GET")||r.method().equals("HEAD"))
        && result.get("error").getAsString().matches("(?is).*?(Network connection lost|ECONNRESET|connection reset).*")) {
      Bridge.trace("Retry idempotent request after connection loss: "+r.url());
      result=JsonParser.parseString(Bridge.http(payload)).getAsJsonObject();
    }
    if(result.has("error"))throw new IOException(result.get("error").getAsString());
    Headers.Builder received=new Headers.Builder();for(JsonElement e:result.getAsJsonArray("headers")){JsonArray a=e.getAsJsonArray();received.add(a.get(0).getAsString(),a.get(1).getAsString());}
    Headers rh=received.build();client.cookieJar().saveFromResponse(r.url(),Cookie.parseAll(r.url(),rh));
    int code=result.get("status").getAsInt();String location=rh.get("Location");
    if(client.followRedirects()&&location!=null&&Arrays.asList(301,302,303,307,308).contains(code)){
      if(redirects>=10)throw new IOException("Too many redirects");HttpUrl next=r.url().resolve(location);if(next==null)throw new IOException("Bad redirect");
      Request.Builder builder=r.newBuilder().url(next);if(!next.host().equals(r.url().host()))builder.removeHeader("Authorization").removeHeader("Cookie");
      if(code==303||((code==301||code==302)&&r.method().equals("POST")))builder.get();return transport(builder.build(),redirects+1);
    }
    byte[] body=Base64.getDecoder().decode(result.get("body").getAsString());
    return new Response.Builder().request(r).protocol(Protocol.HTTP_1_1).code(code).message(result.get("message").getAsString()).headers(rh).body(ResponseBody.create(body,MediaType.parse(rh.get("Content-Type")==null?"application/octet-stream":rh.get("Content-Type")))).build();
  }
}
