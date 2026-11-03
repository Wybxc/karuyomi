package eu.kanade.tachiyomi.network;

import okhttp3.*;
import kotlin.coroutines.*;

public class OkHttpExtensionsKt {
  public static Object await(Call call, Continuation<? super Response> c)
      throws java.io.IOException {
    return call.execute();
  }

  public static Object awaitSuccess(Call call, Continuation<? super Response> c)
      throws java.io.IOException {
    Response r = call.execute();
    if (!r.isSuccessful()) {
      r.close();
      throw new HttpException(r.code());
    }
    return r;
  }

  public static Call newCachelessCallWithProgress(OkHttpClient c, Request r, ProgressListener l) {
    return c.newCall(r);
  }
}
