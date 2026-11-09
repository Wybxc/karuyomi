import assert from 'node:assert/strict';
import {
  chmodSync,
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  realpathSync,
  rmSync,
  symlinkSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test, type TestContext } from 'node:test';
import { createHash } from 'node:crypto';
import stableStringify from 'json-stable-stringify';
import writeFileAtomic from 'write-file-atomic';
import { ROOT, git } from './catalog.ts';
import { addHostTestSubmodules } from './test-submodules.ts';
import { encodeBundle, StaticHttpError } from './assets.ts';
import { PreferenceValueKind } from '@karuyomi/protocol';
import { preferenceSyncRulesForBuild } from './builder.ts';
import {
  BuilderProcesses,
  BuildCancelled,
  ExtensionPipeline,
  VerifiedBuild,
  assertCiRuntimeCompatible,
  cleanupBuiltWork,
  emptyState,
  finalizeBaseline,
  loadState,
  MAX_STATE_BYTES,
  makeBaselinePlan,
  makePlan,
  persistStateCheckpoint,
  removeBuildWork,
  runtimeIdentity,
  validateState,
} from './pipeline.ts';
import {
  publishedBuildId,
  runtimeIdentitySchema,
  type Catalog,
  type ExtensionDescriptor,
  type ExtensionPlan,
  type ExtensionState,
  type PipelineResult,
  type RuntimeIdentity,
} from './model.ts';
import { parseExtensionIndex, parseManifest } from './verify-manifest.ts';
const materialIdentity = runtimeIdentitySchema.parse({
  ...JSON.parse(
    readFileSync(path.join(ROOT, 'packages/contracts/protocol.json'), 'utf8'),
  ),
  bridgeVersion: 2,
  hostScripts: [],
  resources: [],
});
class Fixture {
  readonly root: string;
  readonly results: string;
  readonly snapshot: string;
  readonly stateFile: string;
  readonly pipeline: ExtensionPipeline;
  readonly fetched: string[] = [];
  readonly remoteOverrides = new Map<string, Buffer>();
  private readonly identity: RuntimeIdentity;
  constructor(t: TestContext, identity = materialIdentity) {
    this.identity = identity;
    const environment = {
      CI: process.env.CI,
      GITHUB_ACTIONS: process.env.GITHUB_ACTIONS,
    };
    process.env.CI = 'false';
    process.env.GITHUB_ACTIONS = 'false';
    t.after(() => {
      for (const [key, value] of Object.entries(environment)) {
        if (value === undefined) delete process.env[key];
        else process.env[key] = value;
      }
    });
    this.root = realpathSync(
      mkdtempSync(path.join(tmpdir(), 'karuyomi-pipeline-')),
    );
    t.after(() => rmSync(this.root, { recursive: true, force: true }));
    this.results = path.join(this.root, 'results');
    mkdirSync(this.results);
    this.snapshot = path.join(this.root, 'snapshot');
    this.stateFile = path.join(this.root, 'state.json');
    git(this.root, 'init', '-q');
    writeFileSync(path.join(this.root, 'fixture.txt'), 'fixture');
    git(this.root, 'add', 'fixture.txt');
    git(
      this.root,
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.invalid',
      'commit',
      '-qm',
      'fixture',
    );
    addHostTestSubmodules(this.root);
    this.pipeline = new ExtensionPipeline({
      root: this.root,
      materials: async () => this.identity,
      fetchBytes: async (_origin, relative) => {
        this.fetched.push(relative);
        const override = this.remoteOverrides.get(relative);
        if (override) return override;
        const file = path.join(this.snapshot, relative.slice(1));
        if (!existsSync(file)) throw new StaticHttpError(404);
        return readFileSync(file);
      },
    });
  }
  descriptor(key = 'a', packageName = 'example.one'): ExtensionDescriptor {
    return {
      schemaVersion: 1,
      packageName,
      sourcePath: 'src/en/' + packageName.split('.').at(-1),
      buildId: 'ext-' + packageName + '-' + key.repeat(32),
      versionName: '1.6.1',
      versionCode: 106001,
      declaredVersionCode: 1,
      effectiveVersionCode: 1,
      inputFingerprint: key.repeat(64),
      hostFingerprint: 'd'.repeat(64),
      sourceFingerprint: 'e'.repeat(64),
      upstreamCommit: 'a'.repeat(40),
      sourceInputs: {},
      sharedInputs: {},
      hostInputs: {},
    };
  }
  catalog(entries: ExtensionDescriptor[]): Catalog {
    return {
      schemaVersion: 1,
      entries,
      upstreamCommit: 'a'.repeat(40),
      hostFingerprint: 'd'.repeat(64),
      catalogFingerprint: createHash('sha256')
        .update(
          stableStringify(entries.map((entry) => entry.inputFingerprint)) ??
            assert.fail('Fixture must be valid JSON'),
        )
        .digest('hex'),
      discoveryFailures: [],
    };
  }
  plan(
    entries: ExtensionDescriptor[],
    state = emptyState(),
    selected = entries,
  ): ExtensionPlan {
    return {
      ...this.catalog(entries),
      selected,
      baseRevision: state.revision,
      repositoryCommit: git(this.root, 'rev-parse', 'HEAD'),
      pendingCount: selected.length,
      remainingCount: 0,
      ci: false,
      snapshotNeeded: true,
    };
  }
  output(
    descriptor: ExtensionDescriptor,
    failed = false,
    suffix = '',
    resultsDirectory = this.results,
  ): { directory: string; result: PipelineResult } {
    const directory = path.join(resultsDirectory, descriptor.inputFingerprint);
    mkdirSync(directory, { recursive: true });
    const result: PipelineResult = {
      schemaVersion: 1,
      descriptor,
      status: failed ? 'failed' : 'built',
    };
    if (failed)
      result.failure = {
        stage: 'aot',
        code: 'source_failed',
        message: 'Compilation failed',
      };
    else {
      const { encoded, reference } = encodeBundle(
        Buffer.from(
          'const packageName = ' +
            JSON.stringify(descriptor.packageName) +
            ';' +
            suffix,
        ),
      );
      mkdirSync(path.join(directory, 'artifacts'), { recursive: true });
      writeFileSync(
        path.join(directory, 'artifacts', reference.sha256 + '.gz'),
        encoded,
      );
      writeFileAtomic.sync(
        path.join(directory, 'manifest.json'),
        JSON.stringify({
          ...this.identity,
          buildId: publishedBuildId(descriptor, reference.sha256),
          repoId: 'keiyoushi',
          packageName: descriptor.packageName,
          version: descriptor.versionName,
          sourceIds: ['1'],
          sources: [{ id: '1', name: 'Fixture', lang: 'en' }],
          preferenceSyncRules: preferenceSyncRulesForBuild(
            descriptor.packageName,
          ),
          storageSchema: '1',
          bundle: reference,
        }) + '\n',
      );
    }
    writeFileAtomic.sync(
      path.join(directory, 'pipeline-result.json'),
      JSON.stringify(result) + '\n',
    );
    return { directory, result };
  }
  prepare(
    plan: ExtensionPlan,
    state = emptyState(),
    options: Parameters<ExtensionPipeline['prepareSnapshot']>[4] = {},
  ) {
    return this.pipeline.prepareSnapshot(
      plan,
      state,
      this.results,
      this.snapshot,
      options,
    );
  }
  index() {
    return parseExtensionIndex(
      readFileSync(path.join(this.snapshot, 'extensions/index.json')),
    );
  }
}
test('checkpoint persistence validates before replacement, bounds metadata and preserves private file permissions', (t) => {
  const f = new Fixture(t);
  const directory = path.join(f.root, 'checkpoints');
  const file = path.join(directory, 'state.json');
  const state = emptyState();
  persistStateCheckpoint(file, state);
  if (process.platform !== 'win32') chmodSync(file, 0o600);
  state.revision = 'a'.repeat(32);
  persistStateCheckpoint(file, state);
  const before = readFileSync(file);
  assert.equal(before.toString(), stableStringify(state) + '\n');
  assert.deepEqual(loadState(file), state);
  if (process.platform !== 'win32')
    assert.equal(statSync(file).mode & 0o777, 0o600);
  const invalid = { ...state, active: { 'unknown.package': 'a'.repeat(64) } };
  assert.throws(() => persistStateCheckpoint(file, invalid), /pointer/);
  assert.deepEqual(readFileSync(file), before);
  const descriptor = f.descriptor();
  const oversized: ExtensionState = {
    ...state,
    attempts: {
      [descriptor.inputFingerprint]: {
        descriptor,
        status: 'failed',
        attempts: 1,
        failure: {
          stage: 'upstream',
          code: 'fixture',
          message: 'x'.repeat(MAX_STATE_BYTES),
        },
      },
    },
  };
  assert.throws(() => persistStateCheckpoint(file, oversized), /Oversized/);
  assert.deepEqual(readFileSync(file), before);
  assert.deepEqual(readdirSync(directory), ['state.json']);
});
test('complete gzip-only snapshot commits checkpoint only after remote confirmation', async (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor();
  f.output(descriptor);
  const candidate = await f.prepare(f.plan([descriptor]), emptyState(), {
    finalize: true,
  });
  assert.equal(existsSync(f.stateFile), false);
  assert.equal(
    candidate.indexSha256,
    createHash('sha256')
      .update(readFileSync(path.join(f.snapshot, 'extensions/index.json')))
      .digest('hex'),
  );
  assert.equal(candidate.bootstrap.complete, true);
  assert.deepEqual((await f.index()).builds[0]?.sources, [
    { id: '1', name: 'Fixture', lang: 'en' },
  ]);
  const build = (await f.index()).builds[0];
  assert.ok(build);
  const current = await parseManifest(
    readFileSync(path.join(f.snapshot, build.manifestPath.slice(1))),
  );
  assert.deepEqual(current.sources, build.sources);
  assert.equal(
    build.manifestPath,
    '/extensions/builds/' +
      publishedBuildId(descriptor, current.bundle.sha256) +
      '/manifest.json',
  );
  assert.equal(
    candidate.attempts[descriptor.inputFingerprint]?.bundleSha256,
    current.bundle.sha256,
  );
  assert.ok(
    readdirSync(path.join(f.snapshot, 'extensions/artifacts')).every((name) =>
      name.endsWith('.gz'),
    ),
  );
  assert.equal(
    candidate.attempts[descriptor.inputFingerprint]?.runtimeReady,
    false,
  );
  await f.pipeline.commitSnapshot(
    f.stateFile,
    f.snapshot,
    'https://example.invalid',
  );
  assert.deepEqual(loadState(f.stateFile), candidate);
});
test('AOT preference rules survive fresh and retained snapshot assembly without entering the index', async (t) => {
  const f = new Fixture(t);
  const reviewed = f.descriptor(
    'a',
    'eu.kanade.tachiyomi.extension.en.mangakatana',
  );
  const unrelated = f.descriptor('b', reviewed.packageName + '.other');
  f.output(reviewed);
  f.output(unrelated);
  const descriptors = [reviewed, unrelated];
  const state = await f.prepare(f.plan(descriptors));
  const assertSnapshotRules = async () => {
    const index = await f.index();
    assert.equal(index.builds.length, 2);
    for (const build of index.builds) {
      assert.equal(Object.hasOwn(build, 'preferenceSyncRules'), false);
      const manifest = await parseManifest(
        readFileSync(path.join(f.snapshot, build.manifestPath.slice(1))),
      );
      const rules = (manifest.preferenceSyncRules ?? []).map(
        ({ key, kind, sourceId }) => ({ key, kind, sourceId }),
      );
      assert.deepEqual(
        rules,
        build.packageName === reviewed.packageName
          ? [
              {
                key: 'server_preference',
                kind: PreferenceValueKind.TEXT,
                sourceId: undefined,
              },
              {
                key: 'SERVER_PREFERENCE',
                kind: PreferenceValueKind.TEXT,
                sourceId: undefined,
              },
            ]
          : [],
      );
    }
  };
  await assertSnapshotRules();
  await f.prepare(f.plan(descriptors, state, []), state);
  assert.equal(
    f.fetched.filter((entry) => entry.endsWith('/manifest.json')).length,
    2,
  );
  await assertSnapshotRules();
});

