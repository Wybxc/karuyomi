import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import {
  mkdtemp,
  mkdir,
  readFile,
  readdir,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test, { type TestContext } from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import { execa } from 'execa';
import { create as createTar } from 'tar';
import {
  imageCodecBuildIdentity,
  imageCodecBuildManifestSchema,
  type ImageCodecBuildInputs,
} from './build.ts';
import {
  packageImageCodecArtifacts,
  prepareImageCodecArtifacts,
} from './artifacts.ts';

const digest = (bytes: Uint8Array) => ({
  size: bytes.byteLength,
  sha256: createHash('sha256').update(bytes).digest('hex'),
});
const own = [
  'runtime/image-codec/codec.h',
  'runtime/image-codec/png.c',
  'runtime/image-codec/jpeg.c',
  'runtime/image-codec/encoder.c',
  'runtime/image-codec/encoder.h',
  'tools/images/build.ts',
  'tools/images/toolchain.ts',
];
const outputs = [
  'png.mjs',
  'png.wasm',
  'jpeg.mjs',
  'jpeg.wasm',
  'encoder.mjs',
  'encoder.wasm',
  'licenses/libspng-LICENSE.txt',
  'licenses/libjpeg-turbo-LICENSE.md',
  'licenses/libjpeg-turbo-README.ijg',
  'licenses/zlib-README',
];
async function fixture(context: TestContext) {
  const root = await mkdtemp(
    path.join(os.tmpdir(), 'karuyomi-codec-artifacts-'),
  );
  context.after(() => rm(root, { recursive: true, force: true }));
  const build = path.join(root, 'build');
  await mkdir(path.join(build, 'licenses'), { recursive: true });
  const files: ImageCodecBuildInputs['files'] = {};
  for (const name of own) {
    const bytes = Buffer.from('Maintained fixture: ' + name + '\n');
    await mkdir(path.dirname(path.join(root, name)), { recursive: true });
    await writeFile(path.join(root, name), bytes);
    files[name] = digest(bytes);
  }
  const sdkLock = Buffer.from('Locked fixture toolchain\n');
  await writeFile(
    path.join(root, 'runtime/image-codec/toolchain-lock.json'),
    sdkLock,
  );
  await execa('git', ['init', root]);
  for (const [name, pin] of [
    ['vendor/libspng', 'a'],
    ['vendor/libjpeg-turbo', 'b'],
  ])
    await execa(
      'git',
      [
        'update-index',
        '--add',
        '--cacheinfo',
        `160000,${pin!.repeat(40)},${name}`,
      ],
      { cwd: root },
    );
  const inputs: ImageCodecBuildInputs = {
    schemaVersion: 1,
    toolchain: {
      host: 'fixture',
      archiveSha256: 'a'.repeat(64),
      lockSha256: digest(sdkLock).sha256,
      node: process.version,
      python: 'Fixture Python',
      cmake: '4.4.5',
    },
    sources: {
      libspng: { path: 'vendor/libspng', commit: 'a'.repeat(40) },
      libjpeg: { path: 'vendor/libjpeg-turbo', commit: 'b'.repeat(40) },
    },
    files,
    zlib: {
      version: '1.3.1',
      sha512: 'c'.repeat(128),
      portSha256: 'd'.repeat(64),
    },
    recipe: { common: [], png: [], jpeg: [], encoder: [], configure: [] },
  };
  const artifacts: Record<string, { size: number; sha256: string }> = {};
  for (const name of outputs) {
    const bytes = name.endsWith('.wasm')
      ? Buffer.from([0, 97, 115, 109, 1, 0, 0, 0])
      : Buffer.from('Public fixture ' + name + '\n');
    await writeFile(path.join(build, name), bytes);
    artifacts[name] = digest(bytes);
  }
  const manifest = {
    schemaVersion: 1,
    identity: imageCodecBuildIdentity(inputs),
    inputs,
    abi: 'karuyomi-image-strips-v1',
    encoderAbi: 'karuyomi-png-tiles-v1',
    artifacts,
    toolchainVersions: { node: process.version },
  };
  await writeFile(
    path.join(build, 'build-manifest.json'),
    JSON.stringify(manifest) + '\n',
  );
  const archive = path.join(root, 'codec.tar.gz');
  const result = await packageImageCodecArtifacts({
    projectRoot: root,
    buildDirectory: build,
    archiveFile: archive,
    url: 'https://example.invalid/codec.tar.gz',
  });
  return {
    root,
    build,
    archive,
    lock: result.lock,
    options: { projectRoot: root, archiveFile: archive },
    async saveLock() {
      await writeFile(
        path.join(root, 'runtime/image-codec/artifacts-lock.json'),
        JSON.stringify(this.lock) + '\n',
      );
    },
  };
}
async function cleanCache(root: string) {
  const entries = await readdir(
    path.join(root, 'runtime/image-codec/.local/artifacts'),
  );
  assert.deepEqual(
    entries,
    [],
    'failed preparation must remove staging directories and locks',
  );
}

test('packages portable assets, imports offline and reuses without opening the archive or network', async (context) => {
  const f = await fixture(context);
  const one = await readFile(f.archive);
  const secondArchive = path.join(f.root, 'again.tar.gz');
  await packageImageCodecArtifacts({
    projectRoot: f.root,
    buildDirectory: f.build,
    archiveFile: secondArchive,
    url: f.lock.archive.url,
  });
  assert.deepEqual(await readFile(secondArchive), one);
  const prepared = await prepareImageCodecArtifacts(f.options);
  assert.equal(prepared.reused, false);
  assert.equal(prepared.manifest.encoderAbi, 'karuyomi-png-tiles-v1');
  assert.equal(Object.keys(prepared.manifest.artifacts).length, 10);
  await rm(f.archive);
  const reused = await prepareImageCodecArtifacts(f.options);
  assert.equal(reused.reused, true);
  assert.equal(reused.directory, prepared.directory);
});

test('rejects a same-size archive digest mismatch before extracting and releases the lock', async (context) => {
  const f = await fixture(context);
  const bytes = await readFile(f.archive);
  const first = bytes.at(0);
  assert(first !== undefined);
  bytes[0] = first ^ 1;
  await writeFile(f.archive, bytes);
  await assert.rejects(
    prepareImageCodecArtifacts(f.options),
    /transfer integrity/,
  );
  await cleanCache(f.root);
});

test('rejects changed archive size before import', async (context) => {
  const f = await fixture(context);
  await writeFile(f.archive, 'bad');
  await assert.rejects(prepareImageCodecArtifacts(f.options), /size mismatch/);
  await cleanCache(f.root);
});

for (const variant of [
  'extra-file',
  'symlink',
  'duplicate',
  'missing',
] as const)
  test(`archive member contract rejects ${variant} and removes all partial output`, async (context) => {
    const f = await fixture(context);
    const names = [...outputs, 'build-manifest.json'];
    if (variant === 'extra-file') {
      await writeFile(path.join(f.build, 'extra'), 'extra');
      names.push('extra');
    }
    if (variant === 'symlink') {
      await symlink('/tmp/karuyomi-no-artifact', path.join(f.build, 'linked'));
      names.push('linked');
    }
    if (variant === 'duplicate') names.push('png.mjs');
    if (variant === 'missing') names.splice(names.indexOf('encoder.wasm'), 1);
    await createTar(
      { file: f.archive, cwd: f.build, gzip: true, portable: true },
      names,
    );
    f.lock.archive = {
      url: f.lock.archive.url,
      ...digest(await readFile(f.archive)),
    };
    await f.saveLock();
    await assert.rejects(
      prepareImageCodecArtifacts(f.options),
      /Unexpected codec archive entry|incomplete/,
    );
    await cleanCache(f.root);
  });

test('detects a corrupted cached module and does not replace it with an unreviewed download', async (context) => {
  const f = await fixture(context);
  const prepared = await prepareImageCodecArtifacts(f.options);
  const file = path.join(prepared.directory, 'png.wasm');
  const bytes = await readFile(file);
  const first = bytes.at(0);
  assert(first !== undefined);
  bytes[0] = first ^ 1;
  await writeFile(file, bytes);
  await assert.rejects(
    prepareImageCodecArtifacts(f.options),
    /member digest mismatch/,
  );
  assert.equal((await readFile(file))[0], bytes[0]);
  assert.deepEqual(
    (await readdir(path.dirname(prepared.directory))).filter(
      (name) => name.endsWith('.lock') || name.startsWith('.stage-'),
    ),
    [],
  );
});

test('rejects stale maintained compiler input before opening an archive', async (context) => {
  const f = await fixture(context);
  await writeFile(
    path.join(f.root, 'runtime/image-codec/encoder.c'),
    'changed',
  );
  await assert.rejects(
    prepareImageCodecArtifacts({
      ...f.options,
      archiveFile: path.join(f.root, 'absent'),
    }),
    /stale.*encoder.c/,
  );
});

test('rejects a changed indexed upstream without requiring a submodule checkout', async (context) => {
  const f = await fixture(context);
  await execa(
    'git',
    ['update-index', '--cacheinfo', `160000,${'f'.repeat(40)},vendor/libspng`],
    { cwd: f.root },
  );
  await assert.rejects(
    prepareImageCodecArtifacts(f.options),
    /indexed upstream/,
  );
});

test('rejects an archive manifest inconsistent with its pinned build identity', async (context) => {
  const f = await fixture(context);
  const file = path.join(f.build, 'build-manifest.json');
  const manifest = imageCodecBuildManifestSchema.parse(
    JSON.parse(await readFile(file, 'utf8')),
  );
  manifest.identity = 'f'.repeat(64);
  const bytes = Buffer.from(JSON.stringify(manifest) + '\n');
  await writeFile(file, bytes);
  f.lock.files['build-manifest.json'] = digest(bytes);
  await createTar(
    { file: f.archive, cwd: f.build, gzip: true, portable: true },
    [...outputs, 'build-manifest.json'],
  );
  f.lock.archive = {
    url: f.lock.archive.url,
    ...digest(await readFile(f.archive)),
  };
  await f.saveLock();
  await assert.rejects(
    prepareImageCodecArtifacts(f.options),
    /build identity is inconsistent/,
  );
  await cleanCache(f.root);
});

test(
  'cancels an actual slow HTTP transfer, closes the response and cleans its lock',
  { timeout: 5000 },
  async (context) => {
    const f = await fixture(context);
    const bytes = await readFile(f.archive);
    let requested!: () => void;
    const ready = new Promise<void>((resolve) => {
      requested = resolve;
    });
    let closeResponse!: () => void;
    const closed = new Promise<void>((resolve) => {
      closeResponse = resolve;
    });
    const server = createServer((_request, response) => {
      response.writeHead(200, { 'content-type': 'application/gzip' });
      response.write(bytes.subarray(0, 32));
      const timer = setTimeout(() => response.end(bytes.subarray(32)), 10_000);
      response.once('close', () => {
        clearTimeout(timer);
        closeResponse();
      });
      requested();
    });
    await new Promise<void>((resolve) =>
      server.listen(0, '127.0.0.1', resolve),
    );
    context.after(
      () =>
        new Promise<void>((resolve) => {
          server.closeAllConnections();
          server.close(() => resolve());
        }),
    );
    const address = server.address();
    assert(address && typeof address !== 'string');
    f.lock.archive.url = `http://127.0.0.1:${address.port}/codec.tar.gz`;
    await f.saveLock();
    const controller = new AbortController();
    const running = prepareImageCodecArtifacts({
      projectRoot: f.root,
      signal: controller.signal,
    });
    await ready;
    controller.abort(new Error('fixture transfer cancelled'));
    await assert.rejects(running, /cancel|abort/i);
    await closed;
    await cleanCache(f.root);
  },
);

async function extractorFixture(
  root: string,
  mode: 'failure' | 'cancel' | 'success',
) {
  const executable = path.join(root, 'extractor-fixture.mjs');
  const ready = path.join(root, 'extractor-ready.json');
  const lateWrite = path.join(root, 'extractor-late-write');
  const childCode = `
const fs=require('node:fs');
const path=require('node:path');
setTimeout(()=>{
 fs.mkdirSync(process.argv[1],{recursive:true});
 fs.writeFileSync(path.join(process.argv[1],'late-member'),'late');
 fs.writeFileSync(process.argv[2],'late');
},300);
setInterval(()=>{},1000);
process.send('ready');`;
  await writeFile(
    executable,
    `#!/usr/bin/env node
import fs from 'node:fs';
import {spawn,spawnSync} from 'node:child_process';
const args=process.argv.slice(2);
const payload=args[args.indexOf('-C')+1];
if(${JSON.stringify(mode)}==='success') {
 const result=spawnSync('tar',args,{stdio:'inherit'});
 if(result.status!==0) process.exit(result.status??8);
}
const child=spawn(process.execPath,['-e',${JSON.stringify(childCode)},payload,${JSON.stringify(lateWrite)}],{stdio:['ignore','inherit','inherit','ipc']});
child.once('message',()=>{
 fs.writeFileSync(${JSON.stringify(ready)},JSON.stringify({parent:process.pid,child:child.pid}));
 if(${JSON.stringify(mode)}==='failure') process.exit(7);
 if(${JSON.stringify(mode)}==='success') process.exit(0);
});
setInterval(()=>{},1000);
`,
    { mode: 0o755 },
  );
  return { executable, ready, lateWrite };
}
async function extractorState(file: string) {
  let bytes: string | undefined;
  for (let attempt = 0; attempt < 300; attempt++) {
    try {
      bytes = await readFile(file, 'utf8');
      break;
    } catch (error) {
      if (!(
        error instanceof Error &&
        'code' in error &&
        error.code === 'ENOENT'
      ))
        throw error;
      await delay(10);
    }
  }
  assert(
    bytes,
    'the real extractor must reach its descendant before cancellation',
  );
  const input: unknown = JSON.parse(bytes);
  assert(
    input !== null &&
      typeof input === 'object' &&
      'parent' in input &&
      typeof input.parent === 'number' &&
      'child' in input &&
      typeof input.child === 'number',
  );
  return { parent: input.parent, child: input.child };
}
async function assertExited(pid: number) {
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      process.kill(pid, 0);
    } catch (error) {
      assert(
        error instanceof Error && 'code' in error && error.code === 'ESRCH',
      );
      return;
    }
    await delay(10);
  }
  assert.fail('extractor process remains alive: ' + pid);
}

