import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import locked from '../../runtime/teavm/toolchain-lock.json' with { type: 'json' };
import { ROOT, run, safeName } from '../lib/io.ts';
import { digest, writeJson } from '../lib/json.ts';
import { extractTar, extractZip } from '../lib/archive.ts';

interface JavaArchive {
  url: string;
  mirrors?: string[];
  sha256: string;
  home: string;
}
interface AndroidArchive {
  url: string;
  sha1: string;
  destination: string;
}
export interface RuntimeLock {
  schemaVersion: number;
  java: { major: number; archives: Record<string, JavaArchive> };
  teavm: string;
  maven: { version: string; url: string; sha512: string };
  gradle: { version: string; sha256: string };
  seed: {
    repo: string;
    tag: string;
    asset: string;
    url: string;
    sha256: string;
    size: number;
    members: Record<string, string>;
  };
  android: {
    archives: Record<string, AndroidArchive>;
    metadata: Record<string, { path: string; sha256: string }>;
  };
}
export const LOCK: RuntimeLock = locked;
export interface PreparedRuntime {
  schemaVersion: number;
  materials: string;
  maven: string;
  androidSdk: string;
  javaHome: string;
  lockSha256: string;
  seedSha256: string;
}
export interface RuntimeOptions {
  root?: string;
  seed?: string;
  android?: boolean;
  lock?: RuntimeLock;
}

function hash(data: Uint8Array, algorithm: 'sha1' | 'sha512'): string {
  return createHash(algorithm).update(data).digest('hex');
}
function requireEntry<T>(entry: T | undefined, name: string): T {
  if (entry === undefined) throw new Error(`Missing locked archive: ${name}`);
  return entry;
}
async function download(url: string): Promise<Buffer> {
  const response = await fetch(url, { signal: AbortSignal.timeout(180000) });
  if (!response.ok)
    throw new Error(`Download failed (${response.status}): ${url}`);
  return Buffer.from(await response.arrayBuffer());
}
export function verifyMaterials(
  destination: string,
  lock: RuntimeLock = LOCK,
): void {
  for (const [name, expected] of Object.entries(lock.seed.members)) {
    safeName(name);
    const file = path.join(destination, name);
    if (!existsSync(file) || digest(readFileSync(file)) !== expected)
      throw new Error(`Runtime material missing or altered: ${name}`);
  }
}