test('CI never bootstraps/retries failures and local retry remains explicit', (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor(),
    state = emptyState();
  assert.throws(
    () => makePlan(f.catalog([descriptor]), state, { ci: true, root: f.root }),
    /bootstrap/,
  );
  state.bootstrap.complete = true;
  assert.throws(
    () => makePlan(f.catalog([descriptor]), state, { ci: true, root: f.root }),
    /bootstrap/,
  );
  state.revision = 'a'.repeat(32);
  state.attempts[descriptor.inputFingerprint] = {
    descriptor,
    status: 'failed',
    attempts: 1,
  };
  assert.deepEqual(
    makePlan(f.catalog([descriptor]), state, { ci: true, root: f.root })
      .selected,
    [],
  );
  assert.equal(
    makePlan(f.catalog([descriptor]), state, {
      retryFailed: true,
      root: f.root,
    }).selected[0]?.inputFingerprint,
    descriptor.inputFingerprint,
  );
  assert.throws(
    () =>
      makePlan(f.catalog([descriptor]), state, {
        ci: true,
        retryFailed: true,
        root: f.root,
      }),
    /retry/,
  );
  assert.throws(
    () =>
      makePlan(f.catalog([descriptor]), state, {
        ci: true,
        limit: 25,
        root: f.root,
      }),
    /limit/,
  );
});
test('same-runtime failed update keeps last successful build', async (t) => {
  const f = new Fixture(t),
    previous = f.descriptor();
  f.output(previous);
  const first = await f.prepare(f.plan([previous]));
  const update = f.descriptor('b');
  f.output(update, true);
  const second = await f.prepare(f.plan([update], first), first);
  assert.equal(second.active[update.packageName], previous.inputFingerprint);
  const digest = first.attempts[previous.inputFingerprint]?.bundleSha256;
  assert.ok(digest);
  const buildId = publishedBuildId(previous, digest);
  assert.equal((await f.index()).builds[0]?.buildId, buildId);
  assert.deepEqual(f.fetched, [
    '/extensions/builds/' + buildId + '/manifest.json',
    '/extensions/artifacts/' + digest + '.gz',
  ]);
  assert.equal(second.attempts[update.inputFingerprint]?.status, 'failed');
});
test('discovery failure retains existing source, instead of retiring it', async (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor();
  f.output(descriptor);
  const first = await f.prepare(f.plan([descriptor]));
  const plan = f.plan([], first);
  plan.discoveryFailures = [
    {
      sourcePath: descriptor.sourcePath,
      status: 'discovery_failed',
      message: 'Unsupported DSL',
    },
  ];
  const second = await f.prepare(plan, first);
  const digest = first.attempts[descriptor.inputFingerprint]?.bundleSha256;
  assert.ok(digest);
  assert.equal(
    (await f.index()).builds[0]?.buildId,
    publishedBuildId(descriptor, digest),
  );
  assert.equal(second.attempts[descriptor.inputFingerprint]?.stale, true);
});
test('failed rebuild of unavailable success stays recorded without infinite automatic retry', async (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor();
  f.output(descriptor);
  const first = await f.prepare(f.plan([descriptor]));
  const previous = first.attempts[descriptor.inputFingerprint];
  assert.ok(previous);
  previous.available = false;
  f.output(descriptor, true);
  const second = await f.prepare(f.plan([descriptor], first), first),
    record = second.attempts[descriptor.inputFingerprint];
  assert.equal(record?.status, 'published');
  assert.ok(record?.rebuildFailure);
  assert.equal(record.available, false);
  assert.deepEqual(
    makePlan(f.catalog([descriptor]), second, { root: f.root }).selected,
    [],
  );
});
test('old ABI remains state-only and requires a rebuild before restoration', async (t) => {
  const f = new Fixture(t),
    previous = f.descriptor();
  f.output(previous);
  const first = await f.prepare(f.plan([previous]));
  const record = first.attempts[previous.inputFingerprint];
  assert.ok(record?.runtimeIdentity);
  record.runtimeIdentity.hostAbi = 'old';
  const update = f.descriptor('b');
  f.output(update, true);
  const second = await f.prepare(f.plan([update], first), first);
  assert.deepEqual((await f.index()).builds, []);
  assert.deepEqual(
    readdirSync(path.join(f.snapshot, 'extensions/artifacts')),
    [],
  );
  assert.equal(second.attempts[previous.inputFingerprint]?.available, false);
  assert.equal(
    makePlan(f.catalog([previous]), second, { root: f.root }).selected.length,
    1,
  );
});
test('CI rejects a runtime switch before replacing any deployed artifacts', async (t) => {
  const graphics = (byte: string) => {
    const sha256 = byte.repeat(64);
    return {
      path: '/runtime/materials/' + sha256,
      sha256,
      size: 100,
      contentType: 'text/javascript',
      logicalName: 'graphics-bridge.js',
    };
  };
  const identity = { ...materialIdentity, hostScripts: [graphics('a')] };
  const f = new Fixture(t, identity);
  const previous = f.descriptor();
  const unselected = f.descriptor('c', 'example.other');
  for (const descriptor of [previous, unselected]) f.output(descriptor);
  const deployed = await f.prepare(
    f.plan([previous, unselected]),
    emptyState(),
    { finalize: true },
  );
  const update = f.descriptor('b');
  const plan = makePlan(f.catalog([update, unselected]), deployed, {
    ci: true,
    limit: 1,
    root: f.root,
  });
  const selected = plan.selected[0];
  assert.ok(selected);
  f.output(selected);
  const files = ['extensions/index.json', 'extensions/build-state.json'];
  for (const { descriptor, bundleSha256 } of Object.values(deployed.attempts)) {
    assert.ok(bundleSha256);
    const buildId = publishedBuildId(descriptor, bundleSha256);
    files.push(
      `extensions/builds/${buildId}/manifest.json`,
      `extensions/artifacts/${bundleSha256}.gz`,
    );
  }
  const snapshot = () =>
    files.map((file) => readFileSync(path.join(f.snapshot, file)));
  const before = snapshot();
  for (const old of [
    { ...identity, hostAbi: 'old-abi' },
    { ...identity, protocolVersion: identity.protocolVersion + 1 },
    { ...identity, hostScripts: [graphics('b')] },
    undefined,
  ] satisfies (RuntimeIdentity | undefined)[]) {
    const parent = structuredClone(deployed);
    const active = parent.attempts[previous.inputFingerprint];
    assert.ok(active);
    if (old) active.runtimeIdentity = old;
    else delete active.runtimeIdentity;
    const unchanged = structuredClone(parent);
    const message = /CI runtime guard:.*complete local baseline/;
    await assert.rejects(
      assertCiRuntimeCompatible(parent, () => identity),
      message,
    );
    // Even if the one incompatible package is rebuilt in the batch, the
    // guard runs against the deployed snapshot before merging any results.
    await assert.rejects(f.prepare(plan, parent), message);
    assert.deepEqual(parent, unchanged);
    assert.deepEqual(snapshot(), before);
    assert.deepEqual(f.fetched, []);
  }
  for (const active of Object.values(deployed.attempts))
    active.available = false;
  await assertCiRuntimeCompatible(deployed, () => {
    assert.fail('No deployed builds require a runtime comparison');
  });
});
test('CI keeps unselected builds when host inputs change without changing the runtime', async (t) => {
  const f = new Fixture(t);
  const previous = [f.descriptor(), f.descriptor('b', 'example.other')];
  for (const descriptor of previous) f.output(descriptor);
  const deployed = await f.prepare(f.plan(previous), emptyState(), {
    finalize: true,
  });
  const updatedHost = 'f'.repeat(64);
  const updated = [
    { ...f.descriptor('c'), hostFingerprint: updatedHost },
    { ...f.descriptor('e', 'example.other'), hostFingerprint: updatedHost },
  ];
  const plan = makePlan(
    { ...f.catalog(updated), hostFingerprint: updatedHost },
    deployed,
    { ci: true, limit: 1, root: f.root },
  );
  assert.equal(plan.pendingCount, 2);
  assert.equal(plan.remainingCount, 1);
  const [selected] = plan.selected;
  assert.ok(selected);
  f.output(selected);
  await assertCiRuntimeCompatible(deployed, () => materialIdentity);
  const next = await f.prepare(plan, deployed);
  assert.equal(next.hostFingerprint, updatedHost);
  assert.equal(next.active[selected.packageName], selected.inputFingerprint);
  assert.equal(next.active['example.other'], deployed.active['example.other']);
  assert.equal((await f.index()).builds.length, 2);
});
test('success replaces previous build and prunes removed packages and bundles', async (t) => {
  const f = new Fixture(t),
    old = f.descriptor(),
    removed = f.descriptor('c', 'example.removed');
  f.output(old);
  f.output(removed);
  const first = await f.prepare(f.plan([old, removed]));
  const update = f.descriptor('b');
  f.output(update);
  const second = await f.prepare(f.plan([update], first), first);
  assert.equal(Object.keys(second.active).length, 1);
  assert.deepEqual(Object.keys(second.attempts), [update.inputFingerprint]);
  const digest = second.attempts[update.inputFingerprint]?.bundleSha256;
  assert.ok(digest);
  assert.deepEqual(readdirSync(path.join(f.snapshot, 'extensions/builds')), [
    publishedBuildId(update, digest),
  ]);
  assert.equal(
    readdirSync(path.join(f.snapshot, 'extensions/artifacts')).length,
    1,
  );
});
test('a rebuild of the same input with different bundle bytes retires the previous public ID and path', async (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor();
  const { directory } = f.output(descriptor);
  const first = await f.prepare(f.plan([descriptor]));
  const original = (await f.index()).builds[0];
  const originalSha = first.attempts[descriptor.inputFingerprint]?.bundleSha256;
  assert.ok(original && originalSha);
  assert.equal(original.buildId, descriptor.buildId + '-' + originalSha);
  assert.ok(existsSync(path.join(f.snapshot, original.manifestPath.slice(1))));

  rmSync(directory, { recursive: true });
  f.output(descriptor, false, '\nconst secondCompilerOutput = true;');
  const second = await f.prepare(f.plan([descriptor], first), first);
  const current = (await f.index()).builds[0];
  const currentSha = second.attempts[descriptor.inputFingerprint]?.bundleSha256;
  assert.ok(current && currentSha);
  assert.notEqual(currentSha, originalSha);
  assert.notEqual(current.buildId, original.buildId);
  assert.notEqual(current.manifestPath, original.manifestPath);
  assert.equal(current.buildId, descriptor.buildId + '-' + currentSha);
  assert.equal(
    second.active[descriptor.packageName],
    descriptor.inputFingerprint,
  );
  assert.deepEqual(Object.keys(second.attempts), [descriptor.inputFingerprint]);
  assert.notEqual(second.indexSha256, first.indexSha256);
  assert.equal(
    existsSync(path.join(f.snapshot, original.manifestPath.slice(1))),
    false,
  );
  assert.deepEqual(readdirSync(path.join(f.snapshot, 'extensions/artifacts')), [
    currentSha + '.gz',
  ]);
});

