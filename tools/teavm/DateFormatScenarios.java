package prototype;

import java.text.ParsePosition;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

/** The same strict HTTP-date contract runs on the JDK and on generated TeaVM JavaScript. */
public final class DateFormatScenarios {
  private static int checks;

  private static void check(boolean value, String message) {
    checks++;
    if (!value) throw new AssertionError("HTTP date assertion " + checks + ": " + message);
  }

  public static void main(String[] args) {
    SimpleDateFormat format = new SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'", Locale.US);
    format.setLenient(false);
    format.setTimeZone(TimeZone.getTimeZone("GMT"));
    String[] weekdays = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
    long first = 1793622896000L;
    for (int day = 0; day < weekdays.length; day++) {
      String text = weekdays[day] + ", 0" + (day + 2) + " Nov 2026 12:34:56 GMT";
      ParsePosition position = new ParsePosition(0);
      Date parsed;
      try {
        parsed = format.parse(text, position);
      } catch (RuntimeException error) {
        throw new AssertionError("Strict RFC date escaped on " + weekdays[day], error);
      }
      check(parsed != null, weekdays[day] + " strict date parses");
      check(parsed.getTime() == first + day * 86400000L, weekdays[day] + " exact UTC instant");
      check(position.getIndex() == text.length(), "successful parse consumes the full RFC date");
      check(position.getErrorIndex() == -1, "successful parse has no new error");
      check(format.format(parsed).equals(text), "parsed date formats to its original weekday");
    }

    String valid = "Sat, 07 Nov 2026 12:34:56 GMT";
    ParsePosition offset = new ParsePosition(2);
    Date parsed = format.parse("xx" + valid, offset);
    check(parsed != null && parsed.getTime() == first + 5 * 86400000L, "nonzero parse offset");
    check(
        offset.getIndex() == valid.length() + 2, "nonzero offset advances from the initial index");

    for (String text :
        new String[] {
          "Mon, 31 Feb 2026 12:34:56 GMT",
          "Mon, 02 Nov 2026 25:34:56 GMT",
          "Mon, 02 Nov 2026 12:60:56 GMT",
          "Mon, 02 Nov 2026 12:34:60 GMT",
          "Mon, 02 Wut 2026 12:34:56 GMT",
          "Wut, 02 Nov 2026 12:34:56 GMT",
          "Mon, 02 Nov",
          ""
        }) {
      ParsePosition position = new ParsePosition(0);
      check(format.parse(text, position) == null, "bad date returns null instead of throwing");
      check(position.getIndex() == 0, "failed parse preserves its initial index");
      check(position.getErrorIndex() >= 0, "failed parse records an error index");
      check(format.parse(valid, position) != null, "a prior error does not poison the next parse");
      check(position.getIndex() == valid.length(), "reused position consumes the next valid date");
    }
    ParsePosition invalidOffset = new ParsePosition(2);
    check(format.parse("xxMon, 02 Nov", invalidOffset) == null, "bad date at nonzero offset");
    check(invalidOffset.getIndex() == 2, "failure restores a nonzero initial index");
    check(invalidOffset.getErrorIndex() >= 2, "nonzero offset reports the failing position");
    System.out.println("DATE_FORMAT_SCENARIOS_PASS " + checks);
  }
}
