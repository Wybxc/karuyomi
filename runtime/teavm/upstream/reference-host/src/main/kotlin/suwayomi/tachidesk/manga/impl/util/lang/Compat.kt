package suwayomi.tachidesk.manga.impl.util.lang
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import rx.Observable
val String.Companion.EMPTY: String get() = ""
val kotlinx.serialization.json.JsonObject.Companion.EMPTY: kotlinx.serialization.json.JsonObject get() = kotlinx.serialization.json.JsonObject(emptyMap())
suspend fun <T> Observable<T>.awaitSingle(): T = suspendCancellableCoroutine { c ->
    val subscription = single().subscribe({ if(c.isActive)c.resume(it) }, {if(c.isActive)c.resumeWithException(it)})
    c.invokeOnCancellation { subscription.unsubscribe() }
}