test('a legacy success without a digest must rebuild and is never pulled from the work ID path', async (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor();
  f.output(descriptor);
  const state = await f.prepare(f.plan([descriptor]));
  const record = state.attempts[descriptor.inputFingerprint];
  assert.ok(record);
  delete record.bundleSha256;
  const indexed = (await f.index()).builds[0];
  assert.ok(indexed);
  const manifest = await parseManifest(
    readFileSync(path.join(f.snapshot, indexed.manifestPath.slice(1))),
  );
  f.remoteOverrides.set(
    '/extensions/builds/' + descriptor.buildId + '/manifest.json',
    Buffer.from(JSON.stringify({ ...manifest, buildId: descriptor.buildId })),
  );
  assert.deepEqual(
    makePlan(f.catalog([descriptor]), state, { root: f.root }).selected.map(
      (build) => build.inputFingerprint,
    ),
    [descriptor.inputFingerprint],
  );
  state.bootstrap.complete = true;
  assert.throws(
    () => makePlan(f.catalog([descriptor]), state, { ci: true, root: f.root }),
    /bootstrap|baseline|unbound/i,
  );
  f.remoteOverrides.set(
    '/extensions/build-state.json',
    Buffer.from(JSON.stringify(state)),
  );
  await assert.rejects(
    f.pipeline.pullState('https://example.invalid', f.stateFile),
    /bootstrap|baseline|unbound/i,
  );
  assert.equal(existsSync(f.stateFile), false);

  f.fetched.length = 0;
  const candidate = await f.prepare(f.plan([descriptor], state, []), state);
  assert.deepEqual(f.fetched, []);
  assert.deepEqual((await f.index()).builds, []);
  assert.equal(candidate.active[descriptor.packageName], undefined);
  assert.equal(candidate.attempts[descriptor.inputFingerprint], undefined);
  assert.equal(candidate.bootstrap.complete, false);
  await f.pipeline.checkBase(f.snapshot, 'https://example.invalid');
});

