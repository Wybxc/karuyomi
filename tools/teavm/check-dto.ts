import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execa } from 'execa';
import { checkFiles } from './check-files.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));

export async function checkDto(root = ROOT): Promise<void> {
  const materials = path.join(
      root,
      'runtime/teavm/.local/runtime-seed/public/runtime',
    ),
    output = path.join(root, 'runtime/teavm/.local/dto-test');
  let jars: string[] = [];
  try {
    jars = readdirSync(materials, { recursive: true, withFileTypes: true })
      .filter((entry) => entry.isFile() && entry.name.endsWith('.jar'))
      .map((entry) => path.join(entry.parentPath, entry.name))
      .sort();
  } catch {
    /* Report the missing bootstrap below. */
  }
  if (!jars.length)
    throw new Error(
      'Prepare verified runtime materials using node scripts/prepare-runtime.ts',
    );
  mkdirSync(output, { recursive: true });
  const classpath = jars.join(path.delimiter);
  const oracle = execa({
    shell: false,
    stdin: 'ignore',
    stdout: 'inherit',
    stderr: 'inherit',
    buffer: false,
    preferLocal: false,
    verbose: 'none',
  });
  await oracle('javac', [
    '--release',
    '17',
    '-cp',
    classpath,
    '-d',
    output,
    ...[
      'runtime/teavm/java/src/main/java/prototype/HostDto.java',
      'runtime/teavm/java/src/main/java/prototype/HostJson.java',
      'tools/teavm/HostDtoTest.java',
      'runtime/teavm/java/src/main/java/prototype/HttpBodySource.java',
      'runtime/teavm/java/src/main/java/prototype/HttpRequestSink.java',
      'tools/teavm/HttpBodyTest.java',
      'runtime/teavm/java/src/main/java/prototype/GraphicsStreams.java',
      'tools/teavm/GraphicsTest.java',
    ].map((file) => path.join(root, file)),
  ]);
  for (const oracleClass of [
    'prototype.HostDtoTest',
    'prototype.HttpBodyTest',
    'prototype.GraphicsTest',
  ])
    await oracle('java', [
      '-cp',
      output + path.delimiter + classpath,
      oracleClass,
    ]);
  // The seed OkHttp JAR has its newCall bytecode adapted for BrowserCall.
  // Oracle execution must use the untouched same-version upstream artifact.
  const originalDependencies = path.join(output, 'cache-original-dependencies');
  mkdirSync(originalDependencies, { recursive: true });
  const originalOkHttp = path.join(
    originalDependencies,
    'okhttp-jvm-5.5.0.jar',
  );
  if (!existsSync(originalOkHttp)) {
    const response = await fetch(
      'https://repo.maven.apache.org/maven2/com/squareup/okhttp3/okhttp-jvm/5.5.0/okhttp-jvm-5.5.0.jar',
    );
    if (!response.ok)
      throw new Error(
        'Original OkHttp oracle dependency: HTTP ' + response.status,
      );
    const bytes = Buffer.from(await response.arrayBuffer());
    if (
      createHash('sha256').update(bytes).digest('hex') !==
      '234194a04aac54858df0a750d243af7b2e39df5e4eb86e9912043ad33a9f9a52'
    )
      throw new Error('Original OkHttp oracle dependency checksum mismatch');
    writeFileSync(originalOkHttp, bytes);
  }
  if (
    createHash('sha256').update(readFileSync(originalOkHttp)).digest('hex') !==
    '234194a04aac54858df0a750d243af7b2e39df5e4eb86e9912043ad33a9f9a52'
  )
    throw new Error('Original OkHttp oracle cache checksum mismatch');
  const originalCacheClasspath = [
    originalOkHttp,
    ...jars.filter(
      (file) =>
        !path.basename(file).startsWith('host-') &&
        path.basename(file) !== 'okhttp-jvm-5.5.0.jar',
    ),
  ].join(path.delimiter);
  const cacheOutput = path.join(output, 'cache-original');
  mkdirSync(cacheOutput, { recursive: true });
  await oracle('javac', [
    '--release',
    '17',
    '-cp',
    originalCacheClasspath,
    '-d',
    cacheOutput,
    ...['CacheScenarios.java', 'CacheTest.java'].map((file) =>
      path.join(root, 'tools/teavm', file),
    ),
  ]);
  await oracle('java', [
    '-cp',
    cacheOutput + path.delimiter + originalCacheClasspath,
    'prototype.CacheTest',
  ]);
  await oracle('javac', [
    '--release',
    '17',
    '-cp',
    cacheOutput + path.delimiter + classpath,
    '-d',
    cacheOutput,
    ...[
      'runtime/teavm/java/src/main/java/prototype/HttpBodySource.java',
      'runtime/teavm/java/src/main/java/prototype/CacheSink.java',
      'tools/teavm/CacheSinkTest.java',
    ].map((file) => path.join(root, file)),
  ]);
  await oracle('java', [
    '-cp',
    cacheOutput + path.delimiter + classpath,
    'prototype.CacheSinkTest',
  ]);
  const imageOutput = path.join(output, 'image');
  mkdirSync(imageOutput, { recursive: true });
  await oracle('javac', [
    '--release',
    '17',
    '-cp',
    classpath,
    '-d',
    imageOutput,
    ...[
      'runtime/teavm/java/src/main/java/prototype/HttpBodySource.java',
      'runtime/teavm/java/src/main/java/prototype/HttpRequestSink.java',
      'runtime/teavm/java/src/main/java/prototype/BrowserCall.java',
      'runtime/teavm/java/src/main/java/prototype/PageSessions.java',
      'runtime/teavm/java/src/main/java/prototype/SourceImages.java',
      'runtime/teavm/java/src/main/java/prototype/GreenCoroutines.java',
      'runtime/teavm/java/src/main/java/eu/kanade/tachiyomi/network/OkHttpExtensionsKt.java',
      'tools/teavm/fixtures/image/prototype/Bridge.java',
      'tools/teavm/ImageTest.java',
    ].map((file) => path.join(root, file)),
  ]);
  await oracle('java', [
    '-cp',
    imageOutput + path.delimiter + classpath,
    'prototype.ImageTest',
  ]);
  // Check the product adapter as well as the original seed HttpSource. Java's
  // checked throws signature is absent from the original Kotlin bytecode.
  const ownedOutput = path.join(output, 'owned-http-source');
  mkdirSync(ownedOutput, { recursive: true });
  await oracle('javac', [
    '--release',
    '17',
    '-cp',
    imageOutput + path.delimiter + classpath,
    '-d',
    ownedOutput,
    ...[
      'runtime/teavm/java/src/main/java/eu/kanade/tachiyomi/source/online/HttpSource.java',
      'runtime/teavm/java/src/main/java/prototype/SourceImages.java',
      'tools/teavm/fixtures/image/prototype/TeaHost.java',
    ].map((file) => path.join(root, file)),
  ]);
  console.log(
    'Running image oracle against the current owned HttpSource adapter',
  );
  await oracle('java', [
    '-cp',
    [ownedOutput, imageOutput, classpath].join(path.delimiter),
    'prototype.ImageTest',
  ]);
  await checkFiles(root);
}
if (import.meta.main) await checkDto();
