package prototype;

import com.google.gson.*;
import java.io.IOException;
import java.util.*;
import org.teavm.runtime.fs.*;

/** Durable per-plugin filesystem. Original extension File/Okio calls stay unchanged. */
public final class PersistentFileSystem implements VirtualFileSystem {
    public static void install() {
        try {
            call(request("initialize", "/"));
            VirtualFileSystemProvider.setInstance(new PersistentFileSystem());
        } catch (IOException e) {
            throw new IllegalStateException("Persistent Java filesystem could not initialize", e);
        }
    }

    public String getUserDir() { return "/"; }
    public boolean isWindows() { return false; }
    public boolean isCaseSensitive() { return true; }
    public String[] getRoots() { return new String[]{"/"}; }
    public String canonicalize(String path) { return normalize(path); }
    public VirtualFile getFile(String path) { return new Entry(normalize(path)); }

    private static String normalize(String path) {
        Objects.requireNonNull(path);
        Deque<String> parts = new ArrayDeque<>();
        for (String part : path.split("/")) {
            if (part.isEmpty() || part.equals(".")) continue;
            if (part.equals("..")) { if (!parts.isEmpty()) parts.removeLast(); }
            else parts.addLast(part);
        }
        return "/" + String.join("/", parts);
    }

    private static JsonObject request(String operation, String path) {
        JsonObject result = new JsonObject();
        result.addProperty("operation", operation);
        result.addProperty("path", path);
        return result;
    }

    private static JsonObject call(JsonObject request) throws IOException {
        JsonObject result = JsonParser.parseString(Bridge.file(request.toString())).getAsJsonObject();
        if (result.has("error")) throw new IOException(result.get("error").getAsString());
        return result;
    }

    private static boolean flag(JsonObject object, String name) {
        return object.has(name) && object.get(name).getAsBoolean();
    }

    private static final class Entry implements VirtualFile {
        private final String path;
        Entry(String path) { this.path = path; }
        public String getName() { return path.substring(path.lastIndexOf('/') + 1); }
        private JsonObject stat() {
            try { return call(request("stat", path)); }
            catch (IOException e) { return new JsonObject(); }
        }
        public boolean exists() { return flag(stat(), "exists"); }
        public boolean isDirectory() { return flag(stat(), "directory"); }
        public boolean isFile() { return flag(stat(), "file"); }
        public boolean canRead() { return flag(stat(), "readable"); }
        public boolean canWrite() { return flag(stat(), "writable"); }
        public long lastModified() { JsonObject s=stat(); return s.has("modified") ? s.get("modified").getAsLong() : 0; }
        public int length() { JsonObject s=stat(); return s.has("size") ? s.get("size").getAsInt() : 0; }
        public String[] listFiles() {
            try {
                JsonObject result = call(request("list", path));
                if (!result.has("names")) return null;
                JsonArray names = result.getAsJsonArray("names");
                String[] out = new String[names.size()];
                for (int i=0;i<out.length;i++) out[i]=names.get(i).getAsString();
                return out;
            } catch (IOException e) { return null; }
        }
        private JsonObject child(String operation, String name) throws IOException {
            if (name.isEmpty() || name.equals(".") || name.equals("..") || name.indexOf('/')>=0 || name.indexOf('\0')>=0)
                throw new IOException("Invalid file name");
            return request(operation, path.equals("/") ? "/"+name : path+"/"+name);
        }
        public boolean createFile(String name) throws IOException { return flag(call(child("create", name)), "changed"); }
        public boolean createDirectory(String name) {
            try { return flag(call(child("mkdir", name)), "changed"); }
            catch (IOException e) { return false; }
        }
        public boolean delete() { return mutate(request("delete", path)); }
        public boolean adopt(VirtualFile source, String name) {
            if (!(source instanceof Entry)) return false;
            try {
                JsonObject r=child("rename",name);r.addProperty("source",((Entry)source).path);
                return mutate(r);
            } catch (IOException e) { return false; }
        }
        public boolean setLastModified(long time) {
            JsonObject r=request("modified",path);r.addProperty("modified",time);return mutate(r);
        }
        public boolean setReadOnly(boolean readOnly) {
            JsonObject r=request("readonly",path);r.addProperty("readOnly",readOnly);return mutate(r);
        }
        private boolean mutate(JsonObject r) {
            try { return flag(call(r), "changed"); } catch (IOException e) { return false; }
        }
        public VirtualFileAccessor createAccessor(boolean readable, boolean writable, boolean append) {
            try {
                JsonObject r=request("open",path);r.addProperty("readable",readable);
                r.addProperty("writable",writable);r.addProperty("append",append);
                JsonObject out=call(r);return out.has("handle") ? new Accessor(out.get("handle").getAsString()) : null;
            } catch (IOException e) { return null; }
        }
    }

    private static final class Accessor implements VirtualFileAccessor {
        private final String handle;
        private boolean closed;
        Accessor(String handle) { this.handle=handle; }
        private JsonObject command(String operation) throws IOException {
            if (closed) throw new IOException("Stream is closed");
            JsonObject r=request(operation,"/");r.addProperty("handle",handle);return r;
        }
        public int read(byte[] bytes,int offset,int length) throws IOException {
            Objects.checkFromIndexSize(offset,length,bytes.length);
            JsonObject r=command("read");if(length==0)return 0;r.addProperty("length",length);
            JsonObject out=call(r);if(flag(out,"eof"))return -1;
            byte[] data=Base64.getDecoder().decode(out.get("body").getAsString());
            System.arraycopy(data,0,bytes,offset,data.length);return data.length;
        }
        public void write(byte[] bytes,int offset,int length) throws IOException {
            Objects.checkFromIndexSize(offset,length,bytes.length);
            JsonObject r=command("write");r.addProperty("body",Base64.getEncoder().encodeToString(Arrays.copyOfRange(bytes,offset,offset+length)));call(r);
        }
        public int tell() throws IOException { return call(command("tell")).get("position").getAsInt(); }
        public void seek(int position) throws IOException {
            if(position<0)throw new IOException("Negative seek offset");
            JsonObject r=command("seek");r.addProperty("position",position);call(r);
        }
        public void skip(int count) throws IOException {
            JsonObject r=command("skip");r.addProperty("count",count);call(r);
        }
        public int size() throws IOException { return call(command("size")).get("size").getAsInt(); }
        public void resize(int size) throws IOException {
            if(size<0)throw new IOException("Negative file length");
            JsonObject r=command("resize");r.addProperty("size",size);call(r);
        }
        public void flush() throws IOException { call(command("flush")); }
        public void close() throws IOException { if(!closed){call(command("close"));closed=true;} }
    }
}
