import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { createServer } from 'node:http';
import {
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import test, { type TestContext } from 'node:test';
import { c as createTar } from 'tar';
import {
  prepareImageCodecToolchain,
  type ImageCodecToolchainLock,
} from './toolchain.ts';

async function fixture(context: TestContext, emccSource?: string) {
  const root = await mkdtemp(path.join(tmpdir(), 'karuyomi-image-sdk-'));
  context.after(() => rm(root, { recursive: true, force: true }));
  await writeFile(
    path.join(root, '.node-version'),
    process.version.slice(1) + '\n',
  );
  const upstream = path.join(root, 'source/upstream');
  await mkdir(path.join(upstream, 'emscripten'), { recursive: true });
  await mkdir(path.join(upstream, 'bin'));
  const commit = 'a'.repeat(40);
  const clangCommit = 'b'.repeat(40);
  await writeFile(
    path.join(upstream, 'emscripten/emcc.py'),
    emccSource ??
      `import os,sys
assert '-Werror=version-check' in sys.argv
assert not os.environ.get('EM_IGNORE_SANITY')
assert not os.environ.get('EMCC_SKIP_SANITY_CHECK')
print('emcc (Emscripten gcc/clang-like replacement) 5.0.7-git (${commit})')
`,
  );
  await writeFile(
    path.join(upstream, 'bin/clang'),
    `#!/bin/sh\necho 'clang version 23.0.0git (llvm ${clangCommit})'\n`,
    { mode: 0o755 },
  );
  await writeFile(
    path.join(upstream, 'bin/wasm-opt'),
    "#!/bin/sh\necho 'wasm-opt version 129 (fixture)'\n",
    { mode: 0o755 },
  );
  const archive = path.join(root, 'sdk.tar.gz');
  await createTar(
    { file: archive, gzip: true, cwd: path.join(root, 'source') },
    ['upstream'],
  );
  const bytes = await readFile(archive);
  const host = `${process.platform}-${process.arch}`;
  const sha256 = createHash('sha256').update(bytes).digest('hex');
  const lock: ImageCodecToolchainLock = {
    schemaVersion: 1,
    emsdk: {
      repository: 'https://github.com/emscripten-core/emsdk',
      commit: 'c'.repeat(40),
      version: '5.0.7',
      releaseTag: 'd'.repeat(40),
    },
    emscriptenCommit: commit,
    archives: {
      [host]: {
        verification: 'verified',
        url: 'https://example.invalid/archive?generation=1',
        generation: '1',
        size: bytes.length,
        sha256,
        versions: {
          clang: '23.0.0git',
          clangCommit,
          binaryen: '129',
          binaryenRevision: 'fixture',
        },
      },
    },
  };
  const cacheRoot = path.join(root, 'cache');
  const options = { projectRoot: root, lock, cacheRoot, archiveFile: archive };
  return { root, lock, host, archive, cacheRoot, bytes, options };
}

test('a verified archive installs atomically and its completed cache can be reused offline', async (context) => {
  const f = await fixture(context);
  const prepared = await prepareImageCodecToolchain(f.options);
  assert.equal(prepared.versions.node, process.version);
  assert.match(prepared.versions.python, /^Python 3\./);
  assert.ok(prepared.emcc.startsWith(prepared.sdk));
  const config = await readFile(prepared.emConfig, 'utf8');
  assert.ok(config.includes(`NODE_JS = [${JSON.stringify(process.execPath)}]`));
  assert.ok(config.includes(path.join(prepared.sdk, 'bin')));
  assert.ok(!config.includes('Homebrew'));
  assert.equal(prepared.environment['EM_CONFIG'], prepared.emConfig);
  assert.equal(prepared.environment['EMCC_SKIP_SANITY_CHECK'], undefined);
  const marker: unknown = JSON.parse(
    await readFile(path.join(prepared.directory, 'installation.json'), 'utf8'),
  );
  assert.deepEqual(marker, {
    schemaVersion: 1,
    host: prepared.host,
    archiveSha256: prepared.archiveSha256,
  });
  await rm(f.archive);
  const reused = await prepareImageCodecToolchain(f.options);
  assert.equal(reused.directory, prepared.directory);
  assert.deepEqual(await readdir(f.cacheRoot), [
    path.basename(prepared.directory),
  ]);
});

for (const corruption of ['size', 'sha256'] as const) {
  test(`local archive ${corruption} corruption is rejected before installation`, async (context) => {
    const f = await fixture(context);
    const bytes =
      corruption === 'size'
        ? f.bytes.subarray(0, f.bytes.length - 1)
        : Buffer.from(f.bytes);
    if (corruption === 'sha256') bytes[0] = (bytes[0] ?? 0) ^ 1;
    await writeFile(f.archive, bytes);
    await assert.rejects(
      prepareImageCodecToolchain(f.options),
      /archive size or SHA-256 mismatch/,
    );
    assert.deepEqual(await readdir(f.cacheRoot), []);
  });
}

for (const corruption of ['missing', 'json', 'host', 'archive'] as const) {
  test(`a cached SDK with a ${corruption} marker fails without replacing the installation`, async (context) => {
    const f = await fixture(context);
    const prepared = await prepareImageCodecToolchain(f.options);
    const file = path.join(prepared.directory, 'installation.json');
    if (corruption === 'missing') await rm(file);
    else if (corruption === 'json') await writeFile(file, '{invalid');
    else
      await writeFile(
        file,
        JSON.stringify({
          schemaVersion: 1,
          host: corruption === 'host' ? 'other-host' : prepared.host,
          archiveSha256:
            corruption === 'archive' ? 'f'.repeat(64) : prepared.archiveSha256,
        }),
      );
    await assert.rejects(
      prepareImageCodecToolchain(f.options),
      /marker is missing or invalid|cache identity mismatch/,
    );
    assert.deepEqual(await readdir(f.cacheRoot), [
      path.basename(prepared.directory),
    ]);
  });
}

for (const executable of ['emcc', 'clang', 'wasmOpt'] as const) {
  test(`a cached SDK with a mismatching ${executable} version fails before reuse`, async (context) => {
    const f = await fixture(context);
    const prepared = await prepareImageCodecToolchain(f.options);
    await writeFile(
      prepared[executable],
      executable === 'emcc'
        ? "print('emcc 5.0.8')\n"
        : "#!/bin/sh\necho 'unexpected compiler version'\n",
    );
    await assert.rejects(
      prepareImageCodecToolchain(f.options),
      /Image SDK (Emscripten|Clang|Binaryen) version/,
    );
    assert.deepEqual(await readdir(f.cacheRoot), [
      path.basename(prepared.directory),
    ]);
  });
}

test('an unexpected official executable version cannot become a completed installation', async (context) => {
  const f = await fixture(context, "print('emcc 5.0.8')\n");
  await assert.rejects(
    prepareImageCodecToolchain(f.options),
    /Emscripten version or commit mismatch/,
  );
  assert.deepEqual(await readdir(f.cacheRoot), []);
});

test('unverified platform metadata is refused before preparing or downloading anything', async (context) => {
  const f = await fixture(context);
  f.lock.archives['linux-x64'] = {
    verification: 'pending_sha256',
    url: 'https://example.invalid/sdk?generation=2',
    generation: '2',
    size: 1,
    reason: 'Archive SHA-256 and executable versions are unverified',
  };
  await assert.rejects(
    prepareImageCodecToolchain({ ...f.options, host: 'linux-x64' }),
    /is not verified/,
  );
  await assert.rejects(readdir(f.cacheRoot), { code: 'ENOENT' });
});

test('Node must match the project pin rather than a broad supported engines range', async (context) => {
  const f = await fixture(context);
  await writeFile(path.join(f.root, '.node-version'), '24.0.0\n');
  await assert.rejects(
    prepareImageCodecToolchain(f.options),
    /requires project Node 24.0.0/,
  );
  await assert.rejects(readdir(f.cacheRoot), { code: 'ENOENT' });
});

async function httpFixture(
  context: TestContext,
  mode: 'valid' | 'hash' | 'oversize' | 'cancel',
) {
  const f = await fixture(context);
  const controller = new AbortController();
  context.after(() => controller.abort());
  let requestCount = 0;
  let openResponses = 0;
  let notifyStarted: (() => void) | undefined;
  const started = new Promise<void>((resolve) => {
    notifyStarted = resolve;
  });
  const server = createServer((_request, response) => {
    requestCount++;
    openResponses++;
    response.once('close', () => {
      openResponses--;
    });
    if (mode === 'valid') {
      response.end(f.bytes);
      return;
    }
    if (mode === 'hash') {
      const bytes = Buffer.from(f.bytes);
      bytes[0] = (bytes[0] ?? 0) ^ 1;
      response.end(bytes);
      return;
    }
    response.write(f.bytes.subarray(0, 16));
    notifyStarted?.();
    if (mode === 'oversize') response.end(Buffer.alloc(f.bytes.length));
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  context.after(async () => {
    server.closeAllConnections();
    await new Promise<void>((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  });
  const address = server.address();
  assert.ok(address && typeof address !== 'string');
  const archive = f.lock.archives[f.host];
  assert.ok(archive);
  archive.url = `http://127.0.0.1:${address.port}/sdk?generation=1`;
  const { archiveFile: _archiveFile, ...withoutLocalArchive } = f.options;
  return {
    ...f,
    controller,
    started,
    requests: () => requestCount,
    responses: () => openResponses,
    downloadOptions: { ...withoutLocalArchive, signal: controller.signal },
  };
}

test('a local HTTP transfer is hashed and its cache is reused without a second request', async (context) => {
  const f = await httpFixture(context, 'valid');
  const prepared = await prepareImageCodecToolchain(f.downloadOptions);
  assert.equal(f.requests(), 1);
  const second = await prepareImageCodecToolchain(f.downloadOptions);
  assert.equal(second.directory, prepared.directory);
  assert.equal(f.requests(), 1);
});

for (const mode of ['hash', 'oversize'] as const) {
  test(`a ${mode} HTTP response removes partial transfer, installation and lock`, async (context) => {
    const f = await httpFixture(context, mode);
    await assert.rejects(
      prepareImageCodecToolchain(f.downloadOptions),
      /archive (size or SHA-256 mismatch|exceeds locked size)/,
    );
    assert.deepEqual(await readdir(f.cacheRoot), []);
  });
}

test('canceling a live HTTP download closes its response and leaves no partial installation', async (context) => {
  const f = await httpFixture(context, 'cancel');
  const running = prepareImageCodecToolchain(f.downloadOptions);
  const expected = assert.rejects(running, /cancel requested/);
  await f.started;
  f.controller.abort(new Error('cancel requested'));
  await expected;
  for (let i = 0; i < 100 && f.responses(); i++) await delay(10);
  assert.equal(f.responses(), 0);
  assert.deepEqual(await readdir(f.cacheRoot), []);
});

test('canceling a version check terminates the SDK subprocess and its descendant', async (context) => {
  const pidName = `karuyomi-sdk-child-${process.pid}-${Date.now()}`;
  const pidFile = path.join(tmpdir(), pidName);
  context.after(() => rm(pidFile, { force: true }));
  const f = await fixture(
    context,
    `import pathlib,subprocess,sys,time
child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(120)'])
pathlib.Path(${JSON.stringify(pidFile)}).write_text(str(child.pid))
time.sleep(120)
`,
  );
  const controller = new AbortController();
  context.after(() => controller.abort());
  const expected = assert.rejects(
    prepareImageCodecToolchain({ ...f.options, signal: controller.signal }),
    /aborted|canceled|cancel/i,
  );
  let pid: number | undefined;
  for (let i = 0; i < 300; i++) {
    try {
      pid = Number(await readFile(pidFile, 'utf8'));
      break;
    } catch {
      await delay(10);
    }
  }
  assert.ok(pid && Number.isInteger(pid));
  context.after(() => {
    try {
      process.kill(pid, 'SIGKILL');
    } catch {
      /* Already reaped. */
    }
  });
  controller.abort(new Error('cancel SDK version check'));
  await expected;
  let alive = true;
  for (let i = 0; i < 200 && alive; i++) {
    try {
      process.kill(pid, 0);
      await delay(10);
    } catch (error) {
      assert.ok(
        error instanceof Error && 'code' in error && error.code === 'ESRCH',
      );
      alive = false;
    }
  }
  assert.equal(
    alive,
    false,
    'the SDK descendant must not outlive canceled preparation',
  );
  assert.deepEqual(await readdir(f.cacheRoot), []);
});

test('successful SDK version checks promptly close descendants that inherited stdout', async (context) => {
  const pidFile = path.join(
    tmpdir(),
    `karuyomi-sdk-success-${process.pid}-${Date.now()}`,
  );
  context.after(() => rm(pidFile, { force: true }));
  const f = await fixture(
    context,
    `import os,pathlib,subprocess,sys
child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(120)'])
with pathlib.Path(${JSON.stringify(pidFile)}).open('a') as output:
    output.write(str(child.pid) + '\\n')
print('emcc 5.0.7-git (${'a'.repeat(40)})', flush=True)
os._exit(0)
`,
  );
  const started = performance.now();
  const prepared = await prepareImageCodecToolchain({
    ...f.options,
    signal: AbortSignal.timeout(4000),
  });
  assert.equal(prepared.versions.node, process.version);
  assert.ok(
    performance.now() - started < 3000,
    'successful preparation must not wait for the version-check timeout',
  );
  const pids = (await readFile(pidFile, 'utf8')).trim().split('\n').map(Number);
  assert.equal(
    pids.length,
    2,
    'both staging and installed SDK checks must exercise descendant cleanup',
  );
  for (const pid of pids) {
    assert.ok(Number.isSafeInteger(pid) && pid > 0);
    let alive = true;
    for (let i = 0; i < 100 && alive; i++) {
      try {
        process.kill(pid, 0);
        await delay(10);
      } catch (error) {
        assert.ok(
          error instanceof Error && 'code' in error && error.code === 'ESRCH',
        );
        alive = false;
      }
    }
    assert.equal(
      alive,
      false,
      'a successful version-check descendant must have exited before reuse',
    );
  }
});
