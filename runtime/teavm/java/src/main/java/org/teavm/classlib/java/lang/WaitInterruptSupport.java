package org.teavm.classlib.java.lang;
import org.teavm.interop.AsyncCallback;

/** Restore the waiting Java thread and monitor before delivering interruption. */
public final class WaitInterruptSupport {
 public static void resume(TThread thread,TObject object,int count,AsyncCallback<Void> callback){
  TThread.setCurrentThread(thread);
  TThread.interrupted();
  TObject.monitorEnterWait(object,count,new Failure(callback));
 }
 private static final class Failure implements AsyncCallback<Void>{
  private final AsyncCallback<Void> callback;Failure(AsyncCallback<Void> callback){this.callback=callback;}
  public void complete(Void ignored){callback.error(new TInterruptedException());}
  public void error(Throwable error){callback.error(error);}
 }
}
