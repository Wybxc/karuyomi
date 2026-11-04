/** Reproducible PNG/JPEG WASM build. Product integration consumes the published manifest separately. */
import { createHash } from 'node:crypto';
import {
  mkdir,
  mkdtemp,
  readFile,
  rename,
  rm,
  stat,
  copyFile,
  realpath,
} from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { execa, ExecaError } from 'execa';
import stableStringify from 'json-stable-stringify';
import lockfile from 'proper-lockfile';
import writeFileAtomic from 'write-file-atomic';
import { z } from 'zod';
import {
  prepareImageCodecToolchain,
  type PreparedImageCodecToolchain,
} from './toolchain.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
const hashSchema = z.string().regex(/^[a-f0-9]{64}$/);
const fileSchema = z
  .object({ size: z.number().int().nonnegative(), sha256: hashSchema })
  .strict();
const sourceSchema = z
  .object({ path: z.string(), commit: z.string().regex(/^[a-f0-9]{40}$/) })
  .strict();
export const imageCodecBuildInputsSchema = z
  .object({
    schemaVersion: z.literal(1),
    toolchain: z
      .object({
        host: z.string(),
        archiveSha256: hashSchema,
        lockSha256: hashSchema,
        node: z.string(),
        python: z.string(),
        cmake: z.string(),
      })
      .strict(),
    sources: z
      .object({ libspng: sourceSchema, libjpeg: sourceSchema })
      .strict(),
    files: z.record(z.string(), fileSchema),
    zlib: z
      .object({
        version: z.literal('1.3.1'),
        sha512: z.string().regex(/^[a-f0-9]{128}$/),
        portSha256: hashSchema,
      })
      .strict(),
    recipe: z
      .object({
        common: z.array(z.string()),
        png: z.array(z.string()),
        jpeg: z.array(z.string()),
        configure: z.array(z.string()),
      })
      .strict(),
  })
  .strict();
export type ImageCodecBuildInputs = z.infer<typeof imageCodecBuildInputsSchema>;
export const imageCodecBuildManifestSchema = z
  .object({
    schemaVersion: z.literal(1),
    identity: hashSchema,
    inputs: imageCodecBuildInputsSchema,
    abi: z.literal('karuyomi-image-strips-v1'),
    artifacts: z.record(z.string(), fileSchema),
    toolchainVersions: z.record(z.string(), z.string()),
  })
  .strict();
export type ImageCodecBuildManifest = z.infer<
  typeof imageCodecBuildManifestSchema
>;
export interface ImageCodecBuildOptions {
  projectRoot?: string;
  outputRoot?: string;
  cacheRoot?: string;
  archiveFile?: string;
  zlibArchive?: string;
  cmake?: string;
  signal?: AbortSignal;
  prepareToolchain?: typeof prepareImageCodecToolchain;
}
export interface BuiltImageCodecs {
  directory: string;
  manifest: ImageCodecBuildManifest;
  reused: boolean;
}

const COMMON = [
  '-O2',
  '-Werror=version-check',
  '-sMODULARIZE=1',
  '-sEXPORT_ES6=1',
  '-sENVIRONMENT=node,web,worker',
  '-sINITIAL_MEMORY=16777216',
  '-sMAXIMUM_MEMORY=33554432',
  '-sALLOW_MEMORY_GROWTH=1',
  '-sFILESYSTEM=0',
  '-sABORTING_MALLOC=0',
  '-sMALLOC=emmalloc',
  '-sASSERTIONS=1',
  '-sEXPORTED_RUNTIME_METHODS=HEAPU8',
  '--no-entry',
];
const PNG = ['-DSPNG_STATIC', '-sUSE_ZLIB=1'];
const JPEG = ['-sSUPPORT_LONGJMP=emscripten'];
const CONFIGURE = [
  '-G',
  'Unix Makefiles',
  '-DCMAKE_BUILD_TYPE=Release',
  '-DCMAKE_C_FLAGS=',
  '-DCMAKE_CXX_FLAGS=',
  '-DCMAKE_CXX_FLAGS_RELEASE=-O2 -DNDEBUG -Werror=version-check',
  '-DCMAKE_EXE_LINKER_FLAGS=',
  '-DCMAKE_EXE_LINKER_FLAGS_RELEASE=',
  '-DCMAKE_SHARED_LINKER_FLAGS=',
  '-DCMAKE_SHARED_LINKER_FLAGS_RELEASE=',
  '-DCMAKE_MODULE_LINKER_FLAGS=',
  '-DCMAKE_MODULE_LINKER_FLAGS_RELEASE=',
  '-DCMAKE_STATIC_LINKER_FLAGS=',
  '-DCMAKE_STATIC_LINKER_FLAGS_RELEASE=',
  '-DENABLE_SHARED=OFF',
  '-DENABLE_STATIC=ON',
  '-DWITH_SIMD=OFF',
  '-DWITH_TURBOJPEG=OFF',
  '-DWITH_TOOLS=OFF',
  '-DWITH_TESTS=OFF',
  '-DWITH_JPEG8=OFF',
  '-DCMAKE_C_FLAGS_RELEASE=-O2 -DNDEBUG -Werror=version-check',
];
const NOTICE_SOURCES = {
  'libspng-LICENSE.txt': 'vendor/libspng/LICENSE',
  'libjpeg-turbo-LICENSE.md': 'vendor/libjpeg-turbo/LICENSE.md',
  'libjpeg-turbo-README.ijg': 'vendor/libjpeg-turbo/README.ijg',
};
const OWN_SOURCES = [
  'runtime/image-codec/codec.h',
  'runtime/image-codec/png.c',
  'runtime/image-codec/jpeg.c',
];

