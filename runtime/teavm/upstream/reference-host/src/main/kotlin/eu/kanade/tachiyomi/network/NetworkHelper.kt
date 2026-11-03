package eu.kanade.tachiyomi.network
import okhttp3.*
import android.content.Context
import eu.kanade.tachiyomi.network.interceptor.*
class NetworkHelper(context: Context) {
    fun defaultUserAgentProvider() = System.getProperty("http.agent", "MihonBrowserPrototype/0.1")
    val client = OkHttpClient.Builder().cookieJar(prototype.Cookies.INSTANCE).addInterceptor(UncaughtExceptionInterceptor()).addInterceptor(UserAgentInterceptor(::defaultUserAgentProvider)).addInterceptor(CloudflareInterceptor()).build()
    val cloudflareClient get() = client
}
