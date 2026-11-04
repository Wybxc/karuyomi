import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test, type TestContext } from 'node:test';
import {
  git,
  scan,
  SHARED_PATHS,
  treeHash,
  HOST_PATHS,
  hostFingerprint,
} from './catalog.ts';
import stableStringify from 'json-stable-stringify';
function fixture(t: TestContext) {
  const root = mkdtempSync(path.join(tmpdir(), 'karuyomi-catalog-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  git(root, 'init', '-q');
  const put = (file: string, text: string) => {
    mkdirSync(path.dirname(path.join(root, file)), { recursive: true });
    writeFileSync(path.join(root, file), text);
  };
  const commit = () => {
    git(root, 'add', '.');
    git(
      root,
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.invalid',
      'commit',
      '-qm',
      'fixture',
    );
  };
  for (const name of SHARED_PATHS)
    put(
      path.basename(name).includes('.') || name.startsWith('gradlew')
        ? name
        : name + '/shared.txt',
      'fixed input\n',
    );
  put(
    'src/en/first/build.gradle.kts',
    'keiyoushi {\nversionCode = 2\nlibVersion = "1.6"\ntheme = "theme"\n}\n',
  );
  put('src/en/first/src/First.kt', 'class First\n');
  put(
    'src/en/second/build.gradle.kts',
    'keiyoushi {\nversionCode = 3\nlibVersion = "1.6"\n}\n',
  );
  put(
    'lib-multisrc/theme/build.gradle.kts',
    'baseVersionCode = 7\nlibVersion = "1.6"\napi(project(":lib:helper"))\n',
  );
  put('lib/helper/build.gradle.kts', 'implementation(project(":lib:leaf"))\n');
  put('lib/leaf/build.gradle.kts', 'plugins {}\n');
  commit();
  return {
    root,
    put,
    commit,
    scan: (host = '0'.repeat(64)) => scan(root, host),
  };
}
test('Gradle version, package and transitive dependencies', (t) => {
  const f = fixture(t),
    result = f.scan(),
    first = result.entries[0];
  assert.ok(first);
  assert.deepEqual(result.discoveryFailures, []);
  assert.equal(first.packageName, 'eu.kanade.tachiyomi.extension.en.first');
  assert.equal(first.versionName, '1.6.9');
  assert.equal(first.versionCode, 106009);
  assert.deepEqual(
    Object.keys(first.sourceInputs).sort(),
    ['src/en/first', 'lib-multisrc/theme', 'lib/helper', 'lib/leaf'].sort(),
  );
});
test('transitive library changes invalidate only dependents without version changes', (t) => {
  const f = fixture(t),
    before = f.scan().entries;
  f.put('lib/leaf/Leaf.kt', 'class Changed');
  f.commit();
  const after = f.scan().entries;
  assert.notEqual(before[0]?.inputFingerprint, after[0]?.inputFingerprint);
  assert.equal(before[1]?.inputFingerprint, after[1]?.inputFingerprint);
});
test('shared inputs and host changes invalidate all affected identities', (t) => {
  const f = fixture(t),
    before = f.scan().entries;
  f.put('core/shared.txt', 'changed');
  f.commit();
  const after = f.scan().entries;
  assert.ok(
    after.every(
      (entry, index) =>
        entry.inputFingerprint !== before[index]?.inputFingerprint,
    ),
  );
  assert.ok(
    f
      .scan('1'.repeat(64))
      .entries.every(
        (entry, index) =>
          entry.inputFingerprint !== after[index]?.inputFingerprint,
      ),
  );
});
test('unrelated commits preserve closure identities', (t) => {
  const f = fixture(t),
    before = f.scan();
  f.put('README.md', 'unrelated');
  f.commit();
  const after = f.scan();
  assert.notEqual(before.upstreamCommit, after.upstreamCommit);
  assert.deepEqual(
    before.entries.map((entry) => entry.inputFingerprint),
    after.entries.map((entry) => entry.inputFingerprint),
  );
});
test('dirty trees fail and unsupported Kotlin is isolated per package', (t) => {
  const f = fixture(t);
  f.put(
    'src/en/first/build.gradle.kts',
    'versionCode = 1 + 2\nlibVersion = "1.6"\n',
  );
  assert.throws(() => f.scan(), /dirty/);
  f.commit();
  const result = f.scan();
  assert.equal(result.entries.length, 1);
  assert.equal(result.discoveryFailures.length, 1);
  assert.match(
    result.discoveryFailures[0]?.message ?? '',
    /Unsupported expression/,
  );
});
test('generated host outputs do not change fingerprints; stable JSON uses lexical UTF-16 keys', (t) => {
  const f = fixture(t),
    before = treeHash(f.root, 'lib');
  f.put('lib/target/classes/Generated.class', 'generated');
  f.put('lib/__pycache__/module.pyc', 'generated');
  assert.equal(treeHash(f.root, 'lib'), before);
  assert.equal(
    stableStringify({ '2': 2, '10': 10, '\ue000': 3, '😀': 4 }),
    '{"10":10,"2":2,"😀":4,"\ue000":3}',
  );
  assert.equal(
    stableStringify({ z: 1, A: 2, _: 3, a: { b: '漫画', a: 1 } }),
    '{"A":2,"_":3,"a":{"a":1,"b":"漫画"},"z":1}',
  );
});

test('candidate codec sources, artifact locks and caches stay outside the Source host identity', (t) => {
  const f = fixture(t);
  for (const name of HOST_PATHS) {
    f.put(
      path.basename(name).includes('.') ? name : name + '/fixture.txt',
      'fixed host input\n',
    );
  }
  const candidateInputs = [
    'runtime/image-codec/png.c',
    'runtime/image-codec/worker.ts',
    'runtime/image-codec/assets.ts',
    'runtime/image-codec/tile-store.ts',
    'runtime/image-codec/artifacts-lock.json',
    'tools/images/build.ts',
    'tools/images/artifacts.ts',
  ];
  for (const name of candidateInputs) f.put(name, 'candidate input v1\n');
  const before = hostFingerprint(f.root).fingerprint;
  for (const name of candidateInputs) {
    f.put(name, 'candidate input v2\n');
    assert.equal(hostFingerprint(f.root).fingerprint, before, name);
  }
  f.put(
    'runtime/image-codec/.local/build/generated.wasm',
    'ignored cached build',
  );
  assert.equal(hostFingerprint(f.root).fingerprint, before);

  f.put('runtime/teavm/bridge/graphics-bridge.ts', 'changed Source bridge\n');
  const bridgeChanged = hostFingerprint(f.root).fingerprint;
  assert.notEqual(bridgeChanged, before);
  f.put('packages/runtime-host/materials.ts', 'changed Source materials\n');
  assert.notEqual(hostFingerprint(f.root).fingerprint, bridgeChanged);
});
