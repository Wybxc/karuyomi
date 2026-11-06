import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import {
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { gzipSync } from 'node:zlib';
import type { TestContext } from 'node:test';
import type {
  BuildManifest,
  ExtensionIndex,
} from '../../packages/contracts/src/index.ts';
import isRecord from 'is-plain-obj';
import { createHash } from 'node:crypto';
import { parseManifest, repositoryRoot } from './verify-manifest.ts';

export async function fixture(
  t: TestContext,
  content = Buffer.from('const source = 1;'),
) {
  const directory = await mkdtemp(
    path.join(tmpdir(), 'karuyomi-registration-'),
  );
  t.after(() => rm(directory, { recursive: true, force: true }));
  const artifacts = path.join(directory, 'artifacts');
  await mkdir(artifacts);
  const protocol: unknown = JSON.parse(
    await readFile(
      path.join(repositoryRoot, 'packages/contracts/protocol.json'),
      'utf8',
    ),
  );
  assert(isRecord(protocol));
  const encoded = gzipSync(content);
  const sha256 = createHash('sha256').update(content).digest('hex');
  const manifest = await parseManifest(
    Buffer.from(
      JSON.stringify({
        ...protocol,
        bridgeVersion: 2,
        buildId: 'regression-build',
        packageName: 'example.source',
        repoId: 'example',
        version: '1',
        storageSchema: '1',
        sourceIds: ['9223372036854775807'],
        sources: [{ id: '9223372036854775807', name: 'Fixture', lang: 'en' }],
        bundle: {
          path: `/extensions/artifacts/${sha256}.gz`,
          sha256,
          size: content.length,
          contentType: 'application/javascript',
          encoding: 'gzip',
          encodedSha256: createHash('sha256').update(encoded).digest('hex'),
          encodedSize: encoded.length,
        },
        hostScripts: [],
        resources: [],
      }),
    ),
  );
  const file = path.join(artifacts, sha256 + '.gz');
  const manifestFile = path.join(directory, 'manifest.json');
  await writeFile(file, encoded);
  await writeFile(manifestFile, JSON.stringify(manifest));
  return { directory, artifacts, manifest, manifestFile, file, encoded };
}
export async function snapshot(directory: string, manifest: BuildManifest) {
  const manifestPath = `/extensions/builds/${manifest.buildId}/manifest.json`;
  const index: ExtensionIndex = {
    schemaVersion: 1,
    builds: [
      {
        buildId: manifest.buildId,
        packageName: manifest.packageName,
        repoId: manifest.repoId,
        version: manifest.version,
        sourceIds: manifest.sourceIds,
        sources: manifest.sources,
        manifestPath,
      },
    ],
  };
  const indexFile = path.join(directory, 'extensions/index.json');
  const manifestFile = path.join(directory, manifestPath);
  await mkdir(path.dirname(manifestFile), { recursive: true });
  await writeFile(indexFile, JSON.stringify(index));
  await writeFile(manifestFile, JSON.stringify(manifest));
  return { index, indexFile, manifestFile };
}
export async function database(t: TestContext) {
  const db = new DatabaseSync(':memory:');
  t.after(() => db.close());
  db.exec('PRAGMA foreign_keys=ON');
  const migrations = path.join(repositoryRoot, 'apps/api/migrations');
  for (const name of (await readdir(migrations))
    .filter((value) => value.endsWith('.sql'))
    .sort())
    db.exec(await readFile(path.join(migrations, name), 'utf8'));
  return db;
}
export function transaction(db: DatabaseSync, sql: string) {
  db.exec('BEGIN');
  try {
    db.exec(sql);
    db.exec('COMMIT');
  } catch (error) {
    db.exec('ROLLBACK');
    throw error;
  }
}
