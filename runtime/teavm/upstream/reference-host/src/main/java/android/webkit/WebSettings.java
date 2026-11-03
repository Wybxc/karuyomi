package android.webkit;
import android.content.Context;
/** Supported settings for the sandboxed iframe adapter. */
public class WebSettings {
  private boolean javaScriptEnabled, domStorageEnabled, blockNetworkImage, useWideViewPort, loadWithOverviewMode;
  private String userAgentString=getDefaultUserAgent(null);
  public static String getDefaultUserAgent(Context context){return System.getProperty("http.agent", "MihonBrowserPrototype/0.1");}
  public void setJavaScriptEnabled(boolean value){javaScriptEnabled=value;}
  public boolean getJavaScriptEnabled(){return javaScriptEnabled;}
  public void setDomStorageEnabled(boolean value){domStorageEnabled=value;}
  public boolean getDomStorageEnabled(){return domStorageEnabled;}
  public void setBlockNetworkImage(boolean value){blockNetworkImage=value;}
  public boolean getBlockNetworkImage(){return blockNetworkImage;}
  public void setUseWideViewPort(boolean value){useWideViewPort=value;}
  public boolean getUseWideViewPort(){return useWideViewPort;}
  public void setLoadWithOverviewMode(boolean value){loadWithOverviewMode=value;}
  public boolean getLoadWithOverviewMode(){return loadWithOverviewMode;}
  public void setUserAgentString(String value){userAgentString=value==null?getDefaultUserAgent(null):value;}
  public String getUserAgentString(){return userAgentString;}
}
