package prototype;

import eu.kanade.tachiyomi.source.model.Page;
import eu.kanade.tachiyomi.source.online.HttpSource;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import kotlin.ResultKt;
import kotlin.coroutines.Continuation;
import kotlin.coroutines.intrinsics.IntrinsicsKt;
import kotlinx.coroutines.Dispatchers;
import okhttp3.Response;
import okhttp3.ResponseBody;
import okio.Buffer;
import okio.BufferedSource;

/** Calls the original Source image API and exports only its processed response body. */
public final class SourceImages {
  public interface Sink {
    String open() throws IOException;

    void write(String handle, byte[] bytes) throws IOException;

    String close(String handle) throws IOException;

    void cancel(String handle) throws IOException;
  }

  public static String acquire(HttpSource source, Page page, Sink sink) throws IOException {
    if (page.getImageUrl() == null) {
      String url =
          GreenCoroutines.<String>block(
              (scope, continuation) -> source.getImageUrl(page, continuation),
              Dispatchers.getDefault());
      if (url == null || url.isEmpty()) throw new IOException("Source returned an empty image URL");
      page.setImageUrl(url);
    }
    Response response =
        GreenCoroutines.<Response>block(
            (scope, continuation) -> {
              try {
                return requestImage(source, page, continuation);
              } catch (IOException error) {
                continuation.resumeWith(ResultKt.createFailure(error));
                return IntrinsicsKt.getCOROUTINE_SUSPENDED();
              }
            },
            Dispatchers.getDefault());
    if (response == null) throw new IOException("Source returned no image response");
    String handle = null;
    try {
      try (response) {
        ResponseBody body = response.body();
        if (body == null) throw new IOException("Source returned no image body");
        long length = body.contentLength();
        if (length < -1 || length > HttpBodySource.MAX_RESPONSE)
          throw new IOException("Processed image exceeds 64 MiB or has an invalid length");
        handle = sink.open();
        if (handle == null || handle.isEmpty()) throw new IOException("Missing image sink handle");
        pump(body.source(), length, sink, handle);
      }
      // The HTTP body is closed before a resource can become visible to its owner.
      String resource = sink.close(handle);
      if (resource == null
          || resource.isEmpty()
          || resource.getBytes(StandardCharsets.UTF_8).length > 16 * 1024)
        throw new IOException("Invalid image resource descriptor");
      return resource;
    } catch (IOException | RuntimeException | Error error) {
      if (handle != null) {
        try {
          sink.cancel(handle);
        } catch (Throwable cleanup) {
          if (cleanup != error) error.addSuppressed(cleanup);
        }
      }
      throw error;
    }
  }

  // The original Kotlin method omits Java's checked throws declaration. Keep
  // the owned adapter's checked contract visible to the suspend caller above.
  private static Object requestImage(
      HttpSource source, Page page, Continuation<? super Response> continuation)
      throws IOException {
    return source.getImage(page, continuation);
  }

  static void pump(BufferedSource source, long length, Sink sink, String handle)
      throws IOException {
    Buffer chunk = new Buffer();
    long total = 0;
    while (true) {
      long count = source.read(chunk, HttpBodySource.MAX_CHUNK);
      if (count == -1) break;
      if (count < 1 || count > HttpBodySource.MAX_CHUNK)
        throw new IOException("Invalid processed image chunk");
      if (count > HttpBodySource.MAX_RESPONSE - total || length >= 0 && count > length - total)
        throw new IOException("Processed image exceeds its length limit");
      total += count;
      sink.write(handle, chunk.readByteArray(count));
    }
    if (total == 0) throw new IOException("Source returned an empty image body");
    if (length >= 0 && total != length) throw new IOException("Processed image length mismatch");
  }
}
