/** Fixed official Drift assets used by both Flutter Web development and release. */
import { createHash } from 'node:crypto';
import { lstat, mkdir, mkdtemp, readFile, rename, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execa } from 'execa';
import writeFileAtomic from 'write-file-atomic';

export const DATABASE_ASSET_VERSION = 'drift-2.35.3';
export const DATABASE_ASSETS = [
  {
    name: 'sqlite3.wasm',
    size: 758619,
    sha256: 'efd308be92a34f3aa15f289a37f213b0230fd80888a1364326ee29579d892d37',
    contentType: 'application/wasm',
  },
  {
    name: 'drift_worker.js',
    size: 361829,
    sha256: 'a54b81412d4c4ab56653bb9e4c02912b0820bb37e2bba00722ddef4d78083d4a',
    contentType: 'application/javascript; charset=utf-8',
  },
] as const;
type DatabaseAsset = (typeof DATABASE_ASSETS)[number];
const ROOT = fileURLToPath(new URL('../../', import.meta.url));

async function readDatabaseAsset(
  file: string,
  asset: DatabaseAsset,
): Promise<Buffer | undefined> {
  let information;
  try {
    information = await lstat(file);
  } catch (error) {
    if (error instanceof Error && 'code' in error && error.code === 'ENOENT')
      return undefined;
    throw error;
  }
  if (!information.isFile())
    throw new Error('Drift database asset must be a regular file: ' + file);
  if (information.size !== asset.size) return undefined;
  const bytes = await readFile(file);
  if (
    bytes.length !== asset.size ||
    createHash('sha256').update(bytes).digest('hex') !== asset.sha256
  )
    return undefined;
  return bytes;
}

export interface DatabaseAssetOptions {
  root?: string;
  cacheDirectory?: string;
  webDirectory?: string;
  /** Test fixtures may supply a local executable; asset identity stays fixed. */
  curl?: string;
}

export async function prepareDatabaseAssets(
  options: DatabaseAssetOptions = {},
): Promise<{ sqlite3Wasm: string; driftWorker: string }> {
  const root = path.resolve(options.root ?? ROOT);
  const cache = path.resolve(
    options.cacheDirectory ??
      path.join(root, '.local/database-assets', DATABASE_ASSET_VERSION),
  );
  const web = path.resolve(
    options.webDirectory ?? path.join(root, 'apps/reader/web/database'),
  );
  await mkdir(cache, { recursive: true });
  const assets: { name: DatabaseAsset['name']; bytes: Buffer }[] = [];
  // Validate both resources before touching Flutter's served directory.
  for (const asset of DATABASE_ASSETS) {
    const destination = path.join(cache, asset.name);
    let bytes = await readDatabaseAsset(destination, asset);
    if (!bytes) {
      const temporary = await mkdtemp(path.join(cache, '.download-'));
      try {
        const file = path.join(temporary, asset.name);
        await execa(
          options.curl ?? 'curl',
          [
            '--fail',
            '--location',
            '--silent',
            '--show-error',
            '--retry',
            '2',
            '--connect-timeout',
            '20',
            '--max-time',
            '180',
            '--max-filesize',
            String(asset.size),
            '--output',
            file,
            `https://github.com/simolus3/drift/releases/download/${DATABASE_ASSET_VERSION}/${asset.name}`,
          ],
          {
            stdin: 'ignore',
            stdout: 'ignore',
            stderr: 'pipe',
            shell: false,
            preferLocal: false,
            verbose: 'none',
            maxBuffer: 16384,
            timeout: 190000,
          },
        );
        bytes = await readDatabaseAsset(file, asset);
        if (!bytes)
          throw new Error(
            'Official Drift database asset size or checksum mismatch: ' +
              asset.name,
          );
        await rename(file, destination);
      } finally {
        await rm(temporary, { recursive: true, force: true });
      }
    }
    assets.push({ name: asset.name, bytes });
  }
  await mkdir(web, { recursive: true });
  for (const asset of assets) {
    const destination = path.join(web, asset.name);
    try {
      if (!(await lstat(destination)).isFile())
        throw new Error(
          'Drift database output must be a regular file: ' + destination,
        );
    } catch (error) {
      if (
        !(error instanceof Error) ||
        !('code' in error) ||
        error.code !== 'ENOENT'
      )
        throw error;
    }
    await writeFileAtomic(destination, asset.bytes);
  }
  return {
    sqlite3Wasm: path.join(web, 'sqlite3.wasm'),
    driftWorker: path.join(web, 'drift_worker.js'),
  };
}

/** Verify the actual files at the Static Assets upload boundary. */
export async function verifyDatabaseAssets(directory: string): Promise<void> {
  for (const asset of DATABASE_ASSETS) {
    if (!(await readDatabaseAsset(path.join(directory, asset.name), asset)))
      throw new Error(
        'Missing or invalid Flutter database asset: ' + asset.name,
      );
  }
}
