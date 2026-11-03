// Manual real-workerd D1/R2 integration. Only the separate test entry trusts
// this run's RSA public key; production index.ts never imports that entry.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { exportJWK, generateKeyPair, SignJWT } from 'jose';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const api = path.join(root, 'apps/api');
const manifestPath = process.argv[2] && path.resolve(process.argv[2]);
assert(
  manifestPath,
  'Usage: node apps/api/test/workerd-probe.mjs MANIFEST [ARTIFACT_FOLDER] [EVIDENCE_JSON]',
);
const evidencePath = process.argv[4] && path.resolve(process.argv[4]);
const artifactFolder = process.argv[3]
  ? path.resolve(process.argv[3])
  : path.join(root, 'runtime/teavm/.local/artifacts');
const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
const temporary = await mkdtemp(path.join(tmpdir(), 'karuyomi-api-probe-'));
const state = path.join(temporary, 'state');
const environment = {
  ...process.env,
  CLOUDFLARE_SEND_METRICS: 'false',
  WRANGLER_LOG_PATH: path.join(temporary, 'wrangler.log'),
};
const wrangler = (...args) =>
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
const python = (...args) =>
  execFileSync('python3', args, {
    cwd: root,
    env: environment,
    encoding: 'utf8',
  });
const require = createRequire(new URL('../package.json', import.meta.url));
const wranglerRequire = createRequire(require.resolve('wrangler'));
const { build } = await import(wranglerRequire.resolve('esbuild'));
const { Miniflare, convertV4MiniflareOptions } = await import(
  wranglerRequire.resolve('miniflare')
);
let mf;