test('a malformed locked tar is rejected by read-only listing before extraction can write later members', async (context) => {
  const f = await fixture(context);
  await createTar({ file: f.archive, cwd: f.build }, [
    ...outputs,
    'build-manifest.json',
  ]);
  const bytes = await readFile(f.archive);
  const first = bytes.at(0);
  assert(first !== undefined);
  bytes[0] = first ^ 1;
  await writeFile(f.archive, bytes);
  f.lock.archive = { url: f.lock.archive.url, ...digest(bytes) };
  await f.saveLock();
  await assert.rejects(
    prepareImageCodecArtifacts(f.options),
    /checksum failure/,
  );
  await cleanCache(f.root);
  await delay(100);
  await cleanCache(f.root);
});

for (const mode of ['failure', 'cancel'] as const)
  test(
    `extraction ${mode} waits for the real process and descendant before removing staging and releasing the lock`,
    { timeout: 5000 },
    async (context) => {
      const f = await fixture(context);
      const extractor = await extractorFixture(f.root, mode);
      const controller = new AbortController();
      const running = prepareImageCodecArtifacts({
        ...f.options,
        tarExecutable: extractor.executable,
        signal: controller.signal,
      });
      context.after(async () => {
        controller.abort();
        await running.catch(() => {});
      });
      const rejected = assert.rejects(
        running,
        mode === 'failure' ? /exit code 7/ : /cancel|abort/i,
      );
      const state = await extractorState(extractor.ready);
      context.after(() => {
        for (const pid of [state.parent, state.child]) {
          try {
            process.kill(pid, 'SIGKILL');
          } catch {}
        }
      });
      if (mode === 'cancel')
        controller.abort(new Error('cancel actual codec extraction'));
      await rejected;
      await assertExited(state.parent);
      await assertExited(state.child);
      await cleanCache(f.root);
      await delay(400);
      await assert.rejects(readFile(extractor.lateWrite), { code: 'ENOENT' });
      await cleanCache(f.root);
    },
  );

test(
  'successful extraction terminates a stdout-holding descendant before validating and publishing the cache',
  { timeout: 5000 },
  async (context) => {
    const f = await fixture(context);
    const extractor = await extractorFixture(f.root, 'success');
    const started = performance.now();
    const prepared = await prepareImageCodecArtifacts({
      ...f.options,
      tarExecutable: extractor.executable,
    });
    assert(
      performance.now() - started < 3000,
      'a successful extractor must not wait for the operation timeout',
    );
    const state = await extractorState(extractor.ready);
    context.after(() => {
      for (const pid of [state.parent, state.child]) {
        try {
          process.kill(pid, 'SIGKILL');
        } catch {}
      }
    });
    await assertExited(state.parent);
    await assertExited(state.child);
    assert.equal(prepared.reused, false);
    await delay(400);
    await assert.rejects(readFile(extractor.lateWrite), { code: 'ENOENT' });
    assert.deepEqual(await readdir(path.dirname(prepared.directory)), [
      path.basename(prepared.directory),
    ]);
  },
);
