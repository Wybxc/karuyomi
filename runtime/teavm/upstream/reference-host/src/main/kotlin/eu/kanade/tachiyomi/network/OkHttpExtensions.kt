package eu.kanade.tachiyomi.network
import okhttp3.*
import rx.Observable
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resumeWithException
fun Call.asObservable(): Observable<Response> = Observable.fromCallable { execute() }
fun Call.asObservableSuccess(): Observable<Response> = asObservable().map { if(!it.isSuccessful)throw HttpException(it.code);it }
suspend fun Call.await(): Response = suspendCancellableCoroutine { continuation ->
    continuation.invokeOnCancellation { cancel() }
    enqueue(object: Callback {
        override fun onFailure(call:Call,error:java.io.IOException) {
            if(continuation.isActive) continuation.resumeWithException(error)
        }
        override fun onResponse(call:Call,response:Response) {
            continuation.resume(response) { _,unclaimed,_ -> unclaimed.close() }
        }
    })
}
suspend fun Call.awaitSuccess(): Response = await().also { if(!it.isSuccessful){it.close();throw HttpException(it.code)} }
fun OkHttpClient.newCachelessCallWithProgress(request:Request,listener:ProgressListener):Call=newCall(request)
