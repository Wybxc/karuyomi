package probe;

import java.io.IOException;
import java.io.InterruptedIOException;
import org.teavm.interop.Async;
import org.teavm.interop.AsyncCallback;
import org.teavm.jso.*;
import org.teavm.jso.typedarrays.Uint8Array;

/** Isolated TeaVM 0.16.0 JS boundary probe, never a product network bridge. */
public final class ByteProbe {
    private static final int MAX_CHUNK = 64 * 1024;
    private static byte[] retained;
    public static void main(String[] args) { }

    private static byte[] copyIn(Uint8Array input) {
        int length = input.getByteLength();
        if (length > MAX_CHUNK) throw new IllegalArgumentException("Chunk exceeds 64 KiB");
        byte[] bytes = new byte[length];
        for (int index = 0; index < length; index++) bytes[index] = (byte) input.get(index);
        return bytes;
    }

    private static Uint8Array copyOut(byte[] bytes) {
        Uint8Array output = new Uint8Array(bytes.length);
        for (int index = 0; index < bytes.length; index++) output.set(index, (short) (bytes[index] & 255));
        return output;
    }

    @JSExport public static Uint8Array probeRoundTrip(Uint8Array input) { return copyOut(copyIn(input)); }
    @JSExport public static Uint8Array probeRetain(Uint8Array input) { retained = copyIn(input); return copyOut(retained); }
    @JSExport public static Uint8Array probeRetained() { return copyOut(retained); }
    @JSExport public static boolean probeRetainedPresent() { return retained != null; }
    @JSExport public static void probeRelease() { retained = null; }

    @JSExport public static void probeRead(String id, int maxBytes) {
        new Thread(() -> {
            try {
                if (maxBytes < 1 || maxBytes > MAX_CHUNK) throw new IllegalArgumentException("Invalid chunk limit");
                Uint8Array input = read(id, maxBytes);
                if (input.getByteLength() > maxBytes) throw new IOException("Supplier exceeded requested chunk limit");
                deliver(id, copyOut(copyIn(input)));
            } catch (Throwable error) { failed(id, error.getClass().getName() + ": " + error.getMessage()); }
        }).start();
    }

    @JSExport public static void probeCancel(String id) { cancel(id); }
    @Async private static native Uint8Array read(String id, int maxBytes) throws IOException;
    private static void read(String id, int maxBytes, AsyncCallback<Uint8Array> callback) {
        request(id, maxBytes, callback::complete, (message, cancelled) -> callback.error(
            cancelled ? new InterruptedIOException(message) : new IOException(message)));
    }
    @JSFunctor interface ChunkReply extends JSObject { void call(Uint8Array bytes); }
    @JSFunctor interface FailureReply extends JSObject { void call(String message, boolean cancelled); }
    @JSBody(params={"id", "max", "ok", "fail"}, script="self.byteProbe.read(id,max).then(ok,failureReason=>fail(String(failureReason.message),failureReason.name==='AbortError'));")
    private static native void request(String id, int max, ChunkReply ok, FailureReply fail);
    @JSBody(params={"id", "bytes"}, script="self.byteProbe.done(id,bytes);")
    private static native void deliver(String id, Uint8Array bytes);
    @JSBody(params={"id", "message"}, script="self.byteProbe.failed(id,message);")
    private static native void failed(String id, String message);
    @JSBody(params="id", script="self.byteProbe.cancel(id);")
    private static native void cancel(String id);
}
