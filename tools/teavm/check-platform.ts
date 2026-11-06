/** Compare owned platform behavior with the JDK and execute dependency bytecode adaptation. */
import { copyFileSync, mkdirSync, mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execa } from 'execa';
import { LOCK } from './runtime.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));

export async function checkPlatform(root = ROOT): Promise<void> {
  const local = path.join(root, 'runtime/teavm/.local'),
    platform =
      (process.platform === 'darwin' ? 'macos' : process.platform) +
      '-' +
      process.arch,
    archive = LOCK.java.archives[platform],
    javaHome =
      process.env['JAVA_HOME'] ??
      (archive ? path.join(local, 'jdks', archive.home) : undefined);
  if (javaHome === undefined)
    throw new Error(
      'No locked Java runtime for platform checks on ' + platform,
    );
  const java = path.join(javaHome, 'bin/java'),
    javac = path.join(javaHome, 'bin/javac'),
    work = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-platform-'));
  const jdk = execa({
    shell: false,
    stdin: 'ignore',
    preferLocal: false,
    stripFinalNewline: false,
    verbose: 'none',
    timeout: 30_000,
    forceKillAfterDelay: 1000,
    maxBuffer: 2 * 1024 * 1024,
  });
  try {
    const source = path.join(work, 'source'),
      patch = path.join(work, 'patch'),
      relative = 'java/util/concurrent/locks/LockSupport.java';
    mkdirSync(path.dirname(path.join(source, relative)), { recursive: true });
    mkdirSync(patch);
    // Compile only LockSupport, so unrelated JDK classes remain the oracle.
    copyFileSync(
      path.join(root, 'runtime/teavm/java/compat', relative),
      path.join(source, relative),
    );
    await jdk(javac, [
      '--patch-module',
      `java.base=${source}`,
      '-d',
      patch,
      path.join(source, relative),
    ]);
    await jdk(javac, [
      '--release',
      '17',
      '-d',
      work,
      path.join(root, 'tools/teavm/LockSupportContract.java'),
    ]);
    const args = ['-cp', work, 'LockSupportContract'];
    const stock = await jdk(java, args, { timeout: 15_000 }),
      adapted = await jdk(
        java,
        ['--patch-module', `java.base=${patch}`, ...args],
        { timeout: 15_000 },
      );
    if (stock.stdout !== adapted.stdout)
      throw new Error('LockSupport behavior differs from the stock JDK');
    console.log('LockSupport: stock JDK behavioral comparison passed');

    const asm = path.join(
        local,
        'build-cache/m2/org/ow2/asm/asm/9.9.1/asm-9.9.1.jar',
      ),
      core = path.join(
        local,
        'runtime-seed/public/runtime/kotlinx-coroutines-core-jvm-1.11.0.jar',
      );
    await jdk(javac, [
      '--release',
      '17',
      '-cp',
      asm,
      '-d',
      work,
      path.join(root, 'tools/teavm/PatchLibraries.java'),
      path.join(root, 'tools/teavm/PatchLibrariesTest.java'),
    ]);
    const transformed = await jdk(
      java,
      [
        '-cp',
        [work, asm].join(path.delimiter),
        'PatchLibrariesTest',
        core,
        work,
      ],
      { timeout: 15_000 },
    );
    console.log(transformed.stdout.trimEnd());
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}

if (import.meta.main) await checkPlatform();
