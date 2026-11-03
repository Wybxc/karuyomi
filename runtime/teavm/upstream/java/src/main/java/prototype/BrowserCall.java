package prototype;
import okhttp3.*;
import okio.Buffer;
import okio.Timeout;
import com.google.gson.*;
import java.lang.reflect.*;
import java.util.*;
import java.io.IOException;

/** Replaces only OkHttpClient.newCall; plugin interceptors still execute as JVM bytecode. */
public final class BrowserCall implements Call {
  private final OkHttpClient client; private final Request request;
  private boolean executed,cancelled; private Call proxy;
  
  private BrowserCall(OkHttpClient c,Request r){client=c;request=r;}
  public static Call create(OkHttpClient c,Request r){
    BrowserCall b=new BrowserCall(c,r);b.proxy=b;return b;
  }
  public Request request(){return request;} public void enqueue(Callback c){new Thread(()->{try{c.onResponse(this,execute());}catch(IOException e){c.onFailure(this,e);}}).start();}
  public void cancel(){cancelled=true;}public boolean isExecuted(){return executed;}public boolean isCanceled(){return cancelled;}public Timeout timeout(){return new Timeout();}
  public Call clone(){return create(client,request);} public void addEventListener(okhttp3.EventListener e){throw new UnsupportedOperationException("event listener");}
  public <T>T tag(kotlin.reflect.KClass<T> c){return null;} public <T>T tag(Class<? extends T> c){return null;}
  public <T>T tag(kotlin.reflect.KClass<T> c,kotlin.jvm.functions.Function0<? extends T> f){return f.invoke();}public <T>T tag(Class<T> c,kotlin.jvm.functions.Function0<? extends T> f){return f.invoke();}
  public Response execute()throws IOException {
    if(executed)throw new IllegalStateException("Already executed");executed=true;
    Bridge.trace("execute "+request.url());
    List<Interceptor> list=new ArrayList<>(client.interceptors());list.add(this::follow);list.add(this::bridgeRequest);list.add(new okhttp3.internal.cache.CacheInterceptor());list.addAll(client.networkInterceptors());
    return proceed(list,0,request);
  }
  private Response proceed(List<Interceptor> list,int index,Request r)throws IOException {
    return proceed(list,index,r,client.connectTimeoutMillis(),client.readTimeoutMillis(),client.writeTimeoutMillis(),client.cache());
  }
  private Response proceed(List<Interceptor> list,int index,Request r,int connectMs,int readMs,int writeMs,Cache cache)throws IOException {
    if(cancelled)throw new IOException("Cancelled");
    if(index==list.size())return transport(r);
    return list.get(index).intercept(chain(list,index,r,connectMs,readMs,writeMs,cache));
  }
  private Interceptor.Chain chain(List<Interceptor> list,int index,Request r,int connectMs,int readMs,int writeMs,Cache cache) {
    return new Interceptor.Chain(){public okhttp3.Request request(){return r;}public okhttp3.Response proceed(okhttp3.Request a0) throws IOException{return BrowserCall.this.proceed(list,index+1,a0,connectMs,readMs,writeMs,cache);}public okhttp3.Connection connection(){return null;}public okhttp3.Call call(){return BrowserCall.this;}public int connectTimeoutMillis(){return connectMs;}public okhttp3.Interceptor.Chain withConnectTimeout(int a0,java.util.concurrent.TimeUnit a1){return chain(list,index,r,(int)a1.toMillis(a0),readMs,writeMs,cache);}public int readTimeoutMillis(){return readMs;}public okhttp3.Interceptor.Chain withReadTimeout(int a0,java.util.concurrent.TimeUnit a1){return chain(list,index,r,connectMs,(int)a1.toMillis(a0),writeMs,cache);}public int writeTimeoutMillis(){return writeMs;}public okhttp3.Interceptor.Chain withWriteTimeout(int a0,java.util.concurrent.TimeUnit a1){return chain(list,index,r,connectMs,readMs,(int)a1.toMillis(a0),cache);}public boolean getFollowSslRedirects(){return client.followSslRedirects();}public boolean getFollowRedirects(){return client.followRedirects();}public okhttp3.Dns getDns(){throw new UnsupportedOperationException("Chain.getDns");}public okhttp3.Interceptor.Chain withDns(okhttp3.Dns a0){throw new UnsupportedOperationException("Chain.withDns");}public javax.net.SocketFactory getSocketFactory(){throw new UnsupportedOperationException("Chain.getSocketFactory");}public okhttp3.Interceptor.Chain withSocketFactory(javax.net.SocketFactory a0){throw new UnsupportedOperationException("Chain.withSocketFactory");}public boolean getRetryOnConnectionFailure(){return client.retryOnConnectionFailure();}public okhttp3.Interceptor.Chain withRetryOnConnectionFailure(boolean a0){throw new UnsupportedOperationException("Chain.withRetryOnConnectionFailure");}public okhttp3.Authenticator getAuthenticator(){throw new UnsupportedOperationException("Chain.getAuthenticator");}public okhttp3.Interceptor.Chain withAuthenticator(okhttp3.Authenticator a0){throw new UnsupportedOperationException("Chain.withAuthenticator");}public okhttp3.CookieJar getCookieJar(){return client.cookieJar();}public okhttp3.Interceptor.Chain withCookieJar(okhttp3.CookieJar a0){throw new UnsupportedOperationException("Chain.withCookieJar");}public okhttp3.Cache getCache(){return cache;}public okhttp3.Interceptor.Chain withCache(okhttp3.Cache a0){return chain(list,index,r,connectMs,readMs,writeMs,a0);}public java.net.Proxy getProxy(){throw new UnsupportedOperationException("Chain.getProxy");}public okhttp3.Interceptor.Chain withProxy(java.net.Proxy a0){throw new UnsupportedOperationException("Chain.withProxy");}public java.net.ProxySelector getProxySelector(){throw new UnsupportedOperationException("Chain.getProxySelector");}public okhttp3.Interceptor.Chain withProxySelector(java.net.ProxySelector a0){throw new UnsupportedOperationException("Chain.withProxySelector");}public okhttp3.Authenticator getProxyAuthenticator(){throw new UnsupportedOperationException("Chain.getProxyAuthenticator");}public okhttp3.Interceptor.Chain withProxyAuthenticator(okhttp3.Authenticator a0){throw new UnsupportedOperationException("Chain.withProxyAuthenticator");}public javax.net.ssl.SSLSocketFactory getSslSocketFactoryOrNull(){throw new UnsupportedOperationException("Chain.getSslSocketFactoryOrNull");}public okhttp3.Interceptor.Chain withSslSocketFactory(javax.net.ssl.SSLSocketFactory a0,javax.net.ssl.X509TrustManager a1){throw new UnsupportedOperationException("Chain.withSslSocketFactory");}public javax.net.ssl.X509TrustManager getX509TrustManagerOrNull(){throw new UnsupportedOperationException("Chain.getX509TrustManagerOrNull");}public javax.net.ssl.HostnameVerifier getHostnameVerifier(){throw new UnsupportedOperationException("Chain.getHostnameVerifier");}public okhttp3.Interceptor.Chain withHostnameVerifier(javax.net.ssl.HostnameVerifier a0){throw new UnsupportedOperationException("Chain.withHostnameVerifier");}public okhttp3.CertificatePinner getCertificatePinner(){throw new UnsupportedOperationException("Chain.getCertificatePinner");}public okhttp3.Interceptor.Chain withCertificatePinner(okhttp3.CertificatePinner a0){throw new UnsupportedOperationException("Chain.withCertificatePinner");}public okhttp3.ConnectionPool getConnectionPool(){throw new UnsupportedOperationException("Chain.getConnectionPool");}public okhttp3.Interceptor.Chain withConnectionPool(okhttp3.ConnectionPool a0){throw new UnsupportedOperationException("Chain.withConnectionPool");}public okhttp3.EventListener getEventListener(){return okhttp3.EventListener.NONE;}};
  }

