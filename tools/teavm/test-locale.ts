import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { ROOT, run } from '../lib/io.ts';

export async function testLocale(root = ROOT): Promise<void> {
  const javaHome =
    process.env['JAVA_HOME'] ??
    path.join(root, 'runtime/teavm/.local/jdks/jdk-25.0.5+8/Contents/Home');
  const java = path.join(javaHome, 'bin/java'),
    javac = path.join(javaHome, 'bin/javac');
  const work = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-locale-'));
  try {
    const patch = path.join(work, 'patch'),
      compat = path.join(root, 'runtime/teavm/java/compat');
    mkdirSync(patch);
    await run(javac, [
      '--patch-module',
      `java.base=${compat}`,
      '-d',
      patch,
      path.join(compat, 'java/util/Locale$Builder.java'),
      path.join(compat, 'java/util/IllformedLocaleException.java'),
    ]);
    const test = path.join(work, 'LocaleContract.java');
    writeFileSync(
      test,
      `import java.util.*;
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
}`,
    );
    await run(javac, ['-d', work, test]);
    const args = ['-cp', work, 'LocaleContract'];
    const stock = await run(java, args, { capture: true }),
      adapted = await run(
        java,
        ['--patch-module', `java.base=${patch}`, ...args],
        { capture: true },
      );
    if (stock.stdout !== adapted.stdout)
      throw new Error('Locale.Builder differs from the stock JDK');
    console.log('Locale.Builder: 15 JDK comparison cases passed');
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}
if (import.meta.main) await testLocale();
