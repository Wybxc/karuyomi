package prototype
import android.app.Application
import com.google.gson.Gson
import com.google.gson.JsonParser
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.source.*
import eu.kanade.tachiyomi.source.model.*
import eu.kanade.tachiyomi.source.online.HttpSource
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.*
import kotlinx.serialization.json.Json
import kotlinx.serialization.protobuf.ProtoBuf
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.addSingleton
import java.io.File
import java.net.URLClassLoader
import com.squareup.zstd.okio.zstdDecompress
import okio.source
import okio.buffer

object Host {
    private val gson=Gson()
    private val sources=linkedMapOf<String,Source>()
    private val mangas=java.util.concurrent.ConcurrentHashMap<String,SManga>()
    private val chapters=java.util.concurrent.ConcurrentHashMap<String,List<SChapter>>()
    private val invocationScope=CoroutineScope(SupervisorJob()+java.util.concurrent.Executors.newScheduledThreadPool(2){task->Thread(task,"browser-invocation").apply{isDaemon=true}}.asCoroutineDispatcher())
    private val invocations=java.util.concurrent.ConcurrentHashMap<String,String>()
    @JvmStatic fun beginInvoke(id:String,op:String,arg:String):String {
        check(invocations.size<4) {"Too many pending invocations"}
        val token=java.util.UUID.randomUUID().toString()
        invocations[token]="{\"complete\":false}"
        invocationScope.launch {
            val watch=Diagnostic.watch("$id $op")
            // Metadata/chapters can legitimately enumerate hundreds of editions.
            // Keep per-request network deadlines, but allow the full operation longer.
            val deadline=if(op=="details"||op=="chapters") 180000L else 85000L
            try { invocations[token]=gson.toJson(mapOf("complete" to true,"value" to JsonParser.parseString(withTimeout(deadline){invokeSource(id,op,arg)}))) }
            catch(t:Throwable){
                val formatted=Diagnostic.format(t)
                invocations[token]=gson.toJson(mapOf("complete" to true,"error" to formatted))
                try {Bridge.trace(formatted)} catch(_:Throwable) {}
            }
            finally {watch.cancel(false)}
        }
        return token
    }
    @JvmStatic fun pollInvoke(token:String):String {
        val value=invocations[token]?:error("Unknown invocation")
        if(value!="{\"complete\":false}") invocations.remove(token)
        return value
    }
    @JvmStatic fun setUserAgent(value:String) { System.setProperty("http.agent",value) }
    @JvmStatic fun init():String {
        val app=Application()
        Injekt.addSingleton<Application>(app)
        Injekt.addSingleton<android.content.Context>(app)
        Injekt.addSingleton<NetworkHelper>(NetworkHelper(app))
        Injekt.addSingleton<Json>(Json {ignoreUnknownKeys=true;explicitNulls=false})
        Injekt.addSingleton<ProtoBuf>(ProtoBuf)
        return "host ready; java="+System.getProperty("java.version")
    }
    @JvmStatic fun load(path:String,entry:String):String {
        val loader=URLClassLoader(arrayOf(File(path).toURI().toURL()),Host::class.java.classLoader)
        val instance=Class.forName(entry,true,loader).getDeclaredConstructor().newInstance()
        val found=when(instance){is Source->listOf(instance);is SourceFactory->instance.createSources();else->error("Unknown entry "+instance.javaClass.name)}
        found.forEach{sources[it.id.toString()]=it}
        return gson.toJson(found.map{mapOf("id" to it.id.toString(),"name" to it.name,"lang" to it.lang,"baseUrl" to (it as? HttpSource)?.baseUrl)})
    }
    @JvmStatic fun invoke(id:String,op:String,arg:String):String = runBlocking {invokeSource(id,op,arg)}
    private suspend fun invokeSource(id:String,op:String,arg:String):String {
        Bridge.trace("invoke $id $op")
        val source=sources[id]?:error("Unknown source $id")
        val result:Any=when(op){
            "resetFilterCache"->{
                val file=File(Application().cacheDir,"source_$id/filters.json.zst")
                check(!file.exists()||file.delete()) {"Could not clear test filter cache"}
                mapOf("exists" to false)
            }
            "filterCache"->{
                val file=File(Application().cacheDir,"source_$id/filters.json.zst")
                if(!file.isFile) mapOf("exists" to false)
                else {
                    val json=file.source().zstdDecompress().buffer().use {it.readUtf8()}
                    mapOf("exists" to true,"bytes" to file.length(),"data" to json,"filters" to source.getFilterList().map {it.name})
                }
            }
            "settings"->{
                val screen=androidx.preference.PreferenceScreen(Application())
                (source as? ConfigurableSource)?.setupPreferenceScreen(screen)
                mapOf("count" to screen.preferenceCount,"preferences" to (0 until screen.preferenceCount).map {index->
                    val preference=screen.getPreference(index)
                    mapOf("key" to preference.key,"title" to preference.title?.toString(),"type" to preference.javaClass.simpleName)
                })
            }
            "popular","search"->{
                val page=if(op=="popular")source.getPopularManga(1) else source.getSearchManga(1,arg,source.getFilterList())
                page.mangas.firstOrNull()?.let{mangas[id]=it;chapters.remove(id)}
                mapOf("count" to page.mangas.size,"hasNextPage" to page.hasNextPage,"mangas" to page.mangas.take(5).map{mapOf("url" to it.url,"title" to it.title)})
            }
            "details","chapters"->{
                val manga=mangas[id]?:error("Call popular first")
                val update=source.getMangaUpdate(manga,chapters[id].orEmpty(),op=="details",op=="chapters")
                mergeManga(manga,update.manga)
                if(op=="chapters"){chapters[id]=update.chapters;mapOf("count" to update.chapters.size,"chapters" to update.chapters.take(3).map{mapOf("name" to it.name,"url" to it.url)})}
                else mapOf("title" to manga.title,"description" to manga.description,"thumbnail" to manga.thumbnail_url)
            }
            "pages"->{
                val chapter=if(arg.startsWith("/")) SChapter.create().apply {url=arg;name="Selected chapter"} else chapters[id]?.firstOrNull()?:error("No chapters")
                val pages=source.getPageList(chapter)
                mapOf("count" to pages.size,"pages" to pages.take(3).map{mapOf("index" to it.index,"url" to it.url,"imageUrl" to it.imageUrl)})
            }
            else->error("Unknown operation $op")
        }
        return gson.toJson(result)
    }
    @JvmStatic fun zstdProbe(fixtures:String):String = ZstdProbe.run(fixtures)
    // Details responses often contain metadata only. The host owns the stored URL identity.
    internal fun mergeManga(stored:SManga,update:SManga) {
        if(stored===update)return
        try { stored.title=update.title } catch(_:UninitializedPropertyAccessException) {}
        stored.artist=update.artist?:stored.artist
        stored.author=update.author?:stored.author
        stored.description=update.description?:stored.description
        stored.genre=update.genre?:stored.genre
        stored.thumbnail_url=update.thumbnail_url?:stored.thumbnail_url
        stored.status=update.status
        stored.update_strategy=update.update_strategy
        stored.initialized=stored.initialized||update.initialized
        stored.memo=kotlinx.serialization.json.JsonObject(stored.memo+update.memo)
    }
    interface Calculator { fun add(a:Int,b:Int):Int;fun fail():String;fun record(value:String) }
    class DomBinding(private val view:android.webkit.WebView) {
        @android.webkit.JavascriptInterface fun decorate(value:String)="Java $value"
        @android.webkit.JavascriptInterface fun reenter(){view.evaluateJavascript("1",null)}
        fun hidden()="must not be exposed"
    }
    @JvmStatic fun quickJsProbe():String {
        app.cash.quickjs.QuickJs.create().use {js->
            val value=js.evaluate("var counter=40; counter+2")
            val second=js.evaluate("counter+=1; counter")
            val compiled=js.execute(js.compile("'compiled-'+(6*7)","probe.js"))
            var recorded=""
            js.set("calculator",Calculator::class.java,object:Calculator{
                override fun add(a:Int,b:Int)=a+b
                override fun fail():String=throw IllegalStateException("expected Java error")
                override fun record(value:String){recorded=value}
            })
            val callback=js.evaluate("var answer=calculator.add(20,22);calculator.record('callback:'+answer);answer")
            val callbackError=js.evaluate("try{calculator.fail();false}catch(e){String(e).includes('expected Java error')}")
            return gson.toJson(mapOf("value" to value,"state" to second,"compiled" to compiled,"callback" to callback,"callbackError" to callbackError,"recorded" to recorded))
        }
    }
    @JvmStatic fun domProbe():String {
        val context=Application()
        val web=android.webkit.WebView(context)
        check(web is android.view.View && web.context===context)
        web.addJavascriptInterface(DomBinding(web),"androidBridge")
        web.loadDataWithBaseURL("https://example.invalid/","<h1 id='title'>Hello</h1><script>document.getElementById('title').textContent=androidBridge.decorate('DOM '+(6*7))+'|'+typeof androidBridge.hidden;</script>","text/html","UTF-8",null)
        var result=""
        web.evaluateJavascript("document.querySelector('#title').textContent",android.webkit.ValueCallback{result=it})
        web.evaluateJavascript("try{androidBridge.reenter();false}catch(e){String(e).includes('Reentrant browser evaluation')}",android.webkit.ValueCallback{check(it=="true"){"Reentry must be rejected in Java without stopping the thread"}})
        var domFailure=false
        try { web.evaluateJavascript("throw Error('expected DOM error')",null) } catch(error:IllegalStateException) { domFailure=error.message?.contains("expected DOM error")==true }
        check(domFailure){"DOM failures must return as Java exceptions"}
        web.evaluateJavascript("6*7",android.webkit.ValueCallback{check(it=="42"){"DOM must remain usable after failure"}})
        web.destroy()
        val navigation=android.webkit.WebView(context)
        var startedValue=""
        navigation.webViewClient=object:android.webkit.WebViewClient(){
            override fun onPageStarted(view:android.webkit.WebView,url:String,favicon:android.graphics.Bitmap?){
                view.evaluateJavascript("window.started=0;document.addEventListener('probe',()=>window.started++);42",android.webkit.ValueCallback{startedValue=it})
            }
        }
        repeat(2){
            navigation.loadDataWithBaseURL("https://navigation.invalid/","<script>document.dispatchEvent(new Event('probe'));</script>","text/html","UTF-8",null)
            check(startedValue=="42") {"Page-start evaluation callback"}
            navigation.evaluateJavascript("window.started",android.webkit.ValueCallback{check(it=="1") {"Page-start injection must target the new document"}})
        }
        navigation.destroy()
        runBlocking { kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Main) {
            withTimeout(1000){delay(1)}
            check(android.os.Looper.myLooper()===android.os.Looper.getMainLooper()) {"Main dispatcher thread identity"}
            var finished=0
            fun storage(base:String,code:String):String {
                val view=android.webkit.WebView(context)
                view.webViewClient=object:android.webkit.WebViewClient(){override fun onPageFinished(v:android.webkit.WebView,url:String){finished++}}
                view.loadDataWithBaseURL(base,"<p>Storage probe</p>","text/html","UTF-8",null)
                var value=""
                view.evaluateJavascript(code,android.webkit.ValueCallback{value=it})
                view.destroy()
                return value
            }
            for(index in 1..8) {
                check(storage("https://storage-a.invalid/","localStorage.setItem('probe','$index');localStorage.getItem('probe')")=="\"$index\"")
                check(storage("https://storage-a.invalid/","localStorage.getItem('probe')")=="\"$index\"") {"Storage must persist across WebView instances"}
            }
            check(storage("https://storage-b.invalid/","localStorage.getItem('probe')")=="null") {"Storage must be isolated by origin"}
            check(finished==17) {"Page-finished callback count"}
        }}
        return result
    }
    @JvmStatic fun abiProbe():String {
        val app=Application()
        check(app is android.content.ContextWrapper)
        val preferences=app.getSharedPreferences("prototype_abi",0)
        preferences.edit().clear().commit()
        var notifications=0
        val listener=android.content.SharedPreferences.OnSharedPreferenceChangeListener{_,_->notifications++}
        preferences.registerOnSharedPreferenceChangeListener(listener)
        val edit=preferences.edit().putString("key","value")
        check(!preferences.contains("key"))
        check(edit.commit())
        check(preferences.getString("key",null)=="value")
        preferences.edit().remove("key").apply()
        check(!preferences.contains("key")&&notifications==2)
        preferences.unregisterOnSharedPreferenceChangeListener(listener)
        var configured=false
        val client=okhttp3.OkHttpClient.Builder().addInterceptor { chain->
            val changed=chain.withReadTimeout(3,java.util.concurrent.TimeUnit.SECONDS).withWriteTimeout(4,java.util.concurrent.TimeUnit.SECONDS)
            check(changed.readTimeoutMillis()==3000&&changed.writeTimeoutMillis()==4000&&chain.readTimeoutMillis()!=3000)
            configured=true
            okhttp3.Response.Builder().request(chain.request()).protocol(okhttp3.Protocol.HTTP_1_1).code(200).message("OK")
                .body(okhttp3.ResponseBody.create(null as okhttp3.MediaType?,"probe")).build()
        }.build()
        client.newCall(okhttp3.Request.Builder().url("https://example.invalid/").build()).execute().close()
        check(configured)
        return gson.toJson(mapOf("icu" to IcuProbe.run(),"preferences" to true,"notifications" to notifications,"chainTimeouts" to configured,"applicationInheritance" to true,"nullUnpark" to Diagnostic.nullUnpark(),"networkCancellation" to NetworkCancellationProbe.run(),"errorFormatting" to Diagnostic.errorFormattingProbe()))
    }
    @JvmStatic fun main(args:Array<String>){println(init());for(path in args)try{println(load(path,"keiyoushi.source.Generated"))}catch(t:Throwable){t.printStackTrace()}}
}
