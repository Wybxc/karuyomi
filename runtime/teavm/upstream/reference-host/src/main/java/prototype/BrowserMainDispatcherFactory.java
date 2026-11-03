package prototype;
import android.os.*;
import java.util.List;
import kotlin.coroutines.CoroutineContext;
import kotlinx.coroutines.MainCoroutineDispatcher;
import kotlinx.coroutines.internal.MainDispatcherFactory;
/** Serial Android-main task queue. DOM work itself is forwarded to the browser main thread. */
public final class BrowserMainDispatcherFactory implements MainDispatcherFactory {
  private static final Handler HANDLER=new Handler(Looper.getMainLooper());
  private static final MainCoroutineDispatcher IMMEDIATE=new Dispatcher(true);
  private static final MainCoroutineDispatcher MAIN=new Dispatcher(false);
  public int getLoadPriority(){return 100;}
  public MainCoroutineDispatcher createDispatcher(List<? extends MainDispatcherFactory> factories){return MAIN;}
  private static final class Dispatcher extends MainCoroutineDispatcher implements kotlinx.coroutines.Delay {
    private final boolean immediate;
    Dispatcher(boolean immediate){this.immediate=immediate;}
    public MainCoroutineDispatcher getImmediate(){return IMMEDIATE;}
    public boolean isDispatchNeeded(CoroutineContext context){return !immediate || Looper.myLooper()!=Looper.getMainLooper();}
    public void dispatch(CoroutineContext context,Runnable block){HANDLER.post(block);}
    public void scheduleResumeAfterDelay(long millis,kotlinx.coroutines.CancellableContinuation<? super kotlin.Unit> continuation){
      Runnable resume=()->continuation.resumeUndispatched(this,kotlin.Unit.INSTANCE);
      HANDLER.postDelayed(resume,millis);
      continuation.invokeOnCancellation(error->{HANDLER.removeCallbacks(resume);return kotlin.Unit.INSTANCE;});
    }
    public kotlinx.coroutines.DisposableHandle invokeOnTimeout(long millis,Runnable block,CoroutineContext context){
      HANDLER.postDelayed(block,millis);
      return ()->HANDLER.removeCallbacks(block);
    }
  }
}
