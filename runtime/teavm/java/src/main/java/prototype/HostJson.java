package prototype;

import com.google.gson.JsonElement;
import com.google.gson.internal.Streams;
import com.google.gson.stream.JsonWriter;
import java.io.IOException;
import java.io.StringWriter;

/** Match the original Host's default Gson map output without enabling reflective adapters. */
public final class HostJson {
    private HostJson() { }

    public static String write(JsonElement value) {
        StringWriter output = new StringWriter();
        JsonWriter writer = new JsonWriter(output);
        writer.setSerializeNulls(false);
        writer.setHtmlSafe(true);
        try {
            Streams.write(value, writer);
        } catch (IOException impossible) {
            throw new AssertionError(impossible);
        }
        return output.toString();
    }
}
