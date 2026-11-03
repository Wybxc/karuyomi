import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { execa } from 'execa';
import { unzipSync } from 'fflate';
import { LOCK } from './runtime.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const SDK = '15-robolectric-13954326-i7';
const artifacts = [
  [
    'org/robolectric/android-all/15-robolectric-13954326/android-all-15-robolectric-13954326.jar',
    'e17105f6c432357e6bb278a527f8e848d01fc56ccee01be77725bea23d871990',
  ],
  [
    `org/robolectric/android-all-instrumented/${SDK}/android-all-instrumented-${SDK}.jar`,
    '06c4c8602d6db7486266a982bc55834ed6dfebd62a0b88daca204139ecf142cb',
  ],
  [
    'org/robolectric/nativeruntime-dist-compat/1.0.19/nativeruntime-dist-compat-1.0.19.jar',
    '33e0a0982b3ba599763af250b86eb8d67ab6c186c2fa2c5e823ee003bdcd4ed8',
  ],
  [
    'androidx/test/monitor/1.8.0/monitor-1.8.0.aar',
    '56cb7496a06d9f2dca7d3ff76c50a8a30bd18e00a24a3b267d5a31437b278e67',
  ],
  [
    'androidx/test/espresso/espresso-idling-resource/3.7.0/espresso-idling-resource-3.7.0.aar',
    '5ff62326b49c308c1d060466ae3cf4aa0e3deaf9295f077a6886048dda3e9b14',
  ],
] as const;

export interface TextLayoutOracleOptions {
  root?: string;
  repository?: string;
  maven?: string;
  javaHome?: string;
}

/** Independent Android oracle: no runtime seed, owned Android classes, or AWT substitutes. */
export async function checkTextLayout(
  options: TextLayoutOracleOptions = {},
): Promise<void> {
  const root = path.resolve(options.root ?? ROOT);
  const local = path.join(root, 'runtime/teavm/.local');
  const output = path.join(local, 'text-layout-oracle');
  const repository = path.resolve(
    options.repository ?? path.join(local, 'build-cache/m2'),
  );
  const platform = `${process.platform === 'darwin' ? 'macos' : process.platform}-${process.arch}`;
  const archive = LOCK.java.archives[platform];
  const javaHome =
    options.javaHome !== undefined
      ? path.resolve(options.javaHome)
      : archive
        ? path.join(local, 'jdks', archive.home)
        : undefined;
  const maven =
    options.maven !== undefined
      ? path.resolve(options.maven)
      : path.join(
          local,
          `build-cache/apache-maven-${LOCK.maven.version}/bin/mvn`,
        );
  if (
    !javaHome ||
    !existsSync(path.join(javaHome, 'bin/java')) ||
    !existsSync(maven)
  )
    throw new Error(
      'Prepare the locked JDK/Maven, or supply --java-home PATH and --maven PATH. This oracle does not require the runtime seed.',
    );
  // Rebuild only this generated test tree; keep the independent Maven cache.
  for (const name of ['src', 'target'])
    rmSync(path.join(output, name), { recursive: true, force: true });
  const source = path.join(output, 'src/test/java/prototype');
  mkdirSync(source, { recursive: true });
  copyFileSync(
    path.join(root, 'tools/teavm/fixtures/text-layout/pom.xml'),
    path.join(output, 'pom.xml'),
  );
  copyFileSync(
    path.join(root, 'tools/teavm/fixtures/text-layout/AndroidTextTest.java'),
    path.join(source, 'AndroidTextTest.java'),
  );
  copyFileSync(
    path.join(root, 'tools/teavm/TextLayoutScenarios.java'),
    path.join(source, 'TextLayoutScenarios.java'),
  );
  const execute = execa({
    shell: false,
    cwd: output,
    env: { JAVA_HOME: javaHome },
    stdin: 'ignore',
    stdout: 'inherit',
    stderr: 'inherit',
    buffer: false,
    preferLocal: false,
    verbose: 'none',
  });
  const args = [
    '--batch-mode',
    '--no-transfer-progress',
    `-Dmaven.repo.local=${repository}`,
    `-Dandroid.sdk.jar.directory=${path.join(repository, 'org/robolectric/android-all-instrumented', SDK)}`,
  ];
  // Resolve exact dependencies before extracting the two official AndroidX AAR classpaths.
  await execute(maven, [...args, 'test-compile']);
  for (const [relative, expected] of artifacts) {
    const file = path.join(repository, relative);
    const bytes = readFileSync(file);
    if (createHash('sha256').update(bytes).digest('hex') !== expected)
      throw new Error(
        `Android text oracle dependency checksum mismatch: ${relative}`,
      );
    if (file.endsWith('.aar')) {
      const classes = unzipSync(bytes, {
        filter: (entry) => entry.name === 'classes.jar',
      })['classes.jar'];
      if (!classes)
        throw new Error(
          `Android text oracle AAR has no classes.jar: ${relative}`,
        );
      const destination = path.join(
        output,
        'target/aar',
        path.basename(file, '.aar'),
      );
      mkdirSync(destination, { recursive: true });
      writeFileSync(path.join(destination, 'classes.jar'), classes);
    }
  }
  await execute(maven, [...args, 'test']);
}

if (import.meta.main) {
  const { values } = parseArgs({
    options: {
      maven: { type: 'string' },
      'java-home': { type: 'string' },
      repository: { type: 'string' },
    },
  });
  const options: TextLayoutOracleOptions = {};
  if (values.maven !== undefined) options.maven = values.maven;
  if (values['java-home'] !== undefined) options.javaHome = values['java-home'];
  if (values.repository !== undefined) options.repository = values.repository;
  await checkTextLayout(options);
}
