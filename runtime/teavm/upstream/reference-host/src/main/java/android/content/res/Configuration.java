package android.content.res;
/** Fixed light-mode configuration for the prototype's headless Android context. */
public class Configuration {
  public static final int UI_MODE_NIGHT_MASK=0x30,UI_MODE_NIGHT_NO=0x10,UI_MODE_NIGHT_YES=0x20;
  public int uiMode=UI_MODE_NIGHT_NO;
  public float fontScale=1f;
  public java.util.Locale locale=java.util.Locale.getDefault();
}
