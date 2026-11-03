package android.util;
/** CSS-pixel metrics; these do not imply the existence of an Android Activity. */
public class DisplayMetrics {
  public static final int DENSITY_DEFAULT=160;
  public int widthPixels=800,heightPixels=600,densityDpi=DENSITY_DEFAULT;
  public float density=1f,scaledDensity=1f,xdpi=160f,ydpi=160f;
}
