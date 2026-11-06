/** Resumable local AOT bootstrap and bounded latest-only static snapshots. */
import { randomUUID, createHash } from 'node:crypto';
import { once } from 'node:events';
import {
  appendFileSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { parseArgs, isDeepStrictEqual } from 'node:util';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import lockfile from 'proper-lockfile';
import pLimit from 'p-limit';
import { execa, execaSync } from 'execa';
import stableStringify from 'json-stable-stringify';
import writeFileAtomic from 'write-file-atomic';
import isRecord from 'is-plain-obj';
import type {
  BuildManifest,
  ExtensionIndex,
} from '../../packages/contracts/src/index.ts';
import {
  ROOT,
  HOST_PATHS,
  git,
  hostFingerprint,
  hostSubmodules,
  scan,
  treeHash,
} from './catalog.ts';
import {
  decodeBundle,
  fetchBytes,
  MAX_ENCODED,
  StaticHttpError,
} from './assets.ts';
import { verifyBuild } from './registration.ts';
import {
  extensionDescriptorSchema,
  extensionPlanSchema,
  extensionStateSchema,
  pipelineResultSchema,
  runtimeIdentitySchema,
  type BuildRecord,
  type Catalog,
  type ExtensionDescriptor,
  type ExtensionPlan,
  type ExtensionState,
  type PipelineResult,
  type RuntimeIdentity,
} from './model.ts';

export const MAX_STATE_BYTES = 16 * 1024 * 1024;
export const DEFAULT_ASSETS = path.join(ROOT, '.local/extensions-assets');
export const DEFAULT_ORIGIN = 'https://karuyomi.wybxc.cc';
export const STATE_PATH = '/extensions/build-state.json';
export const INDEX_PATH = '/extensions/index.json';
const equal = isDeepStrictEqual;
export const ciEnvironment = (): boolean =>
  process.env.GITHUB_ACTIONS === 'true' || process.env.CI === 'true';
export function emptyState(): ExtensionState {
  return {
    schemaVersion: 1,
    kind: 'static-extension-build-state',
    revision: null,
    bootstrap: { complete: false },
    attempts: {},
    active: {},
  };
}
export const validateState = (value: unknown): ExtensionState =>
  extensionStateSchema.parse(value);
export function loadState(file: string): ExtensionState {
  if (!existsSync(file)) return emptyState();
  if (statSync(file).size > MAX_STATE_BYTES)
    throw new Error('Oversized state metadata');
  const bytes = readFileSync(file);
  if (bytes.length > MAX_STATE_BYTES)
    throw new Error('Oversized state metadata');
  return validateState(JSON.parse(bytes.toString('utf8')));
}
export function loadPlan(file: string): ExtensionPlan {
  if (statSync(file).size > MAX_STATE_BYTES)
    throw new Error('Oversized plan metadata');
  const bytes = readFileSync(file);
  if (bytes.length > MAX_STATE_BYTES)
    throw new Error('Oversized plan metadata');
  return extensionPlanSchema.parse(JSON.parse(bytes.toString('utf8')));
}
export function loadPipelineResult(file: string): PipelineResult {
  if (statSync(file).size > 2 * 1024 * 1024)
    throw new Error('Oversized pipeline result');
  const bytes = readFileSync(file);
  if (bytes.length > 2 * 1024 * 1024)
    throw new Error('Oversized pipeline result');
  return pipelineResultSchema.parse(JSON.parse(bytes.toString('utf8')));
}
function persistPipelineResult(file: string, result: PipelineResult): void {
  const serialized = stableStringify(pipelineResultSchema.parse(result));
  if (serialized === undefined) throw new Error('Pipeline result is not JSON');
  writeFileAtomic.sync(file, serialized + '\n');
}
export function persistStateCheckpoint(
  file: string,
  state: ExtensionState,
): void {
  const serialized = stableStringify(validateState(state));
  if (serialized === undefined) throw new Error('State checkpoint is not JSON');
  if (Buffer.byteLength(serialized + '\n') > MAX_STATE_BYTES)
    throw new Error('Oversized state checkpoint');
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileAtomic.sync(file, serialized + '\n');
}

export class BuildCancelled extends Error {
  constructor() {
    super('Extension build cancelled');
  }
}
class ChildFailure extends Error {
  readonly code: number | null;
  constructor(code: number | null) {
    super('Builder process failed: ' + code);
    this.code = code;
  }
}
interface BuilderChild {
  kill(signal: NodeJS.Signals): boolean;
}
type BuilderOutput = 'ignore' | 'inherit' | { file: string; append: boolean };
interface BuilderProcessOptions {
  cwd?: string;
  env?: NodeJS.ProcessEnv;
  stdout?: BuilderOutput;
  stderr?: BuilderOutput;
}
/** Own process groups until all writers stop, then allow the state lock to release. */
export class BuilderProcesses {
  readonly controller = new AbortController();
  signalNumber: number | undefined;
  private compromised: Error | undefined;
  private readonly active = new Set<() => Promise<void>>();
  private handlers: { signal: NodeJS.Signals; handler: () => void }[] = [];
  get cancelled(): boolean {
    return this.controller.signal.aborted;
  }
  check(): void {
    if (this.compromised) throw this.compromised;
    if (this.cancelled) throw new BuildCancelled();
  }
  cancel(number?: number): void {
    if (number !== undefined) this.signalNumber ??= number;
    this.controller.abort();
  }
  installSignals(): void {
    for (const [signal, number] of [
      ['SIGINT', 2],
      ['SIGTERM', 15],
    ] as const) {
      const handler = (): void => this.cancel(number);
      process.on(signal, handler);
      this.handlers.push({ signal, handler });
    }
  }
  loseLock(error: Error): void {
    this.compromised = error;
    this.cancel();
  }
  private async terminate(
    child: BuilderChild,
    exited: Promise<void>,
  ): Promise<void> {
    if (child.kill('SIGTERM')) {
      const timeout = new AbortController();
      try {
        await Promise.race([
          exited.catch(() => {}),
          delay(3000, undefined, { signal: timeout.signal }),
        ]);
      } finally {
        timeout.abort();
        // The direct builder may already have exited while descendants still
        // own files. Execa's killDescendants also targets that remaining group.
        child.kill('SIGKILL');
      }
    }
    await exited.catch(() => {});
  }
  async run(
    command: string,
    args: string[],
    options: BuilderProcessOptions = {},
  ): Promise<void> {
    this.check();
    const child = execa(command, args, {
      shell: false,
      stdin: 'ignore',
      preferLocal: false,
      stripFinalNewline: false,
      verbose: 'none',
      ...options,
      extendEnv: false,
      killDescendants: true,
      forceKillAfterDelay: false,
      buffer: false,
      reject: false,
    });
    let code: number | null = null;
    const exited = child.then((result) => {
      code = result.exitCode ?? null;
      if (result.failed && result.exitCode === undefined && !result.signal)
        throw result;
    });
    let stopping: Promise<void> | undefined;
    const stop = (): Promise<void> =>
      (stopping ??= this.terminate(child, exited));
    this.active.add(stop);
    // Execa settles after its redirected stdio has closed. A descendant can
    // retain those pipes after the builder exits, so use the native exit event
    // to start tree cleanup before awaiting the final logs/result.
    const nativeProcess = child.nodeChildProcess;
    const nativeExit =
      nativeProcess.exitCode !== null || nativeProcess.signalCode !== null
        ? Promise.resolve()
        : once(nativeProcess, 'exit').then(
            () => {},
            () => {},
          );
    const completed = nativeExit.then(stop).then(() => exited);
    const aborted = new Promise<never>((_resolve, reject) => {
      const cancel = (): void => reject(new BuildCancelled());
      this.controller.signal.addEventListener('abort', cancel, { once: true });
      exited
        .finally(() =>
          this.controller.signal.removeEventListener('abort', cancel),
        )
        .catch(() => {});
    });
    try {
      await Promise.race([completed, aborted]);
      this.check();
      if (code !== 0) throw new ChildFailure(code);
    } finally {
      await stop();
      this.active.delete(stop);
    }
  }
  async stop(): Promise<void> {
    this.cancel();
    await Promise.all([...this.active].map((stop) => stop()));
  }
  async close(): Promise<void> {
    await this.stop();
    for (const { signal, handler } of this.handlers)
      process.off(signal, handler);
    this.handlers = [];
  }
}
export async function withStateLock<T>(
  state: string,
  processes: BuilderProcesses,
  action: () => Promise<T>,
): Promise<T> {
  mkdirSync(path.dirname(state), { recursive: true });
  let compromised: Error | undefined;
  const release = await lockfile.lock(state, {
    realpath: false,
    lockfilePath: state.replace(/\.[^/.]+$/, '') + '.lock',
    retries: 0,
    stale: 60_000,
    update: 10_000,
    onCompromised: (error) => {
      compromised = error;
      processes.loseLock(error);
    },
  });
  try {
    const result = await action();
    processes.check();
    return result;
  } catch (error) {
    throw compromised ?? error;
  } finally {
    await processes.stop();
    if (!compromised) await release();
  }
}
function pendingEntries(
  entries: ExtensionDescriptor[],
  state: ExtensionState,
  retryFailed: boolean,
): ExtensionDescriptor[] {
  return entries.filter((entry) => {
    const previous = state.attempts[entry.inputFingerprint];
    return (
      !previous ||
      (previous.status === 'published' &&
        previous.available === false &&
        (!previous.rebuildFailure || retryFailed)) ||
      (retryFailed && previous.status === 'failed')
    );
  });
}
export function makePlan(
  catalog: Catalog,
  state: ExtensionState,
  options: {
    limit?: number;
    ci?: boolean;
    retryFailed?: boolean;
    root?: string;
  } = {},
): ExtensionPlan {
  const { limit = 12, ci = false, retryFailed = false, root = ROOT } = options;
  if (ci && (!state.bootstrap.complete || state.revision === null))
    throw new Error(
      'CI bootstrap guard: deploy the initial local baseline first',
    );
  if (ci && retryFailed) throw new Error('CI cannot retry unchanged failures');
  if (!Number.isInteger(limit) || limit < 1 || limit > (ci ? 24 : 10000))
    throw new Error('Invalid batch limit');
  const commit = git(root, 'rev-parse', 'HEAD'),
    pins = hostSubmodules(root);
  const entries = catalog.entries.map((entry) => ({
    ...entry,
    hostRepositoryCommit: commit,
    hostSubmodules: pins,
  }));
  const pending = pendingEntries(entries, state, retryFailed);
  return {
    ...catalog,
    entries,
    repositoryCommit: commit,
    selected: pending.slice(0, limit),
    pendingCount: pending.length,
    remainingCount: Math.max(0, pending.length - limit),
    ci,
    baseRevision: state.revision,
    snapshotNeeded: !!(
      pending.length || state.catalogFingerprint !== catalog.catalogFingerprint
    ),
  };
}
export function resumePlan(
  plan: ExtensionPlan,
  state: ExtensionState,
  limit = 10000,
  retryFailed = false,
  ci = ciEnvironment(),
): ExtensionPlan {
  if (ci) throw new Error('CI cannot resume an initial frozen baseline');
  if (!Number.isInteger(limit) || limit < 1 || limit > 10000)
    throw new Error('Invalid batch limit');
  const first = plan.entries[0];
  if (!first) throw new Error('Frozen plan must contain its complete catalog');
  for (const entry of plan.entries)
    for (const field of [
      'hostRepositoryCommit',
      'hostFingerprint',
      'hostInputs',
      'hostSubmodules',
      'upstreamCommit',
    ] as const)
      if (!equal(entry[field] ?? null, first[field] ?? null))
        throw new Error('Frozen plan mixes host or source identities');
  const pending = pendingEntries(plan.entries, state, retryFailed);
  return {
    ...plan,
    selected: pending.slice(0, limit),
    pendingCount: pending.length,
    remainingCount: Math.max(0, pending.length - limit),
    ci: false,
    baseRevision: state.revision,
    snapshotNeeded:
      !!pending.length || state.catalogFingerprint !== plan.catalogFingerprint,
  };
}
export function validateBuildCheckout(
  checkout: string,
  descriptor: ExtensionDescriptor,
): string {
  checkout = realpathSync(checkout);
  if (git(checkout, 'rev-parse', 'HEAD') !== descriptor.hostRepositoryCommit)
    throw new Error('Build checkout differs from the frozen host commit');
  const names = descriptor.hostInputs;
  if (
    !Object.keys(names).length ||
    git(checkout, 'status', '--porcelain', '--', ...Object.keys(names))
  )
    throw new Error('Frozen host inputs must be present and clean');
  const pins = hostSubmodules(checkout);
  if (!equal(pins, descriptor.hostSubmodules))
    throw new Error('Frozen host submodules changed');
  const inputs = Object.fromEntries(
    Object.keys(names).map((name) => [name, treeHash(checkout, name)]),
  );
  const encoded = stableStringify({
    schemaVersion: 1,
    inputs,
    pinnedSubmodules: pins,
  });
  if (encoded === undefined)
    throw new Error('Frozen host fingerprint is not JSON');
  if (
    !equal(inputs, names) ||
    createHash('sha256').update(encoded).digest('hex') !==
      descriptor.hostFingerprint
  )
    throw new Error('Frozen host fingerprint mismatch');
  if (
    git(
      path.join(checkout, 'vendor/extensions-source'),
      'rev-parse',
      'HEAD',
    ) !== descriptor.upstreamCommit
  )
    throw new Error('Frozen source checkout changed');
  return checkout;
}
export function runtimeIdentity(manifest: BuildManifest): RuntimeIdentity {
  return runtimeIdentitySchema.parse(manifest);
}
export interface ValidationSummary extends Record<string, unknown> {
  runtimeReady: boolean;
}
export class VerifiedBuild {
  private readonly file: string;
  private readonly signature: string;
  readonly result: PipelineResult;
  readonly manifest: BuildManifest;
  readonly validation: ValidationSummary;
  constructor(
    result: PipelineResult,
    manifest: BuildManifest,
    directory: string,
    validation: ValidationSummary,
  ) {
    this.result = result;
    this.manifest = manifest;
    this.validation = validation;
    this.file = path.join(
      directory,
      'artifacts',
      manifest.bundle.sha256 + '.gz',
    );
    this.signature = this.identity();
  }
  private identity(): string {
    const info = lstatSync(this.file, { bigint: true });
    if (!info.isFile() || info.isSymbolicLink())
      throw new Error('Bundle must remain a regular file');
    return [info.dev, info.ino, info.size, info.mtimeNs, info.ctimeNs].join(
      ':',
    );
  }
  payload(): Buffer {
    if (this.identity() !== this.signature)
      throw new Error('Verified output changed before snapshot assembly');
    return readFileSync(this.file);
  }
}
export type BuildOutcome = PipelineResult | VerifiedBuild;
export const resultOf = (outcome: BuildOutcome): PipelineResult =>
  outcome instanceof VerifiedBuild ? outcome.result : outcome;
function failure(
  error: unknown,
  stage: string,
): NonNullable<BuildRecord['failure']> {
  return {
    stage,
    code: error instanceof Error ? error.name : 'build_failed',
    message: (error instanceof Error
      ? error.message
      : 'Extension build failed'
    ).slice(0, 500),
  };
}
function filesIn(directory: string): string[] {
  if (!existsSync(directory)) return [];
  const files: string[] = [];
  for (const name of readdirSync(directory).sort()) {
    const file = path.join(directory, name),
      info = lstatSync(file);
    if (info.isSymbolicLink())
      throw new Error('Build output must not contain symlinks');
    if (info.isDirectory()) files.push(...filesIn(file));
    else if (info.isFile()) files.push(file);
  }
  return files;
}
export interface PipelineOptions {
  root?: string;
  fetchBytes?: typeof fetchBytes;
  materials?: (checkout: string) => Promise<RuntimeIdentity>;
}
export class ExtensionPipeline {
  readonly root: string;
  private readonly download: typeof fetchBytes;
  private readonly catalogs = new Map<string, Promise<RuntimeIdentity>>();
  private readonly materialProvider: PipelineOptions['materials'];
  constructor(options: PipelineOptions = {}) {
    this.root = path.resolve(options.root ?? ROOT);
    this.download = options.fetchBytes ?? fetchBytes;
    this.materialProvider = options.materials;
  }
  async currentRuntime(checkout = this.root): Promise<RuntimeIdentity> {
    let value = this.catalogs.get(checkout);
    if (!value) {
      value = this.materialProvider
        ? this.materialProvider(checkout)
        : Promise.resolve().then(() => {
            execaSync(
              'pnpm',
              ['--filter', '@karuyomi/runtime-host', 'build:materials'],
              {
                cwd: checkout,
                shell: false,
                stdin: 'ignore',
                preferLocal: false,
                verbose: 'none',
                maxBuffer: 2 * 1024 * 1024,
              },
            );
            const catalog: unknown = JSON.parse(
              readFileSync(
                path.join(
                  checkout,
                  'packages/runtime-host/dist/materials.json',
                ),
                'utf8',
              ),
            );
            if (!isRecord(catalog))
              throw new Error('Invalid runtime material catalog');
            return runtimeIdentitySchema.parse({
              ...catalog,
              bridgeVersion: 2,
            });
          });
      this.catalogs.set(checkout, value);
    }
    return value;
  }
  async verifyOutput(
    directory: string,
    descriptor?: ExtensionDescriptor,
    checkout = this.root,
  ): Promise<{
    manifest: BuildManifest;
    encoded: Buffer;
    validation: ValidationSummary;
  }> {
    if (lstatSync(directory).isSymbolicLink())
      throw new Error('Build output must not contain symlinks');
    filesIn(directory);
    const manifestFile = path.join(directory, 'manifest.json');
    if (statSync(manifestFile).size > 64 * 1024)
      throw new Error('Oversized build manifest');
    const manifestBytes = readFileSync(manifestFile);
    if (manifestBytes.length > 64 * 1024)
      throw new Error('Oversized build manifest');
    const manifest = await verifyBuild(
      JSON.parse(manifestBytes.toString('utf8')),
      path.join(directory, 'artifacts'),
      {
        verifyHashes: false,
        materialCatalog: await this.currentRuntime(checkout),
      },
    );
    if (
      descriptor &&
      (manifest.packageName !== descriptor.packageName ||
        manifest.buildId !== descriptor.buildId ||
        manifest.version !== descriptor.versionName)
    )
      throw new Error('Build output differs from its pinned descriptor');
    const encoded = readFileSync(
      path.join(directory, 'artifacts', manifest.bundle.sha256 + '.gz'),
    );
    await decodeBundle(manifest.bundle, encoded);
    const validationFile = path.join(directory, 'validation.json');
    if (
      existsSync(validationFile) &&
      statSync(validationFile).size > 2 * 1024 * 1024
    )
      throw new Error('Oversized validation report');
    const input = existsSync(validationFile)
      ? JSON.parse(readFileSync(validationFile, 'utf8'))
      : {
          schemaVersion: 1,
          valid: false,
          stages: {
            artifactIntegrity: 'passed',
            workerInit: 'not_run',
            browserLoad: 'not_run',
          },
        };
    if (!isRecord(input)) throw new Error('Invalid validation report');
    const stages = isRecord(input.stages) ? input.stages : {};
    const runtimeReady =
      input.valid === true &&
      ['artifactIntegrity', 'workerInit', 'browserLoad'].every(
        (key) => stages[key] === 'passed',
      ) &&
      input.buildId === manifest.buildId &&
      input.manifestSha256 ===
        createHash('sha256').update(manifestBytes).digest('hex');
    return { manifest, encoded, validation: { ...input, runtimeReady } };
  }
  async buildOne(
    descriptor: ExtensionDescriptor,
    output: string,
    options: {
      checkout?: string;
      processes?: BuilderProcesses;
      retryFailed?: boolean;
    } = {},
  ): Promise<BuildOutcome> {
    const processes = options.processes ?? new BuilderProcesses(),
      checkout = path.resolve(options.checkout ?? this.root);
    processes.check();
    output = path.resolve(output);
    mkdirSync(output, { recursive: true });
    let result: PipelineResult = {
      schemaVersion: 1,
      descriptor,
      status: 'failed',
    };
    const saved = path.join(output, 'pipeline-result.json');
    try {
      if (options.checkout) validateBuildCheckout(checkout, descriptor);
      const current = options.checkout
        ? descriptor.hostFingerprint
        : hostFingerprint(this.root).fingerprint;
      if (current !== descriptor.hostFingerprint)
        throw new Error('Host inputs changed since planning');
      if (
        git(
          path.join(checkout, 'vendor/extensions-source'),
          'rev-parse',
          'HEAD',
        ) !== descriptor.upstreamCommit
      )
        throw new Error('Source checkout differs from planned commit');
      if (existsSync(saved)) {
        const cached = loadPipelineResult(saved);
        if (equal(cached.descriptor, descriptor)) {
          if (cached.status === 'built') {
            const verified = await this.verifyOutput(
              output,
              descriptor,
              checkout,
            );
            cleanupBuiltWork(output, descriptor, checkout);
            return new VerifiedBuild(
              cached,
              verified.manifest,
              output,
              verified.validation,
            );
          }
          if (!options.retryFailed) return cached;
        }
      }
      for (const name of [
        'manifest.json',
        'validation.json',
        'provenance.json',
      ])
        rmSync(path.join(output, name), { force: true });
      rmSync(path.join(output, 'artifacts'), { recursive: true, force: true });
      const descriptorFile = path.join(output, 'descriptor.json');
      const serializedDescriptor = stableStringify(descriptor);
      if (serializedDescriptor === undefined)
        throw new Error('Build descriptor is not JSON');
      writeFileAtomic.sync(descriptorFile, serializedDescriptor + '\n');
      const environment = Object.fromEntries(
        Object.entries(process.env).filter(
          ([key]) =>
            !['GH_TOKEN', 'GITHUB_TOKEN', 'CLOUDFLARE_API_TOKEN'].includes(key),
        ),
      );
      await this.currentRuntime(checkout);
      const log = path.join(output, 'build.log');
      writeFileSync(log, '');
      await processes.run(
        process.execPath,
        [
          path.join(checkout, 'tools/extensions/builder.ts'),
          '--descriptor',
          descriptorFile,
          '--output',
          output,
        ],
        {
          cwd: checkout,
          env: environment,
          stdout: { file: log, append: true },
          stderr: { file: log, append: true },
        },
      );
      const verified = await this.verifyOutput(output, descriptor, checkout);
      const serializedValidation = stableStringify(verified.validation);
      if (serializedValidation === undefined)
        throw new Error('Validation report is not JSON');
      writeFileAtomic.sync(
        path.join(output, 'validation.json'),
        serializedValidation + '\n',
      );
      result = {
        schemaVersion: 1,
        descriptor,
        status: 'built',
        validationStatus: verified.validation.runtimeReady
          ? 'browser_verified'
          : 'compiled_unverified',
      };
      persistPipelineResult(saved, result);
      cleanupBuiltWork(output, descriptor, checkout);
      return new VerifiedBuild(
        result,
        verified.manifest,
        output,
        verified.validation,
      );
    } catch (error) {
      if (error instanceof BuildCancelled) throw error;
      result.failure = failure(error, 'build');
      const failureFile = path.join(output, 'build-result.json');
      if (error instanceof ChildFailure && existsSync(failureFile)) {
        if (statSync(failureFile).size > 2 * 1024 * 1024)
          throw new Error('Oversized build failure report');
        const input: unknown = JSON.parse(readFileSync(failureFile, 'utf8'));
        if (
          isRecord(input) &&
          isRecord(input.failure) &&
          typeof input.failure.stage === 'string' &&
          ['upstream', 'host', 'aot', 'complete'].includes(input.failure.stage)
        )
          result.failure = {
            stage: input.failure.stage,
            code: String(input.failure.code ?? 'build_failed').slice(0, 100),
            message: 'Official extension build failed; see local build log',
          };
      }
    }
    persistPipelineResult(saved, result);
    return result;
  }
  async recordResult(
    state: ExtensionState,
    descriptor: ExtensionDescriptor,
    outcome: BuildOutcome,
    directory: string,
    checkout = this.root,
  ): Promise<{ record: BuildRecord; content?: VerifiedBuild }> {
    const key = descriptor.inputFingerprint,
      result = resultOf(outcome);
    let record: BuildRecord = {
      descriptor,
      status: 'failed',
      attempts: (state.attempts[key]?.attempts ?? 0) + 1,
    };
    let content: VerifiedBuild | undefined;
    if (!equal(result.descriptor, descriptor) || result.status !== 'built')
      record.failure = result.failure ?? {
        stage: 'build',
        code: 'missing_result',
        message: 'No matching successful build output',
      };
    else
      try {
        if (outcome instanceof VerifiedBuild) content = outcome;
        else {
          const verified = await this.verifyOutput(
            directory,
            descriptor,
            checkout,
          );
          content = new VerifiedBuild(
            result,
            verified.manifest,
            directory,
            verified.validation,
          );
        }
        record = {
          ...record,
          status: 'published',
          available: true,
          runtimeIdentity: runtimeIdentity(content.manifest),
          runtimeReady: content.validation.runtimeReady,
          validationStatus: content.validation.runtimeReady
            ? 'browser_verified'
            : 'compiled_unverified',
        };
        state.active[descriptor.packageName] = key;
      } catch (error) {
        record.failure = failure(error, 'integrity');
      }
    if (
      record.status === 'failed' &&
      state.active[descriptor.packageName] === key
    ) {
      const previous = state.attempts[key];
      if (!previous) throw new Error('Invalid previous successful pointer');
      record = {
        ...previous,
        attempts: record.attempts,
        available: false,
        ...(record.failure ? { rebuildFailure: record.failure } : {}),
      };
    }
    state.attempts[key] = record;
    return { record, ...(content ? { content } : {}) };
  }
  async prepareSnapshot(
    plan: ExtensionPlan,
    state: ExtensionState,
    results: string,
    assetsDirectory = DEFAULT_ASSETS,
    options: {
      origin?: string;
      finalize?: boolean;
      checkout?: string;
      processes?: BuilderProcesses;
      verifiedResults?: Map<
        string,
        { directory: string; outcome: BuildOutcome }
      >;
    } = {},
  ): Promise<ExtensionState> {
    const processes = options.processes ?? new BuilderProcesses();
    processes.check();
    if (plan.baseRevision !== state.revision)
      throw new Error('Plan was based on a different deployed snapshot');
    const candidate = structuredClone(state),
      current = new Map(
        plan.entries.map((entry) => [entry.packageName, entry]),
      );
    const discoveryPaths = new Set(
        plan.discoveryFailures.map((item) => item.sourcePath),
      ),
      retainedDiscovery = new Set<string>();
    for (const [packageName, key] of Object.entries(state.active)) {
      const descriptor = state.attempts[key]?.descriptor;
      if (
        descriptor &&
        !current.has(packageName) &&
        discoveryPaths.has(descriptor.sourcePath)
      ) {
        current.set(packageName, descriptor);
        retainedDiscovery.add(packageName);
      }
    }
    const resultByKey = new Map<
      string,
      { directory: string; outcome: BuildOutcome }
    >();
    for (const file of filesIn(results).filter(
      (file) => path.basename(file) === 'pipeline-result.json',
    )) {
      const result = loadPipelineResult(file),
        key = result.descriptor.inputFingerprint;
      if (resultByKey.has(key))
        throw new Error('Ambiguous duplicate build results');
      resultByKey.set(key, { directory: path.dirname(file), outcome: result });
    }
    for (const [key, value] of options.verifiedResults ?? [])
      resultByKey.set(key, value);
    const verified = new Map<string, VerifiedBuild>();
    for (const descriptor of plan.selected) {
      processes.check();
      const result = resultByKey.get(descriptor.inputFingerprint);
      if (!result)
        throw new Error(
          'Missing matrix result; keep previous snapshot and retry interrupted build',
        );
      const recorded = await this.recordResult(
        candidate,
        descriptor,
        result.outcome,
        result.directory,
        options.checkout,
      );
      if (recorded.content)
        verified.set(descriptor.packageName, recorded.content);
    }
    candidate.active = Object.fromEntries(
      Object.entries(candidate.active).filter(([packageName]) =>
        current.has(packageName),
      ),
    );
    const retained = new Set(
      [...current.values()]
        .map((entry) => entry.inputFingerprint)
        .concat(Object.values(candidate.active)),
    );
    candidate.attempts = Object.fromEntries(
      Object.entries(candidate.attempts).filter(([key]) => retained.has(key)),
    );
    Object.assign(candidate, {
      discoveryFailures: plan.discoveryFailures,
      upstreamCommit: plan.upstreamCommit,
      hostFingerprint: plan.hostFingerprint,
      catalogFingerprint: plan.catalogFingerprint,
      parentRevision: state.revision,
      revision: randomUUID().replaceAll('-', ''),
    });
    if (options.finalize) finalizeBaseline(candidate, plan);
    assetsDirectory = path.resolve(assetsDirectory);
    mkdirSync(path.dirname(assetsDirectory), { recursive: true });
    const temporary = mkdtempSync(
      path.join(
        path.dirname(assetsDirectory),
        path.basename(assetsDirectory) + '.stage-',
      ),
    );
    try {
      const staged = path.join(temporary, 'snapshot'),
        extension = path.join(staged, 'extensions'),
        artifacts = path.join(extension, 'artifacts');
      mkdirSync(artifacts, { recursive: true });
      const manifests: BuildManifest[] = [],
        identity = await this.currentRuntime(options.checkout);
      for (const [packageName, key] of Object.entries(candidate.active).sort(
        ([a], [b]) => (a < b ? -1 : 1),
      )) {
        processes.check();
        const record = candidate.attempts[key],
          latest = current.get(packageName);
        if (!record || !latest) throw new Error('Invalid active build pointer');
        const descriptor = record.descriptor;
        record.stale =
          key !== latest.inputFingerprint || retainedDiscovery.has(packageName);
        if (!equal(record.runtimeIdentity ?? null, identity)) {
          record.available = false;
          record.availability = 'stale_host';
          continue;
        }
        if (!verified.has(packageName) && record.available === false) {
          record.availability = 'rebuild_required';
          continue;
        }
        record.available = true;
        record.availability = retainedDiscovery.has(packageName)
          ? 'discovery_failed'
          : 'available';
        let manifest: BuildManifest, encoded: Buffer;
        const receipt = verified.get(packageName);
        if (receipt) {
          manifest = receipt.manifest;
          encoded = receipt.payload();
          verified.delete(packageName);
        } else {
          const manifestBytes = await this.download(
            options.origin ?? DEFAULT_ORIGIN,
            '/extensions/builds/' + descriptor.buildId + '/manifest.json',
            64 * 1024,
          );
          const input: unknown = JSON.parse(manifestBytes.toString('utf8'));
          if (
            !isRecord(input) ||
            input.buildId !== descriptor.buildId ||
            input.packageName !== descriptor.packageName ||
            input.version !== descriptor.versionName
          )
            throw new Error('Static successful build identity mismatch');
          const { parseManifestValue } = await import('./verify-manifest.ts');
          manifest = await parseManifestValue(input);
          encoded = await this.download(
            options.origin ?? DEFAULT_ORIGIN,
            manifest.bundle.path,
            MAX_ENCODED,
          );
          await decodeBundle(manifest.bundle, encoded);
        }
        writeFileSync(
          path.join(artifacts, manifest.bundle.sha256 + '.gz'),
          encoded,
        );
        const serializedManifest = stableStringify(manifest);
        if (serializedManifest === undefined)
          throw new Error('Manifest is not JSON');
        const manifestFile = path.join(
          extension,
          'builds',
          descriptor.buildId,
          'manifest.json',
        );
        mkdirSync(path.dirname(manifestFile), { recursive: true });
        writeFileAtomic.sync(manifestFile, serializedManifest + '\n');
        await verifyBuild(manifest, artifacts, {
          verifyHashes: false,
          materialCatalog: identity,
        });
        manifests.push(manifest);
      }
      candidate.summary = {
        available: manifests.length,
        unavailable: Object.values(candidate.active).filter(
          (key) => !candidate.attempts[key]?.available,
        ).length,
        failed: Object.values(candidate.attempts).filter(
          (record) => record.status === 'failed',
        ).length,
        pending: [...current.values()].filter(
          (entry) => !candidate.attempts[entry.inputFingerprint],
        ).length,
      };
      const serializedIndex = stableStringify(staticIndex(manifests));
      if (serializedIndex === undefined)
        throw new Error('Static index is not JSON');
      const indexBytes = Buffer.from(serializedIndex + '\n');
      if (indexBytes.length > 2 * 1024 * 1024)
        throw new Error('Static extension index exceeds 2 MiB');
      writeFileSync(path.join(extension, 'index.json'), indexBytes);
      candidate.indexSha256 = createHash('sha256')
        .update(indexBytes)
        .digest('hex');
      const serializedState = stableStringify(validateState(candidate));
      if (serializedState === undefined)
        throw new Error('Static state is not JSON');
      const stateBytes = Buffer.from(serializedState + '\n');
      if (stateBytes.length > MAX_STATE_BYTES)
        throw new Error('Static build state exceeds 16 MiB');
      writeFileSync(path.join(extension, 'build-state.json'), stateBytes);
      processes.check();
      replaceDirectory(staged, assetsDirectory);
      return candidate;
    } finally {
      rmSync(temporary, { recursive: true, force: true });
    }
  }
  async remoteState(
    origin: string,
    allowMissing = false,
  ): Promise<ExtensionState> {
    try {
      return validateState(
        JSON.parse(
          (await this.download(origin, STATE_PATH, MAX_STATE_BYTES)).toString(
            'utf8',
          ),
        ),
      );
    } catch (error) {
      if (error instanceof StaticHttpError) {
        if (error.status === 404 && allowMissing) return emptyState();
        throw new Error(
          'Static build state unavailable; cannot infer a baseline',
        );
      }
      throw error;
    }
  }
  async pullState(origin: string, file: string): Promise<ExtensionState> {
    const state = await this.remoteState(origin),
      index = await this.download(origin, INDEX_PATH, 2 * 1024 * 1024);
    if (createHash('sha256').update(index).digest('hex') !== state.indexSha256)
      throw new Error(
        'Static index and build state are from different snapshots',
      );
    if (!state.bootstrap.complete || state.revision === null)
      throw new Error(
        'CI bootstrap guard: deploy initial local baseline first',
      );
    persistStateCheckpoint(file, state);
    return state;
  }
  async checkBase(
    assetsDirectory: string,
    origin: string,
    initialize = false,
  ): Promise<void> {
    const candidate = loadState(
      path.join(assetsDirectory, 'extensions/build-state.json'),
    );
    if (candidate.revision === null)
      throw new Error('Candidate snapshot is missing');
    if (initialize && (ciEnvironment() || candidate.parentRevision !== null))
      throw new Error(
        'Explicit initialization is local-only and requires no previous baseline',
      );
    let remote: ExtensionState;
    try {
      remote = await this.remoteState(
        origin,
        candidate.parentRevision === null,
      );
    } catch (error) {
      if (!(error instanceof SyntaxError)) throw error;
      if (!initialize)
        throw new Error(
          'Static build state is not JSON; use explicit local initialization only for known pre-baseline SPA',
        );
      const bytes = await this.download(origin, STATE_PATH, MAX_STATE_BYTES);
      if (!/^\s*(?:<!doctype html|<html)/i.test(bytes.toString('utf8')))
        throw new Error(
          'Initialization cannot replace an arbitrary invalid response',
        );
      remote = emptyState();
    }
    if (remote.revision !== candidate.parentRevision)
      throw new Error(
        'Remote static snapshot advanced; pull and replan before deploying',
      );
  }
  async commitSnapshot(
    stateFile: string,
    assetsDirectory: string,
    origin: string,
  ): Promise<ExtensionState> {
    const candidate = loadState(
        path.join(assetsDirectory, 'extensions/build-state.json'),
      ),
      index = readFileSync(path.join(assetsDirectory, 'extensions/index.json'));
    if (candidate.revision === null)
      throw new Error('Candidate snapshot is missing');
    if (
      createHash('sha256').update(index).digest('hex') !==
        candidate.indexSha256 ||
      !equal(await this.remoteState(origin), candidate) ||
      !(await this.download(origin, INDEX_PATH, 2 * 1024 * 1024)).equals(index)
    )
      throw new Error(
        'Static deployment is not confirmed; checkpoint unchanged',
      );
    const persisted = loadState(stateFile);
    if (
      persisted.revision !== candidate.parentRevision &&
      persisted.revision !== candidate.revision
    )
      throw new Error('Local checkpoint advanced; refusing to overwrite it');
    persistStateCheckpoint(stateFile, candidate);
    return candidate;
  }
}
export function finalizeBaseline(
  state: ExtensionState,
  catalog: Catalog,
  local = true,
  ci = ciEnvironment(),
): void {
  if (!local || ci)
    throw new Error('CI cannot create or finalize initial baseline');
  const records = catalog.entries.map(
    (entry) => state.attempts[entry.inputFingerprint],
  );
  if (
    records.some(
      (record) => !record || !['published', 'failed'].includes(record.status),
    )
  )
    throw new Error('Initial baseline still has unattempted packages');
  state.bootstrap = {
    complete: true,
    upstreamCommit: catalog.upstreamCommit,
    catalogFingerprint: catalog.catalogFingerprint,
    published: records.filter((record) => record?.status === 'published')
      .length,
    failed: records.filter((record) => record?.status === 'failed').length,
    discoveryFailed: catalog.discoveryFailures.length,
  };
}
export function staticIndex(manifests: BuildManifest[]): ExtensionIndex {
  if (manifests.some((manifest) => manifest.repoId !== 'keiyoushi'))
    throw new Error('Default pipeline cannot publish another repository');
  return {
    schemaVersion: 1,
    repoId: 'keiyoushi',
    builds: [...manifests]
      .sort((a, b) => (a.packageName < b.packageName ? -1 : 1))
      .map(({ buildId, packageName, repoId, version, sourceIds, sources }) => ({
        buildId,
        packageName,
        repoId,
        version,
        sourceIds,
        sources,
        manifestPath: '/extensions/builds/' + buildId + '/manifest.json',
      })),
  };
}
export function replaceDirectory(staged: string, destination: string): void {
  const backup = destination + '.previous';
  if (existsSync(backup))
    throw new Error('Interrupted snapshot swap: inspect previous directory');
  const previous = existsSync(destination);
  if (previous) renameSync(destination, backup);
  try {
    renameSync(staged, destination);
  } catch (error) {
    if (previous) renameSync(backup, destination);
    throw error;
  }
  if (previous) rmSync(backup, { recursive: true });
}
export function removeBuildWork(buildId: string, checkout = ROOT): string[] {
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$/.test(buildId))
    throw new Error('Unsafe build ID for cache cleanup');
  const local = path.join(path.resolve(checkout), 'runtime/teavm/.local');
  if (!existsSync(local)) return [];
  if (realpathSync(local) !== local || lstatSync(local).isSymbolicLink())
    throw new Error('Cache cleanup root must not contain symbolic links');
  const removed: string[] = [];
  for (const name of ['extension-work', 'extension-cache', 'gradle-launcher']) {
    const parent = path.join(local, name);
    if (!existsSync(parent)) continue;
    if (lstatSync(parent).isSymbolicLink() || realpathSync(parent) !== parent)
      throw new Error('Cache cleanup parent must not contain symbolic links');
    const target = path.join(parent, buildId);
    let info: ReturnType<typeof lstatSync>;
    try {
      info = lstatSync(target);
    } catch (error) {
      if (error instanceof Error && 'code' in error && error.code === 'ENOENT')
        continue;
      throw error;
    }
    if (!info.isSymbolicLink() && !info.isDirectory())
      throw new Error('Expected disposable build directory: ' + name);
    rmSync(target, { recursive: true, force: true });
    removed.push(name + '/' + buildId);
  }
  return removed;
}
export function cleanupBuiltWork(
  directory: string,
  descriptor: ExtensionDescriptor,
  checkout = ROOT,
): string[] {
  const saved = loadPipelineResult(
    path.join(directory, 'pipeline-result.json'),
  );
  if (saved.status !== 'built' || !equal(saved.descriptor, descriptor))
    throw new Error(
      'Successful build checkpoint must be saved before cache cleanup',
    );
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,199}$/.test(descriptor.buildId))
    throw new Error('Unsafe build ID for cache cleanup');
  try {
    return removeBuildWork(descriptor.buildId, checkout);
  } catch (error) {
    console.error(
      'extensions: retained compiler work: ' +
        (error instanceof Error ? error.message : 'cleanup failed'),
    );
    return [];
  }
}

