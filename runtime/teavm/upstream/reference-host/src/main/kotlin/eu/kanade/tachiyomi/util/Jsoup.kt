package eu.kanade.tachiyomi.util
import okhttp3.Response
import org.jsoup.Jsoup
fun Response.asJsoup() = Jsoup.parse(body.string(),request.url.toString())
