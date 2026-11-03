package org.teavm.classlib.java.util.regex;

/** Java's Lu/Ll/Lt properties share the cased-letter set under CASE_INSENSITIVE. */
final class CasedLetterProperty extends TAbstractCharClass {
    CasedLetterProperty(boolean negative) {
        mayContainSupplCodepoints = true;
        setNegative(negative);
    }

    @Override
    public boolean contains(int codePoint) {
        int type = Character.getType(codePoint);
        return alt ^ (type == Character.UPPERCASE_LETTER
                || type == Character.LOWERCASE_LETTER || type == Character.TITLECASE_LETTER);
    }
}
