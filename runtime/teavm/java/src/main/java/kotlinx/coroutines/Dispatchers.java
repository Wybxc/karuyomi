package kotlinx.coroutines;

import kotlin.coroutines.CoroutineContext;

public final class Dispatchers {
  public static final Dispatchers INSTANCE = new Dispatchers();
  private static final CoroutineDispatcher D =
      new CoroutineDispatcher() {
        public void dispatch(CoroutineContext c, Runnable r) {
          new Thread(
                  () -> {
                    prototype.Bridge.trace("dispatch coroutine");
                    try {
                      r.run();
                    } catch (Throwable t) {
                      prototype.Bridge.trace("dispatcher error " + t);
                    }
                  })
              .start();
        }

        public boolean isDispatchNeeded(CoroutineContext c) {
          return true;
        }
      };

  public static CoroutineDispatcher getDefault() {
    return D;
  }

  public static CoroutineDispatcher getIO() {
    return D;
  }

  public static CoroutineDispatcher getUnconfined() {
    return D;
  }

  public static MainCoroutineDispatcher getMain() {
    throw new UnsupportedOperationException("Main dispatcher");
  }
}
