package prototype;

import java.io.IOException;
import java.io.InterruptedIOException;
import kotlin.coroutines.Continuation;
import org.teavm.interop.Async;
import org.teavm.interop.AsyncCallback;
import org.teavm.jso.JSBody;

public final class SourceInput {
  private SourceInput() {}

  public static Object askInput(
      String title,
      String message,
      String hint,
      String initialValue,
      boolean password,
      boolean required,
      Continuation<?> completion)
      throws IOException {
    BrowserCall.Operation owner = BrowserCall.currentOperation();
    if (owner == null) throw new InterruptedIOException("No active Source operation");
    owner.checkOpen();
    return request(
        owner.requestId,
        owner.generation,
        owner.token,
        title,
        message,
        hint,
        initialValue,
        password,
        required);
  }

  @Async
  private static native String request(
      String requestId,
      String generation,
      String token,
      String title,
      String message,
      String hint,
      String initialValue,
      boolean password,
      boolean required)
      throws IOException;

  private static void request(
      String requestId,
      String generation,
      String token,
      String title,
      String message,
      String hint,
      String initialValue,
      boolean password,
      boolean required,
      AsyncCallback<String> callback) {
    request(
        requestId,
        generation,
        token,
        title,
        message,
        hint,
        initialValue,
        password,
        required,
        callback::complete,
        error -> callback.error(new IOException(error)));
  }

  @JSBody(
      params = {
        "requestId",
        "generation",
        "token",
        "title",
        "message",
        "hint",
        "initialValue",
        "password",
        "required",
        "ok",
        "fail"
      },
      script =
          "Promise.resolve().then(() => self.teaSourceInput(requestId, generation, token, title,"
              + " message, hint, initialValue, password, required)).then(ok, e => fail(String(e)));")
  private static native void request(
      String requestId,
      String generation,
      String token,
      String title,
      String message,
      String hint,
      String initialValue,
      boolean password,
      boolean required,
      Bridge.Reply ok,
      Bridge.Reply fail);
}
