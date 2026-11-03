/** Verify the locked seed gap and the owned Source network configuration separately. */
import { mkdirSync, readdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execa } from 'execa';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));

export async function checkNetwork(root = ROOT): Promise<void> {
  const local = path.join(root, 'runtime/teavm/.local'),
    materials = path.join(local, 'runtime-seed/public/runtime'),
    output = path.join(local, 'network-test'),
    seedOutput = path.join(output, 'seed'),
    ownedOutput = path.join(output, 'owned'),
    jars = readdirSync(materials)
      .filter((name) => name.endsWith('.jar'))
      .sort()
      .map((name) => path.join(materials, name)),
    host = jars.find((file) => path.basename(file) === 'host-44fb93b22828.jar');
  if (!host)
    throw Error('Prepare the locked runtime seed before network checks');
  const teavm = path.join(local, 'build-cache/m2/org/teavm'),
    teavmJars = readdirSync(teavm, { recursive: true, withFileTypes: true })
      .filter((entry) => entry.isFile() && entry.name.endsWith('.jar'))
      .map((entry) => path.join(entry.parentPath, entry.name)),
    // The seed supplies the runtime Android classes; the Android API stub JAR
    // must not shadow Context/Application when exercising the actual adapter.
    classpath = [
      host,
      ...jars.filter((file) => file !== host),
      ...teavmJars,
    ].join(path.delimiter),
    test = path.join(root, 'tools/teavm/NetworkHelperTest.java'),
    execute = execa({
      shell: false,
      stdin: 'ignore',
      stdout: 'inherit',
      stderr: 'inherit',
      buffer: false,
      preferLocal: false,
      verbose: 'none',
    });
  // Old class files must not turn a missing owned input into a passing check.
  rmSync(output, { recursive: true, force: true });
  for (const directory of [seedOutput, ownedOutput])
    mkdirSync(directory, { recursive: true });
  await execute('javac', [
    '--release',
    '17',
    '-cp',
    classpath,
    '-d',
    seedOutput,
    test,
  ]);
  await execute('java', [
    '-cp',
    [seedOutput, classpath].join(path.delimiter),
    'prototype.NetworkHelperTest',
    'seed',
    pathToFileURL(host).href,
  ]);
  await execute('javac', [
    '--release',
    '17',
    '-cp',
    classpath,
    '-d',
    ownedOutput,
    ...[
      'eu/kanade/tachiyomi/network/NetworkHelper',
      'eu/kanade/tachiyomi/network/OkHttpExtensionsKt',
      'okhttp3/OkHttpClient',
      'okhttp3/Cache',
      'prototype/Bridge',
      'prototype/BrowserCall',
      'prototype/Callbacks',
      'prototype/CacheSink',
      'prototype/JsonValues',
      'prototype/HttpBodySource',
      'prototype/HttpRequestSink',
    ].map((name) =>
      path.join(root, 'runtime/teavm/java/src/main/java', name + '.java'),
    ),
    test,
  ]);
  await execute('java', [
    '-cp',
    [ownedOutput, classpath].join(path.delimiter),
    'prototype.NetworkHelperTest',
    'owned',
    pathToFileURL(ownedOutput + path.sep).href,
  ]);
}

if (import.meta.main) await checkNetwork();