test('retaining a build rejects a different digest at its registered path and leaves the deployed snapshot intact', async (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor();
  f.output(descriptor);
  const first = await f.prepare(f.plan([descriptor]));
  const build = (await f.index()).builds[0];
  const digest = first.attempts[descriptor.inputFingerprint]?.bundleSha256;
  assert.ok(build && digest);
  const files = [
    'extensions/build-state.json',
    'extensions/index.json',
    build.manifestPath.slice(1),
    'extensions/artifacts/' + digest + '.gz',
  ];
  const before = files.map((file) => readFileSync(path.join(f.snapshot, file)));
  const manifest = await parseManifest(
    readFileSync(path.join(f.snapshot, build.manifestPath.slice(1))),
  );
  const changed = encodeBundle(Buffer.from('const substitute = true;'));
  f.remoteOverrides.set(
    build.manifestPath,
    Buffer.from(JSON.stringify({ ...manifest, bundle: changed.reference })),
  );
  f.remoteOverrides.set(changed.reference.path, changed.encoded);

  await assert.rejects(
    f.prepare(f.plan([descriptor], first, []), first),
    /Static successful build identity mismatch/,
  );
  assert.deepEqual(f.fetched, [build.manifestPath]);
  assert.deepEqual(
    files.map((file) => readFileSync(path.join(f.snapshot, file))),
    before,
  );
});

