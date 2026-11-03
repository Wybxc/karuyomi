import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import {
  mkdtemp,
  mkdir,
  readFile,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import type { TestContext } from 'node:test';
import type { Artifact } from '../../packages/contracts/src/index.ts';
import { isRecord } from './types.ts';
import type { ValidationFailure } from './types.ts';
import { collectMaterials } from '../../packages/runtime-host/materials.ts';
import {
  completeBrowserValidation,
  digest,
  repositoryRoot,
  verifyIntegrity,
} from './verify-manifest.ts';

const protocolInput: unknown = JSON.parse(
  await readFile(
    path.join(repositoryRoot, 'packages/contracts/protocol.json'),
    'utf8',
  ),
);

assert(isRecord(protocolInput));
assert(typeof protocolInput.protocolVersion === 'number');
assert(typeof protocolInput.hostAbi === 'string');
assert(typeof protocolInput.runtimeBaseline === 'string');
const protocol = {
  protocolVersion: protocolInput.protocolVersion,
  hostAbi: protocolInput.hostAbi,
  runtimeBaseline: protocolInput.runtimeBaseline,
};
interface FixtureManifest {
  protocolVersion: number;
  hostAbi: string;
  runtimeBaseline: string;
  buildId: string;
  packageName: string;
  repoId: string;
  version: string;
  bridgeVersion: number;
  storageSchema: string;
  sourceIds: string[];
  bundle: Artifact;
  hostScripts: Artifact[];
  resources: (Artifact & { logicalName: string })[];
}
async function fixture(
  t: TestContext,
  edit: (manifest: FixtureManifest) => void = () => {},
) {
  const directory = await mkdtemp(
    path.join(tmpdir(), 'karuyomi-validator-test-'),
  );
  t.after(() => rm(directory, { recursive: true, force: true }));
  await mkdir(path.join(directory, 'artifacts'));
  // Integrity-only tests deliberately use an unexecutable bundle. No fixture is
  // sent to the browser gate or written as a verified release attestation.
  const bytes = Buffer.from(
    'throw new Error("Integrity validation must not execute this bundle");',
  );
  const sha256 = digest(bytes);
  const manifest: FixtureManifest = {
    protocolVersion: protocol.protocolVersion,
    hostAbi: protocol.hostAbi,
    runtimeBaseline: protocol.runtimeBaseline,
    buildId: 'validator-unit-test',
    packageName: 'example.test',
    repoId: 'test',
    version: '1',
    bridgeVersion: 2,
    storageSchema: 'test-v1',
    sourceIds: ['1234567890123456789'],
    bundle: {
      path: '/api/extensions/artifacts/' + sha256,
      sha256,
      size: bytes.length,
      contentType: 'application/javascript',
    },
    hostScripts: [],
    resources: [],
  };
  edit(manifest);
  await writeFile(
    path.join(directory, 'manifest.json'),
    JSON.stringify(manifest),
  );
  await writeFile(path.join(directory, 'artifacts', sha256), bytes);
  return {
    directory,
    manifest,
    bytes,
    artifact: path.join(directory, 'artifacts', sha256),
  };
}

async function command(
  args: string[],
): Promise<{ code: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn(
      process.execPath,
      [path.join(repositoryRoot, 'tools/extensions/verify-build.ts'), ...args],
      {
        cwd: repositoryRoot,
        stdio: ['ignore', 'pipe', 'pipe'],
      },
    );
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (value) => {
      stdout += value;
    });
    child.stderr.on('data', (value) => {
      stderr += value;
    });
    child.on('error', reject);
    child.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}

test('integrity hashes actual bytes without executing JS or claiming runtime readiness', async (t) => {
  const { directory, manifest } = await fixture(t);
  const { report } = await verifyIntegrity(directory);
  assert.equal(report.buildId, manifest.buildId);
  assert.equal(
    report.manifestSha256,
    digest(await readFile(path.join(directory, 'manifest.json'))),
  );
  assert.equal(report.valid, false);
  assert.equal(report.runtimeReady, false);
  assert.equal(report.onlineCompatibility, 'not_tested');
  assert.deepEqual(report.stages, {
    artifactIntegrity: 'passed',
    workerInit: 'not_run',
    browserLoad: 'not_run',
  });
  assert.equal(report.failure?.code, 'browser_not_run');
});

