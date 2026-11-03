package java.text;
import java.util.*;import org.teavm.jso.*;
public class Collator implements Comparator<Object>,Cloneable {
 public static final int PRIMARY=0,SECONDARY=1,TERTIARY=2,IDENTICAL=3,NO_DECOMPOSITION=0,CANONICAL_DECOMPOSITION=1,FULL_DECOMPOSITION=2;
 private final String locale;private int strength=TERTIARY;private JSObject nativeCollator;
 private Collator(Locale l){locale=l.toString().replace('_','-');refresh();}public static Collator getInstance(){return getInstance(Locale.getDefault());}public static Collator getInstance(Locale l){return new Collator(l);}public void setStrength(int n){strength=n;refresh();}public int getStrength(){return strength;}public void setDecomposition(int d){if(d!=NO_DECOMPOSITION&&d!=CANONICAL_DECOMPOSITION)throw new IllegalArgumentException("Unsupported decomposition");}
 private void refresh(){nativeCollator=create(locale,strength);}
 @JSBody(params={"locale","strength"},script="return new Intl.Collator(locale||undefined,{sensitivity:strength===0?'base':strength===1?'accent':'variant'});") private static native JSObject create(String locale,int strength);
 @JSBody(params={"collator","a","b"},script="return collator.compare(a,b);") private static native int compareNative(JSObject collator,String a,String b);
 public int compare(String a,String b){return compareNative(nativeCollator,a,b);}public int compare(Object a,Object b){return compare((String)a,(String)b);}public boolean equals(String a,String b){return compare(a,b)==0;}
}
