package prototype;

import java.lang.invoke.CallSite;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.invoke.StringConcatFactory;
import org.teavm.classlib.impl.JCLPlugin;
import org.teavm.classlib.impl.PatchedStringConcatFactorySubstitutor;
import org.teavm.model.MethodReference;
import org.teavm.vm.spi.After;
import org.teavm.vm.spi.TeaVMHost;
import org.teavm.vm.spi.TeaVMPlugin;

/** Install the pinned class library fix for invokedynamic concatenation recipes. */
@After(JCLPlugin.class)
public final class StringConcatPlugin implements TeaVMPlugin {
  @Override
  public void install(TeaVMHost host) {
    host.add(
        new MethodReference(
            StringConcatFactory.class,
            "makeConcatWithConstants",
            MethodHandles.Lookup.class,
            String.class,
            MethodType.class,
            String.class,
            Object[].class,
            CallSite.class),
        new PatchedStringConcatFactorySubstitutor());
  }
}
