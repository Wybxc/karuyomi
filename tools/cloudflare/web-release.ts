import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import {
  mkdir,
  mkdtemp,
  readFile,
  rename,
  rm,
  writeFile,
} from 'node:fs/promises';
import path from 'node:path';
import { getStreamAsBuffer } from 'get-stream';
import pLimit from 'p-limit';
import { z } from 'zod';
import {
  runtimeMaterialCatalogSchema,
  type RuntimeMaterialCatalog,
} from '../../packages/contracts/src/index.ts';
import { fetchBytes } from '../extensions/assets.ts';
import {
  extensionStateSchema,
  publishedBuildId,
  sha256Schema,
} from '../extensions/model.ts';
import {
  decodeBundleBytes,
  parseExtensionIndex,
  parseManifest,
  verifyMaterialReferences,
} from '../extensions/verify-manifest.ts';
import {
  immutableCache,
  readFlutterWebManifest,
} from '../flutter/web-assets.ts';

const indexPath = '/extensions/index.json';
const statePath = '/extensions/build-state.json';
const hash = (bytes: Uint8Array) =>
  createHash('sha256').update(bytes).digest('hex');
type Download = typeof fetchBytes;

/** Reuse the deployed bytes, including a partial baseline; never plan or build AOT. */
export async function prepareWebSnapshot({
  origin,
  destination,
  catalog,
  download = fetchBytes,
}: {
  origin: string;
  destination: string;
  catalog: RuntimeMaterialCatalog;
  download?: Download;
}): Promise<void> {
  const [indexBytes, stateBytes] = await Promise.all([
    download(origin, indexPath, 2 * 1024 * 1024),
    download(origin, statePath, 16 * 1024 * 1024),
  ]);
  const index = await parseExtensionIndex(indexBytes);
  const state = extensionStateSchema.parse(
    JSON.parse(stateBytes.toString('utf8')),
  );
  assert(state.revision, 'Production extension snapshot is missing');
  assert.equal(
    hash(indexBytes),
    state.indexSha256,
    'Extension index/state disagree',
  );
  assert(
    index.builds.length > 0,
    'Refusing to publish an empty extension catalog',
  );
  await mkdir(path.dirname(destination), { recursive: true });
  const staged = await mkdtemp(
    path.join(path.dirname(destination), '.web-snapshot-'),
  );
  const bundles = new Map<string, Promise<void>>();
  const limit = pLimit(4);
  let failure: unknown;
  try {
    const results = await Promise.allSettled(
      index.builds.map((build) =>
        limit(async () => {
          if (failure !== undefined) throw failure;
          try {
            const bytes = await download(origin, build.manifestPath, 64 * 1024);
            const manifest = await parseManifest(bytes);
            assert.deepEqual(
              [
                manifest.buildId,
                manifest.packageName,
                manifest.repoId,
                manifest.version,
                manifest.sourceIds,
                manifest.sources,
              ],
              [
                build.buildId,
                build.packageName,
                build.repoId,
                build.version,
                build.sourceIds,
                build.sources,
              ],
              'Extension index/manifest disagree',
            );
            const key = state.active[build.packageName];
            const record = key ? state.attempts[key] : undefined;
            assert(
              record?.status === 'published' && record.available !== false,
              'Extension is not an available publication',
            );
            assert.equal(record.bundleSha256, manifest.bundle.sha256);
            assert.equal(
              publishedBuildId(record.descriptor, manifest.bundle.sha256),
              build.buildId,
            );
            assert.deepEqual(
              [
                manifest.protocolVersion,
                manifest.hostAbi,
                manifest.runtimeBaseline,
              ],
              [
                catalog.protocolVersion,
                catalog.hostAbi,
                catalog.runtimeBaseline,
              ],
              'Runtime changed; publish matching remote AOT builds first',
            );
            verifyMaterialReferences(manifest, catalog);
            assert.equal(
              manifest.hostScripts.length,
              catalog.hostScripts.length,
              'Runtime material set changed',
            );
            assert.equal(
              manifest.resources.length,
              catalog.resources.length,
              'Runtime material set changed',
            );
            let bundle = bundles.get(manifest.bundle.path);
            if (!bundle) {
              bundle = (async () => {
                const encoded = await download(
                  origin,
                  manifest.bundle.path,
                  manifest.bundle.encodedSize,
                );
                await decodeBundleBytes(manifest.bundle, encoded);
                const file = path.join(staged, manifest.bundle.path.slice(1));
                await mkdir(path.dirname(file), { recursive: true });
                await writeFile(file, encoded);
              })();
              bundles.set(manifest.bundle.path, bundle);
            }
            await bundle;
            const file = path.join(staged, build.manifestPath.slice(1));
            await mkdir(path.dirname(file), { recursive: true });
            await writeFile(file, bytes);
          } catch (error) {
            failure ??= error;
            throw error;
          }
        }),
      ),
    );
    const rejected = results.find((result) => result.status === 'rejected');
    if (rejected?.status === 'rejected') throw rejected.reason;
    await writeFile(path.join(staged, indexPath.slice(1)), indexBytes);
    await writeFile(path.join(staged, statePath.slice(1)), stateBytes);
    await rm(destination, { recursive: true, force: true });
    await rename(staged, destination);
    console.log(
      `Reused ${index.builds.length} extensions; baseline complete=${state.bootstrap.complete}`,
    );
  } finally {
    await rm(staged, { recursive: true, force: true });
  }
}

