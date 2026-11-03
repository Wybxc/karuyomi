#!/usr/bin/env python3
"""Compare the current-source Locale.Builder subset against the actual JDK."""

from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
JAVA = (
    Path(
        os.environ.get(
            "JAVA_HOME", ROOT / "runtime/teavm/.local/jdks/jdk-25.0.5+8/Contents/Home"
        )
    )
    / "bin"
)
with tempfile.TemporaryDirectory() as temporary:
    work = Path(temporary)
    patch = work / "patch"
    patch.mkdir()
    compat = ROOT / "runtime/teavm/java/compat"
    subprocess.run(
        [
            JAVA / "javac",
            "--patch-module",
            "java.base=" + str(compat),
            "-d",
            patch,
            compat / "java/util/Locale$Builder.java",
            compat / "java/util/IllformedLocaleException.java",
        ],
        check=True,
    )
    test = work / "LocaleContract.java"
    test.write_text("""import java.util.*;
public class LocaleContract {
 public static void main(String[] args) {
  for(String language:new String[]{"en","fr","zh","iw","ji","in","fil",""})
   System.out.println(new Locale.Builder().setLanguage(language).build().toLanguageTag());
  System.out.println(new Locale.Builder().setLanguage("zh").setScript("Hant").setRegion("TW").build().toLanguageTag());
  System.out.println(new Locale.Builder().setLanguage("de").setVariant("1901").setExtension('u',"ca-gregory").build().toLanguageTag());
  System.out.println(new Locale.Builder().setLanguage("en").setRegion("US").clear().build().toLanguageTag());
  for(String invalid:new String[]{"a","en1","en-US","123"}) {
   try {new Locale.Builder().setLanguage(invalid);throw new AssertionError(invalid);}
   catch(IllformedLocaleException expected){System.out.println("invalid");}
  }
 }
}""")
    subprocess.run([JAVA / "javac", "-d", work, test], check=True)
    arguments = ["-cp", str(work), "LocaleContract"]
    stock = subprocess.check_output([JAVA / "java", *arguments])
    adapted = subprocess.check_output(
        [JAVA / "java", "--patch-module", "java.base=" + str(patch), *arguments]
    )
    if stock != adapted:
        raise AssertionError((stock, adapted))
    print("Locale.Builder: 15 JDK comparison cases passed")