test('same-length artifact corruption fails its SHA-256 gate', async (t) => {
  const { directory, artifact, bytes } = await fixture(t);
  bytes[0] = bytes[0]! ^ 1;
  await writeFile(artifact, bytes);
  const { report } = await verifyIntegrity(directory);
  assert.equal(report.stages.artifactIntegrity, 'failed');
  assert.equal(report.failure?.code, 'hash_mismatch');
});

test('shared materials use verified host bytes without per-build copies', async (t) => {
  const { catalog, data } = await collectMaterials();
  const { directory } = await fixture(t, (manifest: FixtureManifest) => {
    manifest.hostScripts = catalog.hostScripts;
    manifest.resources = catalog.resources;
  });
  const { report, payloads } = await verifyIntegrity(directory);
  assert.equal(report.stages.artifactIntegrity, 'passed');
  assert.equal(report.privateArtifactCount, 1);
  assert.equal(report.sharedMaterialCount, 6);
  for (const material of [...catalog.hostScripts, ...catalog.resources]) {
    assert.deepEqual(
      payloads?.get(material.path)?.bytes,
      data.get(material.sha256)?.bytes,
    );
  }
});

test('shared materials cannot substitute hash, metadata, role or logical name', async (t) => {
  const { catalog } = await collectMaterials();
  for (const edit of [
    (manifest: FixtureManifest) => {
      manifest.hostScripts[0]!.size += 1;
    },
    (manifest: FixtureManifest) => {
      manifest.hostScripts[0]!.contentType = 'text/javascript';
    },
    (manifest: FixtureManifest) => {
      manifest.hostScripts[0]!.sha256 = 'b'.repeat(64);
      manifest.hostScripts[0]!.path = '/runtime/materials/' + 'b'.repeat(64);
    },
    (manifest: FixtureManifest) => {
      manifest.hostScripts = catalog.resources;
    },
    (manifest: FixtureManifest) => {
      manifest.resources[0]!.logicalName = 'other.wasm';
    },
  ]) {
    const { directory } = await fixture(t, (manifest: FixtureManifest) => {
      manifest.hostScripts = structuredClone(catalog.hostScripts);
      manifest.resources = structuredClone(catalog.resources);
      edit(manifest);
    });
    assert.equal(
      (await verifyIntegrity(directory)).report.stages.artifactIntegrity,
      'failed',
    );
  }
});

test('private runtime bridge copies are rejected', async (t) => {
  const { catalog } = await collectMaterials();
  const { directory } = await fixture(t, (manifest) => {
    const material = catalog.hostScripts[0];
    assert(material);
    manifest.hostScripts = [
      { ...material, path: '/api/extensions/artifacts/' + material.sha256 },
    ];
  });
  assert.equal(
    (await verifyIntegrity(directory)).report.failure?.code,
    'invalid_manifest',
  );
});

test('artifact length must exactly match the bounded manifest', async (t) => {
  const { directory, artifact } = await fixture(t);
  await writeFile(artifact, 'smaller');
  assert.equal(
    (await verifyIntegrity(directory)).report.failure?.code,
    'size_mismatch',
  );
});

test('protocol/ABI drift, private-path mismatch and duplicate Source IDs fail', async (t) => {
  for (const edit of [
    (manifest: FixtureManifest) => {
      manifest.protocolVersion += 1;
    },
    (manifest: FixtureManifest) => {
      manifest.hostAbi = 'future-host';
    },
    (manifest: FixtureManifest) => {
      manifest.bundle.path = 'https://example.com/app.js';
    },
    (manifest: FixtureManifest) => {
      manifest.sourceIds.push(manifest.sourceIds[0]!);
    },
  ]) {
    const { directory } = await fixture(t, edit);
    assert.equal(
      (await verifyIntegrity(directory)).report.failure?.code,
      'invalid_manifest',
    );
  }
});

test('runtime scripts require an explicit JavaScript MIME type', async (t) => {
  const { directory } = await fixture(t, (manifest: FixtureManifest) => {
    manifest.bundle.contentType = 'text/html';
  });
  assert.equal(
    (await verifyIntegrity(directory)).report.failure?.code,
    'invalid_script_mime',
  );
});

