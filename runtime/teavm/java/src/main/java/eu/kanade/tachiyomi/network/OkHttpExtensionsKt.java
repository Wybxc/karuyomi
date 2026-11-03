package eu.kanade.tachiyomi.network;

import kotlin.coroutines.*;
import okhttp3.*;

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
    return c.newBuilder()
        .cache(null)
        .addNetworkInterceptor(chain -> {
          Response response = chain.proceed(chain.request());
          return response.newBuilder().body(new ProgressResponseBody(response.body(), l)).build();
        })
        .build()
        .newCall(r);
  }
}