export function writeGithubOutput(file: string, plan: ExtensionPlan): void {
  const matrix = {
    include: plan.selected.map((entry) => ({ key: entry.inputFingerprint })),
  };
  appendFileSync(
    file,
    'matrix=' +
      JSON.stringify(matrix) +
      '\ncount=' +
      plan.selected.length +
      '\nupstream=' +
      plan.upstreamCommit +
      '\nsnapshot_needed=' +
      plan.snapshotNeeded +
      '\n',
  );
}

async function runPipeline(
  argv: string[],
  processes: BuilderProcesses,
): Promise<void> {
  const [command, ...arguments_] = argv;
  if (!command || command === '--help') {
    console.log(
      'Usage: node tools/extensions/pipeline.ts <plan|bootstrap|build|prepare-snapshot|pull-state|check-base|commit-snapshot> [options]',
    );
    return;
  }
  const { values } = parseArgs({
    args: arguments_,
    strict: true,
    options: {
      source: { type: 'string' },
      state: { type: 'string' },
      output: { type: 'string' },
      limit: { type: 'string' },
      'retry-failed': { type: 'boolean', default: false },
      ci: { type: 'boolean', default: false },
      jobs: { type: 'string' },
      finalize: { type: 'boolean', default: false },
      plan: { type: 'string' },
      'build-checkout': { type: 'string' },
      'assets-dir': { type: 'string' },
      origin: { type: 'string' },
      key: { type: 'string' },
      results: { type: 'string' },
      initialize: { type: 'boolean', default: false },
      'github-output': { type: 'string' },
    },
  });
  const required = (
    name: 'state' | 'output' | 'plan' | 'results' | 'key',
  ): string => {
    const value = values[name];
    if (!value) throw new Error('--' + name + ' is required');
    return value;
  };
  const assetsDirectory = path.resolve(values['assets-dir'] ?? DEFAULT_ASSETS),
    origin = values.origin ?? DEFAULT_ORIGIN;
  const pipeline = new ExtensionPipeline();
  const action = async (): Promise<void> => {
    if (command === 'pull-state')
      await pipeline.pullState(origin, required('state'));
    else if (command === 'check-base')
      await pipeline.checkBase(assetsDirectory, origin, values.initialize);
    else if (command === 'commit-snapshot')
      await pipeline.commitSnapshot(required('state'), assetsDirectory, origin);
    else if (command === 'prepare-snapshot')
      await pipeline.prepareSnapshot(
        loadPlan(required('plan')),
        loadState(required('state')),
        required('results'),
        assetsDirectory,
        { origin, processes },
      );
    else if (command === 'build') {
      const plan = loadPlan(required('plan')),
        key = required('key');
      const descriptor = plan.selected.find(
        (entry) => entry.inputFingerprint === key,
      );
      if (!descriptor) throw new Error('Selected input key is not in plan');
      const result = resultOf(
        await pipeline.buildOne(descriptor, required('output'), { processes }),
      );
      console.log(
        JSON.stringify({
          packageName: descriptor.packageName,
          status: result.status,
        }),
      );
      if (result.status !== 'built') process.exitCode = 1;
    } else if (command === 'plan' || command === 'bootstrap') {
      const bootstrap = command === 'bootstrap',
        stateFile = required('state'),
        state = loadState(stateFile);
      if (bootstrap && (values.ci || ciEnvironment()))
        throw new Error('Initial full bootstrap is local-only');
      let plan: ExtensionPlan, checkout: string | undefined;
      const limit = Number(values.limit ?? (bootstrap ? 10000 : 12));
      if (bootstrap && values.plan) {
        if (!values['build-checkout'])
          throw new Error('--plan requires --build-checkout');
        plan = resumePlan(
          loadPlan(values.plan),
          state,
          limit,
          values['retry-failed'],
        );
        const descriptor = plan.entries[0];
        if (!descriptor) throw new Error('Frozen plan is empty');
        checkout = validateBuildCheckout(values['build-checkout'], descriptor);
      } else {
        if (bootstrap && values['build-checkout'])
          throw new Error('--build-checkout requires --plan');
        if (
          bootstrap &&
          git(ROOT, 'status', '--porcelain', '--', ...HOST_PATHS)
        )
          throw new Error(
            'Commit reviewed host inputs before initial baseline',
          );
        const host = hostFingerprint();
        plan = makePlan(
          scan(
            values.source ?? path.join(ROOT, 'vendor/extensions-source'),
            host.fingerprint,
            host.inputs,
          ),
          state,
          {
            limit,
            ci: values.ci || ciEnvironment(),
            retryFailed: values['retry-failed'],
          },
        );
      }
      const output = path.resolve(required('output'));
      const serializedPlan = stableStringify(plan);
      if (serializedPlan === undefined)
        throw new Error('Build plan is not JSON');
      mkdirSync(path.dirname(output), { recursive: true });
      writeFileAtomic.sync(output, serializedPlan + '\n');
      if (values['github-output'])
        writeGithubOutput(values['github-output'], plan);
      console.log(
        JSON.stringify({
          discovered: plan.entries.length,
          selected: plan.selected.length,
          remaining: plan.remainingCount,
        }),
      );
      if (!bootstrap) return;
      const jobs = Number(values.jobs ?? 1);
      if (!Number.isInteger(jobs) || jobs < 1 || jobs > 4)
        throw new Error('--jobs must be between 1 and 4');
      const builds = path.join(path.dirname(output), 'builds'),
        completed = new Map<
          string,
          { directory: string; outcome: BuildOutcome }
        >();
      const limitJobs = pLimit({ concurrency: jobs, rejectOnClear: true });
      const cancelQueue = (): void => limitJobs.clearQueue();
      processes.controller.signal.addEventListener('abort', cancelQueue, {
        once: true,
      });
      try {
        const tasks = plan.selected.map((entry) =>
          limitJobs(async () => {
            processes.check();
            const directory = path.join(builds, entry.inputFingerprint);
            const outcome = await pipeline.buildOne(entry, directory, {
              ...(checkout ? { checkout } : {}),
              processes,
              retryFailed: values['retry-failed'],
            });
            completed.set(entry.inputFingerprint, { directory, outcome });
            console.log(entry.packageName + ': ' + resultOf(outcome).status);
          }),
        );
        const settled = await Promise.allSettled(tasks);
        processes.check();
        for (const result of settled)
          if (result.status === 'rejected') throw result.reason;
      } finally {
        processes.controller.signal.removeEventListener('abort', cancelQueue);
      }
      processes.check();
      await pipeline.prepareSnapshot(plan, state, builds, assetsDirectory, {
        origin,
        finalize: values.finalize,
        ...(checkout ? { checkout } : {}),
        processes,
        verifiedResults: completed,
      });
    } else throw new Error('Unknown pipeline command: ' + command);
    processes.check();
  };
  if (
    [
      'plan',
      'bootstrap',
      'prepare-snapshot',
      'pull-state',
      'commit-snapshot',
    ].includes(command)
  )
    await withStateLock(path.resolve(required('state')), processes, action);
  else await action();
}
export async function main(argv = process.argv.slice(2)): Promise<void> {
  const processes = new BuilderProcesses();
  processes.installSignals();
  try {
    await runPipeline(argv, processes);
  } catch (error) {
    if (!(error instanceof BuildCancelled)) throw error;
    console.error(
      'extensions: cancelled; prior snapshot and completed build results retained',
    );
    process.exitCode = 128 + (processes.signalNumber ?? 2);
  } finally {
    await processes.close();
  }
}
if (
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  await main().catch((error: unknown) => {
    console.error(
      error instanceof Error ? error.message : 'Extension pipeline failed',
    );
    process.exitCode = 1;
  });
}
