// Real workerd/D1 + actual Static Assets routing over a controlled local snapshot.
// Only the separate test entry trusts this run's RSA public key.
import assert from 'node:assert/strict';
import { isRecord } from '../../../tools/extensions/types.ts';
import { registrationSql } from '../../../tools/extensions/registration.ts';
import { parseManifest } from '../../../tools/extensions/verify-manifest.ts';
import { createHash } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';
import { exportJWK, generateKeyPair, SignJWT } from 'jose';
import {
  createStaticSnapshot,
  migrationFiles,
} from './static-extension-probe.ts';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const api = path.join(root, 'apps/api');
const manifestPath = process.argv[2] && path.resolve(process.argv[2]);
assert(
  manifestPath,
  'Usage: node apps/api/test/workerd-probe.ts MANIFEST [ARTIFACT_FOLDER] [EVIDENCE_JSON]',
);
const evidencePath = process.argv[4]
  ? path.resolve(process.argv[4])
  : path.join(root, '.local/probes/workerd-static-extensions.json');
const artifactFolder = process.argv[3]
  ? path.resolve(process.argv[3])
  : path.join(path.dirname(manifestPath), 'artifacts');
const manifest = await parseManifest(await readFile(manifestPath));
const temporary = await mkdtemp(path.join(tmpdir(), 'karuyomi-api-probe-'));
const state = path.join(temporary, 'state');
const environment = {
  ...process.env,
  CLOUDFLARE_SEND_METRICS: 'false',
  WRANGLER_LOG_PATH: path.join(temporary, 'wrangler.log'),
};
const wrangler = (...args: string[]) =>
  execFileSync(
    'pnpm',
    ['exec', 'wrangler', ...args, '--local', '--persist-to', state],
    {
      cwd: api,
      env: environment,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );
const runTool = (...args: string[]) =>
  execFileSync(process.execPath, args, {
    cwd: root,
    env: environment,
    encoding: 'utf8',
  });
const require = createRequire(new URL('../package.json', import.meta.url));
const wranglerRequire = createRequire(require.resolve('wrangler'));
const { build }: typeof import('esbuild') = await import(
  wranglerRequire.resolve('esbuild')
);
const { Miniflare, convertV4MiniflareOptions }: typeof import('miniflare') =
  await import(wranglerRequire.resolve('miniflare'));
let mf: import('miniflare').Miniflare | undefined;
try {
  const staticRoot = await createStaticSnapshot(
    path.join(temporary, 'public'),
    manifest,
    artifactFolder,
    await readFile(manifestPath),
  );
  await writeFile(
    path.join(staticRoot, 'index.html'),
    '<html>public probe shell</html>',
  );
  await mkdir(path.join(staticRoot, 'runtime'), { recursive: true });
  await writeFile(
    path.join(staticRoot, 'runtime/host.html'),
    '<html>runtime control page</html>',
  );
  console.log(
    'Registering current static build network policy in dedicated local D1',
  );
  for (const file of await migrationFiles(api))
    wrangler('d1', 'execute', 'DB', '--file', file, '--yes');
  runTool(
    path.join(root, 'tools/extensions/registration.ts'),
    manifestPath,
    '--artifacts',
    artifactFolder,
    '--local',
    '--static-root',
    staticRoot,
    '--persist-to',
    state,
  );
  const conflictSql = path.join(temporary, 'conflict.sql');
  const sql = registrationSql(
    { ...manifest, bundle: { ...manifest.bundle, sha256: 'f'.repeat(64) } },
    [],
  );
  await writeFile(
    conflictSql,
    "INSERT INTO app_metadata VALUES ('rollback-probe','must-disappear');\n" +
      sql,
  );
  assert.throws(
    () => wrangler('d1', 'execute', 'DB', '--file', conflictSql, '--yes'),
    /NOT NULL constraint failed/,
  );
  const keys = await generateKeyPair('RS256');
  const jwk = await exportJWK(keys.publicKey);
  jwk.kid = 'isolated-workerd-probe';
  const compiled = await build({
    entryPoints: [path.join(api, 'test/workerd-entry.ts')],
    bundle: true,
    format: 'esm',
    platform: 'browser',
    target: 'es2022',
    write: false,
  });
  assert(
    compiled.outputFiles.length === 1,
    'Expected one compiled Worker module',
  );
  const databaseId = /"database_id":\s*"([^"]+)"/.exec(
    await readFile(path.join(api, 'wrangler.jsonc'), 'utf8'),
  )?.[1];
  assert(
    databaseId,
    'D1 database identity missing from Wrangler configuration',
  );
  mf = new Miniflare(
    convertV4MiniflareOptions({
      modules: true,
      script: compiled.outputFiles[0]!.text,
      compatibilityDate: '2026-11-03',
      resourcePersistencePath: path.join(state, 'v3'),
      d1Databases: { DB: databaseId },
      assets: {
        directory: staticRoot,
        binding: 'ASSETS',
        routerConfig: { has_user_worker: true },
        run_worker_first: ['/api', '/api/*', '/runtime/host.html'],
        assetConfig: { not_found_handling: 'none' },
      },
      bindings: {
        ACCESS_TEAM_DOMAIN: 'probe.cloudflareaccess.com',
        ACCESS_AUD: 'probe-app',
        ACCESS_SUBJECT: 'probe-owner',
        OWNER_EMAIL: 'probe@example.com',
        APP_ORIGIN: 'https://read.example.com',
        PROBE_ACCESS_JWKS: JSON.stringify({ keys: [jwk] }),
      },
    }),
  );
  console.log('Static Assets/workerd started; checking policy and routing');
  const db = await mf.getD1Database('DB');
  assert.equal(
    await db
      .prepare("SELECT value FROM app_metadata WHERE key='rollback-probe'")
      .first('value'),
    null,
  );
  assert.equal(
    await db
      .prepare('SELECT bundle_sha256 FROM extension_builds WHERE build_id=?')
      .bind(manifest.buildId)
      .first('bundle_sha256'),
    manifest.bundle.sha256,
  );
  const tables = await db
    .prepare("SELECT name FROM sqlite_master WHERE type='table'")
    .all<{ name: string }>();
  assert(
    !tables.results.some(
      (row: unknown) =>
        isRecord(row) &&
        ['extension_artifacts', 'build_artifacts'].includes(String(row.name)),
    ),
  );
  const columns = await db
    .prepare('PRAGMA table_info(extension_builds)')
    .all<{ name: string }>();
  assert(
    !columns.results.some(
      (row: unknown) => isRecord(row) && row.name === 'manifest_json',
    ),
  );
  const token = (audience = 'probe-app') =>
    new SignJWT({ email: 'probe@example.com' })
      .setProtectedHeader({ alg: 'RS256', kid: String(jwk.kid) })
      .setSubject('probe-owner')
      .setIssuer('https://probe.cloudflareaccess.com')
      .setAudience(audience)
      .setIssuedAt()
      .setExpirationTime('5m')
      .sign(keys.privateKey);
  const signed = await token();
  const worker = mf;
  const request = (
    pathname: string,
    authenticated = false,
    headers: Record<string, string> = {},
  ) =>
    worker.dispatchFetch(`https://read.example.com${pathname}`, {
      headers: {
        ...(authenticated ? { 'Cf-Access-Jwt-Assertion': signed } : {}),
        ...headers,
      },
      redirect: 'manual',
    });
  const unauthenticated = await request('/api/bootstrap');
  assert.equal(unauthenticated.status, 401, await unauthenticated.text());
  assert.equal(
    (
      await request('/api/bootstrap', true, {
        'Cf-Access-Jwt-Assertion': await token('wrong-app'),
      })
    ).status,
    401,
  );
  assert.equal(
    (
      await worker.dispatchFetch('https://alternate.example/api/bootstrap', {
        headers: { 'Cf-Access-Jwt-Assertion': signed },
      })
    ).status,
    403,
  );
  const bootstrap = await request('/api/bootstrap', true);
  assert.equal(bootstrap.status, 200);
  assert.equal(bootstrap.headers.get('x-karuyomi-probe-worker'), '1');
  for (const route of [
    '/api/extensions/builds',
    `/api/extensions/builds/${manifest.buildId}/manifest`,
    `/api/extensions/artifacts/${manifest.bundle.sha256}`,
  ])
    assert.equal((await request(route, true)).status, 404);
  for (const route of [
    '/extensions/index.json',
    `/extensions/builds/${manifest.buildId}/manifest.json`,
  ]) {
    const response = await request(route);
    assert.equal(response.status, 200);
    assert.equal(
      response.headers.get('x-karuyomi-probe-worker'),
      null,
      'Existing static assets must bypass the entry Worker',
    );
    const json: unknown = await response.json();
    if (route.endsWith('manifest.json'))
      assert.deepEqual(
        await parseManifest(Buffer.from(JSON.stringify(json))),
        manifest,
      );
  }
  const bundle = await request(manifest.bundle.path);
  assert.equal(bundle.status, 200);
  assert.equal(bundle.headers.get('x-karuyomi-probe-worker'), null);
  assert.match(bundle.headers.get('content-type') ?? '', /^application\/gzip/);
  assert.equal(bundle.headers.get('content-encoding'), null);
  const encoded = Buffer.from(await bundle.arrayBuffer());
  assert.equal(encoded.length, manifest.bundle.encodedSize);
  assert.equal(
    createHash('sha256').update(encoded).digest('hex'),
    manifest.bundle.encodedSha256,
  );
  const raw = gunzipSync(encoded, { maxOutputLength: manifest.bundle.size });
  assert.equal(raw.length, manifest.bundle.size);
  assert.equal(
    createHash('sha256').update(raw).digest('hex'),
    manifest.bundle.sha256,
  );
  for (const route of [
    '/extensions/missing',
    '/extensions/builds/missing/manifest.json',
    `/extensions/artifacts/${'0'.repeat(64)}.gz`,
    '/runtime/materials/missing',
  ]) {
    const response = await request(route, false, {
      'Sec-Fetch-Mode': 'navigate',
    });
    assert.equal(
      response.status,
      404,
      'Unknown static assets must not become SPA 200',
    );
  }
  for (const route of ['/auth/complete', '/browse', '/settings']) {
    const response = await request(route);
    assert.equal(response.status, 200);
    assert.match(await response.text(), /public probe shell/);
  }
  assert.equal((await request('/%61pi/bootstrap')).status, 400);
  const redirect = await request('/runtime/host.html');
  assert.equal(redirect.status, 307);
  assert.equal(
    new URL(redirect.headers.get('location')!, 'https://read.example.com')
      .pathname,
    '/runtime/host',
  );
  // A deploy job synchronizes only policy metadata after the static index moves.
  // Close this independent workerd instance before the Wrangler D1 subprocesses.
  await mf.dispose();
  mf = undefined;
  wrangler(
    'd1',
    'execute',
    'DB',
    '--command',
    `UPDATE extension_builds SET allowed_hosts_json='["example.org"]'; INSERT INTO extension_builds (build_id,package_name,bundle_sha256,status,created_at,allowed_hosts_json) VALUES ('retired-policy','retired.package','${'a'.repeat(64)}','verified',0,'["retired.example.org"]');`,
    '--yes',
  );
  const updated = {
    ...manifest,
    buildId: manifest.buildId + '-next',
    version: manifest.version + '-next',
  };
  const unapproved = {
    ...manifest,
    buildId: 'unapproved-probe-build',
    packageName: 'unapproved.probe.package',
  };
  for (const value of [updated, unapproved])
    await createStaticSnapshot(
      staticRoot,
      value,
      artifactFolder,
      Buffer.from(JSON.stringify(value)),
    );
  await writeFile(
    path.join(staticRoot, 'extensions/index.json'),
    JSON.stringify({
      schemaVersion: 1,
      builds: [updated, unapproved].map((value) => ({
        buildId: value.buildId,
        packageName: value.packageName,
        repoId: value.repoId,
        version: value.version,
        sourceIds: value.sourceIds,
        manifestPath: `/extensions/builds/${value.buildId}/manifest.json`,
      })),
      nextCursor: null,
    }),
  );
  const synchronization: unknown = JSON.parse(
    runTool(
      path.join(root, 'tools/extensions/network-policies.ts'),
      '--local',
      '--static-root',
      staticRoot,
      '--persist-to',
      state,
    ),
  );
  assert(isRecord(synchronization));
  assert.equal(synchronization.inheritedPolicies, 1);
  assert.equal(synchronization.newPackagesRemainUnapproved, 1);
  const policyResult: unknown = JSON.parse(
    wrangler(
      'd1',
      'execute',
      'DB',
      '--command',
      'SELECT build_id,package_name,bundle_sha256,allowed_hosts_json FROM extension_builds',
      '--json',
    ),
  );
  assert(
    Array.isArray(policyResult) &&
      isRecord(policyResult[0]) &&
      Array.isArray(policyResult[0].results),
  );
  const policies: unknown[] = policyResult[0].results;
  assert.equal(
    policies.length,
    1,
    'Retired policy removed and new package stays unapproved',
  );
  const inherited = policies[0];
  assert(isRecord(inherited));
  assert.equal(inherited.build_id, updated.buildId);
  assert.equal(inherited.bundle_sha256, updated.bundle.sha256);
  assert.deepEqual(JSON.parse(String(inherited.allowed_hosts_json)), [
    'example.org',
  ]);
  const evidence = {
    probe: 'local-workerd-static-extensions-policy',
    passed: true,
    buildId: manifest.buildId,
    realRS256Verification: true,
    productionAccessVerified: false,
    sourceOnlineVerified: false,
    staticSnapshot: true,
    r2Bindings: false,
    encodedBytes: encoded.length,
    canonicalBytes: raw.length,
    bundleSha256: manifest.bundle.sha256,
    encodedSha256: manifest.bundle.encodedSha256,
    checks: [
      'static index/manifest/gzip bypass entry Worker',
      'gzip MIME without HTTP Content-Encoding',
      'encoded/canonical transfer integrity',
      'missing static navigation remains 404',
      'known app route shell',
      'host.html 307 normalization',
      'policy-only D1',
      'D1 batch conflict rollback',
      'RS256/audience/host',
      'removed API routes 404',
      'encoded API path rejected',
      'trusted deployment sync inherits package policy across builds',
      'retired policy deleted and new package unapproved',
    ],
  };
  await mkdir(path.dirname(evidencePath), { recursive: true });
  await writeFile(evidencePath, JSON.stringify(evidence, null, 2) + '\n');
  console.log(JSON.stringify(evidence, null, 2));
} finally {
  await mf?.dispose();
  await rm(temporary, { recursive: true, force: true });
}
