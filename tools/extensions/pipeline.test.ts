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
import { encodeBundle, StaticHttpError } from './assets.ts';
import {
  BuilderProcesses,
  BuildCancelled,
  ExtensionPipeline,
  VerifiedBuild,
  cleanupBuiltWork,
  emptyState,
  finalizeBaseline,
  loadState,
  MAX_STATE_BYTES,
  makePlan,
  persistStateCheckpoint,
  removeBuildWork,
  runtimeIdentity,
  validateState,
} from './pipeline.ts';
import {
  runtimeIdentitySchema,
  type Catalog,
  type ExtensionDescriptor,
  type ExtensionPlan,
  type ExtensionState,
  type PipelineResult,
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
  constructor(t: TestContext) {
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
    this.pipeline = new ExtensionPipeline({
      root: this.root,
      materials: async () => materialIdentity,
      fetchBytes: async (_origin, relative) => {
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
  ): { directory: string; result: PipelineResult } {
    const directory = path.join(this.results, descriptor.inputFingerprint);
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
          'const packageName = ' + JSON.stringify(descriptor.packageName) + ';',
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
          ...materialIdentity,
          buildId: descriptor.buildId,
          repoId: 'keiyoushi',
          packageName: descriptor.packageName,
          version: descriptor.versionName,
          sourceIds: ['1'],
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
  assert.equal(
    (await f.index()).builds[0]?.manifestPath,
    '/extensions/builds/' + descriptor.buildId + '/manifest.json',
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
  assert.equal((await f.index()).builds[0]?.buildId, previous.buildId);
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
  assert.equal((await f.index()).builds[0]?.buildId, descriptor.buildId);
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
  assert.deepEqual(readdirSync(path.join(f.snapshot, 'extensions/builds')), [
    update.buildId,
  ]);
  assert.equal(
    readdirSync(path.join(f.snapshot, 'extensions/artifacts')).length,
    1,
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
