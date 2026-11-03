package prototype;

import org.teavm.backend.javascript.spi.InjectedBy;
import org.teavm.backend.javascript.spi.Injector;
import org.teavm.backend.javascript.spi.InjectorContext;
import org.teavm.model.MethodReference;
import org.teavm.runtime.reflect.ClassReflectionInfo;

/** TeaVM 0.16 omits innerClasses when a reflected class has no nested classes. */
public final class ReflectionSupport {
    @InjectedBy(PrepareInnerClasses.class)
    public static native void prepareInnerClasses(ClassReflectionInfo reflection);

    public static final class PrepareInnerClasses implements Injector {
        @Override public void generate(InjectorContext context, MethodReference method) {
            context.getWriter().append("(");
            context.writeExpr(context.getArgument(0));
            context.getWriter().append(".innerClasses||(");
            context.writeExpr(context.getArgument(0));
            context.getWriter().append(".innerClasses=[]))");
        }
    }
}
