package eu.kanade.tachiyomi.network;

/*
 * Copyright (C) Contributors to the Suwayomi project
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 *
 * Adapted from Suwayomi-Server NetworkHelper.kt at
 * 6b481e8b62938b9c060eb210b934e0fbfdfa466b for the browser runtime.
 */

import android.content.Context;
import eu.kanade.tachiyomi.network.interceptor.CloudflareInterceptor;
import eu.kanade.tachiyomi.network.interceptor.UncaughtExceptionInterceptor;
import eu.kanade.tachiyomi.network.interceptor.UserAgentInterceptor;
import java.io.File;
import java.util.Objects;
import okhttp3.Cache;
import okhttp3.OkHttpClient;
import prototype.Cookies;

/** Source network defaults; the cache backend applies the runtime's namespace and quota. */
public final class NetworkHelper {
  private final OkHttpClient client;

  public NetworkHelper(Context context) {
    Objects.requireNonNull(context, "context");
    client =
        new OkHttpClient.Builder()
            .cookieJar(Cookies.INSTANCE)
            .cache(new Cache(new File(context.getCacheDir(), "network_cache"), 5L * 1024 * 1024))
            .addInterceptor(new UncaughtExceptionInterceptor())
            .addInterceptor(new UserAgentInterceptor(this::defaultUserAgentProvider))
            .addInterceptor(new CloudflareInterceptor())
            .build();
  }

  public final String defaultUserAgentProvider() {
    return System.getProperty("http.agent", "MihonBrowserPrototype/0.1");
  }

  public final OkHttpClient getClient() {
    return client;
  }

  public final OkHttpClient getCloudflareClient() {
    return client;
  }
}
