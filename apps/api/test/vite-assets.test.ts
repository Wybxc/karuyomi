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
import { URL } from 'node:url';
import { afterEach, test, vi } from 'vitest';
import { gzipSync } from 'node:zlib';
import {
  buildManifestSchema,
  preferenceRulesAssetSchema,
  runtimeMaterialCatalogSchema,
} from '@karuyomi/contracts';
import { assembleExtensionAssets } from '../vite.assets.ts';

const temporary: string[] = [];
afterEach(async () => {
  vi.unstubAllEnvs();
  await Promise.all(
    temporary
      .splice(0)
      .map((directory) => rm(directory, { recursive: true, force: true })),
  );
});

async function fixture() {
  const root = await mkdtemp(path.join(tmpdir(), 'karuyomi-static-assemble-'));
  temporary.push(root);
  const catalog = runtimeMaterialCatalogSchema.parse(
    JSON.parse(
      await readFile(
        new URL(
          '../../../packages/runtime-host/dist/materials.json',
          import.meta.url,
        ),
        'utf8',
      ),
    ),
  );
  const source = path.join(root, 'input');
  const target = path.join(root, 'public');
  vi.stubEnv('EXTENSION_ASSETS_DIR', source);
  const raw = Buffer.from('self.currentExtension = true;');
  const encoded = gzipSync(raw);
  const hash = createHash('sha256').update(raw).digest('hex');
  const bundlePath = '/extensions/artifacts/' + hash + '.gz';
  const manifestPath = '/extensions/builds/current-build/manifest.json';
  const index = {
    schemaVersion: 1,
    repoId: 'test',
    builds: [
      {
        buildId: 'current-build',
        packageName: 'example.source',
        repoId: 'test',
        version: '2',
        sourceIds: ['123'],
        sources: [{ id: '123', name: 'Fixture', lang: 'en' }],
        manifestPath,
      },
    ],
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
      indexSha256: createHash('sha256').update(indexBytes).digest('hex'),
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
      sources: [{ id: '123', name: 'Fixture', lang: 'en' }],
      bundle: {
        path: bundlePath,
        sha256: hash,
        size: raw.length,
        contentType: 'application/javascript',
        encoding: 'gzip',
        encodedSha256: createHash('sha256').update(encoded).digest('hex'),
        encodedSize: encoded.length,
      },
      hostScripts: [],
      resources: [],
      preferenceSyncRules: [
        {
          key: 'display_mode',
          kind: 'PREFERENCE_VALUE_KIND_TEXT',
          sourceId: '123',
        },
      ],
    }),
  );
  await put(bundlePath.slice(1), encoded);
  return { source, target, bundlePath, manifestPath, encoded, put, catalog };
}

test('assembly publishes only the current index reachable snapshot', async () => {
  const f = await fixture();
  await f.put('extensions/builds/old-build/manifest.json', '{}');
  await f.put('extensions/artifacts/orphan.gz', 'obsolete');
  assert.equal(await assembleExtensionAssets(f.target, f.catalog), 1);
  assert.deepEqual(
    await readFile(path.join(f.target, f.bundlePath.slice(1))),
    f.encoded,
  );
  await stat(path.join(f.target, f.manifestPath.slice(1)));
  const rules = preferenceRulesAssetSchema.parse(
    JSON.parse(
      await readFile(
        path.join(f.target, 'extensions/preference-rules.json'),
        'utf8',
      ),
    ),
  );
  assert.equal(rules.repoId, 'test');
  assert.equal(rules.packages['example.source']?.[0]?.key, 'display_mode');
  await assert.rejects(
    stat(path.join(f.target, 'extensions/builds/old-build')),
    { code: 'ENOENT' },
  );
  await assert.rejects(
    stat(path.join(f.target, 'extensions/artifacts/orphan.gz')),
    { code: 'ENOENT' },
  );
});

test('assembly refuses an index/state mixture from different deployments', async () => {
  const f = await fixture();
  await f.put(
    'extensions/build-state.json',
    JSON.stringify({ indexSha256: '0'.repeat(64) }),
  );
  await assert.rejects(
    assembleExtensionAssets(f.target, f.catalog),
    /does not bind/,
  );
});

test('assembly checks gzip bytes at the upload boundary', async () => {
  const f = await fixture();
  const corrupted = Buffer.from(f.encoded);
  corrupted[corrupted.length - 1] = (corrupted[corrupted.length - 1] ?? 0) ^ 1;
  await f.put(f.bundlePath.slice(1), corrupted);
  await assert.rejects(
    assembleExtensionAssets(f.target, f.catalog),
    /integrity/,
  );
});

test('an explicit missing snapshot never silently deploys an empty catalog', async () => {
  const f = await fixture();
  vi.stubEnv('EXTENSION_ASSETS_DIR', path.join(f.source, 'missing'));
  await assert.rejects(assembleExtensionAssets(f.target, f.catalog), {
    code: 'ENOENT',
  });
});

test('codec materials cannot become extension host scripts or Source Worker preload resources', async () => {
  const f = await fixture();
  const file = path.join(f.source, f.manifestPath.slice(1));
  const manifest = buildManifestSchema.parse(
    JSON.parse(await readFile(file, 'utf8')),
  );
  manifest.resources = [
    {
      logicalName: 'png.wasm',
      path: '/runtime/materials/' + 'c'.repeat(64),
      sha256: 'c'.repeat(64),
      size: 1,
      contentType: 'application/wasm',
    },
  ];
  await f.put(f.manifestPath.slice(1), JSON.stringify(manifest));
  await assert.rejects(
    assembleExtensionAssets(f.target, f.catalog),
    /unavailable runtime materials/,
  );
});

test('assembly rejects catalog labels or languages that differ from the exact manifest', async () => {
  const f = await fixture();
  const manifest = buildManifestSchema.parse(
    JSON.parse(
      await readFile(path.join(f.source, f.manifestPath.slice(1)), 'utf8'),
    ),
  );
  const source = manifest.sources[0];
  assert(source);
  source.name = 'Different label';
  source.lang = 'zh';
  await f.put(f.manifestPath.slice(1), JSON.stringify(manifest));
  await assert.rejects(
    assembleExtensionAssets(f.target, f.catalog),
    /disagree/,
  );
});
