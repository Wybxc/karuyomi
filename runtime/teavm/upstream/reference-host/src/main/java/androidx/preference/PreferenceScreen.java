package androidx.preference;
public class PreferenceScreen extends Preference {
 public PreferenceScreen(){this(new android.app.Application());}
 public PreferenceScreen(android.content.Context context){super(context);}
 private final java.util.List<Preference> children=new java.util.ArrayList<>();
 public boolean addPreference(Preference preference){if(children.contains(preference))return false;return children.add(preference);}
 public int getPreferenceCount(){return children.size();}
 public Preference getPreference(int index){return children.get(index);}
}
