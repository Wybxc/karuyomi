package android.webkit;
import okhttp3.*;
import prototype.Cookies;
import java.util.*;
public class CookieManager {
 private static final CookieManager INSTANCE=new CookieManager();
 public static CookieManager getInstance(){return INSTANCE;}
 public void setCookie(String url,String value){HttpUrl target=HttpUrl.get(url);Cookie cookie=Cookie.parse(target,value);if(cookie!=null)Cookies.INSTANCE.saveFromResponse(target,Collections.singletonList(cookie));}
 public void setCookie(String url,String value,ValueCallback<Boolean> callback){setCookie(url,value);if(callback!=null)callback.onReceiveValue(true);}
 public String getCookie(String url){StringJoiner joined=new StringJoiner("; ");for(Cookie c:Cookies.INSTANCE.loadForRequest(HttpUrl.get(url)))joined.add(c.name()+"="+c.value());return joined.toString();}
 public void setAcceptCookie(boolean accept){}
 public void flush(){}
 public void removeAllCookies(ValueCallback<Boolean> callback){Cookies.INSTANCE.clear();if(callback!=null)callback.onReceiveValue(true);}
}
