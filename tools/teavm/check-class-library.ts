/** Run the same class library contracts on the JDK and the product TeaVM transformer. */
import {
  copyFileSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  rmSync,
} from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execa } from 'execa';
import { LOCK } from './runtime.ts';
import { prepareSources } from './upstream-sources.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));

export async function checkClassLibrary(root = ROOT): Promise<void> {
  const output = mkdtempSync('/tmp/karuyomi.');
  try {
    await runContracts(root, output);
  } finally {
    rmSync(output, { recursive: true, force: true });
  }
}

async function runContracts(root: string, output: string): Promise<void> {
  const local = path.join(root, 'runtime/teavm/.local');
  const fixtures = path.join(root, 'tools/teavm/fixtures/class-library');
  const platform = `${process.platform === 'darwin' ? 'macos' : process.platform}-${process.arch}`;
  const archive = LOCK.java.archives[platform];
  if (archive === undefined)
    throw new Error('No locked JDK for the class library check on ' + platform);
  const javaHome = path.join(local, 'jdks', archive.home);
  const maven = path.join(
    local,
    `build-cache/apache-maven-${LOCK.maven.version}/bin/mvn`,
  );
  if (!existsSync(path.join(javaHome, 'bin/java')) || !existsSync(maven))
    throw new Error(
      'Prepare the locked JDK and Maven before the class library check',
    );
  const source = path.join(output, 'src/main/java');
  prepareSources(source, root);
  const runtime = path.join(root, 'runtime/teavm/java/src/main');
  const owned = path.join(runtime, 'java');
  for (const relative of [
    'prototype/TeaTransformer.java',
    'prototype/StringConcatPlugin.java',
    'prototype/PlatformSupport.java',
    'prototype/jcl/LocaleMethods.java',
    'prototype/jcl/LocaleState.java',
    'prototype/jcl/PackagedResources.java',
    'prototype/jcl/UrlMethods.java',
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
  for (const name of [
    'ClassLibraryScenarios.java',
    'ClassLibraryResources.java',
    'DigestScenarios.java',
    'Pbkdf2Scenarios.java',
    'EcScenarios.java',
  ])
    copyFileSync(
      path.join(fixtures, name),
      path.join(source, 'prototype', name),
    );
  copyFileSync(
    path.join(root, 'tools/teavm/DateFormatScenarios.java'),
    path.join(source, 'prototype/DateFormatScenarios.java'),
  );
  const resources = path.join(output, 'src/main/resources');
  cpSync(path.join(fixtures, 'resources'), resources, { recursive: true });
  const pluginService = 'META-INF/services/org.teavm.vm.spi.TeaVMPlugin';
  copyFileSync(
    path.join(runtime, 'resources', pluginService),
    path.join(resources, pluginService),
  );
  copyFileSync(path.join(fixtures, 'pom.xml'), path.join(output, 'pom.xml'));
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
  const compat = path.join(root, 'runtime/teavm/java/compat');
  const security = path.join(compat, 'java/security');
  const securitySources = readdirSync(security, {
    recursive: true,
    withFileTypes: true,
  })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.java'))
    .map((entry) => path.join(entry.parentPath, entry.name))
    .sort();
  const classes = path.join(output, 'target/classes');
  const jsoClasspath = ['teavm-interop', 'teavm-jso', 'teavm-jso-apis']
    .map((artifact) =>
      path.join(
        local,
        'build-cache/m2/org/teavm',
        artifact,
        LOCK.teavm,
        `${artifact}-${LOCK.teavm}.jar`,
      ),
    )
    .join(path.delimiter);
  mkdirSync(classes, { recursive: true });
  await execute(path.join(javaHome, 'bin/javac'), [
    '--patch-module',
    `java.base=${compat}`,
    '--add-reads',
    'java.base=ALL-UNNAMED',
    '-cp',
    jsoClasspath,
    '-d',
    classes,
    ...securitySources,
    ...[
      'javax/crypto/KeyAgreement.java',
      'javax/crypto/SecretKeyFactory.java',
      'javax/crypto/spec/PBEKeySpec.java',
      'javax/crypto/spec/SecretKeySpec.java',
    ].map((name) => path.join(compat, name)),
  ]);
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
  const java = (...args: string[]) =>
    execute(path.join(javaHome, 'bin/java'), [
      '-cp',
      classes,
      'prototype.ClassLibraryScenarios',
      ...args,
    ]);
  const javascript = (...args: string[]) =>
    execute(process.execPath, [
      '--input-type=commonjs',
      '--eval',
      `require(${JSON.stringify(path.join(output, 'target/javascript/class-library.cjs'))}).main(process.argv.slice(1));`,
      '--',
      ...args,
    ]);
  const [oracle, generated] = await Promise.all([java(), javascript()]);
  if (
    !oracle.stdout.includes('DATE_FORMAT_SCENARIOS_PASS ') ||
    !oracle.stdout.includes('PACKAGED_RESOURCE_SCENARIOS_PASS ') ||
    !oracle.stdout.includes('DIGEST_SCENARIOS_PASS ') ||
    !oracle.stdout.includes('PBKDF2_SCENARIOS_PASS ') ||
    !oracle.stdout.includes('TIME_ZONE_SCENARIOS_PASS ') ||
    !oracle.stdout.includes('STRING_CONCAT_SCENARIO_PASS') ||
    !oracle.stdout.includes('EC_SCENARIOS_PASS ') ||
    generated.stdout !== oracle.stdout
  )
    throw new Error(
      'Generated TeaVM class library contract differs from the JDK oracle',
    );
  console.log('JDK and generated TeaVM JavaScript: ' + oracle.stdout.trim());
  const [jdkSignature, workerSignature] = await Promise.all([
    java('emit-ec-signature'),
    javascript('emit-ec-signature'),
  ]);
  const [verifiedByJdk, verifiedByWorker] = await Promise.all([
    java('verify-ec-signature', ...signatureFields(workerSignature.stdout)),
    javascript('verify-ec-signature', ...signatureFields(jdkSignature.stdout)),
  ]);
  if (
    [verifiedByJdk, verifiedByWorker].some(
      (result) => result.stdout !== 'EC_INTEROP_VERIFIED',
    )
  )
    throw new Error('ECDSA verification failed between the JDK and TeaVM');
  console.log(
    'ECDSA signatures and X.509 keys verified in both runtime directions',
  );
}

function signatureFields(output: string): [string, string] {
  const match = /^EC_INTEROP ([0-9a-f]{182}) ([0-9a-f]{16,144})$/.exec(output);
  if (!match?.[1] || !match[2])
    throw new Error('Invalid ECDSA interoperability fixture output');
  return [match[1], match[2]];
}

if (import.meta.main) await checkClassLibrary();