test('catalog-only deletion requests a snapshot with zero pending builds', async (t) => {
  const f = new Fixture(t),
    old = f.descriptor(),
    removed = f.descriptor('b', 'example.removed');
  f.output(old);
  f.output(removed);
  const first = await f.prepare(f.plan([old, removed]));
  first.bootstrap.complete = true;
  const plan = makePlan(f.catalog([old]), first, { ci: true, root: f.root });
  assert.equal(plan.selected.length, 0);
  assert.equal(plan.snapshotNeeded, true);
  await f.prepare(plan, first);
  assert.deepEqual(
    (await f.index()).builds.map((item) => item.packageName),
    [old.packageName],
  );
});
test('missing/corrupt matrix results never advertise a broken new build', async (t) => {
  const f = new Fixture(t),
    old = f.descriptor();
  f.output(old);
  const first = await f.prepare(f.plan([old])),
    before = readFileSync(path.join(f.snapshot, 'extensions/build-state.json'));
  const update = f.descriptor('b');
  await assert.rejects(
    f.prepare(f.plan([update], first), first),
    /Missing matrix/,
  );
  const output = f.output(update),
    file = readdirSync(path.join(output.directory, 'artifacts'))[0];
  assert.ok(file);
  writeFileSync(path.join(output.directory, 'artifacts', file), 'bad');
  const recorded = await f.pipeline.recordResult(
    structuredClone(first),
    update,
    output.result,
    output.directory,
  );
  assert.equal(recorded.record.status, 'failed');
  assert.equal(recorded.content, undefined);
  assert.deepEqual(
    readFileSync(path.join(f.snapshot, 'extensions/build-state.json')),
    before,
  );
});
test('cancellation leaves prior snapshot untouched', async (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor();
  f.output(descriptor);
  await f.prepare(f.plan([descriptor]));
  const before = readFileSync(
    path.join(f.snapshot, 'extensions/build-state.json'),
  );
  const processes = new BuilderProcesses();
  processes.cancel();
  await assert.rejects(
    f.prepare(f.plan([descriptor]), emptyState(), { processes }),
    BuildCancelled,
  );
  assert.deepEqual(
    readFileSync(path.join(f.snapshot, 'extensions/build-state.json')),
    before,
  );
});
test('stale revision and unconfirmed deployment cannot commit checkpoint', async (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor();
  f.output(descriptor);
  const candidate = await f.prepare(f.plan([descriptor]));
  writeFileAtomic.sync(
    path.join(f.snapshot, 'extensions/build-state.json'),
    JSON.stringify({
      ...candidate,
      revision: 'b'.repeat(32),
    }) + '\n',
  );
  const offline = path.join(f.root, 'offline');
  cpSync(f.snapshot, offline, { recursive: true });
  writeFileAtomic.sync(
    path.join(offline, 'extensions/build-state.json'),
    JSON.stringify(candidate) + '\n',
  );
  await assert.rejects(
    f.pipeline.checkBase(offline, 'https://example.invalid'),
    /advanced/,
  );
  await assert.rejects(
    f.pipeline.commitSnapshot(f.stateFile, offline, 'https://example.invalid'),
    /not confirmed/,
  );
  assert.equal(existsSync(f.stateFile), false);
});
test('CI pull rejects missing baseline and mixed state/index without overwriting checkpoint', async (t) => {
  const f = new Fixture(t);
  writeFileAtomic.sync(f.stateFile, JSON.stringify(emptyState()) + '\n');
  const before = readFileSync(f.stateFile);
  mkdirSync(path.join(f.snapshot, 'extensions'), { recursive: true });
  writeFileAtomic.sync(
    path.join(f.snapshot, 'extensions/build-state.json'),
    JSON.stringify(emptyState()) + '\n',
  );
  writeFileSync(path.join(f.snapshot, 'extensions/index.json'), '{}');
  await assert.rejects(
    f.pipeline.pullState('https://example.invalid', f.stateFile),
    /different snapshots/,
  );
  assert.deepEqual(readFileSync(f.stateFile), before);
  const nullRevision = {
    ...emptyState(),
    bootstrap: { complete: true },
    indexSha256: createHash('sha256').update(Buffer.from('{}')).digest('hex'),
  };
  writeFileAtomic.sync(
    path.join(f.snapshot, 'extensions/build-state.json'),
    JSON.stringify(nullRevision) + '\n',
  );
  await assert.rejects(
    f.pipeline.pullState('https://example.invalid', f.stateFile),
    /bootstrap/,
  );
  assert.deepEqual(readFileSync(f.stateFile), before);
  rmSync(path.join(f.snapshot, 'extensions/build-state.json'));
  await assert.rejects(
    f.pipeline.pullState('https://example.invalid', f.stateFile),
    /unavailable/,
  );
});
test('explicit initialization only handles a known old HTML SPA, never arbitrary invalid data', async (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor();
  f.output(descriptor);
  await f.prepare(f.plan([descriptor]));
  let body = '<!doctype html><html>old shell</html>';
  const pipeline = new ExtensionPipeline({
    fetchBytes: async () => Buffer.from(body),
  });
  await assert.rejects(
    pipeline.checkBase(f.snapshot, 'https://example.invalid'),
    /not JSON/,
  );
  await pipeline.checkBase(f.snapshot, 'https://example.invalid', true);
  process.env.CI = 'true';
  await assert.rejects(
    pipeline.checkBase(f.snapshot, 'https://example.invalid', true),
    /local-only/,
  );
  process.env.CI = 'false';
  body = 'not HTML or JSON';
  await assert.rejects(
    pipeline.checkBase(f.snapshot, 'https://example.invalid', true),
    /arbitrary/,
  );
});
test('process-owned verification receipt is reused without second integrity pass', async (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor(),
    output = f.output(descriptor),
    verified = await f.pipeline.verifyOutput(output.directory, descriptor);
  const receipt = new VerifiedBuild(
    output.result,
    verified.manifest,
    output.directory,
    verified.validation,
  );
  f.pipeline.verifyOutput = async () => {
    throw new Error('duplicate integrity hash');
  };
  const candidate = await f.prepare(f.plan([descriptor]), emptyState(), {
    verifiedResults: new Map([
      [
        descriptor.inputFingerprint,
        { directory: output.directory, outcome: receipt },
      ],
    ]),
  });
  assert.equal(
    candidate.attempts[descriptor.inputFingerprint]?.status,
    'published',
  );
  assert.deepEqual(receipt.payload(), verified.encoded);
});
test('verification receipts reject changed bytes before local assembly', async (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor(),
    output = f.output(descriptor),
    verified = await f.pipeline.verifyOutput(output.directory, descriptor),
    receipt = new VerifiedBuild(
      output.result,
      verified.manifest,
      output.directory,
      verified.validation,
    );
  writeFileSync(
    path.join(
      output.directory,
      'artifacts',
      verified.manifest.bundle.sha256 + '.gz',
    ),
    Buffer.alloc(verified.encoded.length),
  );
  assert.throws(() => receipt.payload(), /changed/);
});
test('finalization requires every input and is forbidden in CI', (t) => {
  const f = new Fixture(t),
    source = f.catalog([f.descriptor()]);
  assert.throws(
    () => finalizeBaseline(emptyState(), source, true, false),
    /unattempted/,
  );
  assert.throws(() => finalizeBaseline(emptyState(), source, true, true), /CI/);
});

