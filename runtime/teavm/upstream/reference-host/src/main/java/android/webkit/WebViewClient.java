package android.webkit;
import android.graphics.Bitmap;
public class WebViewClient {
  public void onPageStarted(WebView view,String url,Bitmap favicon){}
  public void onPageFinished(WebView view,String url){}
  public void onReceivedError(WebView view,WebResourceRequest request,WebResourceError error){}
  public WebResourceResponse shouldInterceptRequest(WebView view,WebResourceRequest request){return null;}
  public boolean onRenderProcessGone(WebView view,RenderProcessGoneDetail detail){return false;}
  public boolean shouldOverrideUrlLoading(WebView view,String url){return false;}
  public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){return false;}
}
