package prototype;
import org.teavm.jso.*;

/** Test-only entry point reaches the real Bridge.zstd fiber and callback code. */
public final class ProbeHost {
    public static void main(String[] args) { }
    @JSExport public static void probeBridgeZstd(String operation, String payload) {
        new Thread(() -> {
            try { complete(Bridge.zstd(operation, payload)); }
            catch (Throwable error) { failed(error.getClass().getName(), error.getMessage()); }
        }).start();
    }
    @JSBody(params="value", script="self.bridgeProbe.complete(value);")
    private static native void complete(String value);
    @JSBody(params={"javaClass","message"}, script="self.bridgeProbe.failed(javaClass,message);")
    private static native void failed(String javaClass, String message);
}
