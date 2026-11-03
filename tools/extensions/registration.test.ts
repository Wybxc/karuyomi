import assert from 'node:assert/strict';
import { readFile, rename, symlink, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { test } from 'node:test';
import { gzipSync } from 'node:zlib';
import { collectMaterials } from '../../packages/runtime-host/materials.ts';
import { digest, repositoryRoot } from './verify-manifest.ts';
import {
  database,
  fixture,
  snapshot,
  transaction,
} from './registration-fixtures.ts';
import {
  registrationMain,
  registrationSql,
  snapshotLoader,
  verifyBuild,
  verifyStaticAuthority,
} from './registration.ts';

test('policy-only registration and identical retry are idempotent', async (t) => {
  const f = await fixture(t);
  const db = await database(t);
  transaction(db, registrationSql(f.manifest, ['example.org']));
  const before = db.prepare('SELECT * FROM extension_builds').all();
  transaction(db, registrationSql(f.manifest, ['example.org']));
  assert.deepEqual(db.prepare('SELECT * FROM extension_builds').all(), before);
  assert.equal(before[0]?.status, 'verified');
  assert(
    !db
      .prepare("SELECT name FROM sqlite_master WHERE type='table'")
      .all()
      .some((row) =>
        ['extension_artifacts', 'build_artifacts'].includes(String(row.name)),
      ),
  );
  assert(
    !db
      .prepare('PRAGMA table_info(extension_builds)')
      .all()
      .some((row) => row.name === 'manifest_json'),
  );
});
test('new current build replaces previous package policy', async (t) => {
  const f = await fixture(t);
  const db = await database(t);
  transaction(db, registrationSql(f.manifest, ['example.org']));
  transaction(
    db,
    registrationSql({ ...f.manifest, buildId: 'next-current' }, [
      'new.example.org',
    ]),
  );
  const rows = db.prepare('SELECT * FROM extension_builds').all();
  assert.equal(rows.length, 1);
  assert.equal(rows[0]?.build_id, 'next-current');
  assert.equal(rows[0]?.allowed_hosts_json, '["new.example.org"]');
});
test('build identity and policy conflicts roll back the entire batch', async (t) => {
  const f = await fixture(t);
  const db = await database(t);
  transaction(db, registrationSql(f.manifest, ['example.org']));
  const before = db.prepare('SELECT * FROM extension_builds').all();
  for (const [manifest, hosts] of [
    [
      {
        ...f.manifest,
        bundle: { ...f.manifest.bundle, sha256: 'a'.repeat(64) },
      },
      ['example.org'],
    ],
    [f.manifest, ['other.example.org']],
    [{ ...f.manifest, packageName: 'other.package' }, ['example.org']],
  ] as const) {
    assert.throws(
      () =>
        transaction(
          db,
          "INSERT INTO app_metadata VALUES ('rollback','marker');\n" +
            registrationSql(manifest, hosts),
        ),
      /NOT NULL/,
    );
    assert.deepEqual(
      db.prepare('SELECT * FROM extension_builds').all(),
      before,
    );
    assert.deepEqual(db.prepare('SELECT * FROM app_metadata').all(), []);
  }
});
test('migration retires old prototype distribution rows', async () => {
  const db = new DatabaseSync(':memory:');
  try {
    db.exec(
      await readFile(
        path.join(
          repositoryRoot,
          'apps/api/migrations/0001_many_major_mapleleaf.sql',
        ),
        'utf8',
      ),
    );
    db.exec(
      "INSERT INTO extension_builds VALUES ('old','package','{}','verified',0,'[]')",
    );
    db.exec(
      await readFile(
        path.join(
          repositoryRoot,
          'apps/api/migrations/0002_complete_mister_sinister.sql',
        ),
        'utf8',
      ),
    );
    assert.deepEqual(db.prepare('SELECT * FROM extension_builds').all(), []);
  } finally {
    db.close();
  }
});
test('only gzip bundle is read and both transfer hashes are checked', async (t) => {
  const f = await fixture(t);
  assert.deepEqual(await verifyBuild(f.manifest, f.artifacts), f.manifest);
  await assert.rejects(
    verifyBuild(
      {
        ...f.manifest,
        bundle: { ...f.manifest.bundle, encodedSha256: 'a'.repeat(64) },
      },
      f.artifacts,
    ),
    /SHA-256/,
  );
  const manifest = {
    ...f.manifest,
    bundle: {
      ...f.manifest.bundle,
      sha256: 'a'.repeat(64),
      path: '/extensions/artifacts/' + 'a'.repeat(64) + '.gz',
    },
  };
  await writeFile(path.join(f.artifacts, 'a'.repeat(64) + '.gz'), f.encoded);
  await assert.rejects(verifyBuild(manifest, f.artifacts), /SHA-256/);
});
test('gzip truncation, trailing junk, extra members and bombs are rejected', async (t) => {
  const f = await fixture(t);
  for (const encoded of [
    f.encoded.subarray(0, -1),
    Buffer.concat([f.encoded, Buffer.from('trailing')]),
    Buffer.concat([f.encoded, f.encoded]),
    gzipSync(Buffer.alloc(4 * 1024 * 1024, 88)),
    Buffer.from('invalid'),
  ]) {
    await writeFile(f.file, encoded);
    await assert.rejects(
      verifyBuild(
        {
          ...f.manifest,
          bundle: {
            ...f.manifest.bundle,
            encodedSize: encoded.length,
            encodedSha256: digest(encoded),
          },
        },
        f.artifacts,
      ),
      /gzip/,
    );
  }
});
test('valid large gzip obeys the canonical output budget', async (t) => {
  const f = await fixture(
    t,
    Buffer.concat(
      Array.from({ length: 2048 }, () =>
        Buffer.from(Array.from({ length: 256 }, (_, index) => index)),
      ),
    ),
  );
  await verifyBuild(f.manifest, f.artifacts);
  await assert.rejects(
    verifyBuild(
      { ...f.manifest, bundle: { ...f.manifest.bundle, size: 65536 } },
      f.artifacts,
    ),
    /gzip/,
  );
});
test('schema-only mode skips bytes but keeps schema, regular-file and size checks', async (t) => {
  const f = await fixture(t);
  await writeFile(f.file, Buffer.alloc(f.encoded.length));
  await verifyBuild(f.manifest, f.artifacts, { verifyHashes: false });
  await assert.rejects(verifyBuild(f.manifest, f.artifacts));
  await assert.rejects(
    verifyBuild(
      {
        ...f.manifest,
        bundle: { ...f.manifest.bundle, encodedSize: f.encoded.length + 1 },
      },
      f.artifacts,
      { verifyHashes: false },
    ),
    /size/,
  );
});
test('bad metadata, symbolic files and raw artifact paths are rejected', async (t) => {
  const f = await fixture(t);
  for (const [key, value] of [
    ['path', '/api/extensions/artifacts/' + f.manifest.bundle.sha256],
    ['encoding', 'br'],
    ['encodedSha256', 'a'],
    ['encodedSize', true],
    ['size', 0],
    ['contentType', 'application/octet-stream'],
  ] as const)
    await assert.rejects(
      verifyBuild(
        { ...f.manifest, bundle: { ...f.manifest.bundle, [key]: value } },
        f.artifacts,
      ),
    );
  await rename(f.file, f.file + '.original');
  await symlink(f.file + '.original', f.file);
  await assert.rejects(
    verifyBuild(f.manifest, f.artifacts),
    /regular|symbolic/,
  );
});
test('malformed and incompatible manifests are rejected by the shared contract', async (t) => {
  const f = await fixture(t);
  for (const [key, value] of [
    ['sourceIds', []],
    ['bridgeVersion', true],
    ['bridgeVersion', 1],
    ['packageName', ''],
    ['hostScripts', [null]],
    ['resources', [{ logicalName: '' }]],
  ] as const)
    await assert.rejects(
      verifyBuild({ ...f.manifest, [key]: value }, f.artifacts),
    );
});
test('shared materials are catalog-checked without per-build transfers', async (t) => {
  const f = await fixture(t);
  const { catalog } = await collectMaterials({ includeWasmBytes: false });
  const manifest = {
    ...f.manifest,
    hostScripts: catalog.hostScripts,
    resources: catalog.resources,
  };
  await verifyBuild(manifest, f.artifacts, { materialCatalog: catalog });
  const script = catalog.hostScripts[0];
  assert(script);
  await assert.rejects(
    verifyBuild(
      { ...manifest, hostScripts: [{ ...script, size: 1 }] },
      f.artifacts,
      { materialCatalog: catalog },
    ),
    /material/,
  );
});
test('bundle cannot substitute a material and materials cannot be encoded bundles', async (t) => {
  const f = await fixture(t);
  const { catalog } = await collectMaterials({ includeWasmBytes: false });
  const material = catalog.hostScripts[0];
  assert(material);
  await assert.rejects(
    verifyBuild({ ...f.manifest, bundle: material }, f.artifacts),
  );
  for (const role of ['hostScripts', 'resources'])
    await assert.rejects(
      verifyBuild(
        {
          ...f.manifest,
          [role]: [{ ...f.manifest.bundle, logicalName: 'x.js' }],
        },
        f.artifacts,
      ),
    );
  await assert.rejects(
    verifyBuild(
      { ...f.manifest, hostScripts: [{ ...material, encoding: 'gzip' }] },
      f.artifacts,
    ),
  );
});
test('registration requires current static descriptor and exact normalized manifest', async (t) => {
  const f = await fixture(t);
  const s = await snapshot(f.directory, f.manifest);
  const load = snapshotLoader(f.directory);
  await verifyStaticAuthority(f.manifest, load);
  const descriptor = s.index.builds[0];
  assert(descriptor);
  for (const [key, value] of [
    ['buildId', 'old'],
    ['version', 'other'],
    ['sourceIds', ['1']],
    ['manifestPath', 'https://other.example/manifest'],
  ] as const) {
    await writeFile(
      s.indexFile,
      JSON.stringify({ ...s.index, builds: [{ ...descriptor, [key]: value }] }),
    );
    await assert.rejects(verifyStaticAuthority(f.manifest, load));
  }
  await writeFile(s.indexFile, JSON.stringify(s.index));
  await writeFile(
    s.manifestFile,
    JSON.stringify({ ...f.manifest, version: 'other' }),
  );
  await assert.rejects(verifyStaticAuthority(f.manifest, load), /differs/);
});
test('duplicate static packages and missing current builds are rejected', async (t) => {
  const f = await fixture(t);
  const s = await snapshot(f.directory, f.manifest);
  for (const builds of [[], [...s.index.builds, ...s.index.builds]]) {
    await writeFile(s.indexFile, JSON.stringify({ ...s.index, builds }));
    await assert.rejects(
      verifyStaticAuthority(f.manifest, snapshotLoader(f.directory)),
    );
  }
});
test('local CLI submits only policy SQL after checking its explicit snapshot', async (t) => {
  const f = await fixture(t);
  await snapshot(f.directory, f.manifest);
  const db = await database(t);
  let calls = 0;
  t.mock.method(console, 'log', () => {});
  await registrationMain(
    [
      f.manifestFile,
      '--artifacts',
      f.artifacts,
      '--local',
      '--static-root',
      f.directory,
      '--allow-host',
      'example.org',
    ],
    async (args, destination) => {
      calls++;
      assert.equal(destination.mode, 'local');
      const file = args[args.indexOf('--file') + 1];
      assert(file);
      const sql = await readFile(file, 'utf8');
      assert(!sql.includes('extension_artifacts'));
      assert(!sql.includes('manifest_json'));
      transaction(db, sql);
      return [{ success: true }];
    },
  );
  assert.equal(calls, 1);
  assert.equal(db.prepare('SELECT * FROM extension_builds').all().length, 1);
});
test('registration retires policies removed from the current static index', async (t) => {
  const f = await fixture(t);
  const db = await database(t);
  transaction(db, registrationSql(f.manifest, ['example.org']));
  transaction(
    db,
    registrationSql(
      { ...f.manifest, packageName: 'removed.package', buildId: 'removed' },
      ['example.org'],
    ),
  );
  transaction(
    db,
    registrationSql(f.manifest, ['example.org'], new Set([f.manifest.buildId])),
  );
  assert.equal(db.prepare('SELECT * FROM extension_builds').all().length, 1);
});
test('plan-only never writes D1 or contacts deployed authority', async (t) => {
  const f = await fixture(t);
  t.mock.method(console, 'log', () => {});
  const fetch = t.mock.method(globalThis, 'fetch', () => {
    throw new Error('network');
  });
  let calls = 0;
  await registrationMain(
    [f.manifestFile, '--artifacts', f.artifacts],
    async () => {
      calls++;
      throw new Error('D1');
    },
  );
  assert.equal(calls, 0);
  assert.equal(fetch.mock.callCount(), 0);
});
test('Cloudflare encoded single-file limit is enforced before reading', async (t) => {
  const f = await fixture(t);
  await assert.rejects(
    verifyBuild(
      {
        ...f.manifest,
        bundle: { ...f.manifest.bundle, encodedSize: 25 * 1024 * 1024 + 1 },
      },
      f.artifacts,
      { verifyHashes: false },
    ),
  );
});
test('remote CLI rejects snapshots and refuses stale deployed current identity', async (t) => {
  const f = await fixture(t);
  await assert.rejects(
    registrationMain([
      f.manifestFile,
      '--remote',
      '--static-root',
      f.directory,
    ]),
    /require --local/,
  );
  t.mock.method(globalThis, 'fetch', async () =>
    Response.json({ schemaVersion: 1, builds: [], nextCursor: null }),
  );
  let calls = 0;
  await assert.rejects(
    registrationMain(
      [f.manifestFile, '--artifacts', f.artifacts, '--remote'],
      async () => {
        calls++;
        return [];
      },
    ),
    /not current/,
  );
  assert.equal(calls, 0);
});
