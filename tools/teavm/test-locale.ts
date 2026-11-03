import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execa } from 'execa';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));

export async function testLocale(root = ROOT): Promise<void> {
  const javaHome =
    process.env['JAVA_HOME'] ??
    path.join(root, 'runtime/teavm/.local/jdks/jdk-25.0.5+8/Contents/Home');
  const java = path.join(javaHome, 'bin/java'),
    javac = path.join(javaHome, 'bin/javac');
  const work = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-locale-'));
  const jdk = execa({
    shell: false,
    stdin: 'ignore',
    preferLocal: false,
    stripFinalNewline: false,
    verbose: 'none',
    maxBuffer: 2 * 1024 * 1024,
  });
  try {
    const patch = path.join(work, 'patch'),
      compat = path.join(root, 'runtime/teavm/java/compat');
    mkdirSync(patch);
    await jdk(
      javac,
      [
        '--patch-module',
        `java.base=${compat}`,
        '-d',
        patch,
        path.join(compat, 'java/util/Locale$Builder.java'),
        path.join(compat, 'java/util/IllformedLocaleException.java'),
      ],
      { stdout: 'inherit', stderr: 'inherit', buffer: false },
    );
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
    await jdk(javac, ['-d', work, test], {
      stdout: 'inherit',
      stderr: 'inherit',
      buffer: false,
    });
    const args = ['-cp', work, 'LocaleContract'];
    const stock = await jdk(java, args),
      adapted = await jdk(java, [
        '--patch-module',
        `java.base=${patch}`,
        ...args,
      ]);
    if (stock.stdout !== adapted.stdout)
      throw new Error('Locale.Builder differs from the stock JDK');
    console.log('Locale.Builder: 15 JDK comparison cases passed');
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}
if (import.meta.main) await testLocale();