export async function assertWebSnapshotCurrent(
  origin: string,
  directory: string,
  download: Download = fetchBytes,
): Promise<void> {
  for (const [relative, maximum] of [
    [indexPath, 2 * 1024 * 1024],
    [statePath, 16 * 1024 * 1024],
  ] as const) {
    const [local, remote] = await Promise.all([
      readFile(path.join(directory, relative.slice(1))),
      download(origin, relative, maximum),
    ]);
    assert(
      local.equals(remote),
      'Production extensions advanced; prepare a fresh snapshot before publishing',
    );
  }
}

const releaseSchema = z.object({
  schemaVersion: z.literal(1),
  sourceCommit: z.string().regex(/^[a-f0-9]{40}$/),
  origin: z.url(),
  accessTeamDomain: z.string().min(1),
  extensionRevision: z.string().regex(/^[a-f0-9]{32}$/),
  extensionCount: z.number().int().positive(),
  assets: z
    .array(
      z.object({
        path: z.string().regex(/^\/(?!\/)(?!.*\.\.).*$/),
        size: z.number().int().nonnegative(),
        sha256: sha256Schema,
        cacheControl: z.enum([immutableCache, 'no-cache']).optional(),
      }),
    )
    .min(1),
});

export async function recordWebRelease(
  root: string,
  directory: string,
  sourceCommit: string,
) {
  const client = path.join(root, 'apps/api/dist/client');
  const config = z
    .object({
      vars: z.object({
        APP_ORIGIN: z.url(),
        ACCESS_TEAM_DOMAIN: z.string().min(1),
      }),
    })
    .parse(
      JSON.parse(
        await readFile(
          path.join(root, 'apps/api/dist/karuyomi/wrangler.json'),
          'utf8',
        ),
      ),
    );
  const index = await parseExtensionIndex(
    await readFile(path.join(client, indexPath.slice(1))),
  );
  const state = extensionStateSchema.parse(
    JSON.parse(await readFile(path.join(client, statePath.slice(1)), 'utf8')),
  );
  const catalog = runtimeMaterialCatalogSchema.parse(
    JSON.parse(
      await readFile(path.join(client, 'runtime/materials.json'), 'utf8'),
    ),
  );
  const flutterManifest = await readFlutterWebManifest(client);
  const flutterAssets = new Map(
    flutterManifest.entries.map((entry) => [entry.url, entry]),
  );
  const assets = await Promise.all(
    [
      ...new Set([
        'index.html',
        'precache_manifest.json',
        ...flutterAssets.keys(),
        'runtime/host.js',
        'runtime/worker.js',
        'runtime/materials.json',
      ]),
    ].map(async (relative) => {
      const bytes = await readFile(path.join(client, relative));
      const sha256 = hash(bytes);
      const flutter = flutterAssets.get(relative);
      if (flutter) {
        assert.equal(bytes.length, flutter.size, relative);
        assert(
          sha256.startsWith(flutter.hash),
          `Flutter manifest hash mismatch: ${relative}`,
        );
      }
      return {
        path: relative === 'index.html' ? '/' : '/' + relative,
        size: bytes.length,
        sha256,
        ...((flutter || relative === 'precache_manifest.json') && {
          cacheControl: flutter?.urlHashed ? immutableCache : 'no-cache',
        }),
      };
    }),
  );
  const record = releaseSchema.parse({
    schemaVersion: 1,
    sourceCommit,
    origin: config.vars.APP_ORIGIN,
    accessTeamDomain: config.vars.ACCESS_TEAM_DOMAIN,
    extensionRevision: state.revision,
    extensionCount: index.builds.length,
    assets: [...assets, ...catalog.hostScripts, ...catalog.resources],
  });
  await writeFile(
    path.join(directory, 'release.json'),
    JSON.stringify(record, null, 2) + '\n',
  );
  return record;
}

/** Anonymous delivery smoke only; authenticated reading is a separate UI check. */
export async function verifyWebRelease(
  directory: string,
  request: typeof fetch = fetch,
) {
  const record = releaseSchema.parse(
    JSON.parse(await readFile(path.join(directory, 'release.json'), 'utf8')),
  );
  const limit = pLimit(4);
  const results = await Promise.allSettled(
    record.assets.map((asset) =>
      limit(async () => {
        const response = await request(new URL(asset.path, record.origin), {
          credentials: 'omit',
          redirect: 'manual',
          signal: AbortSignal.timeout(45000),
          headers: {
            'Cache-Control': 'no-cache',
            'Accept-Encoding': 'identity',
          },
        });
        if (response.status !== 200 || !response.body) {
          await response.body?.cancel();
          throw new Error(
            `Public asset unavailable: ${asset.path} (${response.status})`,
          );
        }
        const bytes = await getStreamAsBuffer(response.body, {
          maxBuffer: asset.size + 1,
        });
        assert.equal(bytes.length, asset.size, asset.path);
        assert.equal(hash(bytes), asset.sha256, asset.path);
        if (asset.cacheControl)
          assert.equal(
            response.headers.get('Cache-Control'),
            asset.cacheControl,
            asset.path,
          );
      }),
    ),
  );
  const rejected = results.find((result) => result.status === 'rejected');
  if (rejected?.status === 'rejected') throw rejected.reason;
  const response = await request(new URL('/api/session', record.origin), {
    credentials: 'omit',
    redirect: 'manual',
    signal: AbortSignal.timeout(45000),
  });
  await response.body?.cancel();
  assert(
    [302, 303].includes(response.status),
    'Anonymous API must require Access',
  );
  assert.equal(
    new URL(response.headers.get('location') ?? '').hostname,
    record.accessTeamDomain,
  );
  const result = {
    ...record,
    verifiedAt: new Date().toISOString(),
    publicAssetsVerified: record.assets.length,
    accessStatus: response.status,
  };
  await writeFile(
    path.join(directory, 'verification.json'),
    JSON.stringify(result, null, 2) + '\n',
  );
  return result;
}
