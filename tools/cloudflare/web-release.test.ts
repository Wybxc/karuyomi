import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import {
  cp,
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { test, type TestContext } from 'node:test';
import { execa } from 'execa';
import {
  buildManifestSchema,
  runtimeMaterialCatalogSchema,
} from '../../packages/contracts/src/index.ts';
import { encodeBundle, type fetchBytes } from '../extensions/assets.ts';
import {
  extensionStateSchema,
  publishedBuildId,
  runtimeIdentitySchema,
  type ExtensionDescriptor,
} from '../extensions/model.ts';
import {
  assertWebSnapshotCurrent,
  prepareWebSnapshot,
  recordWebRelease,
  verifyWebRelease,
} from './web-release.ts';
import {
  flutterCacheRules,
  flutterWebManifestSchema,
  immutableCache,
} from '../flutter/web-assets.ts';

const hash = (bytes: Uint8Array) =>
  createHash('sha256').update(bytes).digest('hex');
const json = (value: unknown) => Buffer.from(JSON.stringify(value) + '\n');
const protocol = runtimeIdentitySchema.parse({
  ...JSON.parse(
    await readFile(
      new URL('../../packages/contracts/protocol.json', import.meta.url),
      'utf8',
    ),
  ),
  bridgeVersion: 2,
  hostScripts: [],
  resources: [],
});

async function fixture(t: TestContext) {
  const root = await mkdtemp(path.join(tmpdir(), 'karuyomi-web-release-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const directory = path.join(root, 'release');
  const destination = path.join(directory, 'assets');
  const origin = 'https://fixture.example';
  const materialBytes = Buffer.from('shared bridge');
  const material = {
    path: '/runtime/materials/' + hash(materialBytes),
    sha256: hash(materialBytes),
    size: materialBytes.length,
    contentType: 'text/javascript',
    logicalName: 'bridge.js',
  };
  const catalog = runtimeMaterialCatalogSchema.parse({
    ...protocol,
    schemaVersion: 1,
    materialVersion: 'c'.repeat(64),
    hostScripts: [material],
    resources: [],
    sources: {
      zstd: {
        packageName: 'fixture',
        version: '1',
        file: 'fixture.wasm',
        sha256: 'd'.repeat(64),
        size: 1,
      },
      webpEncoder: {
        version: '1',
        upstreamCommit: 'e'.repeat(40),
        compilerVersion: '1',
        sha256: 'f'.repeat(64),
        size: 1,
      },
    },
  });
  const descriptor: ExtensionDescriptor = {
    schemaVersion: 1,
    packageName: 'example.release',
    sourcePath: 'src/en/release',
    buildId: 'ext-release-' + 'b'.repeat(32),
    versionName: '1.6.1',
    versionCode: 106001,
    declaredVersionCode: 1,
    effectiveVersionCode: 1,
    upstreamCommit: 'a'.repeat(40),
    sourceFingerprint: 'b'.repeat(64),
    hostFingerprint: 'c'.repeat(64),
    inputFingerprint: 'd'.repeat(64),
    sourceInputs: {},
    sharedInputs: {},
    hostInputs: {},
  };
  const { encoded, reference } = encodeBundle(
    Buffer.from('self.onmessage = () => {};'),
  );
  const buildId = publishedBuildId(descriptor, reference.sha256);
  const manifest = buildManifestSchema.parse({
    ...protocol,
    hostScripts: [material],
    buildId,
    packageName: descriptor.packageName,
    repoId: 'keiyoushi',
    version: descriptor.versionName,
    sourceIds: ['1'],
    sources: [{ id: '1', name: 'Fixture', lang: 'en' }],
    preferenceSyncRules: [],
    storageSchema: '1',
    bundle: reference,
  });
  const manifestPath = '/extensions/builds/' + buildId + '/manifest.json';
  const index = json({
    schemaVersion: 1,
    repoId: 'keiyoushi',
    builds: [
      {
        buildId,
        packageName: descriptor.packageName,
        repoId: manifest.repoId,
        version: manifest.version,
        sourceIds: manifest.sourceIds,
        sources: manifest.sources,
        manifestPath,
      },
    ],
  });
  const state = extensionStateSchema.parse({
    schemaVersion: 1,
    kind: 'static-extension-build-state',
    revision: 'a'.repeat(32),
    parentRevision: null,
    indexSha256: hash(index),
    bootstrap: { complete: false },
    active: { [descriptor.packageName]: descriptor.inputFingerprint },
    attempts: {
      [descriptor.inputFingerprint]: {
        descriptor,
        status: 'published',
        attempts: 1,
        available: true,
        bundleSha256: reference.sha256,
        runtimeReady: false,
        validationStatus: 'compiled_unverified',
      },
    },
  });
  const remote = new Map<string, Buffer>([
    ['/extensions/index.json', index],
    ['/extensions/build-state.json', json(state)],
    [manifestPath, json(manifest)],
    [reference.path, encoded],
  ]);
  const fetched: string[] = [];
  const download: typeof fetchBytes = async (
    _origin,
    relative,
    maximum = Infinity,
  ) => {
    fetched.push(relative);
    const bytes = remote.get(relative);
    assert(bytes, relative);
    assert(bytes.length <= maximum);
    return bytes;
  };
  const prepare = () =>
    prepareWebSnapshot({ origin, destination, catalog, download });
  async function client(wasm = false) {
    await prepare();
    const main = Buffer.from('new client');
    const mainPath = '/main.dart.' + hash(main).slice(0, 8) + '.js';
    const publicFiles = new Map<string, Buffer>([
      ['/', Buffer.from('<html>fixture</html>')],
      [mainPath, main],
      ['/flutter_bootstrap.js', Buffer.from('bootstrap')],
      [
        '/assets/NOTICES.' + hash(Buffer.from('notice')).slice(0, 8),
        Buffer.from('notice'),
      ],
      ['/canvaskit/canvaskit.wasm', Buffer.from('renderer')],
    ]);
    if (wasm) {
      for (const extension of ['wasm', 'mjs']) {
        const bytes = Buffer.from(extension);
        publicFiles.set(
          '/main.dart.' + hash(bytes).slice(0, 8) + '.' + extension,
          bytes,
        );
      }
    }
    const manifest = {
      version: 1,
      entries: [...publicFiles].map(([relative, bytes]) => ({
        url: relative === '/' ? 'index.html' : relative.slice(1),
        hash: hash(bytes).slice(0, 8),
        size: bytes.length,
        urlHashed: relative.includes(hash(bytes).slice(0, 8)),
      })),
    };
    publicFiles.set('/precache_manifest.json', json(manifest));
    for (const [relative, bytes] of new Map<string, Buffer>([
      ['/runtime/host.js', Buffer.from('host')],
      ['/runtime/worker.js', Buffer.from('worker')],
      ['/runtime/materials.json', json(catalog)],
      [material.path, materialBytes],
    ]))
      publicFiles.set(relative, bytes);
    const clientDirectory = path.join(root, 'apps/api/dist/client');
    for (const [relative, bytes] of publicFiles) {
      const file = path.join(
        clientDirectory,
        relative === '/' ? 'index.html' : relative.slice(1),
      );
      await mkdir(path.dirname(file), { recursive: true });
      await writeFile(file, bytes);
    }
    await cp(
      path.join(destination, 'extensions'),
      path.join(clientDirectory, 'extensions'),
      { recursive: true },
    );
    await mkdir(path.join(root, 'apps/api/dist/karuyomi'), { recursive: true });
    await writeFile(
      path.join(root, 'apps/api/dist/karuyomi/wrangler.json'),
      json({
        vars: {
          APP_ORIGIN: origin,
          ACCESS_TEAM_DOMAIN: 'fixture.cloudflareaccess.com',
        },
      }),
    );
    await recordWebRelease(root, directory, 'a'.repeat(40));
    const request: typeof fetch = async (input, init) => {
      assert.equal(init?.credentials, 'omit');
      assert.equal(init.redirect, 'manual');
      const relative = new URL(String(input)).pathname;
      if (relative === '/api/session')
        return new Response(null, {
          status: 302,
          headers: { location: 'https://fixture.cloudflareaccess.com/login' },
        });
      const bytes = publicFiles.get(relative);
      assert(bytes, relative);
      return new Response(new Uint8Array(bytes), {
        headers: {
          'Cache-Control': manifest.entries.find(
            (entry) => '/' + entry.url === relative,
          )?.urlHashed
            ? immutableCache
            : 'no-cache',
        },
      });
    };
    return { request, publicFiles, mainPath, manifest, clientDirectory };
  }
  return {
    root,
    directory,
    destination,
    origin,
    catalog,
    manifest,
    manifestPath,
    state,
    reference,
    remote,
    fetched,
    download,
    prepare,
    client,
  };
}

test('Web publication preserves partial baseline bytes and unverified build status', async (t) => {
  const f = await fixture(t);
  await f.prepare();
  for (const [relative, bytes] of f.remote)
    assert.deepEqual(
      await readFile(path.join(f.destination, relative.slice(1))),
      bytes,
    );
  assert.equal(
    f.fetched.filter((relative) => relative === f.reference.path).length,
    1,
  );
  const state = extensionStateSchema.parse(
    JSON.parse(
      await readFile(
        path.join(f.destination, 'extensions/build-state.json'),
        'utf8',
      ),
    ),
  );
  assert.equal(state.bootstrap.complete, false);
  assert.equal(Object.values(state.attempts)[0]?.runtimeReady, false);
});

test('A corrupt transfer leaves the previous candidate intact and removes staging', async (t) => {
  const f = await fixture(t);
  await mkdir(f.destination, { recursive: true });
  await writeFile(path.join(f.destination, 'previous'), 'keep');
  f.remote.set(f.reference.path, Buffer.alloc(f.reference.encodedSize));
  await assert.rejects(f.prepare(), /SHA-256/);
  assert.equal(
    await readFile(path.join(f.destination, 'previous'), 'utf8'),
    'keep',
  );
  assert.deepEqual(await readdir(f.directory), ['assets']);
});

test('A runtime material change cannot silently mix old AOT with a new client', async (t) => {
  const f = await fixture(t);
  await assert.rejects(
    prepareWebSnapshot({
      origin: f.origin,
      destination: f.destination,
      catalog: { ...f.catalog, hostScripts: [] },
      download: f.download,
    }),
    /material/,
  );
});

test('Adding a material also requires a matching AOT material set', async (t) => {
  const f = await fixture(t);
  await assert.rejects(
    prepareWebSnapshot({
      origin: f.origin,
      destination: f.destination,
      catalog: {
        ...f.catalog,
        hostScripts: [
          ...f.catalog.hostScripts,
          {
            path: '/runtime/materials/' + 'b'.repeat(64),
            sha256: 'b'.repeat(64),
            size: 1,
            contentType: 'text/javascript',
            logicalName: 'new.js',
          },
        ],
      },
      download: f.download,
    }),
    /material set changed/,
  );
});

test('Mismatched index and state stop before fetching extension bodies', async (t) => {
  const f = await fixture(t);
  f.remote.set(
    '/extensions/build-state.json',
    json({ ...f.state, indexSha256: 'f'.repeat(64) }),
  );
  await assert.rejects(f.prepare(), /index\/state disagree/);
  assert.equal(f.fetched.length, 2);
});

test('Mismatched manifest identity cannot be published', async (t) => {
  const f = await fixture(t);
  f.remote.set(f.manifestPath, json({ ...f.manifest, version: '1.6.2' }));
  await assert.rejects(f.prepare(), /index\/manifest disagree/);
});

test('A publisher refuses an extension snapshot that advanced after preparation', async (t) => {
  const f = await fixture(t);
  await f.prepare();
  await assertWebSnapshotCurrent(f.origin, f.destination, f.download);
  f.remote.set(
    '/extensions/build-state.json',
    json({ ...f.state, revision: 'b'.repeat(32) }),
  );
  await assert.rejects(
    assertWebSnapshotCurrent(f.origin, f.destination, f.download),
    /advanced/,
  );
});

test('Delivery smoke verifies canonical root HTML, client bytes and the Access redirect', async (t) => {
  const f = await fixture(t);
  const { request } = await f.client();
  const result = await verifyWebRelease(f.directory, request);
  assert.equal(result.publicAssetsVerified, 10);
  assert.equal(result.extensionCount, 1);
  assert.equal(result.accessStatus, 302);
  assert(
    (
      await readFile(path.join(f.directory, 'verification.json'), 'utf8')
    ).includes(result.sourceCommit),
  );
});

test('Delivery smoke rejects an old client even when HTTP succeeds', async (t) => {
  const f = await fixture(t);
  const { request, publicFiles, mainPath } = await f.client();
  publicFiles.set(mainPath, Buffer.from('old client'));
  await assert.rejects(
    verifyWebRelease(f.directory, request),
    /main\.dart\.[a-f0-9]{8}\.js/,
  );
});

test('Wasm publication verifies both generated targets, bootstrap, assets and renderer', async (t) => {
  const f = await fixture(t);
  const { request } = await f.client(true);
  const result = await verifyWebRelease(f.directory, request);
  assert.equal(result.publicAssetsVerified, 12);
  for (const suffix of ['js', 'wasm', 'mjs'])
    assert(
      result.assets.some((asset) =>
        asset.path.match(
          new RegExp('^/main\\.dart\\.[a-f0-9]{8}\\.' + suffix + '$'),
        ),
      ),
    );
  assert(result.assets.some((asset) => asset.path === '/flutter_bootstrap.js'));
  assert(
    result.assets.some((asset) => asset.path === '/canvaskit/canvaskit.wasm'),
  );
});

test('Delivery rejects immutable bootstrap or uncached hashed assets', async (t) => {
  const f = await fixture(t);
  const { request, mainPath } = await f.client();
  for (const asset of ['/flutter_bootstrap.js', mainPath]) {
    await assert.rejects(
      verifyWebRelease(f.directory, async (input, init) => {
        const response = await request(input, init);
        if (new URL(String(input)).pathname === asset)
          response.headers.set(
            'Cache-Control',
            asset === mainPath ? 'no-cache' : immutableCache,
          );
        return response;
      }),
      /Cache|flutter_bootstrap|main\.dart/,
    );
  }
});

test('Release recording checks generated manifest bytes before publishing', async (t) => {
  const f = await fixture(t);
  const { clientDirectory, mainPath } = await f.client();
  await writeFile(
    path.join(clientDirectory, mainPath.slice(1)),
    'tampered client',
  );
  await assert.rejects(
    recordWebRelease(f.root, f.directory, 'a'.repeat(40)),
    /main\.dart/,
  );
});

test('Flutter cache groups stay disjoint and keep unhashed renderer files revalidating', async (t) => {
  const f = await fixture(t);
  const { manifest } = await f.client();
  const parsed = flutterWebManifestSchema.parse(manifest);
  const rules = flutterCacheRules(parsed);
  assert(rules.includes('/assets/*\n  Cache-Control: ' + immutableCache));
  assert(rules.includes('/canvaskit/*\n  Cache-Control: no-cache'));
  assert(rules.includes('/flutter_bootstrap.js\n  Cache-Control: no-cache'));
  assert(!rules.some((rule) => rule.startsWith('/*\n')));
  assert(
    !flutterWebManifestSchema.safeParse({
      ...manifest,
      entries: [...manifest.entries, manifest.entries[0]],
    }).success,
  );
  assert(
    !flutterWebManifestSchema.safeParse({
      ...manifest,
      entries: [
        ...manifest.entries,
        { ...manifest.entries[0], url: '../outside' },
      ],
    }).success,
  );
});

test('Delivery smoke rejects an anonymously accessible API', async (t) => {
  const f = await fixture(t);
  const { request } = await f.client();
  await assert.rejects(
    verifyWebRelease(f.directory, async (input, init) =>
      new URL(String(input)).pathname === '/api/session'
        ? new Response('open')
        : request(input, init),
    ),
    /must require Access/,
  );
});

test('Only current main is publishable; obsolete app and extension publishers stop', async (t) => {
  const root = await mkdtemp(path.join(tmpdir(), 'karuyomi-release-main-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await execa('git', ['init', '-q', '-b', 'main'], { cwd: root });
  const commit = [
    '-c',
    'user.name=Fixture',
    '-c',
    'user.email=fixture@example.invalid',
    '-c',
    'commit.gpgsign=false',
    'commit',
    '--allow-empty',
    '-qm',
  ];
  await execa('git', [...commit, 'first'], { cwd: root });
  await execa('git', ['remote', 'add', 'origin', '.'], { cwd: root });
  const sha = (
    await execa('git', ['rev-parse', 'HEAD'], { cwd: root })
  ).stdout.trim();
  const output = path.join(root, 'github-output');
  const script = fileURLToPath(
    new URL('../../scripts/release-web.ts', import.meta.url),
  );
  const options = {
    cwd: root,
    env: { GITHUB_SHA: sha, GITHUB_OUTPUT: output },
  };
  await execa(process.execPath, [script, 'latest'], options);
  assert.equal(await readFile(output, 'utf8'), 'current=true\n');
  await execa('git', [...commit, 'second'], { cwd: root });
  await execa('git', ['checkout', '--detach', sha], { cwd: root });
  await execa(process.execPath, [script, 'latest'], options);
  assert((await readFile(output, 'utf8')).endsWith('current=false\n'));
  const stale = await execa(
    process.execPath,
    [script, 'latest', '--require-latest'],
    { ...options, reject: false },
  );
  assert.equal(stale.exitCode, 1);
  assert.match(stale.stderr, /refusing to replace/);
});