async function baselineFixture(t: TestContext) {
  const f = new Fixture(t);
  const retained = f.descriptor('a', 'example.keep');
  const replaced = f.descriptor('b', 'eu.kanade.tachiyomi.extension.zh.komiic');
  const failed = f.descriptor('c', 'example.failed');
  const frozen = [retained, replaced, failed];
  const newer = frozen.map((descriptor, i) => ({
    ...descriptor,
    hostFingerprint: 'f'.repeat(64),
    inputFingerprint: ['1', '2', '3'][i]!.repeat(64),
    buildId: `${descriptor.buildId}-current`,
  }));
  const selected = newer[1]!;
  const parent: ExtensionState = { ...emptyState(), revision: '9'.repeat(32) };
  const index = Buffer.from(
    '{"schemaVersion":1,"repoId":"keiyoushi","builds":[]}',
  );
  parent.indexSha256 = createHash('sha256').update(index).digest('hex');
  f.remoteOverrides.set(
    '/extensions/build-state.json',
    Buffer.from(JSON.stringify(parent)),
  );
  f.remoteOverrides.set('/extensions/index.json', index);

  function pinnedPlan(entries: ExtensionDescriptor[], revision: string) {
    const pins = [
      {
        path: 'vendor/teavm',
        gitlink: 'a'.repeat(40),
        checkout: 'a'.repeat(40),
      },
    ];
    const pinned = entries.map((entry) => ({
      ...entry,
      hostRepositoryCommit: revision,
      hostSubmodules: pins,
    }));
    return {
      ...f.plan(pinned, parent),
      hostFingerprint: pinned[0]!.hostFingerprint,
      repositoryCommit: revision,
      catalogFingerprint: createHash('sha256')
        .update(
          JSON.stringify({
            entries: pinned.map((entry) => entry.inputFingerprint),
            failures: [],
          }),
        )
        .digest('hex'),
    };
  }

  const frozenPlan = pinnedPlan(frozen, 'a'.repeat(40));
  const supplementPlan = pinnedPlan(newer, 'b'.repeat(40));
  const supplementResults = path.join(f.root, 'supplement-results');
  mkdirSync(supplementResults);
  const { directory: retainedDirectory } = f.output(frozenPlan.entries[0]!);
  const { directory: replacedDirectory } = f.output(frozenPlan.entries[1]!);
  f.output(frozenPlan.entries[2]!, true);
  const oldManifest = path.join(replacedDirectory, 'manifest.json');
  const old = await parseManifest(readFileSync(oldManifest));
  writeFileSync(
    oldManifest,
    JSON.stringify({ ...old, preferenceSyncRules: [] }),
  );
  const { directory: supplementDirectory } = f.output(
    supplementPlan.entries[1]!,
    false,
    '/* current host build */',
    supplementResults,
  );

  return {
    f,
    retained,
    selected,
    replaced,
    failed,
    parent,
    index,
    retainedDirectory,
    replacedDirectory,
    supplementDirectory,
    options: {
      frozenPlan,
      frozenResults: f.results,
      frozenRuntime: materialIdentity,
      supplementPlan,
      supplementResults,
      supplementPackages: [selected.packageName],
      parentState: parent,
      assetsDirectory: f.snapshot,
    },
  };
}

