package prototype;
import android.icu.text.*;
import java.text.StringCharacterIterator;

public final class IcuProbe {
  public static boolean run() {
    if (!Normalizer2.getNFKCCasefoldInstance().normalize("ＡStraße\u00ad").equals("astrasse")) throw new AssertionError("NFKC case folding");
    BreakIterator chars = BreakIterator.getCharacterInstance();
    chars.setText(new StringCharacterIterator("👩‍💻"));
    if (chars.first() != 0 || chars.next() != 5 || chars.next() != BreakIterator.DONE) throw new AssertionError("Grapheme segmentation");
    BreakIterator words = BreakIterator.getWordInstance();
    words.setText(new StringCharacterIterator("hello world"));
    int count=0; words.first();
    while(words.next()!=BreakIterator.DONE) if(words.getRuleStatus()!=BreakIterator.WORD_NONE) count++;
    if(count!=2) throw new AssertionError("Word status");
    RuleBasedCollator collator=(RuleBasedCollator)Collator.getInstance();
    collator.setStrength(Collator.PRIMARY);
    collator.setDecomposition(Collator.NO_DECOMPOSITION);
    collator.setCaseLevel(true);
    StringSearch search=new StringSearch("ana",new StringCharacterIterator("banana"),collator);
    search.setOverlapping(true);
    if(search.first()!=1||!search.getMatchedText().equals("ana")||search.next()!=3||search.next()!=StringSearch.DONE) throw new AssertionError("Overlapping search");
    search.setTarget(new StringCharacterIterator("café"));
    search.setPattern("cafe");
    if(search.first()!=0) throw new AssertionError("Primary collation");
    return true;
  }
  public static void main(String[] args) {System.out.println("ICU Unicode regression: " + run());}
}