function serialized(value: unknown): string {
  const result = stableStringify(value);
  if (result === undefined)
    throw new Error('Image codec build input must be JSON');
  return result;
}
export function imageCodecBuildIdentity(inputs: ImageCodecBuildInputs): string {
  return createHash('sha256')
    .update(serialized(imageCodecBuildInputsSchema.parse(inputs)))
    .digest('hex');
}
async function digest(file: string) {
  const bytes = await readFile(file);
  return {
    size: bytes.length,
    sha256: createHash('sha256').update(bytes).digest('hex'),
  };
}

/** Compiler/CMake operations own their descendants; logs and credentials never become build inputs. */
async function operation(
  executable: string,
  args: string[],
  env: Record<string, string>,
  signal: AbortSignal,
  cwd: string,
) {
  signal.throwIfAborted();
  const child = execa(executable, args, {
    cwd,
    env,
    extendEnv: false,
    killDescendants: true,
    cancelSignal: signal,
    timeout: 10 * 60_000,
    forceKillAfterDelay: 1000,
    maxBuffer: 4 * 1024 * 1024,
    stdin: 'ignore',
  });
  const cleanup = () => {
    child.kill('SIGKILL');
  };
  child.nodeChildProcess.once('exit', cleanup);
  try {
    const result = await child;
    return result.stdout + '\n' + result.stderr;
  } finally {
    child.nodeChildProcess.off('exit', cleanup);
  }
}

async function sourcePin(
  root: string,
  relative: string,
  env: Record<string, string>,
  signal: AbortSignal,
) {
  const index = (
    await operation(
      'git',
      ['ls-files', '--stage', '--', relative],
      env,
      signal,
      root,
    )
  ).trim();
  const pin = /^160000 ([a-f0-9]{40}) 0\t/.exec(index)?.[1];
  if (!pin)
    throw new Error(
      `Image codec upstream must be a fixed Git submodule: ${relative}`,
    );
  const directory = path.join(root, relative);
  const top = (
    await operation(
      'git',
      ['rev-parse', '--show-toplevel'],
      env,
      signal,
      directory,
    )
  ).trim();
  const head = (
    await operation('git', ['rev-parse', 'HEAD'], env, signal, directory)
  ).trim();
  const dirty = (
    await operation(
      'git',
      ['status', '--porcelain', '--untracked-files=all'],
      env,
      signal,
      directory,
    )
  ).trim();
  if (
    (await realpath(top)) !== (await realpath(directory)) ||
    head !== pin ||
    dirty
  )
    throw new Error(
      `Image codec source differs from its clean pinned submodule: ${relative}`,
    );
  return { path: relative, commit: pin };
}

