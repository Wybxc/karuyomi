/** Official image-codec SDK preparation; no compiler/npm dependency rewriting. */
import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { lstat, mkdir, mkdtemp, readFile, rename, rm } from 'node:fs/promises';
import path from 'node:path';
import { Readable, Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { execa } from 'execa';
import lockfile from 'proper-lockfile';
import writeFileAtomic from 'write-file-atomic';
import { z } from 'zod';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const digestSchema = z.string().regex(/^[a-f0-9]{64}$/);
const archiveBase = z.object({
  url: z.url(),
  generation: z.string().regex(/^\d+$/),
  size: z
    .number()
    .int()
    .positive()
    .max(1024 * 1024 * 1024),
});
const verifiedArchive = archiveBase
  .extend({
    verification: z.literal('verified'),
    sha256: digestSchema,
    versions: z
      .object({
        clang: z.string().min(1),
        clangCommit: z.string().regex(/^[a-f0-9]{40}$/),
        binaryen: z.string().regex(/^\d+$/),
        binaryenRevision: z.string().min(1),
      })
      .strict(),
  })
  .strict();
export const imageCodecToolchainLockSchema = z
  .object({
    schemaVersion: z.literal(1),
    emsdk: z
      .object({
        repository: z.url(),
        commit: z.string().regex(/^[a-f0-9]{40}$/),
        version: z.string().regex(/^\d+\.\d+\.\d+$/),
        releaseTag: z.string().regex(/^[a-f0-9]{40}$/),
      })
      .strict(),
    emscriptenCommit: z.string().regex(/^[a-f0-9]{40}$/),
    archives: z.record(
      z.string(),
      z.discriminatedUnion('verification', [
        verifiedArchive,
        archiveBase
          .extend({
            verification: z.literal('pending_sha256'),
            reason: z.string().min(1),
          })
          .strict(),
      ]),
    ),
  })
  .strict();
export type ImageCodecToolchainLock = z.infer<
  typeof imageCodecToolchainLockSchema
>;
type Archive = z.infer<typeof verifiedArchive>;

const installationSchema = z
  .object({
    schemaVersion: z.literal(1),
    host: z.string(),
    archiveSha256: digestSchema,
  })
  .strict();
type Installation = z.infer<typeof installationSchema>;

export interface ImageCodecToolchainOptions {
  projectRoot?: string;
  lockFile?: string;
  lock?: ImageCodecToolchainLock;
  cacheRoot?: string;
  archiveFile?: string;
  host?: string;
  nodeExecutable?: string;
  pythonExecutable?: string;
  signal?: AbortSignal;
}

export interface PreparedImageCodecToolchain {
  host: string;
  directory: string;
  sdk: string;
  emcc: string;
  clang: string;
  wasmOpt: string;
  emConfig: string;
  cache: string;
  node: string;
  python: string;
  archiveSha256: string;
  versions: Record<'node' | 'python' | 'emcc' | 'clang' | 'wasmOpt', string>;
  environment: Record<string, string>;
}

async function hashFile(file: string, signal: AbortSignal) {
  let size = 0;
  const digest = createHash('sha256');
  for await (const chunk of createReadStream(file, { signal })) {
    size += chunk.length;
    digest.update(chunk);
  }
  return { size, sha256: digest.digest('hex') };
}

function executableEnvironment(
  config: string,
  cache: string,
): Record<string, string> {
  const result: Record<string, string> = {};
  for (const [key, value] of Object.entries(process.env)) {
    // Emscripten environment overrides must not replace the selected SDK or suppress its checks.
    if (value !== undefined && !/^EM(?:CC|SDK)?_/.test(key))
      result[key] = value;
  }
  return { ...result, EM_CONFIG: config, EM_CACHE: cache, EMCC_CORES: '2' };
}

/** Each SDK operation owns its process group; cancellation waits for the process and removes descendants. */
async function sdkOperation(
  executable: string,
  args: string[],
  environment: Record<string, string>,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const operationSignal = AbortSignal.any([
    signal,
    AbortSignal.timeout(120_000),
  ]);
  const child = execa(executable, args, {
    env: environment,
    extendEnv: false,
    cancelSignal: operationSignal,
    killDescendants: true,
    forceKillAfterDelay: 1000,
    maxBuffer: 1024 * 1024,
    stdin: 'ignore',
  });
  // Execa owns the process group and parent-exit cleanup. A successful immediate
  // child can still leave descendants holding stdio, so stop them at its exit event.
  const stopDescendants = () => {
    child.kill('SIGKILL');
  };
  child.nodeChildProcess.once('exit', stopDescendants);
  try {
    const result = await child;
    return result.stdout + '\n' + result.stderr;
  } finally {
    child.nodeChildProcess.off('exit', stopDescendants);
  }
}

async function writeConfiguration(
  directory: string,
  node: string,
): Promise<void> {
  // JSON string escaping is also valid for these Python string literals.
  const quote = (value: string) => JSON.stringify(value);
  await writeFileAtomic(
    path.join(directory, '.emscripten'),
    [
      `LLVM_ROOT = ${quote(path.join(directory, 'sdk/bin'))}`,
      `BINARYEN_ROOT = ${quote(path.join(directory, 'sdk'))}`,
      `NODE_JS = [${quote(node)}]`,
      `CACHE = ${quote(path.join(directory, 'emscripten-cache'))}`,
      '',
    ].join('\n'),
  );
}

async function verifyExecutables(
  directory: string,
  node: string,
  python: string,
  lock: ImageCodecToolchainLock,
  archive: Archive,
  signal: AbortSignal,
): Promise<PreparedImageCodecToolchain['versions']> {
  const sdk = path.join(directory, 'sdk');
  const env = executableEnvironment(
    path.join(directory, '.emscripten'),
    path.join(directory, 'emscripten-cache'),
  );
  const emcc = await sdkOperation(
    python,
    [
      path.join(sdk, 'emscripten/emcc.py'),
      '-Werror=version-check',
      '--version',
    ],
    env,
    signal,
  );
  if (!emcc.includes(`${lock.emsdk.version}-git (${lock.emscriptenCommit})`))
    throw new Error('Image SDK Emscripten version or commit mismatch');
  const clang = await sdkOperation(
    path.join(sdk, 'bin/clang'),
    ['--version'],
    env,
    signal,
  );
  if (
    !clang.includes(`clang version ${archive.versions.clang} `) ||
    !clang.includes(archive.versions.clangCommit)
  )
    throw new Error('Image SDK Clang version or commit mismatch');
  const wasmOpt = await sdkOperation(
    path.join(sdk, 'bin/wasm-opt'),
    ['--version'],
    env,
    signal,
  );
  if (
    !wasmOpt.includes(
      `wasm-opt version ${archive.versions.binaryen} (${archive.versions.binaryenRevision})`,
    )
  )
    throw new Error('Image SDK Binaryen version mismatch');
  const nodeVersion = (
    await sdkOperation(node, ['--version'], env, signal)
  ).trim();
  const pythonVersion = (
    await sdkOperation(python, ['--version'], env, signal)
  ).trim();
  return {
    node: nodeVersion,
    python: pythonVersion,
    emcc: emcc.trim(),
    clang: clang.trim(),
    wasmOpt: wasmOpt.trim(),
  };
}

async function downloadArchive(
  archive: Archive,
  file: string,
  signal: AbortSignal,
): Promise<void> {
  const url = new URL(archive.url);
  if (url.searchParams.get('generation') !== archive.generation)
    throw new Error('Image SDK URL must pin the locked generation');
  if (
    url.protocol !== 'https:' &&
    !(url.protocol === 'http:' && ['127.0.0.1', '[::1]'].includes(url.hostname))
  )
    throw new Error('Image SDK download requires HTTPS');
  const response = await fetch(url, { signal, redirect: 'error' });
  if (!response.ok || !response.body)
    throw new Error(`Image SDK download failed: HTTP ${response.status}`);
  const declared = response.headers.get('content-length');
  if (declared !== null && Number(declared) !== archive.size) {
    await response.body.cancel();
    throw new Error('Image SDK archive size mismatch');
  }
  let size = 0;
  const digest = createHash('sha256');
  const limit = new Transform({
    transform(chunk: unknown, _encoding, callback) {
      if (!Buffer.isBuffer(chunk)) {
        callback(new Error('Invalid SDK download chunk'));
        return;
      }
      size += chunk.length;
      if (size > archive.size) {
        callback(new Error('Image SDK archive exceeds locked size'));
        return;
      }
      digest.update(chunk);
      callback(null, chunk);
    },
  });
  const body = response.body;
  async function* chunks() {
    const reader = body.getReader();
    try {
      while (true) {
        const item = await reader.read();
        if (item.done) return;
        yield item.value;
      }
    } finally {
      await reader.cancel().catch(() => undefined);
      reader.releaseLock();
    }
  }
  await pipeline(
    Readable.from(chunks()),
    limit,
    createWriteStream(file, { flags: 'wx' }),
    { signal },
  );
  if (size !== archive.size || digest.digest('hex') !== archive.sha256)
    throw new Error('Image SDK archive size or SHA-256 mismatch');
}

export async function prepareImageCodecToolchain(
  options: ImageCodecToolchainOptions = {},
): Promise<PreparedImageCodecToolchain> {
  const projectRoot = path.resolve(options.projectRoot ?? ROOT);
  const lock: ImageCodecToolchainLock = imageCodecToolchainLockSchema.parse(
    options.lock ??
      JSON.parse(
        await readFile(
          options.lockFile ??
            path.join(projectRoot, 'runtime/image-codec/toolchain-lock.json'),
          'utf8',
        ),
      ),
  );
  const host = options.host ?? `${process.platform}-${process.arch}`;
  const archive = lock.archives[host];
  if (!archive) throw new Error(`No locked image SDK for ${host}`);
  if (archive.verification !== 'verified')
    throw new Error(`Image SDK ${host} is not verified: ${archive.reason}`);
  if (!/^[a-z0-9]+-[a-z0-9]+$/.test(host))
    throw new Error('Invalid image SDK host');
  const signal = AbortSignal.any([
    ...(options.signal ? [options.signal] : []),
    AbortSignal.timeout(15 * 60_000),
  ]);
  signal.throwIfAborted();
  const node = path.resolve(options.nodeExecutable ?? process.execPath);
  const python = options.pythonExecutable ?? 'python3';
  const baseEnv = executableEnvironment('', '');
  const nodeVersion = (
    await sdkOperation(node, ['--version'], baseEnv, signal)
  ).trim();
  const expectedNode = (
    await readFile(path.join(projectRoot, '.node-version'), 'utf8')
  ).trim();
  if (nodeVersion !== `v${expectedNode}`)
    throw new Error(
      `Image SDK requires project Node ${expectedNode}; received ${nodeVersion}`,
    );
  const pythonVersion = (
    await sdkOperation(python, ['--version'], baseEnv, signal)
  ).trim();
  const match = /^Python (\d+)\.(\d+)\.\d+/.exec(pythonVersion);
  if (
    !match ||
    Number(match[1]) < 3 ||
    (Number(match[1]) === 3 && Number(match[2]) < 10)
  )
    throw new Error('Image SDK requires Python 3.10 or later');
  const cacheRoot = path.resolve(
    options.cacheRoot ??
      path.join(projectRoot, 'runtime/image-codec/.local/toolchains'),
  );
  await mkdir(cacheRoot, { recursive: true });
  const key = `${host}-${archive.sha256}`;
  const directory = path.join(cacheRoot, key);
  const release = await lockfile.lock(directory, {
    realpath: false,
    retries: 0,
    stale: 60_000,
    update: 10_000,
  });
  let temporary: string | undefined;
  try {
    signal.throwIfAborted();
    let installed = false;
    try {
      installed = (await lstat(directory)).isDirectory();
    } catch (error) {
      if (!(
        error instanceof Error &&
        'code' in error &&
        error.code === 'ENOENT'
      ))
        throw error;
    }
    if (installed) {
      let record: Installation;
      try {
        record = installationSchema.parse(
          JSON.parse(
            await readFile(path.join(directory, 'installation.json'), 'utf8'),
          ),
        );
      } catch (cause) {
        throw new Error('Image SDK installation marker is missing or invalid', {
          cause,
        });
      }
      if (record.host !== host || record.archiveSha256 !== archive.sha256)
        throw new Error('Image SDK cache identity mismatch');
      // The verified local installation is trusted. Reuse checks its identity and executable versions,
      // rather than reading and hashing the entire expanded SDK on every build.
    } else {
      temporary = await mkdtemp(path.join(cacheRoot, `.${key}-`));
      const archiveFile = options.archiveFile
        ? path.resolve(options.archiveFile)
        : path.join(temporary, 'archive.tar.xz');
      if (options.archiveFile) {
        const checked = await hashFile(archiveFile, signal);
        if (checked.size !== archive.size || checked.sha256 !== archive.sha256)
          throw new Error('Image SDK archive size or SHA-256 mismatch');
      } else await downloadArchive(archive, archiveFile, signal);
      await mkdir(path.join(temporary, 'sdk'));
      await sdkOperation(
        '/usr/bin/tar',
        [
          '-xf',
          archiveFile,
          '--strip-components=1',
          '-C',
          path.join(temporary, 'sdk'),
        ],
        baseEnv,
        signal,
      );
      await writeConfiguration(temporary, node);
      await verifyExecutables(temporary, node, python, lock, archive, signal);
      const installation: Installation = {
        schemaVersion: 1,
        host,
        archiveSha256: archive.sha256,
      };
      await writeFileAtomic(
        path.join(temporary, 'installation.json'),
        JSON.stringify(installation) + '\n',
      );
      // Integrity is verified once at the transfer/import boundary; retain only the completed SDK installation.
      if (!options.archiveFile) await rm(archiveFile);
      signal.throwIfAborted();
      await rename(temporary, directory);
      temporary = undefined;
    }
    await writeConfiguration(directory, node);
    const versions = await verifyExecutables(
      directory,
      node,
      python,
      lock,
      archive,
      signal,
    );
    const emConfig = path.join(directory, '.emscripten');
    const cache = path.join(directory, 'emscripten-cache');
    return {
      host,
      directory,
      sdk: path.join(directory, 'sdk'),
      emcc: path.join(directory, 'sdk/emscripten/emcc.py'),
      clang: path.join(directory, 'sdk/bin/clang'),
      wasmOpt: path.join(directory, 'sdk/bin/wasm-opt'),
      emConfig,
      cache,
      node,
      python,
      archiveSha256: archive.sha256,
      versions,
      environment: executableEnvironment(emConfig, cache),
    };
  } finally {
    try {
      if (temporary) await rm(temporary, { recursive: true, force: true });
    } finally {
      await release();
    }
  }
}

export async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      archive: { type: 'string' },
      'cache-root': { type: 'string' },
      python: { type: 'string' },
    },
  });
  const controller = new AbortController();
  const cancel = () =>
    controller.abort(new Error('Image SDK preparation interrupted'));
  process.once('SIGINT', cancel);
  process.once('SIGTERM', cancel);
  try {
    const prepared = await prepareImageCodecToolchain({
      ...(values.archive ? { archiveFile: values.archive } : {}),
      ...(values['cache-root'] ? { cacheRoot: values['cache-root'] } : {}),
      ...(values.python ? { pythonExecutable: values.python } : {}),
      signal: controller.signal,
    });
    // Do not serialize the inherited process environment (it may contain credentials).
    const { environment: _environment, ...summary } = prepared;
    console.log(JSON.stringify(summary, null, 2));
  } finally {
    process.off('SIGINT', cancel);
    process.off('SIGTERM', cancel);
  }
}
