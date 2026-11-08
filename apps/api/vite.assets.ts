import { createHash } from 'node:crypto';
import {
  cp,
  mkdir,
  readFile,
  readdir,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, URL } from 'node:url';
import {
  runtimeMaterialCatalogSchema,
  preferenceRulesAssetPath,
  type BuildManifest,
  type RuntimeMaterialCatalog,
} from '@karuyomi/contracts';
import {
  parseExtensionIndex,
  parseManifest,
} from '../../tools/extensions/verify-manifest.ts';

import type { Plugin } from 'vite';

export function karuyomiStaticAssets(): Plugin {
  return {
    name: 'karuyomi-static-assets',
    enforce: 'pre',
    apply: 'build',
    async config() {
      await prepareStaticAssets();
    },
  };
}

async function prepareStaticAssets(): Promise<void> {
  const publicDir = new URL('../../dist/public/', import.meta.url);
  const runtime = new URL('../../packages/runtime-host/dist/', import.meta.url);
  const flutterWeb = new URL('../reader/build/web/', import.meta.url);
  const nativeFlutterPath = path.join('assets', 'assets', 'runtime');
  const inside = (relative: string, directory: string) =>
    relative === directory || relative.startsWith(directory + path.sep);
  await rm(publicDir, { recursive: true, force: true });
  await mkdir(publicDir, { recursive: true });
  await cp(flutterWeb, publicDir, {
    recursive: true,
    // Pubspec bundles native assets into Flutter Web too. Web never reads them.
    filter: (source) =>
      !inside(
        path.relative(fileURLToPath(flutterWeb), source),
        nativeFlutterPath,
      ),
  });
  await cp(runtime, new URL('runtime/', publicDir), {
    recursive: true,
    filter: (source) => {
      const relative = path.relative(fileURLToPath(runtime), source);
      return !inside(relative, 'native');
    },
  });

  // Hash-only names need explicit MIME declarations. Keep Flutter's existing
  // rules and publish the current immutable shared materials.
  const catalog = runtimeMaterialCatalogSchema.parse(
    JSON.parse(await readFile(new URL('materials.json', runtime), 'utf8')),
  );
  const materials = [...catalog.hostScripts, ...catalog.resources];
  const extensionCount = await assembleExtensionAssets(
    fileURLToPath(publicDir),
    catalog,
    fileURLToPath(new URL('../../.local/extensions-assets', import.meta.url)),
  );
  const headerFile = new URL('_headers', publicDir);
  let headers = '';
  try {
    headers = await readFile(headerFile, 'utf8');
  } catch (error) {
    if (
      !(error instanceof Error) ||
      !('code' in error) ||
      error.code !== 'ENOENT'
    )
      throw error;
  }
  const rules = materials.map(
    (artifact: { path: string; contentType: string }) =>
      `${artifact.path}\n  Content-Type: ${artifact.contentType}\n  Cache-Control: public, max-age=31536000, immutable\n  X-Content-Type-Options: nosniff`,
  );
  rules.push(
    '/runtime/materials.json\n  Content-Type: application/json; charset=utf-8\n  Cache-Control: no-cache\n  X-Content-Type-Options: nosniff',
    '/extensions/index.json\n  Content-Type: application/json; charset=utf-8\n  Cache-Control: no-cache\n  X-Content-Type-Options: nosniff',
    preferenceRulesAssetPath +
      '\n  Content-Type: application/json; charset=utf-8\n  Cache-Control: no-cache\n  X-Content-Type-Options: nosniff',
    '/extensions/build-state.json\n  Content-Type: application/json; charset=utf-8\n  Cache-Control: no-cache\n  X-Content-Type-Options: nosniff',
    '/extensions/builds/*\n  Content-Type: application/json; charset=utf-8\n  Cache-Control: no-cache\n  X-Content-Type-Options: nosniff',
    '/extensions/artifacts/*\n  Content-Type: application/gzip\n  Cache-Control: public, max-age=31536000, immutable\n  X-Content-Type-Options: nosniff',
  );
  await writeFile(
    headerFile,
    headers.trimEnd() + '\n\n' + rules.join('\n\n') + '\n',
  );

  // Check the actual output tree, including ignored/hidden files. Matching native
  // payloads must not become public under an unexpected name or asset directory.
  const nativePayloads = await Promise.all(
    ['host.js', 'worker.js', 'manifest.json'].map((name) =>
      readFile(new URL('native/' + name, runtime)),
    ),
  );
  const nativeSizes = new Set(nativePayloads.map((bytes) => bytes.length));
  const digest = (bytes: Uint8Array) =>
    createHash('sha256').update(bytes).digest('hex');
  const nativeHashes = new Set(nativePayloads.map(digest));
  let publicFiles = 0;
  async function checkTree(directory: string): Promise<void> {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const file = path.join(directory, entry.name);
      const relative = path.relative(fileURLToPath(publicDir), file);
      if (
        inside(relative, path.join('runtime', 'native')) ||
        inside(relative, nativeFlutterPath)
      ) {
        throw new Error(
          'Native runtime directory entered public assets: ' + relative,
        );
      }
      if (entry.isDirectory()) await checkTree(file);
      else if (entry.isFile()) {
        ++publicFiles;
        if (
          nativeSizes.has((await stat(file)).size) &&
          nativeHashes.has(digest(await readFile(file)))
        ) {
          throw new Error(
            'Native runtime payload entered public assets: ' + relative,
          );
        }
      } else
        throw new Error('Unexpected non-regular public asset: ' + relative);
    }
  }
  await checkTree(fileURLToPath(publicDir));
  console.log(
    `Static assets checked: ${publicFiles} files, ${extensionCount} current extensions; native runtime payloads excluded`,
  );
}