try {
  console.log('Registering actual local artifacts into dedicated D1/R2 state');
  for (const name of [
    '0000_special_thing.sql',
    '0001_many_major_mapleleaf.sql',
  ]) {
    wrangler(
      'd1',
      'execute',
      'DB',
      '--file',
      path.join(api, 'migrations', name),
      '--yes',
    );
  }
  python(
    path.join(root, 'scripts/register-build.py'),
    manifestPath,
    '--artifacts',
    artifactFolder,
    '--local',
    '--persist-to',
    state,
  );
  const conflictPath = path.join(temporary, 'conflict.json');
  const conflictSql = path.join(temporary, 'conflict.sql');
  await writeFile(
    conflictPath,
    JSON.stringify({ ...manifest, version: `${manifest.version}-conflict` }),
  );
  const sql = python(
    '-c',
    `import importlib.util,json,pathlib,sys
s=importlib.util.spec_from_file_location('registration','scripts/register-build.py')
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
v=json.loads(pathlib.Path(sys.argv[1]).read_text())
print(m.registration_sql(v,m.verify(v,pathlib.Path(sys.argv[2])),[]))`,
    conflictPath,
    artifactFolder,
  );
  // The marker precedes the failing guard: its absence proves batch rollback.
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
  const databaseId = /"database_id":\s*"([^"]+)"/.exec(
    await readFile(path.join(api, 'wrangler.jsonc'), 'utf8'),
  )[1];
  mf = new Miniflare(
    convertV4MiniflareOptions({
      modules: true,
      script: compiled.outputFiles[0].text,
      compatibilityDate: '2026-11-03',
      resourcePersistencePath: path.join(state, 'v3'),
      d1Databases: { DB: databaseId },
      r2Buckets: { ARTIFACTS: 'karuyomi-private' },
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
  const db = await mf.getD1Database('DB');
  assert.equal(
    await db
      .prepare("SELECT value FROM app_metadata WHERE key='rollback-probe'")
      .first('value'),
    null,
  );
  const registered = JSON.parse(
    await db
      .prepare('SELECT manifest_json FROM extension_builds WHERE build_id=?')
      .bind(manifest.buildId)
      .first('manifest_json'),
  );
  assert.equal(registered.version, manifest.version);
  const token = (audience = 'probe-app') =>
    new SignJWT({ email: 'probe@example.com' })
      .setProtectedHeader({ alg: 'RS256', kid: jwk.kid })
      .setSubject('probe-owner')
      .setIssuer('https://probe.cloudflareaccess.com')
      .setAudience(audience)
      .setIssuedAt()
      .setExpirationTime('5m')
      .sign(keys.privateKey);
  const signed = await token();
  const request = (pathname, headers = {}, method = 'GET') =>
    mf.dispatchFetch(`https://read.example.com${pathname}`, {
      method,
      headers: { 'Cf-Access-Jwt-Assertion': signed, ...headers },
    });
  const route = `/api/extensions/builds/${manifest.buildId}/manifest`;
  assert.equal(
    (await mf.dispatchFetch(`https://read.example.com${route}`)).status,
    401,
  );
  assert.equal(
    (
      await request(route, {
        'Cf-Access-Jwt-Assertion': await token('wrong-app'),
      })
    ).status,
    401,
  );
  assert.equal(
    (
      await mf.dispatchFetch(`https://alternate.example${route}`, {
        headers: { 'Cf-Access-Jwt-Assertion': signed },
      })
    ).status,
    403,
  );
  const delivered = await request(route);
  assert.equal(delivered.status, 200);
  assert.equal(delivered.headers.get('cache-control'), 'private, no-store');
  assert.equal((await delivered.json()).buildId, manifest.buildId);
  assert.equal(
    (await (await request('/api/extensions/builds')).json()).builds[0].buildId,
    manifest.buildId,
  );
  let total = 0;
  const artifacts = [
    manifest.bundle,
    ...manifest.hostScripts,
    ...(manifest.resources ?? []),
  ];
  for (const item of artifacts) {
    const response = await request(item.path);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'private, no-cache');
    assert.equal(response.headers.get('etag'), `"${item.sha256}"`);
    const bytes = Buffer.from(await response.arrayBuffer());
    assert.equal(bytes.length, item.size);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), item.sha256);
    total += bytes.length;
    const partial = await request(item.path, { Range: 'bytes=0-2' });
    assert.equal(partial.status, 206);
    assert.deepEqual(
      Buffer.from(await partial.arrayBuffer()),
      bytes.subarray(0, 3),
    );
    const head = await request(item.path, {}, 'HEAD');
    assert.equal(head.status, 200);
    assert.equal(head.headers.get('content-length'), String(item.size));
    assert.equal((await head.arrayBuffer()).byteLength, 0);
    assert.equal(
      (await request(item.path, { 'If-None-Match': `"${item.sha256}"` }))
        .status,
      304,
    );
    assert.equal(
      (
        await request(item.path, {
          'Cf-Access-Jwt-Assertion': '',
          'If-None-Match': `"${item.sha256}"`,
        })
      ).status,
      401,
    );
    assert.equal(
      (await request(item.path, { Range: `bytes=${item.size}-` })).status,
      416,
    );
  }
  const evidence = {
    probe: 'local-workerd-registered-artifacts',
    passed: true,
    buildId: manifest.buildId,
    artifacts: artifacts.length,
    totalBytes: total,
    realRS256Verification: true,
    immutableConflictRolledBack: true,
    checks: [
      'D1 verified manifest',
      'R2 SHA256',
      'private cache',
      'wrong audience/host',
      'HEAD',
      '304 after auth',
      'range',
      '416',
    ],
    productionAccessVerified: false,
    manifestSha256: createHash('sha256')
      .update(await readFile(manifestPath))
      .digest('hex'),
    sourceSha256: {},
  };
  for (const name of [
    'apps/api/src/access.ts',
    'apps/api/src/app.ts',
    'apps/api/src/extensions.ts',
    'apps/api/src/http-bridge.ts',
    'apps/api/test/workerd-entry.ts',
    'apps/api/test/workerd-probe.mjs',
    'scripts/register-build.py',
  ]) {
    evidence.sourceSha256[name] = createHash('sha256')
      .update(await readFile(path.join(root, name)))
      .digest('hex');
  }
  const json = JSON.stringify(evidence, null, 2) + '\n';
  if (evidencePath) await writeFile(evidencePath, json);
  console.log(json);
} finally {
  await mf?.dispose();
  await rm(temporary, { recursive: true, force: true });
}
