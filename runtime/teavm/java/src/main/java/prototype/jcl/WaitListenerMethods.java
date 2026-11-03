package prototype.jcl;

import org.teavm.classlib.java.lang.*;
import org.teavm.interop.AsyncCallback;

/** Field references are retargeted to TeaVM's existing wait-listener fields. */
public class WaitListenerMethods {
  TThread currentThread;
  TObject obj;
  int lockCount;
  AsyncCallback<Void> callback;

  public void resumeInterrupted() {
    WaitInterruptSupport.resume(currentThread, obj, lockCount, callback);
  }
}