test('supplemented baseline replaces only requested inputs and finalizes against the deployed parent', async (t) => {
  const { f, options, retained, selected, replaced, failed, parent } =
    await baselineFixture(t);
  const next = await f.pipeline.prepareBaseline(options);
  assert.equal(next.parentRevision, parent.revision);
  assert.equal(next.bootstrap.complete, true);
  assert.equal(next.summary?.pending, 0);
  assert.equal(next.active[retained.packageName], retained.inputFingerprint);
  assert.equal(next.active[selected.packageName], selected.inputFingerprint);
  assert.equal(next.attempts[replaced.inputFingerprint], undefined);
  assert.equal(next.attempts[failed.inputFingerprint]?.status, 'failed');
  assert.equal(
    next.attempts[failed.inputFingerprint]?.failure?.code,
    'source_failed',
  );
  assert.deepEqual(
    Object.keys(next.attempts).sort(),
    [
      retained.inputFingerprint,
      selected.inputFingerprint,
      failed.inputFingerprint,
    ].sort(),
  );
  const index = await f.index();
  const build = index.builds.find(
    (entry) => entry.packageName === selected.packageName,
  );
  assert.ok(build);
  const manifest = await parseManifest(
    readFileSync(path.join(f.snapshot, build.manifestPath.slice(1))),
  );
  assert.deepEqual(manifest.preferenceSyncRules, [
    { key: 'preferred_mirror', kind: PreferenceValueKind.TEXT },
    { key: 'CHAPTER_FILTER', kind: PreferenceValueKind.TEXT },
  ]);
  assert.equal(existsSync(f.stateFile), false);
  assert.deepEqual(f.fetched.sort(), [
    '/extensions/build-state.json',
    '/extensions/index.json',
  ]);
});

test('supplemented baseline aborts on a mismatched live index or damaged artifacts without replacing a prior candidate', async (t) => {
  const {
    f,
    options,
    index,
    retainedDirectory,
    replacedDirectory,
    supplementDirectory,
  } = await baselineFixture(t);
  const previous = path.join(f.snapshot, 'previous-candidate');
  mkdirSync(f.snapshot);
  writeFileSync(previous, 'keep');
  f.remoteOverrides.set('/extensions/index.json', Buffer.from('{}'));
  await assert.rejects(f.pipeline.prepareBaseline(options), /index|snapshot/i);
  f.remoteOverrides.set('/extensions/index.json', index);
  await assert.rejects(
    f.pipeline.prepareBaseline({
      ...options,
      frozenRuntime: { ...materialIdentity, hostAbi: 'different-runtime' },
    }),
    /runtime materials/i,
  );

  const replacedResult = path.join(replacedDirectory, 'pipeline-result.json');
  const frozenOriginal = readFileSync(replacedResult);
  rmSync(replacedResult);
  await assert.rejects(f.pipeline.prepareBaseline(options), /missing frozen/i);
  writeFileSync(replacedResult, frozenOriginal);

  const replacementResult = path.join(
    supplementDirectory,
    'pipeline-result.json',
  );
  const original = readFileSync(replacementResult);
  rmSync(replacementResult);
  await assert.rejects(f.pipeline.prepareBaseline(options), /result|missing/i);
  writeFileSync(replacementResult, original);

  const artifactDirectory = path.join(retainedDirectory, 'artifacts');
  const [artifact] = readdirSync(artifactDirectory);
  assert.ok(artifact);
  writeFileSync(path.join(artifactDirectory, artifact), 'corrupt');
  await assert.rejects(
    f.pipeline.prepareBaseline(options),
    /artifact|bundle|integrity|build/i,
  );
  assert.deepEqual(readdirSync(f.snapshot), ['previous-candidate']);
  assert.equal(readFileSync(previous, 'utf8'), 'keep');
});

