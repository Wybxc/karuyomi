import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import {
  mkdir,
  mkdtemp,
  readFile,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test, type TestContext } from 'node:test';
import { gzipSync } from 'node:zlib';
import { collectMaterials } from '../../packages/runtime-host/materials.ts';
import { assembleExtensionAssets } from './assemble-assets.ts';

const digest = (bytes: Uint8Array) =>
  createHash('sha256').update(bytes).digest('hex');
const { catalog } = await collectMaterials({ includeWasmBytes: false });

async function fixture(t: TestContext) {
  const root = await mkdtemp(path.join(tmpdir(), 'karuyomi-static-assemble-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const source = path.join(root, 'input');
  const target = path.join(root, 'public');
  const previous = process.env.EXTENSION_ASSETS_DIR;
  process.env.EXTENSION_ASSETS_DIR = source;
  t.after(() => {
    if (previous === undefined) delete process.env.EXTENSION_ASSETS_DIR;
    else process.env.EXTENSION_ASSETS_DIR = previous;
  });
  const raw = Buffer.from('self.currentExtension = true;');
  const encoded = gzipSync(raw);
  const hash = digest(raw);
  const bundlePath = '/extensions/artifacts/' + hash + '.gz';
  const manifestPath = '/extensions/builds/current-build/manifest.json';
  const index = {
    schemaVersion: 1,
    builds: [
      {
        buildId: 'current-build',
        packageName: 'example.source',
        repoId: 'test',
        version: '2',
        sourceIds: ['123'],
        manifestPath,
      },
    ],
    nextCursor: null,
  };
  async function put(relative: string, bytes: string | Uint8Array) {
    const file = path.join(source, relative);
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(file, bytes);
  }
  const indexBytes = Buffer.from(JSON.stringify(index) + '\n');
  await put('extensions/index.json', indexBytes);
  await put(
    'extensions/build-state.json',
    JSON.stringify({
      schemaVersion: 1,
      indexSha256: digest(indexBytes),
    }),
  );
  await put(
    manifestPath.slice(1),
    JSON.stringify({
      protocolVersion: catalog.protocolVersion,
      hostAbi: catalog.hostAbi,
      runtimeBaseline: catalog.runtimeBaseline,
      bridgeVersion: 2,
      buildId: 'current-build',
      packageName: 'example.source',
      repoId: 'test',
      version: '2',
      storageSchema: '1',
      sourceIds: ['123'],
      bundle: {
        path: bundlePath,
        sha256: hash,
        size: raw.length,
        contentType: 'application/javascript',
        encoding: 'gzip',
        encodedSha256: digest(encoded),
        encodedSize: encoded.length,
      },
      hostScripts: [],
      resources: [],
    }),
  );
  await put(bundlePath.slice(1), encoded);
  return { source, target, bundlePath, manifestPath, encoded, put };
}

test('assembly publishes only the current index reachable snapshot', async (t) => {
  const f = await fixture(t);
  await f.put('extensions/builds/old-build/manifest.json', '{}');
  await f.put('extensions/artifacts/orphan.gz', 'obsolete');
  assert.equal(await assembleExtensionAssets(f.target, catalog), 1);
  assert.deepEqual(
    await readFile(path.join(f.target, f.bundlePath.slice(1))),
    f.encoded,
  );
  await stat(path.join(f.target, f.manifestPath.slice(1)));
  await assert.rejects(
    stat(path.join(f.target, 'extensions/builds/old-build')),
    { code: 'ENOENT' },
  );
  await assert.rejects(
    stat(path.join(f.target, 'extensions/artifacts/orphan.gz')),
    { code: 'ENOENT' },
  );
});

test('assembly refuses an index/state mixture from different deployments', async (t) => {
  const f = await fixture(t);
  await f.put(
    'extensions/build-state.json',
    JSON.stringify({ indexSha256: '0'.repeat(64) }),
  );
  await assert.rejects(
    assembleExtensionAssets(f.target, catalog),
    /does not bind/,
  );
});

test('assembly checks gzip bytes at the upload boundary', async (t) => {
  const f = await fixture(t);
  const corrupted = Buffer.from(f.encoded);
  corrupted[corrupted.length - 1] = (corrupted[corrupted.length - 1] ?? 0) ^ 1;
  await f.put(f.bundlePath.slice(1), corrupted);
  await assert.rejects(assembleExtensionAssets(f.target, catalog), /integrity/);
});

test('an explicit missing snapshot never silently deploys an empty catalog', async (t) => {
  const f = await fixture(t);
  process.env.EXTENSION_ASSETS_DIR = path.join(f.source, 'missing');
  await assert.rejects(assembleExtensionAssets(f.target, catalog), {
    code: 'ENOENT',
  });
});
