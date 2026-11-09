import { createHash } from 'node:crypto';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath } from 'node:url';
import { execa } from 'execa';
import lockfile from 'proper-lockfile';
import { x as extractTar } from 'tar';
import xzDecompress from 'xz-decompress';
import locked from '../../runtime/teavm/toolchain/webp/toolchain.lock.json' with { type: 'json' };

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const TOOLCHAIN = path.join(ROOT, 'runtime/teavm/toolchain/webp');
const SOURCE = path.join(ROOT, 'vendor/libwebp');
const CACHE = path.join(ROOT, 'runtime/teavm/.local/webp');
const WASM = path.join(CACHE, 'encoder.wasm');
const RECEIPT = path.join(CACHE, 'encoder.inputs.sha256');
const INITIAL_MEMORY = 2 * 1024 * 1024;
const MAX_MEMORY = 192 * 1024 * 1024;
const EXPORTS = ['webp_alloc', 'webp_free', 'webp_encode'];

interface ZigArchive {
  url: string;
  size: number;
  sha256: string;
}
interface EncoderLock {
  libwebp: { version: string; commit: string };
  zig: { version: string; archives: Record<string, ZigArchive> };
  artifact: { size: number; sha256: string };
}
const LOCK: EncoderLock = locked;

export interface WebpEncoderSource {
  version: string;
  upstreamCommit: string;
  compilerVersion: string;
  sha256: string;
  size: number;
}

function sha256(bytes: Uint8Array): string {
  return createHash('sha256').update(bytes).digest('hex');
}

function inputFingerprint(): string {
  const hash = createHash('sha256');
  for (const file of [
    fileURLToPath(import.meta.url),
    path.join(TOOLCHAIN, 'toolchain.lock.json'),
    path.join(TOOLCHAIN, 'encoder.c'),
  ]) {
    hash.update(sha256(readFileSync(file)));
  }
  return hash.digest('hex');
}

export function readWebpEncoderSource(): WebpEncoderSource {
  return {
    version: LOCK.libwebp.version,
    upstreamCommit: LOCK.libwebp.commit,
    compilerVersion: LOCK.zig.version,
    sha256: LOCK.artifact.sha256,
    size: LOCK.artifact.size,
  };
}

export function readPreparedWebpEncoder(): {
  bytes: Buffer;
  source: WebpEncoderSource;
} {
  if (!existsSync(RECEIPT)) {
    throw new Error('WebP encoder not prepared; run pnpm webp:prepare');
  }
  if (readFileSync(RECEIPT, 'utf8').trimEnd() !== inputFingerprint()) {
    throw new Error('WebP encoder inputs changed; run pnpm webp:prepare');
  }
  const source = readWebpEncoderSource();
  const bytes = readFileSync(WASM);
  if (bytes.length !== source.size || sha256(bytes) !== source.sha256) {
    throw new Error('WebP encoder integrity mismatch; run pnpm webp:prepare');
  }
  return { bytes, source };
}

async function verifyLibwebpCheckout(): Promise<void> {
  const cwd = SOURCE;
  const { stdout: commit } = await execa('git', ['rev-parse', 'HEAD'], { cwd });
  if (
    commit !== LOCK.libwebp.commit ||
    !existsSync(path.join(cwd, 'src/webp/encode.h'))
  ) {
    throw new Error(
      `Initialize vendor/libwebp at locked revision ${LOCK.libwebp.commit}`,
    );
  }
  const { stdout: changes } = await execa(
    'git',
    ['status', '--porcelain', '--untracked-files=all'],
    { cwd },
  );
  if (changes)
    throw new Error('Build WebP encoder from a clean vendor/libwebp checkout');
}

async function prepareZig(staging: string): Promise<string> {
  const platform = `${process.platform}-${process.arch}`;
  const archive = LOCK.zig.archives[platform];
  if (!archive) throw new Error(`No pinned Zig compiler for ${platform}`);
  const dir = path.join(
    CACHE,
    `zig-${LOCK.zig.version}-${platform}-${archive.sha256}`,
  );
  const executable = path.join(dir, 'zig');
  if (existsSync(executable)) {
    try {
      if ((await execa(executable, ['version'])).stdout === LOCK.zig.version) {
        return executable;
      }
    } catch {
      // Reinstall a damaged compiler directory from the pinned archive.
    }
  }

  const archiveName = path.basename(new URL(archive.url).pathname);
  const archiveFile = path.join(CACHE, 'downloads', archiveName);
  const data = existsSync(archiveFile)
    ? readFileSync(archiveFile)
    : await downloadZigArchive(archive);
  if (data.length !== archive.size || sha256(data) !== archive.sha256) {
    throw new Error(`Zig archive checksum/size mismatch for ${platform}`);
  }
  if (!existsSync(archiveFile)) {
    const downloaded = path.join(staging, archiveName);
    writeFileSync(downloaded, data);
    mkdirSync(path.dirname(archiveFile), { recursive: true });
    renameSync(downloaded, archiveFile);
  }
  let offset = 0;
  const compressed = new ReadableStream<Uint8Array>({
    pull(controller) {
      if (offset === data.length) {
        controller.close();
      } else {
        const end = Math.min(data.length, offset + 64 * 1024);
        controller.enqueue(data.subarray(offset, end));
        offset = end;
      }
    },
  });
  const compiler = path.join(staging, 'zig');
  mkdirSync(compiler);
  await pipeline(
    new xzDecompress.XzReadableStream(compressed),
    async function* (chunks: AsyncIterable<Uint8Array>) {
      // tar's streaming parser expects Node Buffer methods on every chunk.
      for await (const chunk of chunks) {
        yield Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength);
      }
    },
    extractTar({ cwd: compiler, strip: 1, strict: true, preserveOwner: false }),
  );
  const { stdout: version } = await execa(path.join(compiler, 'zig'), [
    'version',
  ]);
  if (version !== LOCK.zig.version)
    throw new Error(`Unexpected Zig version: ${version}`);
  rmSync(dir, { force: true, recursive: true });
  renameSync(compiler, dir);
  return executable;
}