/** Preserve normal process/network configuration, but give compiler/CMake inputs only the recorded recipe. */
function buildEnvironment(
  environment: Record<string, string>,
): Record<string, string> {
  const result = { ...environment };
  for (const name of Object.keys(result)) {
    if (
      /^(?:CMAKE_.*|CCACHE_.*|DISTCC_.*|BINARYEN_.*|LLVM_.*|CFLAGS|CXXFLAGS|CPPFLAGS|LDFLAGS|ARFLAGS|ASFLAGS|OBJCFLAGS|OBJCXXFLAGS|FFLAGS|FCFLAGS|RCFLAGS|LIBS|CC|CXX|CPP|LD|AR|AS|RANLIB|NM|STRIP|OBJC|OBJCXX|FC|F77|F90|RC|CROSS_COMPILE|CONFIG_SITE|MAKEFLAGS|MFLAGS|GNUMAKEFLAGS|MAKELEVEL|MAKEFILES|MAKEOVERRIDES|MAKE|NINJAFLAGS|DESTDIR|CPATH|C_INCLUDE_PATH|CPLUS_INCLUDE_PATH|OBJC_INCLUDE_PATH|LIBRARY_PATH|COMPILER_PATH|GCC_EXEC_PREFIX|PKG_CONFIG|PKG_CONFIG_PATH|PKG_CONFIG_LIBDIR|PKG_CONFIG_SYSROOT_DIR|EMCC_CFLAGS|EMMAKEN_CFLAGS|EMCC_FORCE_STDLIBS|EMCC_ONLY_FORCED_STDLIBS|EMCC_AUTODEBUG|EMCC_EXTRA_FLAGS|EMCC_JSOPT_MINIFY|CCACHE|SDKROOT|MACOSX_DEPLOYMENT_TARGET|IPHONEOS_DEPLOYMENT_TARGET|ARCHFLAGS|LTOFLAGS)$/.test(
        name,
      )
    )
      delete result[name];
  }
  return result;
}

