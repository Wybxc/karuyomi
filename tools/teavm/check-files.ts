/** Original JVM semantics and the product TeaVM accessor's binary boundary. */
import { mkdirSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execa } from 'execa';
import { LOCK } from './runtime.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
export async function checkFiles(root = ROOT): Promise<void> {
  const local = path.join(root, 'runtime/teavm/.local'),
    output = path.join(local, 'file-tests'),
    materials = path.join(local, 'runtime-seed/public/runtime'),
    teavm = path.join(local, 'build-cache/m2/org/teavm'),
    platform =
      (process.platform === 'darwin' ? 'macos' : process.platform) +
      '-' +
      process.arch,
    archive = LOCK.java.archives[platform];
  if (!archive)
    throw Error('No locked Java runtime for file tests on this platform');
  const javaHome = path.join(local, 'jdks', archive.home),
    seed = readdirSync(materials)
      .filter((name) => name.endsWith('.jar'))
      .map((name) => path.join(materials, name)),
    teavmJars = readdirSync(teavm, { recursive: true, withFileTypes: true })
      .filter((entry) => entry.isFile() && entry.name.endsWith('.jar'))
      .map((entry) => path.join(entry.parentPath, entry.name)),
    classpath = [...seed, ...teavmJars].join(path.delimiter),
    original = path.join(output, 'original'),
    accessor = path.join(output, 'accessor'),
    production = path.join(output, 'production');
  for (const directory of [original, accessor, production])
    mkdirSync(directory, { recursive: true });
  const execute = execa({
    shell: false,
    stdin: 'ignore',
    stdout: 'inherit',
    stderr: 'inherit',
    buffer: false,
    preferLocal: false,
    verbose: 'none',
  });
  await execute(path.join(javaHome, 'bin/javac'), [
    '--release',
    '17',
    '-cp',
    classpath,
    '-d',
    original,
    path.join(root, 'tools/teavm/FileScenarios.java'),
    path.join(root, 'tools/teavm/FileTest.java'),
  ]);
  // No owned Java filesystem class is present in this process's output/classpath.
  await execute(path.join(javaHome, 'bin/java'), [
    '-cp',
    [
      original,
      ...seed.filter((file) => !path.basename(file).startsWith('host-')),
    ].join(path.delimiter),
    'prototype.FileTest',
  ]);
  await execute(path.join(javaHome, 'bin/javac'), [
    '--release',
    '17',
    '-cp',
    classpath,
    '-d',
    accessor,
    path.join(
      root,
      'runtime/teavm/java/src/main/java/prototype/PersistentFileSystem.java',
    ),
    path.join(root, 'tools/teavm/fixtures/files/prototype/Bridge.java'),
    path.join(root, 'tools/teavm/FileAccessorTest.java'),
    ...['FileInputStreamMethods', 'RandomAccessFileMethods'].map((name) =>
      path.join(
        root,
        'runtime/teavm/java/src/main/java/prototype/jcl',
        name + '.java',
      ),
    ),
  ]);
  await execute(path.join(javaHome, 'bin/java'), [
    '-cp',
    accessor + path.delimiter + classpath,
    'prototype.FileAccessorTest',
  ]);
  await execute(path.join(javaHome, 'bin/javac'), [
    '--release',
    '17',
    '-cp',
    classpath,
    '-d',
    production,
    ...[
      'Bridge',
      'Callbacks',
      'JsonValues',
      'HttpBodySource',
      'PersistentFileSystem',
    ].map((name) =>
      path.join(
        root,
        'runtime/teavm/java/src/main/java/prototype',
        name + '.java',
      ),
    ),
  ]);
}
if (import.meta.main) await checkFiles();
