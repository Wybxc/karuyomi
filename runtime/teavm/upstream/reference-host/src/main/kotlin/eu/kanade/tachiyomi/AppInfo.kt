package eu.kanade.tachiyomi

/** Host ABI used in extension request headers. These identify this prototype's own version. */
object AppInfo {
    fun getVersionCode(): Int = 1
    fun getVersionName(): String = "0.1.0"
    // The prototype currently returns image URLs; no reader codecs have been validated.
    fun getSupportedImageMimeTypes(): List<String> = emptyList()
}