async function collectInputs(
  root: string,
  toolchain: PreparedImageCodecToolchain,
  cmake: string,
  signal: AbortSignal,
): Promise<ImageCodecBuildInputs> {
  const env = buildEnvironment(toolchain.environment);
  const sources = {
    libspng: await sourcePin(root, 'vendor/libspng', env, signal),
    libjpeg: await sourcePin(root, 'vendor/libjpeg-turbo', env, signal),
  };
  const files: ImageCodecBuildInputs['files'] = {};
  for (const relative of [...OWN_SOURCES, ...Object.values(NOTICE_SOURCES)])
    files[relative] = await digest(path.join(root, relative));
  for (const relative of ['tools/images/build.ts', 'tools/images/toolchain.ts'])
    files[relative] = await digest(path.join(ROOT, relative));
  const port = await readFile(
    path.join(toolchain.sdk, 'emscripten/tools/ports/zlib.py'),
    'utf8',
  );
  const version = /^VERSION = ['"]([^'"]+)['"]/m.exec(port)?.[1];
  const sha512 = /^HASH = ['"]([a-f0-9]{128})['"]/m.exec(port)?.[1];
  if (version !== '1.3.1' || !sha512)
    throw new Error(
      'Official SDK zlib port must lock version 1.3.1 and SHA-512',
    );
  const cmakeOutput = await operation(cmake, ['--version'], env, signal, root);
  const cmakeVersion = /^cmake version (\d+\.\d+\.\d+)/.exec(cmakeOutput)?.[1];
  if (!cmakeVersion)
    throw new Error('Cannot identify the image codec CMake version');
  return {
    schemaVersion: 1,
    toolchain: {
      host: toolchain.host,
      archiveSha256: toolchain.archiveSha256,
      lockSha256: (
        await digest(path.join(root, 'runtime/image-codec/toolchain-lock.json'))
      ).sha256,
      node: toolchain.versions.node,
      python: toolchain.versions.python,
      cmake: cmakeVersion,
    },
    sources,
    files,
    zlib: {
      version,
      sha512,
      portSha256: createHash('sha256').update(port).digest('hex'),
    },
    recipe: { common: COMMON, png: PNG, jpeg: JPEG, configure: CONFIGURE },
  };
}

async function importZlib(
  archive: string,
  cache: string,
  expected: ImageCodecBuildInputs['zlib'],
  env: Record<string, string>,
  signal: AbortSignal,
  root: string,
): Promise<void> {
  if ((await stat(archive)).size > 4 * 1024 * 1024)
    throw new Error('Local zlib archive exceeds its import budget');
  const bytes = await readFile(archive);
  if (
    bytes.length > 4 * 1024 * 1024 ||
    createHash('sha512').update(bytes).digest('hex') !== expected.sha512
  )
    throw new Error(
      'Local zlib archive differs from the official SDK port SHA-512',
    );
  const ports = path.join(cache, 'ports');
  await mkdir(ports, { recursive: true });
  const temporary = await mkdtemp(path.join(ports, '.zlib-'));
  try {
    await operation(
      '/usr/bin/tar',
      ['-xzf', path.resolve(archive), '-C', temporary],
      env,
      signal,
      root,
    );
    await stat(path.join(temporary, `zlib-${expected.version}/README`));
    await writeFileAtomic(
      path.join(temporary, '.emscripten_url'),
      `https://github.com/madler/zlib/archive/refs/tags/v${expected.version}.tar.gz\n`,
    );
    await rm(path.join(ports, 'zlib'), { recursive: true, force: true });
    await rename(temporary, path.join(ports, 'zlib'));
  } finally {
    await rm(temporary, { recursive: true, force: true });
  }
}

async function cachedBuild(
  directory: string,
  inputs: ImageCodecBuildInputs,
  identity: string,
): Promise<ImageCodecBuildManifest> {
  const manifest = imageCodecBuildManifestSchema.parse(
    JSON.parse(
      await readFile(path.join(directory, 'build-manifest.json'), 'utf8'),
    ),
  );
  if (
    manifest.identity !== identity ||
    serialized(manifest.inputs) !== serialized(inputs)
  )
    throw new Error('Image codec build cache identity mismatch');
  for (const name of [
    'png.mjs',
    'png.wasm',
    'jpeg.mjs',
    'jpeg.wasm',
    ...Object.keys(NOTICE_SOURCES).map((name) => `licenses/${name}`),
    'licenses/zlib-README',
  ]) {
    const expected = manifest.artifacts[name];
    if (
      !expected ||
      serialized(await digest(path.join(directory, name))) !==
        serialized(expected)
    )
      throw new Error(
        `Image codec build artifact differs from its manifest: ${name}`,
      );
  }
  return manifest;
}

export async function buildImageCodecs(
  options: ImageCodecBuildOptions = {},
): Promise<BuiltImageCodecs> {
  const root = path.resolve(options.projectRoot ?? ROOT);
  const signal = AbortSignal.any([
    ...(options.signal ? [options.signal] : []),
    AbortSignal.timeout(20 * 60_000),
  ]);
  const toolchain = await (
    options.prepareToolchain ?? prepareImageCodecToolchain
  )({
    projectRoot: root,
    ...(options.archiveFile ? { archiveFile: options.archiveFile } : {}),
    signal,
  });
  const cmake = options.cmake ?? 'cmake';
  const inputs = await collectInputs(root, toolchain, cmake, signal);
  const identity = imageCodecBuildIdentity(inputs);
  const outputRoot = path.resolve(
    options.outputRoot ?? path.join(root, 'runtime/image-codec/.local/build'),
  );
  const cacheRoot = path.resolve(
    options.cacheRoot ??
      path.join(root, 'runtime/image-codec/.local/build-cache'),
  );
  await mkdir(outputRoot, { recursive: true });
  await mkdir(cacheRoot, { recursive: true });
  const directory = path.join(outputRoot, identity);
  const release = await lockfile.lock(path.join(cacheRoot, identity), {
    realpath: false,
    retries: 0,
    stale: 60_000,
    update: 10_000,
  });
  let temporary: string | undefined;
  try {
    try {
      await stat(directory);
      return {
        directory,
        manifest: await cachedBuild(directory, inputs, identity),
        reused: true,
      };
    } catch (error) {
      if (!(
        error instanceof Error &&
        'code' in error &&
        error.code === 'ENOENT'
      ))
        throw error;
      // Only a missing build directory is a cache miss; incomplete existing output must fail.
      try {
        await stat(directory);
        throw new Error('Incomplete image codec build cache');
      } catch (missing) {
        if (!(
          missing instanceof Error &&
          'code' in missing &&
          missing.code === 'ENOENT'
        ))
          throw missing;
      }
    }
    temporary = await mkdtemp(path.join(outputRoot, `.${identity}-`));
    const work = path.join(cacheRoot, identity);
    await mkdir(work, { recursive: true });
    const cache = path.join(work, 'emscripten-cache');
    const env = {
      ...buildEnvironment(toolchain.environment),
      EM_CACHE: cache,
      EM_PORTS: path.join(cache, 'ports'),
    };
    if (options.zlibArchive)
      await importZlib(
        options.zlibArchive,
        cache,
        inputs.zlib,
        env,
        signal,
        root,
      );
    const pngSource = path.join(root, inputs.sources.libspng.path);
    const jpegSource = path.join(root, inputs.sources.libjpeg.path);
    const jpegBuild = path.join(work, 'libjpeg-build');
    const commands = [
      {
        name: 'png',
        executable: toolchain.python,
        args: [
          toolchain.emcc,
          path.join(root, 'runtime/image-codec/png.c'),
          path.join(pngSource, 'spng/spng.c'),
          '-I' + path.join(pngSource, 'spng'),
          ...PNG,
          ...COMMON,
          '-o',
          path.join(temporary, 'png.mjs'),
        ],
      },
      {
        name: 'jpeg-configure',
        executable: toolchain.python,
        args: [
          path.join(toolchain.sdk, 'emscripten/emcmake.py'),
          cmake,
          '-S',
          jpegSource,
          '-B',
          jpegBuild,
          ...CONFIGURE,
        ],
      },
      {
        name: 'jpeg-static',
        executable: cmake,
        args: [
          '--build',
          jpegBuild,
          '--target',
          'jpeg-static',
          '--parallel',
          '2',
        ],
      },
      {
        name: 'jpeg',
        executable: toolchain.python,
        args: [
          toolchain.emcc,
          path.join(root, 'runtime/image-codec/jpeg.c'),
          path.join(jpegBuild, 'libjpeg.a'),
          '-I' + path.join(jpegSource, 'src'),
          '-I' + jpegBuild,
          ...JPEG,
          ...COMMON,
          '-o',
          path.join(temporary, 'jpeg.mjs'),
        ],
      },
    ];
    for (const command of commands) {
      const log = path.join(work, `${command.name}.log`);
      try {
        const output = await operation(
          command.executable,
          command.args,
          env,
          signal,
          root,
        );
        await writeFileAtomic(log, output);
      } catch (error) {
        if (error instanceof ExecaError)
          await writeFileAtomic(
            log,
            String(error.stdout ?? '') + '\n' + String(error.stderr ?? ''),
          );
        throw error;
      }
    }
    if (
      identity !==
      imageCodecBuildIdentity(
        await collectInputs(root, toolchain, cmake, signal),
      )
    )
      throw new Error('Image codec build inputs changed during compilation');
    await mkdir(path.join(temporary, 'licenses'));
    for (const [name, relative] of Object.entries(NOTICE_SOURCES))
      await copyFile(
        path.join(root, relative),
        path.join(temporary, 'licenses', name),
      );
    await copyFile(
      path.join(cache, 'ports/zlib/zlib-1.3.1/README'),
      path.join(temporary, 'licenses/zlib-README'),
    );
    const artifacts: ImageCodecBuildManifest['artifacts'] = {};
    for (const name of [
      'png.mjs',
      'png.wasm',
      'jpeg.mjs',
      'jpeg.wasm',
      ...Object.keys(NOTICE_SOURCES).map((name) => `licenses/${name}`),
      'licenses/zlib-README',
    ]) {
      const file = path.join(temporary, name);
      const info = await stat(file);
      if (!info.isFile() || info.size === 0 || info.size > 16 * 1024 * 1024)
        throw new Error(`Invalid image codec build artifact: ${name}`);
      if (name.endsWith('.wasm'))
        await WebAssembly.compile(new Uint8Array(await readFile(file)));
      artifacts[name] = await digest(file);
    }
    const manifest: ImageCodecBuildManifest = {
      schemaVersion: 1,
      identity,
      inputs,
      abi: 'karuyomi-image-strips-v1',
      artifacts,
      toolchainVersions: toolchain.versions,
    };
    await writeFileAtomic(
      path.join(temporary, 'build-manifest.json'),
      serialized(manifest) + '\n',
    );
    signal.throwIfAborted();
    await rename(temporary, directory);
    temporary = undefined;
    return { directory, manifest, reused: false };
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
      'zlib-archive': { type: 'string' },
      output: { type: 'string' },
      'cache-root': { type: 'string' },
    },
  });
  const controller = new AbortController();
  const cancel = () =>
    controller.abort(new Error('Image codec build interrupted'));
  process.once('SIGINT', cancel);
  process.once('SIGTERM', cancel);
  try {
    const result = await buildImageCodecs({
      ...(values.archive ? { archiveFile: values.archive } : {}),
      ...(values['zlib-archive']
        ? { zlibArchive: values['zlib-archive'] }
        : {}),
      ...(values.output ? { outputRoot: values.output } : {}),
      ...(values['cache-root'] ? { cacheRoot: values['cache-root'] } : {}),
      signal: controller.signal,
    });
    console.log(JSON.stringify(result, null, 2));
  } finally {
    process.off('SIGINT', cancel);
    process.off('SIGTERM', cancel);
  }
}