async function downloadZigArchive(archive: ZigArchive): Promise<Buffer> {
  const response = await fetch(archive.url, {
    signal: AbortSignal.timeout(300_000),
  });
  if (!response.ok || response.body === null) {
    throw new Error(`Zig download failed (HTTP ${response.status})`);
  }
  const data = Buffer.alloc(archive.size);
  const reader = response.body.getReader();
  let offset = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value.length > data.length - offset) {
        throw new Error('Zig download exceeds locked archive size');
      }
      data.set(value, offset);
      offset += value.length;
    }
  } finally {
    await reader.cancel();
  }
  return data.subarray(0, offset);
}

function cSources(dir: string): string[] {
  return readdirSync(path.join(SOURCE, dir))
    .filter((file) => file.endsWith('.c'))
    .sort()
    .map((file) => `${dir}/${file}`);
}

function verifyEncoderAbi(bytes: Buffer<ArrayBuffer>): void {
  const module = new WebAssembly.Module(bytes);
  const imports = WebAssembly.Module.imports(module);
  if (
    imports.length !== 1 ||
    !imports.some(
      (entry) =>
        entry.module === 'env' &&
        entry.name === 'memory' &&
        entry.kind === 'memory',
    )
  ) {
    throw new Error('Unexpected WebP encoder imports');
  }
  const expected = new Set(['_initialize', ...EXPORTS]);
  const exports = WebAssembly.Module.exports(module);
  if (
    exports.length !== expected.size ||
    exports.some(
      (entry) => entry.kind !== 'function' || !expected.has(entry.name),
    )
  ) {
    throw new Error('Unexpected WebP encoder exports');
  }
}

async function buildEncoder(zig: string, output: string): Promise<void> {
  const dsp = [
    'alpha_processing',
    'cpu',
    'dec',
    'dec_clip_tables',
    'filters',
    'lossless',
    'rescaler',
    'upsampling',
    'yuv',
    'cost',
    'enc',
    'lossless_enc',
    'ssim',
  ];
  await execa(
    zig,
    [
      'cc',
      '-target',
      'wasm32-wasi',
      '-mexec-model=reactor',
      '-Oz',
      '-flto',
      '-DNDEBUG',
      '-I.',
      `-ffile-prefix-map=${ROOT}=.`,
      '-fvisibility=hidden',
      '-ffunction-sections',
      '-fdata-sections',
      '-Wl,--gc-sections',
      '-Wl,--strip-all',
      '-Wl,-z,stack-size=524288',
      '-Wl,--import-memory',
      `-Wl,--initial-memory=${INITIAL_MEMORY}`,
      `-Wl,--max-memory=${MAX_MEMORY}`,
      ...EXPORTS.map((name) => `-Wl,--export=${name}`),
      path.join(TOOLCHAIN, 'encoder.c'),
      ...cSources('src/enc'),
      ...dsp.map((name) => `src/dsp/${name}.c`),
      ...cSources('src/utils'),
      ...cSources('sharpyuv'),
      '-o',
      output,
    ],
    {
      cwd: SOURCE,
      env: {
        ZIG_GLOBAL_CACHE_DIR: path.join(CACHE, 'zig-cache'),
        ZIG_LOCAL_CACHE_DIR: path.join(CACHE, 'zig-local-cache'),
      },
      stdio: ['ignore', 'inherit', 'inherit'],
    },
  );
}

export async function prepareWebpEncoder(): Promise<WebpEncoderSource> {
  mkdirSync(CACHE, { recursive: true });
  const release = await lockfile.lock(CACHE, {
    retries: { retries: 180, minTimeout: 1_000, maxTimeout: 1_000 },
  });
  try {
    await verifyLibwebpCheckout();
    try {
      return readPreparedWebpEncoder().source;
    } catch {
      // The local artifact is missing, stale, or corrupt. Rebuild it below.
    }
    const staging = mkdtempSync(path.join(CACHE, 'building-'));
    try {
      const inputs = inputFingerprint();
      const zig = await prepareZig(staging);
      const output = path.join(staging, 'encoder.wasm');
      await buildEncoder(zig, output);
      const bytes = readFileSync(output);
      verifyEncoderAbi(bytes);
      const source = readWebpEncoderSource();
      const digest = sha256(bytes);
      if (bytes.length !== source.size || digest !== source.sha256) {
        throw new Error(
          `Built WebP encoder differs from the pinned Wasm artifact (${bytes.length} B, SHA-256 ${digest})`,
        );
      }
      if (inputs !== inputFingerprint()) {
        throw new Error('WebP encoder inputs changed during the build');
      }
      const receipt = path.join(staging, path.basename(RECEIPT));
      writeFileSync(receipt, inputs + '\n');
      renameSync(output, WASM);
      renameSync(receipt, RECEIPT);
      return source;
    } finally {
      rmSync(staging, { force: true, recursive: true });
    }
  } finally {
    await release();
  }
}
