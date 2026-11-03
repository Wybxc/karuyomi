import { createHash } from 'node:crypto';
import { lstat, open } from 'node:fs/promises';
import { constants } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { gunzipSync } from 'node:zlib';
import type {
  Artifact,
  BuildManifest,
  ExtensionIndex,
} from '../../packages/contracts/src/index.ts';
import { isRecord, isSourceInfo } from './types.ts';
import type {
  IntegrityResult,
  ValidationReport,
  VerifiedPayload,
} from './types.ts';
import { collectMaterials } from '../../packages/runtime-host/materials.ts';

export const repositoryRoot = fileURLToPath(new URL('../../', import.meta.url));
const runtimeRequire = createRequire(
  path.join(repositoryRoot, 'packages/runtime-host/package.json'),
);
type Contracts = typeof import('../../packages/contracts/src/index.ts');
let schemaPromise: Promise<Contracts> | undefined;

export const digest = (bytes: Uint8Array) =>
  createHash('sha256').update(bytes).digest('hex');

export class VerificationFailure extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

async function schema() {
  // Bundle the actual shared Zod contract: the release tool must not maintain a
  // second, drifting implementation of the runtime manifest/ABI contract.
  schemaPromise ??= (async () => {
    const { build }: typeof import('esbuild') = await import(
      runtimeRequire.resolve('esbuild')
    );
    const compiled = await build({
      entryPoints: [
        path.join(repositoryRoot, 'packages/contracts/src/index.ts'),
      ],
      bundle: true,
      write: false,
      platform: 'node',
      format: 'esm',
      target: 'node24',
    });
    const output = compiled.outputFiles[0];
    if (!output) throw new Error('Missing compiled contract');
    const contracts: typeof import('../../packages/contracts/src/index.ts') =
      await import(
        'data:text/javascript;base64,' +
          Buffer.from(output.text).toString('base64')
      );
    return contracts;
  })();
  return schemaPromise;
}

export async function parseManifest(bytes: Uint8Array): Promise<BuildManifest> {
  const parsed: unknown = JSON.parse(
    new TextDecoder('utf-8', { fatal: true }).decode(bytes),
  );
  return (await schema()).buildManifestSchema.parse(parsed);
}

export async function parseExtensionIndex(
  bytes: Uint8Array,
): Promise<ExtensionIndex> {
  if (bytes.byteLength > 2 * 1024 * 1024)
    throw new VerificationFailure(
      'invalid_index',
      'Extension index exceeds its byte budget',
    );
  const parsed: unknown = JSON.parse(
    new TextDecoder('utf-8', { fatal: true }).decode(bytes),
  );
  return (await schema()).extensionIndexSchema.parse(parsed);
}

async function regularDirectory(directory: string) {
  const info = await lstat(directory);
  if (!info.isDirectory() || info.isSymbolicLink()) {
    throw new VerificationFailure(
      'invalid_directory',
      'Build input directories must not be symbolic links',
    );
  }
}

async function regularFile(file: string, limit: number, expectedSize?: number) {
  const before = await lstat(file);
  if (!before.isFile() || before.isSymbolicLink()) {
    throw new VerificationFailure(
      'invalid_file',
      'Validation inputs must be regular files, without symbolic links',
    );
  }
  const handle = await open(
    file,
    constants.O_RDONLY | (constants.O_NOFOLLOW ?? 0),
  );
  try {
    const info = await handle.stat();
    if (!info.isFile() || info.ino !== before.ino || info.dev !== before.dev) {
      throw new VerificationFailure(
        'input_changed',
        'Input changed while being validated',
      );
    }
    if (
      info.size > limit ||
      (expectedSize !== undefined && info.size !== expectedSize)
    ) {
      throw new VerificationFailure(
        'size_mismatch',
        'Input size does not match its bounded manifest declaration',
      );
    }
    const bytes = await handle.readFile();
    const after = await handle.stat();
    if (
      bytes.length !== info.size ||
      after.size !== info.size ||
      after.mtimeMs !== info.mtimeMs
    ) {
      throw new VerificationFailure(
        'input_changed',
        'Input changed while being validated',
      );
    }
    return bytes;
  } finally {
    await handle.close();
  }
}

export function failure(error: unknown) {
  return {
    code:
      error instanceof VerificationFailure ? error.code : 'validation_failed',
    message:
      error instanceof VerificationFailure
        ? error.message
        : 'Unable to read or validate build inputs',
  };
}

