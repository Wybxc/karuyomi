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
}
if (import.meta.main) await checkDto();