test('baseline plans reject duplicate replacements and a changed upstream source closure', async (t) => {
  const { options, selected } = await baselineFixture(t);
  assert.throws(
    () =>
      makeBaselinePlan(options.frozenPlan, options.supplementPlan, [
        selected.packageName,
        selected.packageName,
      ]),
    /duplicate|unique/i,
  );
  const changed = structuredClone(options.supplementPlan);
  changed.entries[1]!.sourceFingerprint = '8'.repeat(64);
  changed.selected[1]!.sourceFingerprint = '8'.repeat(64);
  assert.throws(
    () => makeBaselinePlan(options.frozenPlan, changed, [selected.packageName]),
    /source|upstream/i,
  );
});

test('initial baseline refuses to drop a deployed package still in the catalog', async (t) => {
  const { f, options, failed, parent } = await baselineFixture(t);
  const previous = f.descriptor('d', failed.packageName);
  const index = Buffer.from(
    JSON.stringify({
      schemaVersion: 1,
      builds: [
        { packageName: previous.packageName, buildId: previous.buildId },
      ],
    }),
  );
  const deployed: ExtensionState = {
    ...parent,
    active: { [previous.packageName]: previous.inputFingerprint },
    attempts: {
      [previous.inputFingerprint]: {
        descriptor: previous,
        status: 'published',
        attempts: 1,
        available: true,
      },
    },
    indexSha256: createHash('sha256').update(index).digest('hex'),
  };
  f.remoteOverrides.set(
    '/extensions/build-state.json',
    Buffer.from(JSON.stringify(deployed)),
  );
  f.remoteOverrides.set('/extensions/index.json', index);

  await assert.rejects(
    f.pipeline.prepareBaseline({ ...options, parentState: deployed }),
    /would drop a deployed package/,
  );
  assert.equal(existsSync(f.snapshot), false);
});
test('state parser rejects inconsistent successful pointers and descriptor identities', (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor(),
    state = emptyState();
  state.active[descriptor.packageName] = descriptor.inputFingerprint;
  assert.throws(() => validateState(state));
  state.active = {};
  state.attempts['b'.repeat(64)] = {
    descriptor,
    status: 'failed',
    attempts: 1,
  };
  assert.throws(() => validateState(state));
});
test('cleanup needs persisted success and preserves outputs, other work and shared symlink targets', (t) => {
  const f = new Fixture(t),
    descriptor = f.descriptor(),
    output = f.output(descriptor),
    local = path.join(f.root, 'runtime/teavm/.local'),
    shared = path.join(local, 'build-cache/m2');
  mkdirSync(shared, { recursive: true });
  writeFileSync(path.join(shared, 'keep'), 'shared');
  for (const name of ['extension-work', 'extension-cache', 'gradle-launcher']) {
    mkdirSync(path.join(local, name, descriptor.buildId), { recursive: true });
    mkdirSync(path.join(local, name, 'other'), { recursive: true });
    writeFileSync(path.join(local, name, 'other/keep'), 'other');
  }
  symlinkSync(
    shared,
    path.join(local, 'extension-cache', descriptor.buildId, 'm2'),
    'dir',
  );
  writeFileAtomic.sync(
    path.join(output.directory, 'pipeline-result.json'),
    JSON.stringify({
      ...output.result,
      status: 'failed',
    }) + '\n',
  );
  assert.throws(
    () => cleanupBuiltWork(output.directory, descriptor, f.root),
    /checkpoint/,
  );
  writeFileAtomic.sync(
    path.join(output.directory, 'pipeline-result.json'),
    JSON.stringify(output.result) + '\n',
  );
  assert.equal(
    cleanupBuiltWork(output.directory, descriptor, f.root).length,
    3,
  );
  assert.equal(existsSync(path.join(shared, 'keep')), true);
  assert.equal(existsSync(path.join(output.directory, 'manifest.json')), true);
  for (const name of ['extension-work', 'extension-cache', 'gradle-launcher']) {
    assert.equal(existsSync(path.join(local, name, descriptor.buildId)), false);
    assert.equal(existsSync(path.join(local, name, 'other/keep')), true);
  }
});
test('unsafe IDs and linked cleanup parents cannot delete unowned directories', (t) => {
  const f = new Fixture(t);
  for (const id of ['../escape', '/absolute', '', '.'])
    assert.throws(() => removeBuildWork(id, f.root), /Unsafe/);
  const descriptor = f.descriptor(),
    output = f.output(descriptor),
    local = path.join(f.root, 'runtime/teavm/.local'),
    target = path.join(f.root, 'unowned');
  mkdirSync(path.join(target, descriptor.buildId), { recursive: true });
  writeFileSync(path.join(target, descriptor.buildId, 'keep'), 'unowned');
  mkdirSync(local, { recursive: true });
  symlinkSync(target, path.join(local, 'extension-work'), 'dir');
  assert.deepEqual(cleanupBuiltWork(output.directory, descriptor, f.root), []);
  assert.equal(existsSync(path.join(target, descriptor.buildId, 'keep')), true);
});
