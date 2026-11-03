package org.teavm.classlib.java.util.regex;

/** Method body transplanted into TeaVM's Matcher by TeaTransformer. */
final class MatcherFindMethods {
  private TAbstractSet start;
  private CharSequence string;
  private TMatchResultImpl matchResult;

  private int findAt(int startIndex) {
    matchResult.reset();
    matchResult.hitEnd = false;
    matchResult.requireEnd = false;
    matchResult.setMode(TMatcher.MODE_FIND);
    matchResult.setStartIndex(startIndex);
    int foundIndex = start.find(startIndex, string, matchResult);
    if (foundIndex == -1) {
      TAbstractSet first = start;
      while (first instanceof TSingleSet) {
        first = ((TSingleSet) first).kid;
      }
      // A non-multiline ^ tests only the beginning. Failure does not
      // imply that matching reached the end; its successor records
      // hitEnd itself if it actually needed more input.
      if (!(first instanceof TSOLSet)) {
        matchResult.hitEnd = true;
      }
    }
    return foundIndex;
  }
}
