package prototype.jcl;

import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URL;
import java.net.URLConnection;
import java.net.URLStreamHandler;

/** Gives TeaVM's packaged classpath resources a URL backed by the existing resource table. */
public final class PackagedResources {
  private static final String PROTOCOL = "teavm-resource";

  private static final URLStreamHandler HANDLER =
      new URLStreamHandler() {
        @Override
        protected URLConnection openConnection(URL url) throws IOException {
          if (!PROTOCOL.equals(url.getProtocol()) || !"".equals(url.getHost()))
            throw new IOException("Invalid packaged resource URL");
          String path = URI.create(url.getPath()).getPath();
          if (path == null || !path.startsWith("/"))
            throw new IOException("Invalid packaged resource path");
          String name = path.substring(1);
          return new URLConnection(url) {
            @Override
            public void connect() {
              connected = true;
            }

            @Override
            public InputStream getInputStream() throws IOException {
              InputStream input = ClassLoader.getSystemResourceAsStream(name);
              if (input == null) throw new FileNotFoundException(name);
              connect();
              return input;
            }
          };
        }
      };

  private PackagedResources() {}

  public static URL getResource(Class<?> owner, String name) {
    String absoluteName = classpathName(owner, name);
    try (InputStream input = ClassLoader.getSystemResourceAsStream(absoluteName)) {
      if (input == null) return null;
      String path = new URI(null, null, "/" + absoluteName, null).getRawPath();
      return new URL(PROTOCOL, "", -1, path, HANDLER);
    } catch (IOException | URISyntaxException error) {
      throw new IllegalStateException("Could not make a packaged resource URL", error);
    }
  }

  private static String classpathName(Class<?> owner, String name) {
    if (name.startsWith("/")) return name.substring(1);
    while (owner.isArray()) owner = owner.getComponentType();
    String type = owner.getName();
    int packageEnd = type.lastIndexOf('.');
    return packageEnd < 0 ? name : type.substring(0, packageEnd + 1).replace('.', '/') + name;
  }
}
