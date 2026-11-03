package org.teavm.classlib.java.util.regex;

import java.util.ArrayList;

/** Bounded lookbehind for one character-class atom, matching the JDK's window. */
final class SingleCharLookBehind extends TAtomicJointSet {
    private final boolean positive;
    private final boolean supplementary;

    static boolean supports(ArrayList<TAbstractSet> children, TFSet end) {
        if (children.size() != 1) {
            return false;
        }
        TAbstractSet atom = children.get(0);
        return atom.getNext() == end && (atom instanceof TSupplRangeSet
                || atom instanceof TRangeSet || atom instanceof TCompositeRangeSet);
    }

    SingleCharLookBehind(ArrayList<TAbstractSet> children, TFSet end,
            boolean positive, boolean supplementary) {
        super(children, end);
        this.positive = positive;
        this.supplementary = supplementary;
    }

    @Override
    public int matches(int index, CharSequence text, TMatchResultImpl result) {
        int left = result.hasTransparentBounds() ? 0 : result.getLeftBound();
        int start = index - 1;
        if (supplementary && start > left && Character.isLowSurrogate(text.charAt(start))
                && Character.isHighSurrogate(text.charAt(start - 1))) {
            start--;
        }
        int saved = result.getConsumed(groupIndex);
        result.setConsumed(groupIndex, index);
        boolean matched;
        try {
            TAbstractSet atom = children.get(0);
            if (start >= left && !supplementary && atom instanceof TCompositeRangeSet
                    && Character.isLowSurrogate(text.charAt(start))) {
                // In its UTF-16 window the JDK can test the trailing surrogate
                // of a pair as a standalone character. The ordinary range node
                // deliberately rejects that split during forward matching.
                TAbstractSet surrogates = ((TCompositeRangeSet) atom).getSurrogates();
                matched = ((TLowHighSurrogateRangeSet) surrogates).getChars()
                        .contains(text.charAt(start));
            } else {
                matched = start >= left && atom.matches(start, text, result) >= 0;
            }
        } finally {
            result.setConsumed(groupIndex, saved);
        }
        return matched == positive ? next.matches(index, text, result) : -1;
    }

    @Override
    public boolean hasConsumed(TMatchResultImpl result) {
        return false;
    }

    @Override
    protected String getName() {
        return "SingleCharLookBehind";
    }
}