  private Response follow(Interceptor.Chain chain)throws IOException {
    Request next=chain.request();Response prior=null;
    for(int redirects=0;;redirects++){
      Response response=chain.proceed(next);if(prior!=null)response=response.newBuilder().priorResponse(prior).build();
      String location=response.header("Location");int code=response.code();
      if(!client.followRedirects()||location==null||!Arrays.asList(301,302,303,307,308).contains(code))return response;
      if(redirects>=10){response.close();throw new IOException("Too many redirects");}
      HttpUrl target=next.url().resolve(location);if(target==null){response.close();throw new IOException("Bad redirect");}
      Request.Builder builder=next.newBuilder().url(target);
      if(!target.host().equals(next.url().host())||target.port()!=next.url().port()||!target.scheme().equals(next.url().scheme()))builder.removeHeader("Authorization").removeHeader("Cookie");
      if(code==303&&!next.method().equals("HEAD")||((code==301||code==302)&&next.method().equals("POST")))builder.get().removeHeader("Content-Type").removeHeader("Content-Length").removeHeader("Transfer-Encoding");
      prior=okhttp3.internal.UnreadableResponseBodyKt.stripBody(response);response.close();next=builder.build();
    }
  }
  private Response bridgeRequest(Interceptor.Chain chain)throws IOException {
    Request user=chain.request();Headers.Builder sent=user.headers().newBuilder();List<Cookie> cookies=client.cookieJar().loadForRequest(user.url());
    if(user.body()!=null&&user.body().contentType()!=null)sent.set("Content-Type",user.body().contentType().toString());
    if(!cookies.isEmpty()){StringJoiner cookie=new StringJoiner("; ");for(Cookie value:cookies)cookie.add(value.name()+"="+value.value());sent.set("Cookie",cookie.toString());}
    Response response=chain.proceed(user.newBuilder().headers(sent.build()).build());
    client.cookieJar().saveFromResponse(user.url(),Cookie.parseAll(user.url(),response.headers()));
    return response.newBuilder().request(user).build();
  }
  private Response transport(Request r)throws IOException {
    Bridge.trace("transport "+r.url());
    JsonObject j=new JsonObject();j.addProperty("url",r.url().toString());j.addProperty("method",r.method());
    Headers h=r.headers();
    JsonArray headers=new JsonArray();for(int i=0;i<h.size();i++){JsonArray a=new JsonArray();a.add(h.name(i));a.add(h.value(i));headers.add(a);}j.add("headers",headers);
    if(r.body()!=null){Buffer b=new Buffer();r.body().writeTo(b);j.addProperty("body",Base64.getEncoder().encodeToString(b.readByteArray()));}
    String payload=j.toString();long sentAt=System.currentTimeMillis();
    JsonObject result=JsonParser.parseString(Bridge.http(payload)).getAsJsonObject();
    if(cancelled)throw new IOException("Cancelled");
    if(result.has("error") && client.retryOnConnectionFailure() && (r.method().equals("GET")||r.method().equals("HEAD"))
        && result.get("error").getAsString().matches("(?is).*?(Network connection lost|ECONNRESET|connection reset).*")) {
      Bridge.trace("Retry idempotent request after connection loss: "+r.url());
      result=JsonParser.parseString(Bridge.http(payload)).getAsJsonObject();
    }
    if(result.has("error"))throw new IOException(result.get("error").getAsString());
    Headers.Builder received=new Headers.Builder();for(JsonElement e:result.getAsJsonArray("headers")){JsonArray a=e.getAsJsonArray();received.add(a.get(0).getAsString(),a.get(1).getAsString());}
    Headers rh=received.build();int code=result.get("status").getAsInt();
    byte[] body=Base64.getDecoder().decode(result.get("body").getAsString());
    return new Response.Builder().request(r).protocol(Protocol.HTTP_1_1).code(code).message(result.get("message").getAsString()).headers(rh).sentRequestAtMillis(sentAt).receivedResponseAtMillis(System.currentTimeMillis()).body(ResponseBody.create(body,MediaType.parse(rh.get("Content-Type")==null?"application/octet-stream":rh.get("Content-Type")))).build();
  }
}
