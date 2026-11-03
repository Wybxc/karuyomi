import { createHash } from 'node:crypto';
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { MaterialCatalog } from '../packages/runtime-host/materials.ts';
import {
  parseExtensionIndex,
  parseManifest,
} from '../tools/extensions/verify-manifest.ts';

/** Publish only the current index's reachable files, never a historical tree. */
export async function assembleExtensionAssets(
  publicDirectory: string,
  materials: MaterialCatalog,
): Promise<number> {
  const explicit = process.env.EXTENSION_ASSETS_DIR;
  const source = path.resolve(explicit ?? '.local/extensions-assets');
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
      JSON.stringify({ schemaVersion: 1, builds: [], nextCursor: null }) + '\n',
    );
    return 0;
  }
  if (indexBytes.length > 2 * 1024 * 1024)
    throw new Error('Extension index exceeds its byte budget');
  const index = await parseExtensionIndex(indexBytes);
  const written = new Set<string>();
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
      JSON.stringify(manifest.sourceIds) !== JSON.stringify(build.sourceIds)
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
  return index.builds.length;
}
