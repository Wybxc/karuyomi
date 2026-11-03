import { mkdirSync } from 'node:fs';
import path from 'node:path';
import { ROOT, files, run } from '../lib/io.ts';

export async function checkDto(root = ROOT): Promise<void> {
  const materials = path.join(
      root,
      'runtime/teavm/.local/runtime-seed/public/runtime',
    ),
    output = path.join(root, 'runtime/teavm/.local/dto-test');
  let jars: string[] = [];
  try {
    jars = files(materials, '.jar');
  } catch {
    /* Report the missing bootstrap below. */
  }
  if (!jars.length)
    throw new Error(
      'Prepare verified runtime materials using node scripts/prepare-runtime.ts',
    );
  mkdirSync(output, { recursive: true });
  const classpath = jars.join(path.delimiter);
  await run('javac', [
    '--release',
    '17',
    '-cp',
    classpath,
    '-d',
    output,
    ...[
      'runtime/teavm/java/src/main/java/prototype/HostDto.java',
      'tools/teavm/HostDtoTest.java',
      'runtime/teavm/java/src/main/java/prototype/HttpBodySource.java',
      'runtime/teavm/java/src/main/java/prototype/HttpRequestSink.java',
      'tools/teavm/HttpBodyTest.java',
    ].map((file) => path.join(root, file)),
  ]);
  for (const oracle of ['prototype.HostDtoTest', 'prototype.HttpBodyTest'])
    await run('java', ['-cp', output + path.delimiter + classpath, oracle]);
  const imageOutput = path.join(output, 'image');
  mkdirSync(imageOutput, { recursive: true });
  await run('javac', [
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
  await run('java', [
    '-cp',
    imageOutput + path.delimiter + classpath,
    'prototype.ImageTest',
  ]);
  // Check the product adapter as well as the original seed HttpSource. Java's
  // checked throws signature is absent from the original Kotlin bytecode.
  const ownedOutput = path.join(output, 'owned-http-source');
  mkdirSync(ownedOutput, { recursive: true });
  await run('javac', [
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
  await run('java', [
    '-cp',
    [ownedOutput, imageOutput, classpath].join(path.delimiter),
    'prototype.ImageTest',
  ]);
}
if (import.meta.main) await checkDto();
