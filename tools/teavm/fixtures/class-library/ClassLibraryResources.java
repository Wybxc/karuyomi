package prototype;

import java.util.Collection;
import org.teavm.extension.spi.resources.ResourcesPolicy;

public final class ClassLibraryResources implements ResourcesPolicy {
  @Override
  public String[] supplyResources(Collection<? extends String> names) {
    return new String[] {"assets/example.txt", "prototype/cover sample #.txt"};
  }
}
