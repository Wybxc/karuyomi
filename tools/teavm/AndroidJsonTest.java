package prototype;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

/** Exercises Android's JSON-LD access pattern used by the unmodified AsgardScans extension. */
public final class AndroidJsonTest {
  public static void main(String[] args) throws JSONException {
    JSONObject root =
        new JSONObject(
            """
            {"@graph":[null,{"@type":"Other"},
              {"@type":"CreativeWorkSeries","description":"قصة",
               "alternateName":["أول","ثان"],"id":9007199254740993}]}
            """);
    JSONArray graph = root.optJSONArray("@graph");
    if (graph == null || graph.length() != 3 || graph.optJSONObject(0) != null)
      throw new AssertionError("Expected graph with a JSON null and two objects");
    JSONObject series = graph.optJSONObject(2);
    if (series == null
        || !"CreativeWorkSeries".equals(series.optString("@type"))
        || !"قصة".equals(series.opt("description"))
        || !"".equals(series.optString("missing"))
        || series.optJSONArray("description") != null
        || series.optLong("id") != 9007199254740993L)
      throw new AssertionError("Expected Android opt behavior and an exact long");
    JSONArray names = series.optJSONArray("alternateName");
    if (names == null || !"ثان".equals(names.optString(1)) || !"".equals(names.optString(2)))
      throw new AssertionError("Expected array string and Android's absent-index fallback");
    try {
      new JSONObject("{\"@graph\":[");
      throw new AssertionError("Expected malformed input to fail");
    } catch (JSONException expected) {
      System.out.println("Android JSON upstream contract passed");
    }
  }
}
