package prototype.jcl;

/** Method body copied into TeaVM's URL; existing fields and the five-argument setter stay in use. */
public class UrlMethods {
    String authority;
    String userInfo;
    String path;
    String query;

    protected void set(String protocol, String host, int port, String authority,
            String userInfo, String path, String query, String ref) {
        String file = path;
        // An empty query is present: its '?' must survive getFile() and toExternalForm().
        if (query != null) {
            file = new StringBuilder(path == null ? "" : path).append('?').append(query).toString();
        }
        set(protocol, host, port, file, ref);
        this.authority = authority;
        this.userInfo = userInfo;
        this.path = path;
        this.query = query;
    }

    protected void set(String protocol, String host, int port, String file, String ref) {
        throw new AssertionError("Only the eight-argument URL setter is installed");
    }
}
