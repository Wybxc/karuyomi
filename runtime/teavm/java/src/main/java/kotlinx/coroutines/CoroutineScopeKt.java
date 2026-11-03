package kotlinx.coroutines;

import kotlin.coroutines.*;
import kotlin.jvm.functions.*;
import prototype.GreenCoroutines;

public class CoroutineScopeKt {
  public static <T> Object coroutineScope(
      Function2<? super CoroutineScope, ? super Continuation<? super T>, ? extends Object> block,
      Continuation<? super T> c) {
    return GreenCoroutines.block(block, c.getContext());
  }

  public static CoroutineScope CoroutineScope(CoroutineContext c) {
    return new GreenCoroutines.Scope(c);
  }

  public static boolean isActive(CoroutineScope s) {
    return true;
  }

  public static void ensureActive(CoroutineScope s) {}

  public static CoroutineScope plus(CoroutineScope s, CoroutineContext c) {
    return CoroutineScope(s.getCoroutineContext().plus(c));
  }

  public static Object currentCoroutineContext(Continuation<? super CoroutineContext> c) {
    return c.getContext();
  }
}
