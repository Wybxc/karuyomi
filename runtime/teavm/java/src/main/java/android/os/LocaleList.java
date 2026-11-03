package android.os;

import java.util.Arrays;
import java.util.Locale;
import java.util.Objects;

/** Android locale-list ABI backed by the host's current default Locale. */
public final class LocaleList {
    private final Locale[] locales;

    public LocaleList(Locale... locales) {
        this.locales = locales.clone();
        for (Locale locale : this.locales) Objects.requireNonNull(locale);
    }

    public static LocaleList getDefault() { return new LocaleList(Locale.getDefault()); }
    public static LocaleList getAdjustedDefault() { return getDefault(); }
    public static LocaleList getEmptyLocaleList() { return new LocaleList(); }
    public Locale get(int index) { return index < 0 || index >= locales.length ? null : locales[index]; }
    public int size() { return locales.length; }
    public boolean isEmpty() { return locales.length == 0; }
    public int indexOf(Locale locale) { return Arrays.asList(locales).indexOf(locale); }
    public String toLanguageTags() {
        String[] tags = new String[locales.length];
        for (int i = 0; i < locales.length; i++) tags[i] = locales[i].toLanguageTag();
        return String.join(",", tags);
    }
}
