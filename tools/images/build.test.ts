import assert from 'node:assert/strict';
import {
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from 'node:fs/promises';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { setTimeout as delay } from 'node:timers/promises';
import test, { type TestContext } from 'node:test';
import { execa } from 'execa';
import {
  buildImageCodecs,
  imageCodecBuildIdentity,
  type ImageCodecBuildOptions,
} from './build.ts';
import type { PreparedImageCodecToolchain } from './toolchain.ts';

async function fixture(context: TestContext) {
  const root = await mkdtemp(path.join(tmpdir(), 'karuyomi-codec-build-'));
  context.after(() => rm(root, { recursive: true, force: true }));
  const git = async (cwd: string, args: string[]) =>
    execa('git', args, { cwd });
  await git(root, ['init', '-q']);
  for (const name of ['libspng', 'libjpeg-turbo']) {
    const source = path.join(root, 'original', name);
    await mkdir(source, { recursive: true });
    await git(source, ['init', '-q']);
    for (const file of name === 'libspng'
      ? ['LICENSE', 'spng/spng.c']
      : ['LICENSE.md', 'README.ijg', 'src/jpeglib.h']) {
      await mkdir(path.dirname(path.join(source, file)), { recursive: true });
      await writeFile(path.join(source, file), `fixture ${name} ${file}\n`);
    }
    await git(source, ['add', '.']);
    await git(source, [
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.invalid',
      'commit',
      '-qm',
      'fixture',
    ]);
    await git(root, [
      '-c',
      'protocol.file.allow=always',
      'submodule',
      'add',
      '--quiet',
      source,
      `vendor/${name}`,
    ]);
  }
  await mkdir(path.join(root, 'runtime/image-codec'), { recursive: true });
  for (const file of ['codec.h', 'png.c', 'jpeg.c'])
    await writeFile(
      path.join(root, 'runtime/image-codec', file),
      `fixture ${file}\n`,
    );
  await writeFile(
    path.join(root, 'runtime/image-codec/toolchain-lock.json'),
    '{"fixture":1}\n',
  );
  const sdk = path.join(root, 'sdk');
  await mkdir(path.join(sdk, 'emscripten/tools/ports'), { recursive: true });
  await writeFile(
    path.join(sdk, 'emscripten/tools/ports/zlib.py'),
    `VERSION = '1.3.1'\nHASH = '${'a'.repeat(128)}'\n`,
  );
  const compiler = path.join(root, 'fake-compiler.mjs');
  const ready = path.join(root, 'ready.json');
  await writeFile(
    compiler,
    `import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
const args=process.argv.slice(2);
if(process.env.CODEC_FIXTURE_ASSERT_ENVIRONMENT==='1') {
 for(const key of ['CFLAGS','CXXFLAGS','CPPFLAGS','LDFLAGS','CMAKE_TOOLCHAIN_FILE','CMAKE_GENERATOR','CMAKE_PREFIX_PATH','CC','CXX','EMCC_CFLAGS','CPATH','MAKEFLAGS']) {
  if(process.env[key]!==undefined) throw new Error('Ambient compiler input leaked: '+key);
 }
 if(process.env.PATH!==process.env.CODEC_EXPECT_PATH) throw new Error('Normal PATH changed');
 if(process.env.HTTP_PROXY!=='http://fixture.invalid:3128'||process.env.HTTPS_PROXY!=='http://fixture.invalid:3128') throw new Error('Normal proxy environment changed');
}

const output=args[args.indexOf('-o')+1];
if(process.env.CODEC_FIXTURE_MODE==='cancel') {
 const child=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{stdio:'inherit'});
 fs.writeFileSync(${JSON.stringify(ready)},JSON.stringify({parent:process.pid,child:child.pid}));
 await new Promise(resolve=>setTimeout(resolve,120000));
}
if(output.endsWith('jpeg.mjs') && process.env.CODEC_FIXTURE_MODE==='failure') process.exit(7);
if(output.endsWith('jpeg.mjs') && process.env.CODEC_FIXTURE_MODE==='changed') fs.appendFileSync(path.join(path.dirname(args[0]),'png.c'),'changed');
const ports=path.join(process.env.EM_CACHE,'ports/zlib/zlib-1.3.1');
fs.mkdirSync(ports,{recursive:true});
fs.writeFileSync(path.join(ports,'README'),'fixture zlib notice');
fs.writeFileSync(output,'export default async function createModule() { return {}; }\\n');
fs.writeFileSync(output.replace(/\\.mjs$/,'.wasm'),Buffer.from([0,97,115,109,1,0,0,0]));
`,
  );
  await writeFile(
    path.join(sdk, 'emscripten/emcmake.py'),
    `const args=process.argv.slice(2);
for(const flag of ['-DCMAKE_C_FLAGS=','-DCMAKE_C_FLAGS_RELEASE=-O2 -DNDEBUG -Werror=version-check','-DCMAKE_EXE_LINKER_FLAGS=','-DCMAKE_STATIC_LINKER_FLAGS=']) {
 if(!args.includes(flag)) throw new Error('Missing explicit CMake recipe flag: '+flag);
}
`,
  );
  const cmake = path.join(root, 'cmake.mjs');
  await writeFile(
    cmake,
    "#!/usr/bin/env node\nif(process.argv.includes('--version')) console.log('cmake version 4.4.5');\n",
    { mode: 0o755 },
  );
  let mode = 'success';
  let pythonVersion = 'Fixture interpreter';
  let environmentOverrides: Record<string, string> = {};
  const prepare: NonNullable<
    ImageCodecBuildOptions['prepareToolchain']
  > = async () => {
    const environment = Object.fromEntries(
      Object.entries(process.env).filter(
        (item): item is [string, string] => item[1] !== undefined,
      ),
    );
    const prepared: PreparedImageCodecToolchain = {
      host: 'fixture-host',
      directory: sdk,
      sdk,
      emcc: compiler,
      clang: compiler,
      wasmOpt: compiler,
      emConfig: path.join(root, '.emscripten'),
      cache: path.join(root, 'sdk-cache'),
      node: process.execPath,
      python: process.execPath,
      archiveSha256: 'a'.repeat(64),
      versions: {
        node: process.version,
        python: pythonVersion,
        emcc: 'Fixture compiler',
        clang: 'Fixture clang',
        wasmOpt: 'Fixture wasm-opt',
      },
      environment: {
        ...environment,
        ...environmentOverrides,
        CODEC_FIXTURE_MODE: mode,
      },
    };
    return prepared;
  };
  const outputRoot = path.join(root, 'output');
  const cacheRoot = path.join(root, 'cache');
  const options = {
    projectRoot: root,
    outputRoot,
    cacheRoot,
    cmake,
    prepareToolchain: prepare,
  };
  return {
    root,
    ready,
    options,
    outputRoot,
    cacheRoot,
    setPythonVersion: (value: string) => {
      pythonVersion = value;
    },
    setEnvironment: (value: Record<string, string>) => {
      environmentOverrides = value;
    },
    setMode: (value: string) => {
      mode = value;
    },
  };
}

test('a complete build records pinned sources, bounded parameters and notices, then reuses the same output', async (context) => {
  const f = await fixture(context);
  const result = await buildImageCodecs(f.options);
  assert.equal(result.reused, false);
  assert.equal(
    result.manifest.identity,
    imageCodecBuildIdentity(result.manifest.inputs),
  );
  assert.match(result.manifest.inputs.sources.libspng.commit, /^[a-f0-9]{40}$/);
  assert.ok(
    result.manifest.inputs.recipe.common.includes('-sMAXIMUM_MEMORY=33554432'),
  );
  assert.ok(
    !result.manifest.inputs.recipe.common.some((value) =>
      /pthread|SHARED_MEMORY|emit-tsd/.test(value),
    ),
  );
  assert.equal(Object.keys(result.manifest.artifacts).length, 8);
  assert.ok(result.manifest.artifacts['licenses/zlib-README']);
  f.setMode('failure');
  const second = await buildImageCodecs(f.options);
  assert.equal(second.reused, true);
  assert.equal(second.directory, result.directory);
  assert.deepEqual(await readdir(f.outputRoot), [
    path.basename(result.directory),
  ]);
});

test('source edits, SDK lock changes and staged upstream pins select new build identities', async (context) => {
  const f = await fixture(context);
  const first = await buildImageCodecs(f.options);
  await writeFile(
    path.join(f.root, 'runtime/image-codec/png.c'),
    'changed project adapter\n',
  );
  const sourceChanged = await buildImageCodecs(f.options);
  assert.notEqual(sourceChanged.manifest.identity, first.manifest.identity);
  await writeFile(
    path.join(f.root, 'runtime/image-codec/toolchain-lock.json'),
    '{"fixture":2}\n',
  );
  const sdkChanged = await buildImageCodecs(f.options);
  assert.notEqual(
    sdkChanged.manifest.identity,
    sourceChanged.manifest.identity,
  );
  await execa('git', [
    '-C',
    path.join(f.root, 'vendor/libjpeg-turbo'),
    '-c',
    'user.name=Fixture',
    '-c',
    'user.email=fixture@example.invalid',
    'commit',
    '--allow-empty',
    '-qm',
    'new pinned source',
  ]);
  await execa('git', ['-C', f.root, 'add', 'vendor/libjpeg-turbo']);
  const upstreamChanged = await buildImageCodecs(f.options);
  assert.notEqual(
    upstreamChanged.manifest.identity,
    sdkChanged.manifest.identity,
  );
  assert.notEqual(
    upstreamChanged.manifest.inputs.sources.libjpeg.commit,
    sdkChanged.manifest.inputs.sources.libjpeg.commit,
  );
  assert.equal(upstreamChanged.reused, false);
});

test('a dirty upstream is rejected before publishing or compiling', async (context) => {
  const f = await fixture(context);
  await writeFile(
    path.join(f.root, 'vendor/libspng/spng/spng.c'),
    'edited upstream',
  );
  await assert.rejects(buildImageCodecs(f.options), /clean pinned submodule/);
  await assert.rejects(readdir(f.outputRoot), { code: 'ENOENT' });
});

test('a same-size modified cached output fails integrity verification instead of being silently reused', async (context) => {
  const f = await fixture(context);
  const first = await buildImageCodecs(f.options);
  const file = path.join(first.directory, 'png.mjs');
  const bytes = await readFile(file);
  bytes[0] = (bytes[0] ?? 0) ^ 1;
  await writeFile(file, bytes);
  await assert.rejects(
    buildImageCodecs(f.options),
    /artifact differs from its manifest/,
  );
  assert.deepEqual(await readdir(f.outputRoot), [
    path.basename(first.directory),
  ]);
});

for (const mode of ['failure', 'changed'] as const) {
  test(`${mode} during compilation cannot publish partial outputs or replace another build`, async (context) => {
    const f = await fixture(context);
    await mkdir(path.join(f.outputRoot, 'previous'), { recursive: true });
    await writeFile(
      path.join(f.outputRoot, 'previous/sentinel'),
      'previous complete output',
    );
    f.setMode(mode);
    await assert.rejects(
      buildImageCodecs(f.options),
      mode === 'changed' ? /inputs changed during compilation/ : /exit code 7/,
    );
    assert.deepEqual(await readdir(f.outputRoot), ['previous']);
    assert.equal(
      await readFile(path.join(f.outputRoot, 'previous/sentinel'), 'utf8'),
      'previous complete output',
    );
    assert.ok(
      !(await readdir(f.cacheRoot)).some((name) => name.endsWith('.lock')),
    );
  });
}

test('cancellation stops a real compiler descendant before releasing the build lock and temporary output', async (context) => {
  const f = await fixture(context);
  f.setMode('cancel');
  const controller = new AbortController();
  context.after(() => controller.abort());
  const expected = assert.rejects(
    buildImageCodecs({ ...f.options, signal: controller.signal }),
    /canceled|cancel/i,
  );
  let child: number | undefined;
  for (let i = 0; i < 300; i++) {
    try {
      const input: unknown = JSON.parse(await readFile(f.ready, 'utf8'));
      assert.ok(
        typeof input === 'object' &&
          input !== null &&
          'child' in input &&
          typeof input.child === 'number',
      );
      child = input.child;
      break;
    } catch {
      await delay(10);
    }
  }
  assert.ok(child);
  controller.abort(new Error('cancel formal image codec build'));
  await expected;
  let alive = true;
  for (let i = 0; i < 100 && alive; i++) {
    try {
      process.kill(child, 0);
      await delay(10);
    } catch (error) {
      assert.ok(
        error instanceof Error && 'code' in error && error.code === 'ESRCH',
      );
      alive = false;
    }
  }
  assert.equal(alive, false);
  assert.deepEqual(await readdir(f.outputRoot), []);
  assert.ok(
    !(await readdir(f.cacheRoot)).some((name) => name.endsWith('.lock')),
  );
});

test('an upstream HEAD that differs from the staged submodule pin is rejected', async (context) => {
  const f = await fixture(context);
  await execa('git', [
    '-C',
    path.join(f.root, 'vendor/libspng'),
    '-c',
    'user.name=Fixture',
    '-c',
    'user.email=fixture@example.invalid',
    'commit',
    '--allow-empty',
    '-qm',
    'unplanned source',
  ]);
  await assert.rejects(buildImageCodecs(f.options), /clean pinned submodule/);
  await assert.rejects(readdir(f.outputRoot), { code: 'ENOENT' });
});

test('a wrong local zlib import cannot publish a partial build', async (context) => {
  const f = await fixture(context);
  const zlib = path.join(f.root, 'wrong-zlib.tar.gz');
  await writeFile(zlib, 'not the locked zlib archive');
  await assert.rejects(
    buildImageCodecs({ ...f.options, zlibArchive: zlib }),
    /official SDK port SHA-512/,
  );
  assert.deepEqual(await readdir(f.outputRoot), []);
  assert.ok(
    !(await readdir(f.cacheRoot)).some((name) => name.endsWith('.lock')),
  );
});

test('the prepared Python interpreter version is part of the actual build identity', async (context) => {
  const f = await fixture(context);
  const first = await buildImageCodecs(f.options);
  f.setPythonVersion('Fixture interpreter 2');
  const second = await buildImageCodecs(f.options);
  assert.equal(second.reused, false);
  assert.notEqual(second.manifest.identity, first.manifest.identity);
  assert.equal(first.manifest.inputs.toolchain.python, 'Fixture interpreter');
  assert.equal(
    second.manifest.inputs.toolchain.python,
    'Fixture interpreter 2',
  );
});

test('ambient compiler and CMake flags cannot change a fresh build with the same identity', async (context) => {
  const f = await fixture(context);
  const first = await buildImageCodecs(f.options);
  f.setEnvironment({
    CFLAGS: '-DFROM_AMBIENT_CFLAGS=1',
    CXXFLAGS: '-DFROM_AMBIENT_CXXFLAGS=1',
    CPPFLAGS: '-DFROM_AMBIENT_CPPFLAGS=1',
    LDFLAGS: '-Wl,--ambient-linker',
    CMAKE_TOOLCHAIN_FILE: '/ambient/toolchain.cmake',
    CMAKE_GENERATOR: 'Ninja',
    CMAKE_PREFIX_PATH: '/ambient/prefix',
    CC: '/ambient/cc',
    CXX: '/ambient/cxx',
    EMCC_CFLAGS: '-sSHARED_MEMORY=1',
    CPATH: '/ambient/include',
    MAKEFLAGS: '--ambient',
    HTTP_PROXY: 'http://fixture.invalid:3128',
    HTTPS_PROXY: 'http://fixture.invalid:3128',
    CODEC_FIXTURE_ASSERT_ENVIRONMENT: '1',
    CODEC_EXPECT_PATH: process.env.PATH ?? '',
  });
  const second = await buildImageCodecs({
    ...f.options,
    outputRoot: path.join(f.root, 'independent-output'),
    cacheRoot: path.join(f.root, 'independent-cache'),
  });
  assert.equal(
    second.reused,
    false,
    'the contaminated case must execute fresh compiler/CMake subprocesses',
  );
  assert.equal(second.manifest.identity, first.manifest.identity);
  assert.deepEqual(second.manifest.artifacts, first.manifest.artifacts);
  assert.ok(
    second.manifest.inputs.recipe.configure.includes('-DCMAKE_C_FLAGS='),
  );
  assert.ok(
    second.manifest.inputs.recipe.configure.includes(
      '-DCMAKE_EXE_LINKER_FLAGS=',
    ),
  );
});
