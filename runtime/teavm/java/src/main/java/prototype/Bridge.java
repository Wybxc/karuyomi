package prototype;

import org.teavm.jso.*;
import org.teavm.interop.Async;
import org.teavm.interop.AsyncCallback;

public final class Bridge {
  @Async
  public static native String file(String request) throws java.io.IOException;

  private static void file(String request, AsyncCallback<String> callback) {
    fileFetch(request, callback::complete, e -> callback.error(new java.io.IOException(e)));
  }

  @JSBody(
      params = {"request", "ok", "err"},
      script = "self.teaFile(request).then(ok,e=>err(String(e)));")
  static native void fileFetch(String request, Reply ok, Reply err);

  @JSBody(params = "m", script = "self.postMessage({type:'trace',message:m});return '';")
  public static native String trace(String m);

  @Async
  public static native String http(String request);

  private static void http(String request, AsyncCallback<String> callback) {
    fetch(request, callback::complete, e -> callback.error(new RuntimeException(e)));
  }

  @JSFunctor
  interface Reply extends JSObject {
    void call(String value);
  }

  @JSBody(
      params = {"request", "ok", "err"},
      script = "self.teaHttp(request).then(ok, e=>err(String(e)));")
  static native void fetch(String request, Reply ok, Reply err);

  public static String js(String id, String operation, String payload) {
    checkReentry(operation);
    return browser("js", id, operation, payload);
  }

  public static String dom(String id, String operation, String payload) {
    checkReentry(operation);
    return browser("dom", id, operation, payload);
  }

  private static void checkReentry(String operation) {
    if (!operation.equals("close") && Callbacks.isInvokingOnCurrentThread())
      throw new IllegalStateException(
          "Reentrant browser evaluation from a synchronous Java callback is unsupported");
  }

  @Async
  private static native String browser(String kind, String id, String operation, String payload);

  private static void browser(
      String kind, String id, String operation, String payload, AsyncCallback<String> callback) {
    browserFetch(
        kind,
        id,
        operation,
        payload,
        callback::complete,
        e -> callback.error(new IllegalStateException(e)));
  }

  @JSBody(
      params = {"kind", "id", "op", "payload", "ok", "err"},
      script = "self.teaBrowser(kind,id,op,payload).then(ok,e=>err(String(e)));")
  static native void browserFetch(
      String kind, String id, String op, String payload, Reply ok, Reply err);

  public static void callbackInvoke(
      String requestId, String instance, String name, String method, String args) {
    new Thread(() -> callbackReply(requestId, Callbacks.invoke(instance, name, method, args)))
        .start();
  }

  @JSBody(
      params = {"id", "result"},
      script = "self.teaCallbackResult(id,result);")
  static native void callbackReply(String id, String result);

  @Async
  public static native String cache(String request);

  private static void cache(String request, AsyncCallback<String> callback) {
    cacheFetch(request, callback::complete, e -> callback.error(new IllegalStateException(e)));
  }

  @JSBody(
      params = {"request", "ok", "err"},
      script = "self.teaCache(request).then(ok,e=>err(String(e)));")
  static native void cacheFetch(String request, Reply ok, Reply err);

  @Async
  public static native String zstd(String operation, String body);

  private static void zstd(String operation, String body, AsyncCallback<String> callback) {
    zstdFetch(operation, body, callback::complete, e -> callback.error(new RuntimeException(e)));
  }

  @JSBody(
      params = {"op", "body", "ok", "err"},
      script = "self.teaZstd(op,body).then(ok,failureReason=>err(String(failureReason)));")
  static native void zstdFetch(String op, String body, Reply ok, Reply err);

  @Async
  public static native String crypto(String request);

  private static void crypto(String request, AsyncCallback<String> callback) {
    cryptoFetch(request, callback::complete, e -> callback.error(new RuntimeException(e)));
  }

  @JSBody(
      params = {"request", "ok", "err"},
      script =
          "self.teaCrypto(JSON.parse(request)).then(v=>ok(JSON.stringify(v)),e=>err(String(e)));")
  static native void cryptoFetch(String request, Reply ok, Reply err);

  @Async
  public static native String graphics(String request);

  private static void graphics(String request, AsyncCallback<String> callback) {
    graphicsFetch(request, callback::complete, e -> callback.error(new RuntimeException(e)));
  }

  @JSBody(
      params = {"request", "ok", "err"},
      script =
          "self.teaGraphicsAsync(JSON.parse(request)).then(v=>ok(JSON.stringify(v)),e=>err(String(e)));")
  static native void graphicsFetch(String request, Reply ok, Reply err);
}