export async function verifyIntegrity(
  directory: string,
): Promise<IntegrityResult> {
  const report: ValidationReport = {
    schemaVersion: 1,
    kind: 'karuyomi-extension-build-validation',
    valid: false,
    runtimeReady: false,
    onlineCompatibility: 'not_tested',
    stages: {
      artifactIntegrity: 'not_run',
      workerInit: 'not_run',
      browserLoad: 'not_run',
    },
    capabilities: [],
  };
  try {
    await regularDirectory(directory);
    await regularDirectory(path.join(directory, 'artifacts'));
    const manifestBytes = await regularFile(
      path.join(directory, 'manifest.json'),
      64 * 1024,
    );
    let parsed: unknown;
    try {
      parsed = JSON.parse(
        new TextDecoder('utf-8', { fatal: true }).decode(manifestBytes),
      );
    } catch {
      throw new VerificationFailure(
        'invalid_manifest',
        'Manifest is not valid bounded UTF-8 JSON',
      );
    }
    const result = (await schema()).buildManifestSchema.safeParse(parsed);
    if (!result.success)
      throw new VerificationFailure(
        'invalid_manifest',
        'Manifest shape, ABI, protocol or artifact budget is incompatible',
      );
    const manifest = result.data;
    if (
      new Set(manifest.sourceIds).size !== manifest.sourceIds.length ||
      new Set(manifest.resources.map((value) => value.logicalName)).size !==
        manifest.resources.length
    ) {
      throw new VerificationFailure(
        'invalid_manifest',
        'Source IDs and resource logical names must be unique',
      );
    }
    Object.assign(report, {
      buildId: manifest.buildId,
      packageName: manifest.packageName,
      protocolVersion: manifest.protocolVersion,
      hostAbi: manifest.hostAbi,
      runtimeBaseline: manifest.runtimeBaseline,
      bundleSha256: manifest.bundle.sha256,
      manifestSha256: digest(manifestBytes),
      sourceIds: manifest.sourceIds,
    });
    if (
      [...manifest.hostScripts, ...manifest.resources].some(
        (artifact) => !artifact.path.startsWith('/runtime/materials/'),
      )
    ) {
      throw new VerificationFailure(
        'unknown_material',
        'Runtime bridges and resources must use the current shared material catalog',
      );
    }
    const scripts = [manifest.bundle, ...manifest.hostScripts];
    const artifacts: Artifact[] = [...scripts, ...manifest.resources];
    for (const script of scripts) {
      if (
        !['application/javascript', 'text/javascript'].includes(
          script.contentType ?? '',
        )
      ) {
        throw new VerificationFailure(
          'invalid_script_mime',
          'Published scripts must declare a JavaScript content type',
        );
      }
    }
    const payloads = new Map<string, VerifiedPayload>();
    const bundle = manifest.bundle;
    const encoded = await regularFile(
      path.join(directory, 'artifacts', bundle.sha256 + '.gz'),
      64 * 1024 * 1024,
      bundle.encodedSize,
    );
    if (digest(encoded) !== bundle.encodedSha256)
      throw new VerificationFailure(
        'hash_mismatch',
        'Compressed artifact SHA-256 does not match its manifest',
      );
    let canonical: Buffer;
    try {
      canonical = gunzipSync(encoded, { maxOutputLength: bundle.size });
    } catch {
      throw new VerificationFailure(
        'invalid_gzip',
        'Artifact gzip is invalid, truncated or exceeds its canonical budget',
      );
    }
    if (canonical.byteLength !== bundle.size)
      throw new VerificationFailure(
        'size_mismatch',
        'Canonical artifact size does not match its manifest',
      );
    if (digest(canonical) !== bundle.sha256)
      throw new VerificationFailure(
        'hash_mismatch',
        'Canonical artifact SHA-256 does not match its manifest',
      );
    payloads.set(bundle.path, {
      ...bundle,
      bytes: encoded,
      transportContentType: 'application/gzip',
      transportSize: bundle.encodedSize,
    });
    let materials: Awaited<ReturnType<typeof collectMaterials>> | undefined;
    for (const artifact of [...manifest.hostScripts, ...manifest.resources]) {
      let bytes;
      if (artifact.path.startsWith('/runtime/materials/')) {
        materials ??= await collectMaterials();
        const isScript = manifest.hostScripts.includes(artifact);
        const candidates = isScript
          ? materials.catalog.hostScripts
          : materials.catalog.resources;
        const expected = candidates.find(
          (value) => value.sha256 === artifact.sha256,
        );
        if (
          !expected ||
          (['path', 'sha256', 'size', 'contentType'] as const).some(
            (key) => artifact[key] !== expected[key],
          ) ||
          (!isScript && artifact.logicalName !== expected.logicalName)
        ) {
          throw new VerificationFailure(
            'unknown_material',
            'Shared runtime material does not match the pinned host catalog',
          );
        }
        bytes = materials.data.get(artifact.sha256)?.bytes;
        if (!bytes || bytes.length !== artifact.size) {
          throw new VerificationFailure(
            'size_mismatch',
            'Shared runtime material size mismatch',
          );
        }
      } else
        throw new VerificationFailure(
          'unknown_material',
          'Shared materials must use static delivery',
        );
      if (digest(bytes) !== artifact.sha256)
        throw new VerificationFailure(
          'hash_mismatch',
          'Artifact SHA-256 does not match its manifest',
        );
      const existing = payloads.get(artifact.path);
      if (existing && existing.contentType !== artifact.contentType) {
        throw new VerificationFailure(
          'invalid_manifest',
          'One artifact cannot have conflicting content types',
        );
      }
      payloads.set(artifact.path, {
        ...artifact,
        bytes,
        transportContentType:
          artifact.contentType ?? 'application/octet-stream',
        transportSize: artifact.size,
      });
    }
    Object.assign(report, {
      buildId: manifest.buildId,
      packageName: manifest.packageName,
      protocolVersion: manifest.protocolVersion,
      hostAbi: manifest.hostAbi,
      runtimeBaseline: manifest.runtimeBaseline,
      bundleSha256: manifest.bundle.sha256,
      manifestSha256: digest(manifestBytes),
      sourceIds: manifest.sourceIds,
      artifactCount: payloads.size,
      bundleArtifactCount: 1,
      sharedMaterialCount: artifacts.filter((value) =>
        value.path.startsWith('/runtime/'),
      ).length,
      artifactBytes: [...payloads.values()].reduce(
        (sum, value) => sum + value.size,
        0,
      ),
      stages: { ...report.stages, artifactIntegrity: 'passed' },
      capabilities: ['verified-artifact-integrity'],
      failure: {
        code: 'browser_not_run',
        message:
          'Artifact integrity passed; real browser Worker initialization has not been run',
      },
      scope:
        'Artifact integrity only. Compilation and file hashes do not establish browser initialization or online Source compatibility.',
    });
    return { report, manifest, manifestBytes, payloads };
  } catch (error) {
    report.stages.artifactIntegrity = 'failed';
    report.failure = failure(error);
    return { report };
  }
}

