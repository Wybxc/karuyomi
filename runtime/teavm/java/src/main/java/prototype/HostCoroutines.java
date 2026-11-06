package prototype;

import java.io.InterruptedIOException;
import kotlin.Unit;
import kotlin.coroutines.AbstractCoroutineContextElement;
import kotlin.coroutines.Continuation;
import kotlin.coroutines.CoroutineContext;
import kotlin.jvm.functions.Function1;
import kotlin.jvm.functions.Function2;
import kotlinx.coroutines.AbstractCoroutine;
import kotlinx.coroutines.BuildersKt;
import kotlinx.coroutines.CoroutineScope;
import kotlinx.coroutines.Job;
import kotlinx.coroutines.ThreadContextElement;

/** Host ownership only. Job state, children, cancellation and builders remain official. */
public final class HostCoroutines {
  private static final OwnerKey KEY = new OwnerKey();

  private static final class OwnerKey implements CoroutineContext.Key<OwnerElement> {}

  public static final class OwnerElement extends AbstractCoroutineContextElement
      implements ThreadContextElement<BrowserCall.Operation> {
    final BrowserCall.Operation owner;
    final boolean entry;
    Binding binding;

    OwnerElement(BrowserCall.Operation owner, boolean entry) {
      super(KEY);
      this.owner = owner;
      this.entry = entry;
    }

    public BrowserCall.Operation updateThreadContext(CoroutineContext context) {
      BrowserCall.Operation previous = BrowserCall.currentOperation();
      owner.enter();
      return previous;
    }

    public void restoreThreadContext(CoroutineContext context, BrowserCall.Operation previous) {
      restore(previous);
    }
  }

  private static void restore(BrowserCall.Operation previous) {
    BrowserCall.Operation current = BrowserCall.currentOperation();
    if (current != null) current.leave();
    if (previous != null) previous.enter();
  }

  public static <T> T block(
      Function2<? super CoroutineScope, ? super Continuation<? super T>, ? extends Object> body,
      CoroutineContext context)
      throws InterruptedIOException {
    try {
      return BuildersKt.runBlocking(entryContext(context), body);
    } catch (InterruptedException error) {
      Thread.currentThread().interrupt();
      InterruptedIOException failure = new InterruptedIOException("Source entry interrupted");
      failure.initCause(error);
      throw failure;
    }
  }

  public static CoroutineContext entryContext(CoroutineContext context) {
    BrowserCall.Operation owner = BrowserCall.currentOperation();
    return owner == null ? context : context.plus(new OwnerElement(owner, true));
  }

  /** Injected before AbstractCoroutine constructs its official parent/context relationship. */
  public static CoroutineContext capture(CoroutineContext context) {
    OwnerElement inherited = context.get(KEY);
    BrowserCall.Operation owner = BrowserCall.currentOperation();
    if (owner == null && inherited != null) owner = inherited.owner;
    if (owner == null) return context;
    boolean entry = inherited != null && inherited.entry && inherited.binding == null;
    return context.plus(new OwnerElement(owner, entry));
  }

  /** Called after JobSupport initialization but before parent attachment or scheduling. */
  public static void created(Job job, CoroutineContext context, boolean active) {
    OwnerElement element = context.get(KEY);
    if (element == null) return;
    Binding binding = new Binding(element.owner, element.entry);
    element.binding = binding;
    if (active) binding.activate();
    job.invokeOnCompletion(new HostCompletion(binding));
  }

  public static void beforeStart(Job job) {
    Binding binding = binding(job);
    if (binding != null && !job.isCompleted()) {
      try {
        binding.activate();
      } catch (RuntimeException | Error failure) {
        java.util.concurrent.CancellationException rejected =
            new java.util.concurrent.CancellationException("Source coroutine start rejected");
        rejected.initCause(failure);
        try {
          job.cancel(rejected);
        } catch (Throwable cleanup) {
          if (cleanup != failure) failure.addSuppressed(cleanup);
        }
        throw failure;
      }
    }
  }

  private static Binding binding(Job job) {
    if (!(job instanceof AbstractCoroutine<?>)) return null;
    CoroutineContext context = ((AbstractCoroutine<?>) job).getContext();
    if (context == null) return null;
    OwnerElement element = context.get(KEY);
    return element == null ? null : element.binding;
  }

  private static final class Binding {
    final BrowserCall.Operation owner;
    final boolean entry;
    BrowserCall.BoundOperation lease;
    boolean completed;
    int completionDepth;

    Binding(BrowserCall.Operation owner, boolean entry) {
      this.owner = owner;
      this.entry = entry;
    }

    synchronized void activate() {
      if (completed || lease != null) return;
      try {
        owner.checkOpen();
      } catch (InterruptedIOException error) {
        throw new IllegalStateException(error);
      }
      if (!entry) lease = BrowserCall.bindOperation(owner, () -> {});
    }

    synchronized void complete() {
      completed = true;
      releaseIfFinished();
    }

    synchronized void releaseIfFinished() {
      if (completed && completionDepth == 0 && lease != null) {
        lease.close();
        lease = null;
      }
    }
  }

  private static final class HostCompletion implements Function1<Throwable, Unit> {
    final Binding binding;

    HostCompletion(Binding binding) {
      this.binding = binding;
    }

    public Unit invoke(Throwable cause) {
      binding.complete();
      return Unit.INSTANCE;
    }
  }

  /** Keep the Job lease until all synchronous completion handlers finish, including suspension. */
  public static final class CompletionScope implements AutoCloseable {
    final Binding binding;
    final BrowserCall.Operation previous;

    CompletionScope(Binding binding) {
      this.binding = binding;
      previous = BrowserCall.currentOperation();
      if (binding != null) {
        synchronized (binding) {
          binding.completionDepth++;
        }
        binding.owner.enter();
      }
    }

    public void close() {
      if (binding != null) {
        synchronized (binding) {
          binding.completionDepth--;
          binding.releaseIfFinished();
        }
      }
      restore(previous);
    }
  }

  public static CompletionScope completing(Job job) {
    return new CompletionScope(binding(job));
  }

  public static Function1<? super Throwable, Unit> captureCompletion(
      Job job, Function1<? super Throwable, Unit> handler) {
    if (handler instanceof HostCompletion || handler instanceof OwnedCompletion) return handler;
    Binding binding = binding(job);
    BrowserCall.Operation owner = binding == null ? BrowserCall.currentOperation() : binding.owner;
    return owner == null ? handler : new OwnedCompletion(owner, handler);
  }

  private static final class OwnedCompletion implements Function1<Throwable, Unit> {
    final BrowserCall.Operation owner;
    final Function1<? super Throwable, Unit> handler;

    OwnedCompletion(BrowserCall.Operation owner, Function1<? super Throwable, Unit> handler) {
      this.owner = owner;
      this.handler = handler;
    }

    public Unit invoke(Throwable cause) {
      Unit[] result = new Unit[1];
      BrowserCall.runInOperation(owner, () -> result[0] = handler.invoke(cause));
      return result[0];
    }
  }
}