export async function prepareRuntime(
  options: RuntimeOptions = {},
): Promise<PreparedRuntime> {
  const root = options.root ?? ROOT,
    lock = options.lock ?? LOCK,
    local = path.join(root, 'runtime/teavm/.local');
  mkdirSync(local, { recursive: true });
  const materials = path.join(local, 'runtime-seed');
  let valid = false;
  try {
    verifyMaterials(materials, lock);
    valid = true;
  } catch {
    /* Rebuild missing or corrupted verified materials. */
  }
  if (!valid) {
    const asset = options.seed
      ? path.resolve(options.seed)
      : path.join(local, 'downloads', lock.seed.asset);
    if (!existsSync(asset)) {
      mkdirSync(path.dirname(asset), { recursive: true });
      await run('gh', [
        'release',
        'download',
        lock.seed.tag,
        '--repo',
        lock.seed.repo,
        '--pattern',
        lock.seed.asset,
        '--dir',
        path.dirname(asset),
        '--clobber',
      ]);
    }
    const data = readFileSync(asset);
    if (data.length !== lock.seed.size || digest(data) !== lock.seed.sha256)
      throw new Error('Runtime seed archive checksum/size mismatch');
    const staging = path.join(local, 'runtime-seed.extracting');
    rmSync(staging, { recursive: true, force: true });
    try {
      await extractTar(asset, staging, new Set(Object.keys(lock.seed.members)));
      verifyMaterials(staging, lock);
      rmSync(materials, { recursive: true, force: true });
      renameSync(staging, materials);
    } finally {
      rmSync(staging, { recursive: true, force: true });
    }
  }
  const cache = path.join(local, 'build-cache'),
    maven = path.join(cache, `apache-maven-${lock.maven.version}/bin/mvn`);
  if (!existsSync(maven)) {
    const data = await download(lock.maven.url);
    if (hash(data, 'sha512') !== lock.maven.sha512)
      throw new Error('Maven checksum mismatch');
    mkdirSync(cache, { recursive: true });
    const archive = path.join(cache, 'maven.tar.gz');
    writeFileSync(archive, data);
    await extractTar(archive, cache);
    rmSync(archive);
  }
  const system =
    process.platform === 'darwin' && process.arch === 'arm64'
      ? 'macos-arm64'
      : process.platform === 'linux' && process.arch === 'x64'
        ? 'linux-x64'
        : undefined;
  if (!system)
    throw new Error('Unsupported build host; use macOS arm64 or Linux x64');
  const jdk = requireEntry(lock.java.archives[system], system),
    javaHome = path.join(local, 'jdks', jdk.home);
  if (!existsSync(path.join(javaHome, 'bin/java'))) {
    const filename = new URL(jdk.url).pathname.split('/').at(-1);
    if (!filename) throw new Error('Invalid locked JDK archive URL');
    const archive = path.join(local, 'downloads', filename);
    mkdirSync(path.dirname(archive), { recursive: true });
    if (!existsSync(archive)) {
      let obtained = false;
      for (const url of [...(jdk.mirrors ?? []), jdk.url]) {
        try {
          const data = await download(url);
          if (digest(data) !== jdk.sha256)
            throw new Error('JDK download checksum mismatch');
          writeFileSync(archive, data);
          obtained = true;
          break;
        } catch (error) {
          console.error(
            `JDK mirror failed: ${error instanceof Error ? error.message : String(error)}`,
          );
        }
      }
      if (!obtained) throw new Error('JDK download failed');
    }
    if (digest(readFileSync(archive)) !== jdk.sha256)
      throw new Error('JDK checksum mismatch');
    await extractTar(archive, path.join(local, 'jdks'));
  }
  const sdk = path.join(local, 'android-sdk');
  if (options.android) {
    for (const key of ['platform', system, `platform-tools-${system}`]) {
      const entry = requireEntry(lock.android.archives[key], key),
        target = path.join(sdk, entry.destination),
        marker = path.join(target, '.karuyomi-archive-sha1');
      if (existsSync(marker) && readFileSync(marker, 'utf8') === entry.sha1)
        continue;
      const data = await download(entry.url);
      if (hash(data, 'sha1') !== entry.sha1)
        throw new Error('Android archive checksum mismatch');
      const archive = path.join(local, 'downloads', `android-${key}.zip`);
      mkdirSync(path.dirname(archive), { recursive: true });
      writeFileSync(archive, data);
      await extractZip(archive, target, true);
      rmSync(archive);
      mkdirSync(target, { recursive: true });
      writeFileSync(marker, entry.sha1);
    }
    const destinations: Record<string, string> = {
      platform: path.join(
        sdk,
        requireEntry(lock.android.archives['platform'], 'platform').destination,
        'package.xml',
      ),
      'build-tools': path.join(
        sdk,
        requireEntry(lock.android.archives[system], system).destination,
        'package.xml',
      ),
      'platform-tools': path.join(sdk, 'platform-tools/package.xml'),
      license: path.join(sdk, 'licenses/android-sdk-license'),
    };
    for (const [name, entry] of Object.entries(lock.android.metadata)) {
      const payload = readFileSync(
        path.join(root, 'runtime/teavm', entry.path),
      );
      if (digest(payload) !== entry.sha256)
        throw new Error(`Android metadata checksum mismatch: ${name}`);
      const target = requireEntry(destinations[name], name);
      mkdirSync(path.dirname(target), { recursive: true });
      writeFileSync(target, payload);
    }
  }
  const result: PreparedRuntime = {
    schemaVersion: 1,
    materials,
    maven,
    androidSdk: sdk,
    javaHome,
    lockSha256: digest(
      readFileSync(path.join(root, 'runtime/teavm/toolchain-lock.json')),
    ),
    seedSha256: lock.seed.sha256,
  };
  writeJson(path.join(local, 'prepared-runtime.json'), result);
  return result;
}

export async function main(args = process.argv.slice(2)): Promise<void> {
  const { parseArgs } = await import('node:util');
  const { values } = parseArgs({
    args,
    options: {
      seed: { type: 'string' },
      android: { type: 'boolean', default: false },
    },
  });
  console.log(
    JSON.stringify(
      await prepareRuntime({
        ...(values.seed ? { seed: values.seed } : {}),
        android: values.android,
      }),
      null,
      2,
    ),
  );
}