export function completeBrowserValidation(
  base: ValidationReport,
  input: unknown,
  networkAttempts: number,
): ValidationReport {
  const value = isRecord(input) ? input : {};
  const report = structuredClone(base);
  report.browser = {
    userAgent: typeof value.userAgent === 'string' ? value.userAgent : '',
    indexedDb: value.indexedDb === true,
    networkAttempts,
  };
  if (networkAttempts > 0) {
    report.stages.browserLoad = 'passed';
    report.stages.workerInit = 'failed';
    report.failure = {
      code: 'network_required',
      message:
        'Initialization attempted an HTTP bridge request; release initialization validation does not permit Source network access',
    };
    return report;
  }
  if (
    !/(?:Chrome|Chromium)\/\d+/.test(report.browser.userAgent) ||
    value.indexedDb !== true
  ) {
    report.stages.browserLoad = 'failed';
    report.failure = {
      code: 'browser_environment',
      message: 'A real Chromium browser with working IndexedDB is required',
    };
    return report;
  }
  report.stages.browserLoad = 'passed';
  const session = isRecord(value.session) ? value.session : {};
  const hello = isRecord(value.hello) ? value.hello : {};
  const browserFailure = isRecord(value.failure) ? value.failure : {};
  const sources =
    Array.isArray(session.sources) && session.sources.every(isSourceInfo)
      ? session.sources
      : undefined;
  const ids = sources?.map((source) => source.id) ?? [];
  if (
    !sources ||
    value.failure ||
    value.buildId !== base.buildId ||
    value.manifestSha256 !== base.manifestSha256 ||
    hello.protocolVersion !== base.protocolVersion ||
    hello.hostAbi !== base.hostAbi ||
    hello.runtimeBaseline !== base.runtimeBaseline ||
    hello.sourceReady !== false ||
    session.protocolVersion !== base.protocolVersion ||
    session.buildId !== base.buildId ||
    typeof session.generation !== 'string' ||
    !session.generation ||
    typeof session.workerInstanceId !== 'string' ||
    !session.workerInstanceId ||
    new Set(ids).size !== ids.length ||
    JSON.stringify([...ids].sort()) !==
      JSON.stringify([...(base.sourceIds ?? [])].sort())
  ) {
    report.stages.workerInit = 'failed';
    report.failure = {
      code:
        typeof browserFailure.code === 'string'
          ? browserFailure.code
          : 'worker_init_failed',
      message:
        typeof browserFailure.message === 'string'
          ? browserFailure.message.slice(0, 2000)
          : 'Real Worker initialization or Source identity validation failed',
    };
    return report;
  }
  report.valid = true;
  report.runtimeReady = true;
  report.stages.workerInit = 'passed';
  report.capabilities.push(
    'chromium-worker-initialized',
    'indexeddb-available',
    'manifest-source-identities',
  );
  report.sources = sources;
  delete report.failure;
  report.scope =
    'Real Chromium Worker hostInit/hostLoad with IndexedDB and verified local artifacts. No live Source operations, private network or production Access validation; online compatibility remains untested.';
  return report;
}
