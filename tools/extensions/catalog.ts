/** Pinned Keiyoushi discovery. Never executes upstream Gradle. */
import { execFileSync } from 'node:child_process';
import { existsSync, lstatSync, readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { ROOT } from '../lib/io.ts';
import { canonical, digest } from '../lib/json.ts';
import type { Catalog, ExtensionDescriptor, SubmodulePin } from './model.ts';
export { canonical, digest } from '../lib/json.ts';
export { ROOT } from '../lib/io.ts';
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
  'tools/lib',
  'packages/contracts/protocol.json',
  'packages/runtime-host/materials.ts',
  'packages/runtime-host/prepare-materials.ts',
  'packages/runtime-host/package.json',
  'pnpm-lock.yaml',
  '.node-version',
  '.gitmodules',
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
  return execFileSync('git', ['-C', root, ...args], {
    encoding: 'utf8',
    maxBuffer: 32 * 1024 * 1024,
  }).trim();
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
        sha256: digest(readFileSync(file)),
        executable: (info.mode & 0o111) !== 0,
      };
  }
  visit(target);
  return digest(canonical(records));
}
export function hostSubmodules(root = ROOT): SubmodulePin[] {
  return git(root, 'ls-files', '--stage')
    .split('\n')
    .filter((line) => line.startsWith('160000 '))
    .map((line) => {
      const [metadata, name] = line.split('\t');
      const commit = metadata?.split(' ')[1];
      if (!name || !commit) throw new Error('Invalid submodule gitlink');
      return {
        path: name,
        gitlink: commit,
        checkout:
          name === 'vendor/extensions-source'
            ? commit
            : git(path.join(root, name), 'rev-parse', 'HEAD'),
      };
    })
    .filter((pin) => pin.path !== 'vendor/extensions-source');
}
export function hostFingerprint(root = ROOT): {
  fingerprint: string;
  inputs: Record<string, string>;
} {
  const inputs = Object.fromEntries(
    HOST_PATHS.map((name) => [name, treeHash(root, name)]),
  );
  return {
    fingerprint: digest(
      canonical({
        schemaVersion: 1,
        inputs,
        pinnedSubmodules: hostSubmodules(root),
      }),
    ),
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
      const identity = {
        packageName,
        versionCode: version,
        sourceFingerprint: digest(canonical({ modules: inputs, shared })),
        hostFingerprint: hostHash,
      };
      const fingerprint = digest(canonical(identity));
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
  return {
    schemaVersion: 1,
    upstreamCommit: commit,
    hostFingerprint: hostHash,
    catalogFingerprint: digest(
      canonical({
        entries: entries.map((entry) => entry.inputFingerprint),
        failures,
      }),
    ),
    entries,
    discoveryFailures: failures,
  };
}
