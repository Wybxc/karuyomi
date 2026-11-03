package androidx.preference;
import android.content.Context;
/** Minimal settings ABI; the prototype does not render Android preferences. */
public class Preference {
 protected final Context context;
 private String key;private CharSequence title,summary;private Object defaultValue;
 private OnPreferenceChangeListener listener;
 private boolean enabled=true, visible=true;
 private OnPreferenceClickListener clickListener;
 public void setVisible(boolean visible){this.visible=visible;}
 public boolean isVisible(){return visible;}
 public void setOnPreferenceClickListener(OnPreferenceClickListener listener){clickListener=listener;}
 public OnPreferenceClickListener getOnPreferenceClickListener(){return clickListener;}
 public interface OnPreferenceClickListener { boolean onPreferenceClick(Preference preference); }
 public Preference(Context context){this.context=context;}
 public Context getContext(){return context;}
 public void setKey(String key){this.key=key;}
 public String getKey(){return key;}
 public void setTitle(CharSequence title){this.title=title;}
 public CharSequence getTitle(){return title;}
 public void setSummary(CharSequence summary){this.summary=summary;}
 public CharSequence getSummary(){return summary;}
 public void setEnabled(boolean enabled){this.enabled=enabled;}
 public boolean isEnabled(){return enabled;}
 public void setDefaultValue(Object value){defaultValue=value;}
 protected Object getDefaultValue(){return defaultValue;}
 public void setOnPreferenceChangeListener(OnPreferenceChangeListener listener){this.listener=listener;}
 public OnPreferenceChangeListener getOnPreferenceChangeListener(){return listener;}
 public boolean callChangeListener(Object value){return listener==null||listener.onPreferenceChange(this,value);}
 public interface OnPreferenceChangeListener{boolean onPreferenceChange(Preference preference,Object value);}
}
