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
import { fileURLToPath } from 'node:url';
import type { MaterialCatalog } from '../packages/runtime-host/materials.ts';
import { assembleExtensionAssets } from '../tools/extensions/assemble-assets.ts';
import {
  DATABASE_ASSETS,
  verifyDatabaseAssets,
} from '../tools/reader/database-assets.ts';

const publicDir = new URL('../dist/public/', import.meta.url);
const runtime = new URL('../packages/runtime-host/dist/', import.meta.url);
const flutterWeb = new URL('../apps/reader/build/web/', import.meta.url);
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
const catalog: MaterialCatalog = JSON.parse(
  await readFile(new URL('materials.json', runtime), 'utf8'),
);
const materials = [
  ...catalog.hostScripts,
  ...catalog.resources,
  ...catalog.imageCodecs,
];
const extensionCount = await assembleExtensionAssets(
  fileURLToPath(publicDir),
  catalog,
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
await verifyDatabaseAssets(path.join(fileURLToPath(publicDir), 'database'));
rules.push(
  ...DATABASE_ASSETS.map(
    (asset) =>
      `/database/${asset.name}\n  Content-Type: ${asset.contentType}\n  Cache-Control: public, max-age=0, must-revalidate\n  X-Content-Type-Options: nosniff`,
  ),
);
rules.push(
  '/runtime/materials.json\n  Content-Type: application/json; charset=utf-8\n  Cache-Control: no-cache\n  X-Content-Type-Options: nosniff',
  '/extensions/index.json\n  Content-Type: application/json; charset=utf-8\n  Cache-Control: no-cache\n  X-Content-Type-Options: nosniff',
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
    } else throw new Error('Unexpected non-regular public asset: ' + relative);
  }
}
await checkTree(fileURLToPath(publicDir));
console.log(
  `Static assets checked: ${publicFiles} files, ${extensionCount} current extensions; native runtime payloads excluded`,
);
