/** Execute one date contract on the JDK and on the actual product TeaVM transformer. */
import { copyFileSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execa } from 'execa';
import { LOCK } from './runtime.ts';
import { prepareSources } from './upstream-sources.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));

export interface DateFormatCheckOptions {
  root?: string;
  output?: string;
}

export async function checkDateFormat(
  options: DateFormatCheckOptions = {},
): Promise<void> {
  const root = options.root ?? ROOT;
  const local = path.join(root, 'runtime/teavm/.local');
  const output = options.output ?? path.join(local, 'date-format-test');
  const platform = `${process.platform === 'darwin' ? 'macos' : process.platform}-${process.arch}`;
  const archive = LOCK.java.archives[platform];
  if (archive === undefined)
    throw new Error('No locked JDK for the date-format check on ' + platform);
  const javaHome = path.join(local, 'jdks', archive.home);
  const maven = path.join(
    local,
    `build-cache/apache-maven-${LOCK.maven.version}/bin/mvn`,
  );
  if (!existsSync(path.join(javaHome, 'bin/java')) || !existsSync(maven))
    throw new Error(
      'Prepare the locked JDK and Maven before the date-format check',
    );
  for (const name of ['src', 'target'])
    rmSync(path.join(output, name), { recursive: true, force: true });
  const source = path.join(output, 'src/main/java');
  prepareSources(source, root);
  const owned = path.join(root, 'runtime/teavm/java/src/main/java');
  for (const relative of [
    'prototype/TeaTransformer.java',
    'prototype/PlatformSupport.java',
    'prototype/jcl/LocaleMethods.java',
    'prototype/jcl/LocaleState.java',
    'prototype/jcl/WaitListenerMethods.java',
    'org/teavm/classlib/java/lang/WaitObjectMethods.java',
    'org/teavm/classlib/java/lang/WaitInterruptSupport.java',
    'org/teavm/classlib/java/util/regex/MatcherFindMethods.java',
    'org/teavm/classlib/java/util/regex/SingleCharLookBehind.java',
    'org/teavm/classlib/java/util/regex/LineBreakSet.java',
    'org/teavm/classlib/java/util/regex/CasedLetterProperty.java',
  ]) {
    const destination = path.join(source, relative);
    mkdirSync(path.dirname(destination), { recursive: true });
    copyFileSync(path.join(owned, relative), destination);
  }
  copyFileSync(
    path.join(root, 'tools/teavm/DateFormatScenarios.java'),
    path.join(source, 'prototype/DateFormatScenarios.java'),
  );
  copyFileSync(
    path.join(root, 'tools/teavm/fixtures/date-format/pom.xml'),
    path.join(output, 'pom.xml'),
  );
  const execute = execa({
    cwd: output,
    env: { JAVA_HOME: javaHome },
    shell: false,
    stdin: 'ignore',
    preferLocal: false,
    verbose: 'none',
    timeout: 180_000,
    forceKillAfterDelay: 1000,
  });
  await execute(
    maven,
    [
      '-q',
      '--batch-mode',
      '--no-transfer-progress',
      `-Dmaven.repo.local=${path.join(local, 'build-cache/m2')}`,
      'process-classes',
    ],
    { stdout: 'inherit', stderr: 'inherit', buffer: false },
  );
  const oracle = await execute(path.join(javaHome, 'bin/java'), [
    '-cp',
    path.join(output, 'target/classes'),
    'prototype.DateFormatScenarios',
  ]);
  const generated = await execute(process.execPath, [
    '--input-type=commonjs',
    '--eval',
    `require(${JSON.stringify(path.join(output, 'target/javascript/date-format.cjs'))}).main([]);`,
  ]);
  if (
    !oracle.stdout.startsWith('DATE_FORMAT_SCENARIOS_PASS ') ||
    generated.stdout !== oracle.stdout
  )
    throw new Error(
      'Generated TeaVM date contract differs from the JDK oracle',
    );
  console.log('JDK and generated TeaVM JavaScript: ' + oracle.stdout.trim());
}

if (import.meta.main) await checkDateFormat();
