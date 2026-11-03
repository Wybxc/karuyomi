package prototype.jcl;
import java.io.IOException;
import org.teavm.runtime.fs.VirtualFileAccessor;

/** Copied into TeaVM's RandomAccessFile; closing must release its filesystem descriptor. */
public final class RandomAccessFileMethods {
    private VirtualFileAccessor accessor;
    public void close() throws IOException {
        if(accessor!=null) {
            try { accessor.close(); }
            finally { accessor=null; }
        }
    }
}
