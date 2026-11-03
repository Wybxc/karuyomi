/* Derived from TeaVM 0.16 TObject.java, Copyright 2013 Alexey Andreev, Apache-2.0. */
package org.teavm.classlib.java.lang;

import java.util.ArrayDeque;
import org.teavm.interop.AsyncCallback;
import org.teavm.platform.Platform;

/** Body copied into Object.waitImpl; pre-interruption must not release its monitor. */
public class WaitObjectMethods extends TObject {
  public void waitSupport(long timeout, int nanos, AsyncCallback<Void> callback) {
    if (timeout < 0 || nanos < 0 || nanos > 999999) {
      callback.error(new IllegalArgumentException("Invalid wait timeout"));
      return;
    }
    if (TThread.interrupted()) {
      callback.error(new TInterruptedException());
      return;
    }
    Monitor monitor = this.monitor;
    NotifyListenerImpl listener = new NotifyListenerImpl(this, callback, monitor.count);
    if (monitor.notifyListeners == null) monitor.notifyListeners = new ArrayDeque<>();
    monitor.notifyListeners.add(listener);
    TThread.currentThread().interruptHandler = listener;
    if (timeout > 0 || nanos > 0) {
      int delay = timeout >= Integer.MAX_VALUE ? Integer.MAX_VALUE : (int) timeout;
      if (nanos > 0 && delay < Integer.MAX_VALUE) delay++;
      // This adapter targets TeaVM's JavaScript backend.
      listener.timerId = Platform.schedule(listener, delay);
    }
    monitorExit(this, monitor.count);
  }
}
