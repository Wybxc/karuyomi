/** Pinned Keiyoushi discovery. Never executes upstream Gradle. */
import {
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
  realpathSync,
} from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import stableStringify from 'json-stable-stringify';
import { execaSync } from 'execa';
import type { Catalog, ExtensionDescriptor, SubmodulePin } from './model.ts';
export const ROOT = fileURLToPath(new URL('../../', import.meta.url));
export const HOST_PATHS = [
  'runtime/teavm/java',
  'runtime/teavm/bridge',
  'runtime/teavm/patches/teavm',
  'runtime/teavm/toolchain',
  'runtime/teavm/toolchain-lock.json',
  'tools/extensions/builder.ts',
  'tools/extensions/catalog.ts',
  'tools/extensions/assets.ts',
  'tools/extensions/model.ts',
  'tools/teavm/runtime.ts',
  'tools/teavm/build.ts',
  'tools/teavm/upstream-sources.ts',
  'tools/teavm/PatchLibraries.java',
  'protocol',
  'buf.yaml',
  'buf.gen.yaml',
  'packages/protocol/package.json',
  'packages/protocol/tsconfig.json',
  'packages/protocol/src',
  'packages/contracts/src',
  'scripts/generate-protocol.ts',
  'scripts/protoc-gen-dart.ts',
  'tools/protocol/generate.ts',
  'tools/protocol/dart-plugin.ts',
  'tools/protocol/generator/pubspec.yaml',
  'tools/protocol/generator/pubspec.lock',
  'packages/contracts/protocol.json',
  'packages/runtime-host/vite.materials.config.ts',
  'packages/runtime-host/vite.runtime-plugin.ts',
  'packages/runtime-host/package.json',
  'pnpm-lock.yaml',
  '.node-version',
];
export const SHARED_PATHS = [
  'common',
  'core',
  'compiler',
  'gradle',
  'build.gradle.kts',
  'settings.gradle.kts',
  'gradle.properties',
  'gradlew',
  'gradlew.bat',
];
export function git(root: string, ...args: string[]): string {
  return execaSync('git', ['-C', root, ...args], {
    shell: false,
    stdin: 'ignore',
    preferLocal: false,
    stripFinalNewline: false,
    verbose: 'none',
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
  }).stdout.trim();
}
export function treeHash(
  root: string,
  relative: string,
  tracked?: ReadonlySet<string>,
): string {
  const target = path.join(root, relative);
  if (!existsSync(target))
    throw new Error('Missing fingerprint input: ' + relative);
  const ignored = new Set([
    '.git',
    '.local',
    'target',
    'build',
    '__pycache__',
    'node_modules',
    'verification',
    'probes',
  ]);
  const records: Record<string, { sha256: string; executable: boolean }> = {};
  function visit(file: string): void {
    const name = path.relative(root, file).split(path.sep).join('/');
    const info = lstatSync(file);
    if (info.isSymbolicLink()) {
      if (tracked && !tracked.has(name)) return;
      throw new Error('Symlink fingerprint input: ' + name);
    }
    if (
      tracked === undefined &&
      (name.split('/').some((part) => ignored.has(part)) ||
        /\.(pyc|class)$/.test(name))
    )
      return;
    if (info.isDirectory())
      for (const child of readdirSync(file).sort())
        visit(path.join(file, child));
    else if (info.isFile() && (tracked === undefined || tracked.has(name)))
      records[name] = {
        sha256: createHash('sha256').update(readFileSync(file)).digest('hex'),
        executable: (info.mode & 0o111) !== 0,
      };
  }
  visit(target);
  const encoded = stableStringify(records);
  if (encoded === undefined)
    throw new Error('Fingerprint records are not JSON');
  return createHash('sha256').update(encoded).digest('hex');
}
// Candidate image codecs have their own build identity and are not Source inputs.
export const HOST_SUBMODULE_PATHS = [
  'vendor/suwayomi-server',
  'vendor/teavm',
] as const;
export function hostSubmodules(root = ROOT): SubmodulePin[] {
  const gitlinks = new Map(
    git(root, 'ls-files', '--stage', '--', ...HOST_SUBMODULE_PATHS)
      .split('\n')
      .filter(Boolean)
      .map((line) => {
        const [metadata, name] = line.split('\t');
        const [mode, commit, stage] = metadata?.split(' ') ?? [];
        if (mode !== '160000' || !name || !commit || stage !== '0')
          throw new Error('Invalid Source host submodule gitlink');
        return [name, commit] as const;
      }),
  );
  const pins = HOST_SUBMODULE_PATHS.map((name) => {
    const commit = gitlinks.get(name);
    if (!commit)
      throw new Error(
        'Missing required Source host submodule gitlink: ' + name,
      );
    const directory = path.join(root, name);
    if (!existsSync(path.join(directory, '.git')))
      throw new Error(
        'Required Source host submodule is not initialized: ' + name,
      );
    if (
      realpathSync(git(directory, 'rev-parse', '--show-toplevel')) !==
      realpathSync(directory)
    )
      throw new Error(
        'Source host submodule must be its own repository: ' + name,
      );
    const checkout = git(directory, 'rev-parse', 'HEAD');
    if (checkout !== commit)
      throw new Error(
        'Source host submodule HEAD differs from pinned gitlink: ' + name,
      );
    if (git(directory, 'status', '--porcelain', '--untracked-files=no'))
      throw new Error('Source host submodule has dirty tracked files: ' + name);
    return { path: name, gitlink: commit, checkout };
  });
  if (
    git(root, 'diff', '--cached', '--name-only', '--', ...HOST_SUBMODULE_PATHS)
  )
    throw new Error('Source host submodule gitlinks have staged changes');
  return pins;
}
export function hostFingerprint(root = ROOT): {
  fingerprint: string;
  inputs: Record<string, string>;
} {
  const inputs = Object.fromEntries(
    HOST_PATHS.map((name) => [name, treeHash(root, name)]),
  );
  const encoded = stableStringify({
    schemaVersion: 1,
    inputs,
    pinnedSubmodules: hostSubmodules(root),
  });
  if (encoded === undefined) throw new Error('Host fingerprint is not JSON');
  return {
    fingerprint: createHash('sha256').update(encoded).digest('hex'),
    inputs,
  };
}
function literal(
  text: string,
  name: string,
  kind: 'string',
  fallback?: string,
): string;
function literal(text: string, name: string, kind: 'number'): number;
function literal(
  text: string,
  name: string,
  kind: 'string' | 'number',
  fallback?: string,
): string | number {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const assignments = [
    ...text.matchAll(
      new RegExp('^\\s*' + escaped + '\\s*=\\s*(.*?)\\s*$', 'gm'),
    ),
  ];
  if (!assignments.length) {
    if (fallback !== undefined) return fallback;
    throw new Error('Missing literal ' + name);
  }
  if (assignments.length !== 1) throw new Error('Ambiguous ' + name);
  const value = assignments[0]?.[1]?.replace(/\s+\/\/.*$/, '').trim() ?? '';
  if (!(kind === 'number' ? /^\d+$/ : /^"[^"$\n]+"$/).test(value))
    throw new Error('Unsupported expression for ' + name);
  if (kind === 'string') return value.slice(1, -1);
  const number = Number(value);
  if (!Number.isSafeInteger(number))
    throw new Error('Unsafe integer literal ' + name);
  return number;
}
function moduleText(source: string, relative: string): string {
  return readFileSync(
    path.join(source, relative, 'build.gradle.kts'),
    'utf8',
  ).replace(/\/\*[\s\S]*?\*\/|^\s*\/\/[^\n]*/gm, '');
}
export function dependencies(source: string, relative: string): string[] {
  const pending = [relative],
    seen = new Set<string>();
  while (pending.length) {
    const item = pending.pop();
    if (!item || seen.has(item)) continue;
    seen.add(item);
    const text = moduleText(source, item);
    const refs = [...text.matchAll(/\bproject\(\s*["'](:[^"']+)["']\s*\)/g)];
    if (refs.length !== [...text.matchAll(/\bproject\s*\(/g)].length)
      throw new Error('Unsupported dynamic project dependency: ' + item);
    for (const match of refs) {
      const ref = match[1];
      if (!ref || !/^:(?:lib|lib-multisrc):[a-zA-Z0-9_-]+$/.test(ref))
        throw new Error('Unsupported project dependency: ' + ref);
      pending.push(ref.slice(1).replaceAll(':', '/'));
    }
    const theme = literal(text, 'theme', 'string', '');
    if (theme) {
      if (!/^[a-zA-Z0-9_-]+$/.test(theme)) throw new Error('Invalid theme');
      pending.push('lib-multisrc/' + theme);
    }
  }
  return [...seen].sort();
}
export function scan(
  source: string,
  hostHash: string,
  hostInputs: Record<string, string> = {},
  requireClean = true,
): Catalog {
  source = path.resolve(source);
  const commit = git(source, 'rev-parse', 'HEAD');
  if (
    requireClean &&
    git(source, 'status', '--porcelain', '--untracked-files=no')
  )
    throw new Error(
      'Upstream tracked files are dirty; refusing unpinned inputs',
    );
  const tracked = new Set(
    git(source, 'ls-tree', '-r', '--name-only', 'HEAD').split('\n'),
  );
  const cache = new Map<string, string>();
  const hashed = (name: string): string => {
    let value = cache.get(name);
    if (value === undefined) {
      value = treeHash(source, name, tracked);
      cache.set(name, value);
    }
    return value;
  };
  const shared = Object.fromEntries(
    SHARED_PATHS.map((name) => [name, hashed(name)]),
  );
  const entries: ExtensionDescriptor[] = [],
    failures: Catalog['discoveryFailures'] = [],
    packages = new Set<string>();
  for (const name of [...tracked]
    .filter((name) => /^src\/[^/]+\/[^/]+\/build.gradle.kts$/.test(name))
    .sort()) {
    const relative = path.posix.dirname(name);
    try {
      const text = moduleText(source, relative);
      const suffix = literal(
        text,
        'pkgName',
        'string',
        relative.split('/').slice(1).join('.'),
      );
      if (!/^\w+(?:\.\w+)+$/.test(suffix))
        throw new Error('Invalid package suffix');
      const packageName = 'eu.kanade.tachiyomi.extension.' + suffix;
      if (packages.has(packageName))
        throw new Error('Duplicate package name: ' + packageName);
      const declared = literal(text, 'versionCode', 'number'),
        lib = literal(text, 'libVersion', 'string');
      if (!/^\d{1,2}\.\d{1,2}$/.test(lib))
        throw new Error('Unsupported libVersion');
      let effective = declared;
      const theme = literal(text, 'theme', 'string', '');
      if (theme) {
        const themeText = moduleText(source, 'lib-multisrc/' + theme);
        if (literal(themeText, 'libVersion', 'string') !== lib)
          throw new Error('Theme libVersion mismatch');
        effective += literal(themeText, 'baseVersionCode', 'number');
      }
      const version =
        Number(
          lib
            .split('.')
            .map((part) => part.padStart(2, '0'))
            .join(''),
        ) *
          1000 +
        effective;
      if (!Number.isSafeInteger(version) || !Number.isSafeInteger(effective))
        throw new Error('Unsafe effective version');
      const inputs = Object.fromEntries(
        dependencies(source, relative).map((item) => [item, hashed(item)]),
      );
      const sourceIdentity = stableStringify({ modules: inputs, shared });
      if (sourceIdentity === undefined)
        throw new Error('Source fingerprint is not JSON');
      const identity = {
        packageName,
        versionCode: version,
        sourceFingerprint: createHash('sha256')
          .update(sourceIdentity)
          .digest('hex'),
        hostFingerprint: hostHash,
      };
      const encoded = stableStringify(identity);
      if (encoded === undefined)
        throw new Error('Input fingerprint is not JSON');
      const fingerprint = createHash('sha256').update(encoded).digest('hex');
      entries.push({
        schemaVersion: 1,
        ...identity,
        sourcePath: relative,
        upstreamCommit: commit,
        declaredVersionCode: declared,
        effectiveVersionCode: effective,
        versionName: lib + '.' + effective,
        sourceInputs: inputs,
        sharedInputs: shared,
        hostInputs,
        inputFingerprint: fingerprint,
        buildId:
          'ext-' +
          suffix.replace(/[^a-zA-Z0-9._-]/g, '-').slice(0, 80) +
          '-' +
          fingerprint.slice(0, 32),
      });
      packages.add(packageName);
    } catch (error) {
      if (!(error instanceof Error)) throw error;
      failures.push({
        sourcePath: relative,
        status: 'discovery_failed',
        message: error.message,
      });
    }
  }
  if (!entries.length && !failures.length)
    throw new Error('No extension modules found in the pinned source tree');
  const catalogIdentity = stableStringify({
    entries: entries.map((entry) => entry.inputFingerprint),
    failures,
  });
  if (catalogIdentity === undefined)
    throw new Error('Catalog fingerprint is not JSON');
  return {
    schemaVersion: 1,
    upstreamCommit: commit,
    hostFingerprint: hostHash,
    catalogFingerprint: createHash('sha256')
      .update(catalogIdentity)
      .digest('hex'),
    entries,
    discoveryFailures: failures,
  };
}
