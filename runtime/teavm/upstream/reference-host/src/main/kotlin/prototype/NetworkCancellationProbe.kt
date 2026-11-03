package prototype

import eu.kanade.tachiyomi.network.await
import kotlinx.coroutines.*
import okhttp3.*
import java.lang.reflect.Proxy
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

object NetworkCancellationProbe {
    @JvmStatic fun run():Boolean {
        val cancelled=AtomicBoolean()
        val closed=AtomicBoolean()
        val callback=AtomicReference<Callback>()
        val call=Proxy.newProxyInstance(Call::class.java.classLoader,arrayOf(Call::class.java)) { _,method,args ->
            when(method.name) {
                "enqueue" -> {callback.set(args[0] as Callback);null}
                "cancel" -> {cancelled.set(true);null}
                "isCanceled" -> cancelled.get()
                else -> error("Unexpected probe call: ${method.name}")
            }
        } as Call
        runBlocking {
            withContext(Dispatchers.Main) {
                try {withTimeout(50){call.await()};error("Pending HTTP call escaped timeout")}
                catch(_:TimeoutCancellationException) {check(cancelled.get()) {"Coroutine cancellation must cancel Call"}}
            }
        }
        val body=object:ResponseBody() {
            override fun contentType():MediaType?=null
            override fun contentLength():Long=0
            override fun source():okio.BufferedSource=okio.Buffer()
            override fun close(){closed.set(true)}
        }
        callback.get().onResponse(call,Response.Builder().request(Request.Builder().url("https://example.invalid/").build())
            .protocol(Protocol.HTTP_1_1).code(200).message("OK").body(body).build())
        check(closed.get()) {"A response arriving after cancellation must be closed"}
        return true
    }
}
