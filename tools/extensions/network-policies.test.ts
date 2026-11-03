import assert from 'node:assert/strict';
import { unlink, writeFile } from 'node:fs/promises';
import { test } from 'node:test';
import type { DatabaseSync } from 'node:sqlite';
import {
  currentBuilds,
  networkPoliciesMain,
  policyRows,
  synchronizationSql,
  type ApprovedPolicy,
} from './network-policies.ts';
import {
  database,
  fixture,
  snapshot,
  transaction,
} from './registration-fixtures.ts';
import { snapshotLoader } from './registration.ts';
import type { BuildManifest } from '../../packages/contracts/src/index.ts';

function insert(
  db: DatabaseSync,
  packageName: string,
  buildId: string,
  hosts: string[],
  status = 'verified',
) {
  db.prepare(
    'INSERT INTO extension_builds (package_name,build_id,bundle_sha256,status,created_at,allowed_hosts_json) VALUES (?,?,?,?,?,?)',
  ).run(packageName, buildId, 'a'.repeat(64), status, 1, JSON.stringify(hosts));
}
function approved(db: DatabaseSync) {
  return policyRows([
    {
      success: true,
      results: db
        .prepare(
          "SELECT package_name,build_id,bundle_sha256,allowed_hosts_json FROM extension_builds WHERE status='verified'",
        )
        .all(),
    },
  ]);
}
function synchronize(
  db: DatabaseSync,
  current: ReadonlyMap<string, BuildManifest>,
  policies: ApprovedPolicy[] = approved(db),
) {
  transaction(db, synchronizationSql(current, policies));
}

test('current build inherits approved policy; new package stays unapproved and retired package is deleted', async (t) => {
  const f = await fixture(t);
  const db = await database(t);
  insert(db, 'example.source', 'old', ['example.org']);
  insert(db, 'retired.package', 'retired', ['retired.example.org']);
  const current = new Map([
    [f.manifest.packageName, f.manifest],
    [
      'new.package',
      {
        ...f.manifest,
        packageName: 'new.package',
        buildId: 'new-package-build',
      },
    ],
  ]);
  synchronize(db, current);
  const rows = db.prepare('SELECT * FROM extension_builds').all();
  assert.equal(rows.length, 1);
  assert.equal(rows[0]?.build_id, f.manifest.buildId);
  assert.equal(rows[0]?.bundle_sha256, f.manifest.bundle.sha256);
  assert.equal(rows[0]?.allowed_hosts_json, '["example.org"]');
  synchronize(db, current);
  assert.deepEqual(db.prepare('SELECT * FROM extension_builds').all(), rows);
});
test('disabled policies are never promoted or inherited', async (t) => {
  const f = await fixture(t);
  const db = await database(t);
  const current = new Map([[f.manifest.packageName, f.manifest]]);
  insert(db, 'example.source', 'old', ['example.org'], 'disabled');
  synchronize(db, current);
  assert.deepEqual(db.prepare('SELECT * FROM extension_builds').all(), []);
  insert(db, 'example.source', f.manifest.buildId, ['example.org'], 'disabled');
  synchronize(db, current);
  assert.equal(
    db.prepare('SELECT status FROM extension_builds').get()?.status,
    'disabled',
  );
});
test('concurrent disable or host policy change aborts before retiring any rows', async (t) => {
  const f = await fixture(t);
  const db = await database(t);
  insert(db, 'example.source', 'old', ['example.org']);
  insert(db, 'retired.package', 'retired', ['retired.example.org']);
  const policies = approved(db);
  for (const [column, value] of [
    ['status', 'disabled'],
    ['allowed_hosts_json', '["changed.example.org"]'],
  ] as const) {
    db.exec(
      "UPDATE extension_builds SET status='verified',allowed_hosts_json='[\"example.org\"]' WHERE package_name='example.source'",
    );
    db.prepare(
      `UPDATE extension_builds SET ${column}=? WHERE package_name='example.source'`,
    ).run(value);
    assert.throws(
      () =>
        synchronize(
          db,
          new Map([[f.manifest.packageName, f.manifest]]),
          policies,
        ),
      /NOT NULL/,
    );
    assert.equal(
      db
        .prepare(
          "SELECT build_id FROM extension_builds WHERE package_name='example.source'",
        )
        .get()?.build_id,
      'old',
    );
    assert(
      db
        .prepare(
          "SELECT * FROM extension_builds WHERE package_name='retired.package'",
        )
        .get(),
    );
  }
});
test('an empty current index retires all approvals', async (t) => {
  const db = await database(t);
  insert(db, 'example.source', 'old', ['example.org']);
  synchronize(db, new Map());
  assert.deepEqual(db.prepare('SELECT * FROM extension_builds').all(), []);
});
test('metadata-only synchronization does not need bundle bytes', async (t) => {
  const f = await fixture(t);
  await snapshot(f.directory, f.manifest);
  await unlink(f.file);
  const current = await currentBuilds(snapshotLoader(f.directory));
  assert.deepEqual(current.get('example.source'), f.manifest);
});
test('current manifest identity must match its static descriptor', async (t) => {
  const f = await fixture(t);
  const s = await snapshot(f.directory, f.manifest);
  await writeFile(
    s.manifestFile,
    JSON.stringify({ ...f.manifest, buildId: 'different' }),
  );
  await assert.rejects(
    currentBuilds(snapshotLoader(f.directory)),
    /not current/,
  );
});
test('malformed D1 JSON and unapproved hostname forms fail closed', async (t) => {
  const db = await database(t);
  insert(db, 'example.source', 'old', ['example.org']);
  for (const response of [
    {},
    [],
    [{ success: false, results: [] }],
    [{ success: true, results: [{}] }],
  ])
    assert.throws(() => policyRows(response));
  for (const hosts of [
    ['*.example.org'],
    ['127.0.0.1'],
    ['service.internal'],
    [true],
    'example.org',
  ]) {
    const policy = approved(db)[0];
    assert(policy);
    assert.throws(() =>
      policyRows([
        {
          success: true,
          results: [
            {
              package_name: policy.packageName,
              build_id: policy.buildId,
              bundle_sha256: policy.bundleSha256,
              allowed_hosts_json: JSON.stringify(hosts),
            },
          ],
        },
      ]),
    );
  }
});
test('remote synchronization never accepts local snapshots or local D1 state', async (t) => {
  const f = await fixture(t);
  for (const option of ['--static-root', '--persist-to'])
    await assert.rejects(
      networkPoliciesMain(['--remote', option, f.directory]),
      /require --local/,
    );
});
