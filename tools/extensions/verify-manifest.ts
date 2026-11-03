import { lstat, open } from 'node:fs/promises';
import { constants } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import * as contracts from '../../packages/contracts/src/index.ts';
import type {
  Artifact,
  BundleArtifact,
  BuildManifest,
  ExtensionIndex,
} from '../../packages/contracts/src/index.ts';
import { isRecord, digest } from '../lib/json.ts';
import { isSourceInfo } from './types.ts';
export { digest } from '../lib/json.ts';
import type {
  IntegrityResult,
  ValidationReport,
  VerifiedPayload,
} from './types.ts';
import { collectMaterials } from '../../packages/runtime-host/materials.ts';

export const repositoryRoot = fileURLToPath(new URL('../../', import.meta.url));

export class VerificationFailure extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

export async function loadContracts() {
  return contracts;
}

export async function parseManifestValue(
  input: unknown,
): Promise<BuildManifest> {
  const result = (await loadContracts()).buildManifestSchema.safeParse(input);
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
  )
    throw new VerificationFailure(
      'invalid_manifest',
      'Source IDs and resource logical names must be unique',
    );
  for (const script of [manifest.bundle, ...manifest.hostScripts]) {
    if (
      !['application/javascript', 'text/javascript'].includes(
        script.contentType ?? '',
      )
    )
      throw new VerificationFailure(
        'invalid_script_mime',
        'Published scripts must declare a JavaScript content type',
      );
  }
  return manifest;
}

export async function parseManifest(bytes: Uint8Array): Promise<BuildManifest> {
  let input: unknown;
  try {
    input = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
  } catch {
    throw new VerificationFailure(
      'invalid_manifest',
      'Manifest is not valid UTF-8 JSON',
    );
  }
  return parseManifestValue(input);
}

export interface MaterialCatalogRefs {
  hostScripts: readonly Artifact[];
  resources: readonly (Artifact & { logicalName: string })[];
}

export function verifyMaterialReferences(
  manifest: BuildManifest,
  catalog: MaterialCatalogRefs,
) {
  for (const [artifacts, candidates, resource] of [
    [manifest.hostScripts, catalog.hostScripts, false],
    [manifest.resources, catalog.resources, true],
  ] as const) {
    for (const artifact of artifacts) {
      const expected = candidates.find(
        (value) => value.sha256 === artifact.sha256,
      );
      if (
        !expected ||
        (['path', 'sha256', 'size', 'contentType'] as const).some(
          (key) => artifact[key] !== expected[key],
        ) ||
        (resource && artifact.logicalName !== expected.logicalName)
      )
        throw new VerificationFailure(
          'unknown_material',
          'Shared runtime material does not match the pinned host catalog',
        );
    }
  }
}

/** One transfer boundary: hash the encoded and canonical byte domains once. */
export async function decodeBundleBytes(
  bundle: BundleArtifact,
  encoded: Uint8Array,
): Promise<Buffer> {
  if (encoded.byteLength !== bundle.encodedSize)
    throw new VerificationFailure(
      'size_mismatch',
      'Encoded artifact size does not match its manifest',
    );
  if (digest(encoded) !== bundle.encodedSha256)
    throw new VerificationFailure(
      'hash_mismatch',
      'Compressed artifact SHA-256 does not match its manifest',
    );
  // WHATWG gzip decompression rejects concatenated members/trailing bytes. The
  // maintained platform decoder owns gzip framing; no project gzip parser.
  const source =
    encoded.buffer instanceof ArrayBuffer
      ? new Uint8Array(encoded.buffer, encoded.byteOffset, encoded.byteLength)
      : Uint8Array.from(encoded);
  const input = new ReadableStream<BufferSource>({
    start(controller) {
      controller.enqueue(source);
      controller.close();
    },
  });
  const reader = input.pipeThrough(new DecompressionStream('gzip')).getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const next = await reader.read();
      if (next.done) break;
      size += next.value.byteLength;
      if (size > bundle.size) throw new Error('canonical_size_exceeded');
      chunks.push(next.value);
    }
  } catch {
    await reader.cancel().catch(() => {});
    throw new VerificationFailure(
      'invalid_gzip',
      'Artifact gzip is invalid, truncated or exceeds its canonical budget',
    );
  } finally {
    reader.releaseLock();
  }
  if (size !== bundle.size)
    throw new VerificationFailure(
      'size_mismatch',
      'Canonical artifact size does not match its manifest',
    );
  const canonical = Buffer.concat(chunks, size);
  if (digest(canonical) !== bundle.sha256)
    throw new VerificationFailure(
      'hash_mismatch',
      'Canonical artifact SHA-256 does not match its manifest',
    );
  return canonical;
}

/** False is for already verified in-process bytes, never a disk-resume receipt. */
export async function verifyBundleFile(
  bundle: BundleArtifact,
  artifactDirectory: string,
  { verifyHashes = true }: { verifyHashes?: boolean } = {},
): Promise<Buffer | undefined> {
  await regularDirectory(artifactDirectory);
  const file = path.join(artifactDirectory, bundle.sha256 + '.gz');
  if (!verifyHashes) {
    const info = await lstat(file);
    if (!info.isFile() || info.isSymbolicLink())
      throw new VerificationFailure(
        'invalid_file',
        'Bundle must be a regular gzip file',
      );
    if (info.size !== bundle.encodedSize)
      throw new VerificationFailure(
        'size_mismatch',
        'Encoded artifact size does not match its manifest',
      );
    return;
  }
  const encoded = await readRegularFile(
    file,
    25 * 1024 * 1024,
    bundle.encodedSize,
  );
  await decodeBundleBytes(bundle, encoded);
  return encoded;
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
  return (await loadContracts()).extensionIndexSchema.parse(parsed);
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

export async function readRegularFile(
  file: string,
  limit: number,
  expectedSize?: number,
) {
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
    const manifestBytes = await readRegularFile(
      path.join(directory, 'manifest.json'),
      64 * 1024,
    );
    const manifest = await parseManifest(manifestBytes);
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
    const artifacts: Artifact[] = [
      manifest.bundle,
      ...manifest.hostScripts,
      ...manifest.resources,
    ];
    const payloads = new Map<string, VerifiedPayload>();
    const bundle = manifest.bundle;
    const encoded = await verifyBundleFile(
      bundle,
      path.join(directory, 'artifacts'),
    );
    if (!encoded) throw new Error('Missing verified bundle');
    payloads.set(bundle.path, {
      ...bundle,
      bytes: encoded,
      transportContentType: 'application/gzip',
      transportSize: bundle.encodedSize,
    });
    const hasMaterials =
      manifest.hostScripts.length + manifest.resources.length > 0;
    const materials = hasMaterials ? await collectMaterials() : undefined;
    if (materials) verifyMaterialReferences(manifest, materials.catalog);
    for (const artifact of [...manifest.hostScripts, ...manifest.resources]) {
      const bytes = materials?.data.get(artifact.sha256)?.bytes;
      if (!bytes || bytes.length !== artifact.size)
        throw new VerificationFailure(
          'size_mismatch',
          'Shared runtime material size mismatch',
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