/** Publish only the current index's reachable files, never a historical tree. */
export async function assembleExtensionAssets(
  publicDirectory: string,
  materials: RuntimeMaterialCatalog,
  defaultSource = '.local/extensions-assets',
): Promise<number> {
  const explicit = process.env.EXTENSION_ASSETS_DIR;
  const source = path.resolve(explicit ?? defaultSource);
  const destination = path.join(publicDirectory, 'extensions');
  await mkdir(destination, { recursive: true });
  let indexBytes: Buffer;
  try {
    indexBytes = await readFile(path.join(source, 'extensions/index.json'));
  } catch (error) {
    if (
      explicit ||
      !(error instanceof Error) ||
      !('code' in error) ||
      error.code !== 'ENOENT'
    )
      throw error;
    await writeFile(
      path.join(destination, 'index.json'),
      JSON.stringify({ schemaVersion: 1, repoId: 'keiyoushi', builds: [] }) +
        '\n',
    );
    await writeFile(
      path.join(publicDirectory, preferenceRulesAssetPath.slice(1)),
      JSON.stringify({ repoId: 'keiyoushi', packages: {} }) + '\n',
    );
    return 0;
  }
  if (indexBytes.length > 2 * 1024 * 1024)
    throw new Error('Extension index exceeds its byte budget');
  const index = await parseExtensionIndex(indexBytes);
  const written = new Set<string>();
  const rules = new Map<string, BuildManifest['preferenceSyncRules']>();
  for (const build of index.builds) {
    const manifestFile = path.join(source, build.manifestPath.slice(1));
    if ((await stat(manifestFile)).size > 64 * 1024)
      throw new Error('Extension manifest exceeds its byte budget');
    const manifestBytes = await readFile(manifestFile);
    const manifest = await parseManifest(manifestBytes);
    if (
      manifest.buildId !== build.buildId ||
      manifest.packageName !== build.packageName ||
      manifest.repoId !== build.repoId ||
      manifest.version !== build.version ||
      JSON.stringify(manifest.sourceIds) !== JSON.stringify(build.sourceIds) ||
      JSON.stringify(manifest.sources) !== JSON.stringify(build.sources)
    )
      throw new Error('Static extension index and manifest disagree');
    for (const [references, expected] of [
      [manifest.hostScripts, materials.hostScripts],
      [manifest.resources, materials.resources],
    ] as const) {
      for (const artifact of references) {
        const known = expected.find((item) => item.sha256 === artifact.sha256);
        if (
          !known ||
          (['path', 'size', 'contentType', 'logicalName'] as const).some(
            (key) => artifact[key] !== known[key],
          )
        )
          throw new Error(
            'Current extension uses unavailable runtime materials',
          );
      }
    }
    if (manifest.preferenceSyncRules.length)
      rules.set(manifest.packageName, manifest.preferenceSyncRules);
    const bundle = manifest.bundle;
    if (bundle.encodedSize > 25 * 1024 * 1024)
      throw new Error(
        'Extension gzip exceeds the Static Assets file size limit',
      );
    if (!written.has(bundle.path)) {
      const file = path.join(source, bundle.path.slice(1));
      if ((await stat(file)).size !== bundle.encodedSize)
        throw new Error(
          'Static extension gzip length does not match its manifest',
        );
      const bytes = await readFile(file);
      if (
        bytes.length !== bundle.encodedSize ||
        createHash('sha256').update(bytes).digest('hex') !==
          bundle.encodedSha256
      )
        throw new Error(
          'Static extension gzip failed upload integrity verification',
        );
      const target = path.join(publicDirectory, bundle.path.slice(1));
      await mkdir(path.dirname(target), { recursive: true });
      await writeFile(target, bytes);
      written.add(bundle.path);
    }
    const target = path.join(publicDirectory, build.manifestPath.slice(1));
    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, manifestBytes);
  }
  const state = await readFile(
    path.join(source, 'extensions/build-state.json'),
  );
  if (state.length > 16 * 1024 * 1024)
    throw new Error('Extension build state exceeds its byte budget');
  const parsed: unknown = JSON.parse(state.toString('utf8'));
  if (
    !parsed ||
    typeof parsed !== 'object' ||
    Array.isArray(parsed) ||
    !('indexSha256' in parsed) ||
    parsed.indexSha256 !== createHash('sha256').update(indexBytes).digest('hex')
  )
    throw new Error('Extension build state does not bind the current index');
  await writeFile(path.join(destination, 'build-state.json'), state);
  await writeFile(path.join(destination, 'index.json'), indexBytes);
  await writeFile(
    path.join(publicDirectory, preferenceRulesAssetPath.slice(1)),
    JSON.stringify({
      repoId: index.repoId,
      packages: Object.fromEntries(rules),
    }) + '\n',
  );
  return index.builds.length;
}
