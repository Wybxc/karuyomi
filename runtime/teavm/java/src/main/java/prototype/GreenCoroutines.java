package prototype;

import java.util.*;
import java.util.concurrent.CancellationException;
import kotlin.*;
import kotlin.coroutines.*;
import kotlin.jvm.functions.*;
import kotlinx.coroutines.*;
import kotlinx.coroutines.selects.*;

/** Kotlin suspend ABI backed by TeaVM cooperative Java threads. No OS thread scheduler. */
public final class GreenCoroutines {
  public static final class Scope implements CoroutineScope {
    final CoroutineContext context;
    final List<Task<?>> children = new ArrayList<>();

    public Scope(CoroutineContext c) {
      context = c;
    }

    public CoroutineContext getCoroutineContext() {
      return context;
    }
  }

  public static <T> T block(
      Function2<? super CoroutineScope, ? super Continuation<? super T>, ? extends Object> f,
      CoroutineContext context) {
    Scope scope = new Scope(context);
    Waiter<T> w = new Waiter<>();
    try {
      Object r = f.invoke(scope, w.continuation(context));
      if (r != kotlin.coroutines.intrinsics.IntrinsicsKt.getCOROUTINE_SUSPENDED())
        w.finish(r, null);
      T result = w.waitResult();
      for (Task<?> child : scope.children) child.value();
      return result;
    } catch (Throwable t) {
      for (Task<?> child : scope.children) child.cancel(t);
      throw propagate(t);
    }
  }

  // Kotlin has no checked-exception wrapping: preserve the original Throwable
  // across block/await and the continuation boundary, including IOException/Error.
  @SuppressWarnings("unchecked")
  static <E extends Throwable> RuntimeException propagate(Throwable t) throws E {
    throw (E) t;
  }

  static final class Waiter<T> {
    volatile boolean complete;
    Object result;
    Throwable error;

    synchronized void finish(Object r, Throwable e) {
      if (complete) return;
      result = r;
      error = e;
      complete = true;
      notifyAll();
    }

    Continuation<T> continuation(CoroutineContext c) {
      return new Continuation<>() {
        public CoroutineContext getContext() {
          return c;
        }

        public void resumeWith(Object r) {
          try {
            ResultKt.throwOnFailure(r);
            finish(r, null);
          } catch (Throwable t) {
            finish(null, t);
          }
        }
      };
    }

    synchronized T waitResult() {
      while (!complete)
        try {
          wait();
        } catch (InterruptedException e) {
          Thread.currentThread().interrupt();
          throw new CancellationException("Interrupted");
        }
      if (error != null) throw propagate(error);
      return (T) result;
    }
  }

  public static final class Task<T> extends AbstractCoroutineContextElement implements Deferred<T> {
    private final Waiter<T> w = new Waiter<>();
    private final Function2<
            ? super CoroutineScope, ? super Continuation<? super T>, ? extends Object>
        f;
    private final CoroutineContext context;
    private boolean started;
    private volatile boolean cancelled;
    private final BrowserCall.Operation owner;
    private final List<Function1<? super Throwable, Unit>> callbacks = new ArrayList<>();

    public Task(
        CoroutineScope scope,
        CoroutineContext c,
        CoroutineStart start,
        Function2<? super CoroutineScope, ? super Continuation<? super T>, ? extends Object> f) {
      super(Job.Key);
      this.context = scope.getCoroutineContext().plus(c);
      this.f = f;
      this.owner = BrowserCall.currentOperation();
      if (scope instanceof Scope) ((Scope) scope).children.add(this);
      if (start != CoroutineStart.LAZY) start();
    }

    public synchronized boolean start() {
      if (started || cancelled) return false;
      started = true;
      BrowserCall.BoundOperation child = null;
      try {
        child =
            BrowserCall.bindOperation(
                owner,
                () -> {
                  try {
                    if (!cancelled) w.finish(block(f, context), null);
                  } catch (Throwable t) {
                    w.finish(null, t);
                  }
                  completeCallbacks();
                });
        BrowserCall.BoundOperation scheduled = child;
        BrowserCall.startBoundThread(
            scheduled,
            () ->
                new Thread(() -> {
                  try {
                    scheduled.run();
                  } catch (Throwable error) {
                    if (w.complete) throw propagate(error);
                    w.finish(null, error);
                    completeCallbacks();
                  }
                }));
      } catch (Throwable error) {
        if (child != null) child.close();
        w.finish(null, error);
        try {
          completeCallbacks();
        } catch (Throwable callbackError) {
          error.addSuppressed(callbackError);
        }
        throw propagate(error);
      }
      return true;
    }

    private void completeCallbacks() {
      List<Function1<? super Throwable, Unit>> list;
      synchronized (this) {
        list = new ArrayList<>(callbacks);
        callbacks.clear();
      }
      if (!list.isEmpty())
        BrowserCall.runInOperation(
            owner,
            () -> {
              for (var callback : list) callback.invoke(w.error);
            });
    }

    public T value() {
      start();
      return w.waitResult();
    }

    public Object await(Continuation<? super T> c) {
      return value();
    }

    public T getCompleted() {
      if (!w.complete) throw new IllegalStateException("Incomplete");
      return w.waitResult();
    }

    public Throwable getCompletionExceptionOrNull() {
      if (!w.complete) throw new IllegalStateException("Incomplete");
      return w.error;
    }

    public Job getParent() {
      return null;
    }

    public boolean isActive() {
      return started && !w.complete;
    }

    public boolean isCompleted() {
      return w.complete;
    }

    public boolean isCancelled() {
      return cancelled;
    }

    public CancellationException getCancellationException() {
      return w.error instanceof CancellationException
          ? (CancellationException) w.error
          : new CancellationException("Cancelled");
    }

    public void cancel(CancellationException e) {
      cancel((Throwable) (e == null ? new CancellationException("Cancelled") : e));
    }

    public boolean cancel(Throwable e) {
      cancelled = true;
      w.finish(null, e == null ? new CancellationException("Cancelled") : e);
      return true;
    }

    public kotlin.sequences.Sequence<Job> getChildren() {
      return kotlin.sequences.SequencesKt.emptySequence();
    }

    public ChildHandle attachChild(ChildJob j) {
      throw new UnsupportedOperationException("Child Job attachment");
    }

    public Object join(Continuation<? super Unit> c) {
      value();
      return Unit.INSTANCE;
    }

    public SelectClause0 getOnJoin() {
      throw new UnsupportedOperationException("select on join");
    }

    public SelectClause1<T> getOnAwait() {
      throw new UnsupportedOperationException("select on await");
    }

    public DisposableHandle invokeOnCompletion(Function1<? super Throwable, Unit> f) {
      return invokeOnCompletion(false, true, f);
    }

    public synchronized DisposableHandle invokeOnCompletion(
        boolean onCancelling, boolean immediate, Function1<? super Throwable, Unit> f) {
      if (w.complete) {
        if (immediate) BrowserCall.runInOperation(owner, () -> f.invoke(w.error));
      } else callbacks.add(f);
      return () -> {
        synchronized (this) {
          callbacks.remove(f);
        }
      };
    }
  }
}
