package eu.kanade.tachiyomi.network.interceptor
import okhttp3.Interceptor
open class UncaughtExceptionInterceptor: Interceptor { override fun intercept(chain:Interceptor.Chain)=chain.proceed(chain.request()) }
class UserAgentInterceptor(private val userAgentProvider: () -> String): Interceptor {
    override fun intercept(chain: Interceptor.Chain): okhttp3.Response {
        val request=chain.request()
        return chain.proceed(if(request.header("User-Agent").isNullOrEmpty()) request.newBuilder().header("User-Agent",userAgentProvider()).build() else request)
    }
}
class CloudflareInterceptor: UncaughtExceptionInterceptor()
