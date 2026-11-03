package kotlinx.coroutines;import kotlin.*;import kotlin.coroutines.*;import kotlin.jvm.functions.*;import prototype.GreenCoroutines;
public class BuildersKt{
 public static <T>Deferred<T> async(CoroutineScope s,CoroutineContext c,CoroutineStart start,Function2<? super CoroutineScope,? super Continuation<? super T>,? extends Object> f){return new GreenCoroutines.Task<T>(s,c,start,f);}
 public static Deferred async$default(CoroutineScope s,CoroutineContext c,CoroutineStart start,Function2 f,int flags,Object marker){return async(s,(flags&1)!=0?EmptyCoroutineContext.INSTANCE:c,(flags&2)!=0?CoroutineStart.DEFAULT:start,f);}
 public static <T>Object withContext(CoroutineContext context,Function2<? super CoroutineScope,? super Continuation<? super T>,? extends Object> f,Continuation<? super T> c){return GreenCoroutines.block(f,c.getContext().plus(context));}
 public static Job launch(CoroutineScope s,CoroutineContext c,CoroutineStart start,Function2 f){return async(s,c,start,f);}public static Job launch$default(CoroutineScope s,CoroutineContext c,CoroutineStart start,Function2 f,int flags,Object marker){return async$default(s,c,start,f,flags,marker);}
 public static <T>T runBlocking(CoroutineContext c,Function2<? super CoroutineScope,? super Continuation<? super T>,? extends Object> f){return GreenCoroutines.block(f,c);}public static Object runBlocking$default(CoroutineContext c,Function2 f,int flags,Object marker){return runBlocking((flags&1)!=0?EmptyCoroutineContext.INSTANCE:c,f);}
 public static <T>T runBlockingK(CoroutineContext c,Function2<? super CoroutineScope,? super Continuation<? super T>,? extends Object> f){return runBlocking(c,f);}
 public static Object runBlockingK$default(CoroutineContext c,Function2 f,int flags,Object marker){return runBlocking$default(c,f,flags,marker);}
}
