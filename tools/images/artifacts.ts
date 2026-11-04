/** Locked, portable codec build dependencies; clients receive Static Assets or bundled bytes. */
import { createHash, randomUUID } from 'node:crypto';
import {
  mkdir,
  mkdtemp,
  readFile,
  rename,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { execa } from 'execa';
import { getStreamAsBuffer } from 'get-stream';
import stableStringify from 'json-stable-stringify';
import lockfile from 'proper-lockfile';
import { create as createTar, list as listTar } from 'tar';
import writeFileAtomic from 'write-file-atomic';
import { z } from 'zod';
import {
  imageCodecBuildIdentity,
  imageCodecBuildManifestSchema,
  type ImageCodecBuildManifest,
} from './build.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const MAX_ARCHIVE_BYTES = 32 * 1024 * 1024;
const MODULES = [
  'png.mjs',
  'png.wasm',
  'jpeg.mjs',
  'jpeg.wasm',
  'encoder.mjs',
  'encoder.wasm',
];
const FILES = [
  ...MODULES,
  'licenses/libspng-LICENSE.txt',
  'licenses/libjpeg-turbo-LICENSE.md',
  'licenses/libjpeg-turbo-README.ijg',
  'licenses/zlib-README',
  'build-manifest.json',
];
const REQUIRED_SOURCES = [
  'runtime/image-codec/codec.h',
  'runtime/image-codec/png.c',
  'runtime/image-codec/jpeg.c',
  'runtime/image-codec/encoder.c',
  'runtime/image-codec/encoder.h',
  'tools/images/build.ts',
  'tools/images/toolchain.ts',
  'runtime/image-codec/toolchain-lock.json',
];
const hashSchema = z.string().regex(/^[a-f0-9]{64}$/);
const fileSchema = z
  .object({
    size: z
      .int()
      .positive()
      .max(16 * 1024 * 1024),
    sha256: hashSchema,
  })
  .strict();
const pinSchema = z
  .object({
    path: z.enum(['vendor/libspng', 'vendor/libjpeg-turbo']),
    commit: z.string().regex(/^[a-f0-9]{40}$/),
  })
  .strict();
export const imageCodecArtifactsLockSchema = z
  .object({
    schemaVersion: z.literal(1),
    archive: z
      .object({
        url: z.url().refine((value) => {
          const url = new URL(value);
          return (
            !url.username &&
            !url.password &&
            (url.protocol === 'https:' ||
              (url.protocol === 'http:' &&
                ['127.0.0.1', 'localhost', '[::1]'].includes(url.hostname)))
          );
        }, 'Codec downloads require HTTPS (HTTP is restricted to local test origins)'),
        size: z.int().positive().max(MAX_ARCHIVE_BYTES),
        sha256: hashSchema,
      })
      .strict(),
    buildIdentity: hashSchema,
    sources: z.object({ libspng: pinSchema, libjpeg: pinSchema }).strict(),
    sourceFiles: z.record(
      z
        .string()
        .regex(
          /^(?:runtime\/image-codec\/[a-z0-9-]+\.(?:c|h|json)|tools\/images\/(?:build|toolchain)\.ts)$/,
        ),
      fileSchema,
    ),
    files: z.record(z.enum(FILES), fileSchema),
  })
  .strict()
  .superRefine((value, context) => {
    if (
      Object.keys(value.files).length !== FILES.length ||
      FILES.some((name) => !value.files[name])
    )
      context.addIssue({
        code: 'custom',
        message:
          'Codec archive must list exactly the generated modules, licenses and manifest',
      });
    if (REQUIRED_SOURCES.some((name) => !value.sourceFiles[name]))
      context.addIssue({
        code: 'custom',
        message: 'Codec lock must identify every maintained compiler input',
      });
  });
export type ImageCodecArtifactsLock = z.infer<
  typeof imageCodecArtifactsLockSchema
>;
export interface PreparedImageCodecArtifacts {
  directory: string;
  manifest: ImageCodecBuildManifest;
  reused: boolean;
}
export interface ImageCodecArtifactsOptions {
  projectRoot?: string;
  cacheRoot?: string;
  archiveFile?: string;
  signal?: AbortSignal;
  tarExecutable?: string;
}
const digest = (bytes: Uint8Array) => ({
  size: bytes.byteLength,
  sha256: createHash('sha256').update(bytes).digest('hex'),
});
const equal = (a: unknown, b: unknown) =>
  stableStringify(a) === stableStringify(b);

async function assertProjectInputs(
  root: string,
  lock: ImageCodecArtifactsLock,
  signal: AbortSignal,
) {
  for (const [name, expected] of Object.entries(lock.sourceFiles)) {
    signal.throwIfAborted();
    if (!equal(digest(await readFile(path.join(root, name))), expected))
      throw new Error(
        'Codec build dependency is stale for maintained input: ' + name,
      );
  }
  for (const source of Object.values(lock.sources)) {
    const result = await execa(
      'git',
      ['ls-files', '--stage', '--', source.path],
      {
        cwd: root,
        stdin: 'ignore',
        timeout: 10_000,
        cancelSignal: signal,
        killDescendants: true,
        maxBuffer: 4096,
      },
    );
    if (result.stdout !== `160000 ${source.commit} 0\t${source.path}`)
      throw new Error(
        'Codec build dependency differs from the indexed upstream: ' +
          source.path,
      );
  }
}
async function validateDirectory(
  directory: string,
  lock: ImageCodecArtifactsLock,
  signal: AbortSignal,
): Promise<ImageCodecBuildManifest> {
  let manifestBytes: Buffer | undefined;
  for (const name of FILES) {
    signal.throwIfAborted();
    const file = path.join(directory, name);
    const info = await stat(file);
    if (!info.isFile() || info.size !== lock.files[name]!.size)
      throw new Error('Codec dependency member size mismatch: ' + name);
    const bytes = await readFile(file);
    if (!equal(digest(bytes), lock.files[name]))
      throw new Error('Codec dependency member digest mismatch: ' + name);
    if (name === 'build-manifest.json') manifestBytes = bytes;
  }
  if (!manifestBytes) throw new Error('Codec dependency manifest is missing');
  const manifest = imageCodecBuildManifestSchema.parse(
    JSON.parse(manifestBytes.toString('utf8')),
  );
  if (
    manifest.identity !== lock.buildIdentity ||
    imageCodecBuildIdentity(manifest.inputs) !== lock.buildIdentity ||
    !equal(manifest.inputs.sources, lock.sources)
  )
    throw new Error('Codec dependency build identity is inconsistent');
  if (
    !equal(
      Object.keys(manifest.artifacts).sort(),
      FILES.filter((name) => name !== 'build-manifest.json').sort(),
    )
  )
    throw new Error('Codec dependency manifest has an unexpected artifact set');
  for (const [name, expected] of Object.entries(manifest.artifacts))
    if (!equal(expected, lock.files[name]))
      throw new Error(
        'Codec dependency manifest differs from its lock: ' + name,
      );
  const maintained = Object.fromEntries(
    Object.entries(manifest.inputs.files).filter(
      ([name]) => !name.startsWith('vendor/'),
    ),
  );
  const expectedMaintained = Object.fromEntries(
    Object.entries(lock.sourceFiles).filter(
      ([name]) => name !== 'runtime/image-codec/toolchain-lock.json',
    ),
  );
  if (
    !equal(maintained, expectedMaintained) ||
    manifest.inputs.toolchain.lockSha256 !==
      lock.sourceFiles['runtime/image-codec/toolchain-lock.json']!.sha256
  )
    throw new Error('Codec dependency compiler inputs differ from its lock');
  return manifest;
}
async function archiveBytes(
  lock: ImageCodecArtifactsLock,
  archiveFile: string | undefined,
  signal: AbortSignal,
): Promise<Buffer> {
  let bytes: Buffer;
  if (archiveFile) {
    if ((await stat(archiveFile)).size !== lock.archive.size)
      throw new Error('Codec archive import size mismatch');
    bytes = await readFile(archiveFile, { signal });
  } else {
    const response = await fetch(lock.archive.url, {
      signal,
      credentials: 'omit',
    });
    if (!response.ok || !response.body) {
      await response.body?.cancel();
      throw new Error(
        'Codec dependency download failed: HTTP ' + response.status,
      );
    }
    bytes = await getStreamAsBuffer(response.body, {
      maxBuffer: lock.archive.size,
    });
  }
  signal.throwIfAborted();
  if (
    !equal(digest(bytes), {
      size: lock.archive.size,
      sha256: lock.archive.sha256,
    })
  )
    throw new Error('Codec archive transfer integrity mismatch');
  return bytes;
}

/** Listing is synchronous and writes nothing; a rejected member can never leave an active unpacker. */
function validateArchiveMembers(
  archive: string,
  lock: ImageCodecArtifactsLock,
  signal: AbortSignal,
): void {
  signal.throwIfAborted();
  const seen = new Set<string>();
  let invalidEntry: Error | undefined;
  listTar({
    file: archive,
    sync: true,
    strict: true,
    onReadEntry: (entry) => {
      const expected = lock.files[entry.path];
      if (
        !expected ||
        entry.type !== 'File' ||
        seen.has(entry.path) ||
        entry.size !== expected.size
      ) {
        invalidEntry ??= new Error(
          'Unexpected codec archive entry: ' + entry.path,
        );
        return;
      }
      seen.add(entry.path);
    },
  });
  signal.throwIfAborted();
  if (invalidEntry) throw invalidEntry;
  if (seen.size !== FILES.length)
    throw new Error('Codec dependency archive is incomplete');
}

/** Execa owns the extractor and all descendants until its stdio is closed. */
async function extractArchive(
  executable: string,
  archive: string,
  payload: string,
  signal: AbortSignal,
): Promise<void> {
  signal.throwIfAborted();
  const child = execa(executable, ['-xzf', archive, '-C', payload], {
    stdin: 'ignore',
    env: { TAR_OPTIONS: undefined },
    cancelSignal: signal,
    timeout: 120_000,
    killDescendants: true,
    forceKillAfterDelay: 1000,
    maxBuffer: 1024 * 1024,
  });
  // The immediate extractor can exit while a descendant still owns stdout.
  const stopDescendants = () => {
    child.kill('SIGKILL');
  };
  child.nodeChildProcess.once('exit', stopDescendants);
  try {
    await child;
  } finally {
    child.nodeChildProcess.off('exit', stopDescendants);
  }
}

/** Imports once at the archive boundary, then verifies cache members against the pinned build. */
export async function prepareImageCodecArtifacts(
  options: ImageCodecArtifactsOptions = {},
): Promise<PreparedImageCodecArtifacts> {
  const root = path.resolve(options.projectRoot ?? ROOT);
  const signal = AbortSignal.any([
    ...(options.signal ? [options.signal] : []),
    AbortSignal.timeout(120_000),
  ]);
  const lock = imageCodecArtifactsLockSchema.parse(
    JSON.parse(
      await readFile(
        path.join(root, 'runtime/image-codec/artifacts-lock.json'),
        'utf8',
      ),
    ),
  );
  await assertProjectInputs(root, lock, signal);
  const cache = path.resolve(
    options.cacheRoot ??
      path.join(root, 'runtime/image-codec/.local/artifacts'),
  );
  await mkdir(cache, { recursive: true });
  const directory = path.join(cache, lock.archive.sha256);
  const release = await lockfile.lock(directory, {
    realpath: false,
    retries: 0,
    stale: 60_000,
    update: 10_000,
  });
  let temporary: string | undefined;
  try {
    let exists = true;
    try {
      await stat(directory);
    } catch (error) {
      if (error instanceof Error && 'code' in error && error.code === 'ENOENT')
        exists = false;
      else throw error;
    }
    if (exists) {
      const manifest = await validateDirectory(directory, lock, signal);
      await assertProjectInputs(root, lock, signal);
      return { directory, manifest, reused: true };
    }
    const bytes = await archiveBytes(lock, options.archiveFile, signal);
    temporary = await mkdtemp(path.join(cache, '.stage-'));
    const archive = path.join(temporary, 'archive.tar.gz');
    const payload = path.join(temporary, 'payload');
    await mkdir(payload);
    await writeFile(archive, bytes);
    validateArchiveMembers(archive, lock, signal);
    await extractArchive(
      options.tarExecutable ?? 'tar',
      archive,
      payload,
      signal,
    );
    const manifest = await validateDirectory(payload, lock, signal);
    await assertProjectInputs(root, lock, signal);
    signal.throwIfAborted();
    await rename(payload, directory);
    return { directory, manifest, reused: false };
  } finally {
    try {
      if (temporary) await rm(temporary, { recursive: true, force: true });
    } finally {
      await release();
    }
  }
}

/** Packages a locally verified build as a locked, platform-neutral build dependency. */
export async function packageImageCodecArtifacts(options: {
  buildDirectory: string;
  archiveFile: string;
  url: string;
  projectRoot?: string;
  lockFile?: string;
  signal?: AbortSignal;
}) {
  const root = path.resolve(options.projectRoot ?? ROOT);
  const signal = options.signal ?? new AbortController().signal;
  const directory = path.resolve(options.buildDirectory);
  const manifest = imageCodecBuildManifestSchema.parse(
    JSON.parse(
      await readFile(path.join(directory, 'build-manifest.json'), 'utf8'),
    ),
  );
  const files: ImageCodecArtifactsLock['files'] = {};
  for (const name of FILES)
    files[name] = digest(await readFile(path.join(directory, name)));
  const sourceFiles = {
    ...Object.fromEntries(
      Object.entries(manifest.inputs.files).filter(
        ([name]) => !name.startsWith('vendor/'),
      ),
    ),
    'runtime/image-codec/toolchain-lock.json': digest(
      await readFile(
        path.join(root, 'runtime/image-codec/toolchain-lock.json'),
      ),
    ),
  };
  const lock = imageCodecArtifactsLockSchema.parse({
    schemaVersion: 1,
    archive: { url: options.url, size: 1, sha256: '0'.repeat(64) },
    buildIdentity: manifest.identity,
    sources: manifest.inputs.sources,
    sourceFiles,
    files,
  });
  await assertProjectInputs(root, lock, signal);
  await validateDirectory(directory, lock, signal);
  const archiveFile = path.resolve(options.archiveFile);
  await mkdir(path.dirname(archiveFile), { recursive: true });
  const temporary = archiveFile + '.' + randomUUID() + '.tmp';
  try {
    await createTar(
      {
        file: temporary,
        cwd: directory,
        gzip: true,
        portable: true,
        mtime: new Date(0),
        strict: true,
      },
      [...FILES].sort(),
    );
    signal.throwIfAborted();
    const info = await stat(temporary);
    if (info.size > MAX_ARCHIVE_BYTES)
      throw new Error('Codec dependency archive exceeds its budget');
    const archive = await readFile(temporary);
    lock.archive = { url: options.url, ...digest(archive) };
    imageCodecArtifactsLockSchema.parse(lock);
    await assertProjectInputs(root, lock, signal);
    await rename(temporary, archiveFile);
    await writeFileAtomic(
      path.resolve(
        options.lockFile ??
          path.join(root, 'runtime/image-codec/artifacts-lock.json'),
      ),
      JSON.stringify(lock, null, 2) + '\n',
    );
    return { archiveFile, lock };
  } finally {
    await rm(temporary, { force: true });
  }
}

export async function prepareMain() {
  const { values } = parseArgs({
    options: { archive: { type: 'string' }, 'cache-root': { type: 'string' } },
  });
  const controller = new AbortController();
  const cancel = () =>
    controller.abort(new Error('Codec dependency preparation interrupted'));
  process.once('SIGINT', cancel);
  process.once('SIGTERM', cancel);
  try {
    console.log(
      JSON.stringify(
        await prepareImageCodecArtifacts({
          ...(values.archive ? { archiveFile: values.archive } : {}),
          ...(values['cache-root'] ? { cacheRoot: values['cache-root'] } : {}),
          signal: controller.signal,
        }),
        null,
        2,
      ),
    );
  } finally {
    process.off('SIGINT', cancel);
    process.off('SIGTERM', cancel);
  }
}
export async function packageMain() {
  const { values } = parseArgs({
    options: {
      build: { type: 'string' },
      archive: { type: 'string' },
      url: { type: 'string' },
      lock: { type: 'string' },
    },
  });
  if (!values.build || !values.archive || !values.url)
    throw new Error(
      'Usage: package-image-codec-artifacts --build DIR --archive FILE --url PUBLIC_HTTPS_URL [--lock FILE]',
    );
  console.log(
    JSON.stringify(
      await packageImageCodecArtifacts({
        buildDirectory: values.build,
        archiveFile: values.archive,
        url: values.url,
        ...(values.lock ? { lockFile: values.lock } : {}),
      }),
      null,
      2,
    ),
  );
}
