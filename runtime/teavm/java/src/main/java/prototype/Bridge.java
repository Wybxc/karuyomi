package prototype;

import java.io.IOException;
import java.io.InterruptedIOException;
import java.net.SocketTimeoutException;
import org.teavm.interop.Async;
import org.teavm.interop.AsyncCallback;
import org.teavm.jso.*;
import org.teavm.jso.typedarrays.Uint8Array;

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

  @JSFunctor
  interface Reply extends JSObject {
    void call(String value);
  }

  public static String httpOpen(String metadata) throws IOException {
    String[] value = new String[1];
    HttpError error = new HttpError();
    httpOpen(metadata, result -> value[0] = result, error::accept);
    error.check();
    if (value[0] == null || value[0].isEmpty()) throw new IOException("Missing HTTP handle");
    return value[0];
  }

  @JSBody(
      params = {"metadata", "ok", "fail"},
      script =
          "try { ok(self.teaHttpOpen(metadata)); } catch (failureReason)"
              + " {fail(String(failureReason.message || failureReason), String(failureReason.name"
              + " || 'Error'), String(failureReason.code || '')); }")
  private static native void httpOpen(String metadata, Reply ok, HttpFailure fail);

  public static void httpWrite(String handle, byte[] bytes) throws IOException {
    if (bytes.length < 1 || bytes.length > HttpBodySource.MAX_CHUNK)
      throw new IOException("Invalid HTTP upload chunk size");
    Uint8Array copy = new Uint8Array(bytes.length);
    for (int index = 0; index < bytes.length; index++)
      copy.set(index, (short) (bytes[index] & 255));
    HttpError error = new HttpError();
    httpWrite(handle, copy, error::accept);
    error.check();
  }

  @JSBody(
      params = {"handle", "bytes", "fail"},
      script =
          "try { self.teaHttpWrite(handle, bytes); } catch (failureReason)"
              + " {fail(String(failureReason.message || failureReason), String(failureReason.name"
              + " || 'Error'), String(failureReason.code || '')); }")
  private static native void httpWrite(String handle, Uint8Array bytes, HttpFailure fail);

  @Async
  public static native String httpFinish(String handle) throws IOException;

  private static void httpFinish(String handle, AsyncCallback<String> callback) {
    httpFinish(
        handle,
        callback::complete,
        (message, name, code, retryable) -> {
          IOException error = httpError(message, name, code);
          callback.error(
              retryable && !(error instanceof InterruptedIOException)
                  ? new NetworkFailure(message)
                  : error);
        });
  }

  @JSBody(
      params = {"handle", "ok", "fail"},
      script =
          "Promise.resolve().then(() => self.teaHttpFinish(handle)).then(ok, failureReason =>"
              + " fail(String(failureReason.message || failureReason), String(failureReason.name ||"
              + " 'Error'), String(failureReason.code || ''), failureReason.retryable === true));")
  private static native void httpFinish(String handle, Reply ok, HttpNetworkFailure fail);

  @JSFunctor
  private interface HttpNetworkFailure extends JSObject {
    void call(String message, String name, String code, boolean retryable);
  }

  public static boolean networkFailure(IOException error) {
    return error instanceof NetworkFailure;
  }

  private static final class NetworkFailure extends IOException {
    NetworkFailure(String message) {
      super(message);
    }
  }

  public static byte[] httpRead(String handle, int maximum) throws IOException {
    if (maximum < 1 || maximum > HttpBodySource.MAX_CHUNK)
      throw new IOException("Invalid HTTP read size");
    Uint8Array input = httpReadChunk(handle, maximum);
    if (input == null) return null;
    int length = input.getByteLength();
    if (length < 1 || length > maximum)
      throw new IOException(
          "HTTP supplier exceeded requested chunk size or returned an empty chunk");
    byte[] copy = new byte[length];
    for (int index = 0; index < length; index++) copy[index] = (byte) input.get(index);
    return copy;
  }

  @Async
  private static native Uint8Array httpReadChunk(String handle, int maximum) throws IOException;

  private static void httpReadChunk(
      String handle, int maximum, AsyncCallback<Uint8Array> callback) {
    httpReadChunk(
        handle,
        maximum,
        callback::complete,
        (message, name, code) -> callback.error(httpError(message, name, code)));
  }

  @JSFunctor
  private interface HttpChunk extends JSObject {
    void call(Uint8Array bytes);
  }

  @JSFunctor
  private interface HttpFailure extends JSObject {
    void call(String message, String name, String code);
  }

  @JSBody(
      params = {"handle", "maximum", "ok", "fail"},
      script =
          "Promise.resolve().then(() => self.teaHttpRead(handle, maximum)).then(ok, failureReason"
              + " => fail(String(failureReason.message || failureReason), String(failureReason.name"
              + " || 'Error'), String(failureReason.code || '')));")
  private static native void httpReadChunk(
      String handle, int maximum, HttpChunk ok, HttpFailure fail);

  public static void httpClose(String handle) throws IOException {
    httpControl("teaHttpClose", handle);
  }

  public static void httpCancel(String handle) throws IOException {
    httpControl("teaHttpCancel", handle);
  }

  public static String imageOpen(String mimeType) throws IOException {
    String[] value = new String[1];
    HttpError error = new HttpError();
    imageOpen(mimeType, result -> value[0] = result, error::accept);
    error.check();
    if (value[0] == null || value[0].isEmpty()) throw new IOException("Missing image sink handle");
    return value[0];
  }

  @JSBody(
      params = {"mimeType", "ok", "fail"},
      script =
          "try { ok(self.teaImageOpen(mimeType)); } catch (failureReason)"
              + " {fail(String(failureReason.message || failureReason), String(failureReason.name"
              + " || 'Error'), String(failureReason.code || '')); }")
  private static native void imageOpen(String mimeType, Reply ok, HttpFailure fail);

  public static void imageWrite(String handle, byte[] bytes) throws IOException {
    if (bytes.length < 1 || bytes.length > HttpBodySource.MAX_CHUNK)
      throw new IOException("Invalid processed image chunk size");
    Uint8Array copy = new Uint8Array(bytes.length);
    for (int index = 0; index < bytes.length; index++)
      copy.set(index, (short) (bytes[index] & 255));
    imageWriteChunk(handle, copy);
  }

  @Async
  private static native String imageWriteChunk(String handle, Uint8Array bytes) throws IOException;

  private static void imageWriteChunk(
      String handle, Uint8Array bytes, AsyncCallback<String> callback) {
    imageWriteChunk(
        handle,
        bytes,
        callback::complete,
        (message, name, code) -> callback.error(httpError(message, name, code)));
  }

  @JSBody(
      params = {"handle", "bytes", "ok", "fail"},
      script =
          "Promise.resolve().then(() => self.teaImageWrite(handle, bytes)).then(() => ok(''),"
              + " failureReason => fail(String(failureReason.message || failureReason),"
              + " String(failureReason.name || 'Error'), String(failureReason.code || '')));")
  private static native void imageWriteChunk(
      String handle, Uint8Array bytes, Reply ok, HttpFailure fail);

  @Async
  public static native String imageClose(String handle) throws IOException;

  private static void imageClose(String handle, AsyncCallback<String> callback) {
    imageClose(
        handle,
        callback::complete,
        (message, name, code) -> callback.error(httpError(message, name, code)));
  }

  @JSBody(
      params = {"handle", "ok", "fail"},
      script =
          "Promise.resolve().then(() => self.teaImageClose(handle)).then(ok, failureReason =>"
              + " fail(String(failureReason.message || failureReason), String(failureReason.name ||"
              + " 'Error'), String(failureReason.code || '')));")
  private static native void imageClose(String handle, Reply ok, HttpFailure fail);

  public static void imageCancel(String handle) throws IOException {
    httpControl("teaImageCancel", handle);
  }

  private static void httpControl(String operation, String handle) throws IOException {
    HttpError error = new HttpError();
    httpControl(operation, handle, error::accept);
    error.check();
  }

  @JSBody(
      params = {"operation", "handle", "fail"},
      script =
          "try { self[operation](handle); } catch (failureReason)"
              + " {fail(String(failureReason.message || failureReason), String(failureReason.name"
              + " || 'Error'), String(failureReason.code || '')); }")
  private static native void httpControl(String operation, String handle, HttpFailure fail);

  private static IOException httpError(String message, String name, String code) {
    if ("TimeoutError".equals(name) || "timeout".equals(code))
      return new SocketTimeoutException(message);
    if ("AbortError".equals(name) || "cancelled".equals(code))
      return new InterruptedIOException(message);
    return new IOException(message);
  }

  private static final class HttpError {
    IOException error;

    void accept(String message, String name, String code) {
      error = httpError(message, name, code);
    }

    void check() throws IOException {
      if (error != null) throw error;
    }
  }

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

  public static byte[] cacheRead(String reader, String handle, int maximum) throws IOException {
    if (maximum < 1 || maximum > HttpBodySource.MAX_CHUNK)
      throw new IllegalArgumentException("Invalid cache read size");
    Uint8Array input = cacheReadChunk(reader, handle, maximum);
    if (input == null) return null;
    int length = input.getByteLength();
    if (length < 1 || length > maximum) throw new IOException("Invalid cache response chunk size");
    byte[] copy = new byte[length];
    for (int index = 0; index < length; index++) copy[index] = (byte) input.get(index);
    return copy;
  }

  @Async
  private static native Uint8Array cacheReadChunk(String reader, String handle, int maximum)
      throws IOException;

  private static void cacheReadChunk(
      String reader, String handle, int maximum, AsyncCallback<Uint8Array> callback) {
    cacheReadChunk(
        reader,
        handle,
        maximum,
        callback::complete,
        error -> callback.error(new IOException(error)));
  }

  @JSBody(
      params = {"reader", "handle", "maximum", "ok", "fail"},
      script =
          "Promise.resolve().then(() => self.teaCacheRead(reader, handle, maximum)).then(ok, error => fail(String(error)));")
  private static native void cacheReadChunk(
      String reader, String handle, int maximum, HttpChunk ok, Reply fail);

  public static boolean cacheWrite(String editor, String handle, int sequence, byte[] bytes)
      throws IOException {
    if (bytes.length < 1 || bytes.length > HttpBodySource.MAX_CHUNK)
      throw new IllegalArgumentException("Invalid cache write size");
    Uint8Array copy = new Uint8Array(bytes.length);
    for (int index = 0; index < bytes.length; index++)
      copy.set(index, (short) (bytes[index] & 255));
    return "1".equals(cacheWriteChunk(editor, handle, sequence, copy));
  }

  @Async
  private static native String cacheWriteChunk(
      String editor, String handle, int sequence, Uint8Array bytes) throws IOException;

  private static void cacheWriteChunk(
      String editor,
      String handle,
      int sequence,
      Uint8Array bytes,
      AsyncCallback<String> callback) {
    cacheWriteChunk(
        editor,
        handle,
        sequence,
        bytes,
        callback::complete,
        error -> callback.error(new IOException(error)));
  }

  @JSBody(
      params = {"editor", "handle", "sequence", "bytes", "ok", "fail"},
      script =
          "Promise.resolve().then(() => self.teaCacheWrite(editor, handle, sequence, bytes)).then(accepted => ok(accepted === true ? '1' : '0'), error => fail(String(error)));")
  private static native void cacheWriteChunk(
      String editor, String handle, int sequence, Uint8Array bytes, Reply ok, Reply fail);

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

  static RuntimeException graphicsFailure(String message, String code) {
    if ("cancelled".equals(code)) return new java.util.concurrent.CancellationException(message);
    if ("unsupported_capability".equals(code)) return new UnsupportedOperationException(message);
    if ("limit_exceeded".equals(code)) return new IllegalStateException(message);
    return new RuntimeException(message);
  }

  private static void graphics(String request, AsyncCallback<String> callback) {
    graphicsFetch(
        request,
        callback::complete,
        (message, name, code) -> callback.error(graphicsFailure(message, code)));
  }

  @JSBody(
      params = {"request", "ok", "err"},
      script =
          "Promise.resolve().then(()=>self.teaGraphicsAsync(JSON.parse(request))).then(v=>ok(JSON.stringify(v)),e=>err(String(e.message || e),String(e.name || 'Error'),String(e.code || '')));")
  static native void graphicsFetch(String request, Reply ok, HttpFailure err);
}