test('symbolic manifest and artifact files are never followed', async (t) => {
  for (const target of ['manifest', 'artifact']) {
    const value = await fixture(t);
    const file =
      target === 'manifest'
        ? path.join(value.directory, 'manifest.json')
        : value.artifact;
    const other = path.join(value.directory, target + '-original');
    await writeFile(other, await readFile(file));
    await rm(file);
    await symlink(other, file);
    assert.equal(
      (await verifyIntegrity(value.directory)).report.failure?.code,
      'invalid_file',
    );
  }
});

test('symbolic artifact directory is rejected even when every file hashes correctly', async (t) => {
  const { directory, manifest, bytes } = await fixture(t);
  const other = await mkdtemp(
    path.join(tmpdir(), 'karuyomi-validator-artifacts-'),
  );
  t.after(() => rm(other, { recursive: true, force: true }));
  await writeFile(path.join(other, manifest.bundle.sha256), bytes);
  await rm(path.join(directory, 'artifacts'), { recursive: true });
  await symlink(other, path.join(directory, 'artifacts'));
  assert.equal(
    (await verifyIntegrity(directory)).report.failure?.code,
    'invalid_directory',
  );
});

test('default CLI writes an atomic unverified report and exits 2', async (t) => {
  const { directory } = await fixture(t);
  const reportFile = path.join(directory, 'validation.json');
  const result = await command([
    '--directory',
    directory,
    '--report',
    reportFile,
  ]);
  assert.equal(result.code, 2, result.stderr);
  const report = JSON.parse(await readFile(reportFile, 'utf8'));
  assert.equal(report.runtimeReady, false);
  assert.equal(report.stages.workerInit, 'not_run');
  assert.equal(report.failure?.code, 'browser_not_run');
});

test('CLI cannot replace manifest/artifact inputs with its report', async (t) => {
  const { directory, artifact } = await fixture(t);
  for (const reportFile of [path.join(directory, 'manifest.json'), artifact]) {
    const before = await readFile(reportFile);
    const result = await command([
      '--directory',
      directory,
      '--report',
      reportFile,
    ]);
    assert.equal(result.code, 64);
    assert.deepEqual(await readFile(reportFile), before);
  }
});

test('browser result reducer rejects missing browser, identity and Source evidence', async (t) => {
  const { directory } = await fixture(t);
  const { report: base } = await verifyIntegrity(directory);
  // Synthetic unit data exercises rejection paths only. Actual passed reports
  // require the separate real browser runner and product Worker initialization.
  const value = {
    userAgent: 'Chrome/156.0',
    indexedDb: true,
    buildId: base.buildId,
    manifestSha256: base.manifestSha256,
    hello: { ...protocol, sourceReady: false },
    session: {
      protocolVersion: base.protocolVersion,
      buildId: base.buildId,
      generation: 'g',
      workerInstanceId: 'w',
      sources: (base.sourceIds ?? []).map((id) => ({
        id,
        name: 'Test',
        lang: 'en',
      })),
    },
  };
  type BrowserFixture = typeof value & { failure?: ValidationFailure };
  for (const edit of [
    (copy: BrowserFixture) => {
      copy.indexedDb = false;
    },
    (copy: BrowserFixture) => {
      copy.userAgent = 'Node';
    },
    (copy: BrowserFixture) => {
      copy.buildId = 'different-build';
    },
    (copy: BrowserFixture) => {
      copy.manifestSha256 = '0'.repeat(64);
    },
    (copy: BrowserFixture) => {
      copy.hello.sourceReady = true;
    },
    (copy: BrowserFixture) => {
      copy.hello.hostAbi = 'wrong';
    },
    (copy: BrowserFixture) => {
      copy.session.sources = [];
    },
    (copy: BrowserFixture) => {
      copy.session.generation = '';
    },
    (copy: BrowserFixture) => {
      copy.failure = { code: 'source_error', message: 'Initialization failed' };
    },
  ]) {
    const copy: BrowserFixture = structuredClone(value);
    edit(copy);
    const result = completeBrowserValidation(base, copy, 0);
    assert.equal(result.valid, false);
    assert.equal(result.runtimeReady, false);
    assert.ok(result.failure);
  }
  const network = completeBrowserValidation(base, value, 1);
  assert.equal(network.valid, false);
  assert.equal(network.failure?.code, 'network_required');
  assert.equal(completeBrowserValidation(base, null, 0).valid, false);
});
