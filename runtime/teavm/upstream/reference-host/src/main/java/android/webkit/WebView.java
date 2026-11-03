package android.webkit;
import prototype.Bridge;
import com.google.gson.Gson;
import com.google.gson.JsonParser;
import java.util.*;
import java.util.concurrent.atomic.AtomicLong;
public class WebView extends android.view.View {
 private static final AtomicLong ids=new AtomicLong();private final String id="dom-"+ids.incrementAndGet();
 private final WebSettings settings=new WebSettings();
 private WebViewClient client=new WebViewClient();
 private WebChromeClient chromeClient=new WebChromeClient();
 private String url="about:blank";
 private boolean startingPage;
 private volatile long navigationSequence;
 private final List<String> startScripts=new ArrayList<>();
 private final List<ValueCallback<String>> startCallbacks=new ArrayList<>();
 public WebView(android.content.Context context){super(context);}
 public WebSettings getSettings(){return settings;}
 public void setWebViewClient(WebViewClient value){client=value;}
 public WebViewClient getWebViewClient(){return client;}
 public void setWebChromeClient(WebChromeClient value){chromeClient=value;}
 public WebChromeClient getWebChromeClient(){return chromeClient;}
 public String getUrl(){return url;}
 public void stopLoading(){navigationSequence++;}


 public void loadDataWithBaseURL(String base,String html,String mime,String encoding,String history){
   // A verification flow needs a user-operated browser surface, absent from this headless adapter.
   if(html!=null&&html.matches("(?is).*<script[^>]+src=[\"'][^\"']*challenges\\.cloudflare\\.com/turnstile/.*"))
     throw new UnsupportedOperationException("Turnstile verification requires a user-operated browser; the headless WebView adapter does not support this flow");
   Map<String,Object> args=new HashMap<>();args.put("base",base);args.put("html",html);url=base==null?"about:blank":base;load("load",args,false);
 }
 public void loadData(String html,String mime,String encoding){loadDataWithBaseURL(null,html,mime,encoding,null);}
 public void loadUrl(String url){loadUrl(url,Collections.emptyMap());}
 public void loadUrl(String url,Map<String,String> headers){this.url=url;load("navigate",new HashMap<>(Map.of("url",url,"headers",headers)),true);}
 private void load(String operation,Map<String,Object> args,boolean asynchronous){
   long sequence=++navigationSequence;
   String loadingUrl=url;
   startScripts.clear();startCallbacks.clear();startingPage=true;
   try{client.onPageStarted(this,url,null);}finally{startingPage=false;}
   args.put("scripts",new ArrayList<>(startScripts));
   var callbacks=new ArrayList<>(startCallbacks);startScripts.clear();startCallbacks.clear();
   Runnable loading=()->{
     String reply=Bridge.dom(id,operation,new Gson().toJson(args));
     Runnable finished=()->{
       if(sequence!=navigationSequence)return;
       if(!callbacks.isEmpty()){
         var values=JsonParser.parseString(reply).getAsJsonArray();
         for(int i=0;i<callbacks.size();i++)if(callbacks.get(i)!=null)callbacks.get(i).onReceiveValue(values.get(i).getAsString());
       }
       client.onPageFinished(this,loadingUrl);
     };
     if(asynchronous)new android.os.Handler(android.os.Looper.getMainLooper()).post(finished);else finished.run();
   };
   if(asynchronous)new Thread(()->{try{loading.run();}catch(Throwable error){Bridge.trace("WebView navigation failed: "+error);}},"browser-webview").start();else loading.run();
 }
 public void evaluateJavascript(String code,ValueCallback<String> callback){if(startingPage){startScripts.add(code);startCallbacks.add(callback);return;}String value=Bridge.dom(id,"evaluate",code);if(callback!=null)callback.onReceiveValue(value);}
 public void addJavascriptInterface(Object object,String name){Bridge.dom(id,"bind",prototype.Callbacks.register(id,name,object.getClass(),object,true));}
 public void destroy(){navigationSequence++;prototype.Callbacks.close(id);Bridge.dom(id,"close","");}
}
