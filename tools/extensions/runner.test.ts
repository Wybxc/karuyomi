import assert from 'node:assert/strict';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';
import { test, type TestContext } from 'node:test';
import lockfile from 'proper-lockfile';
import { execa, execaSync } from 'execa';
import { createHash } from 'node:crypto';
import isRecord from 'is-plain-obj';
import stableStringify from 'json-stable-stringify';
import writeFileAtomic from 'write-file-atomic';
import {
  ROOT,
  git,
  treeHash,
  hostSubmodules,
  hostFingerprint,
  HOST_PATHS,
} from './catalog.ts';
import { addHostTestSubmodules } from './test-submodules.ts';
import {
  ExtensionPipeline,
  BuilderProcesses,
  emptyState,
  resultOf,
  resumePlan,
  validateBuildCheckout,
  writeGithubOutput,
  withStateLock,
} from './pipeline.ts';

import {
  runtimeIdentitySchema,
  type Catalog,
  type ExtensionDescriptor,
  type ExtensionPlan,
} from './model.ts';
const protocol: unknown = JSON.parse(
  readFileSync(path.join(ROOT, 'packages/contracts/protocol.json'), 'utf8'),
);
assert.ok(isRecord(protocol));
const materials = runtimeIdentitySchema.parse({
  ...protocol,
  bridgeVersion: 2,
  hostScripts: [],
  resources: [],
});
const builder = `import fs from 'node:fs'; import path from 'node:path'; import {gzipSync} from 'node:zlib'; import {createHash} from 'node:crypto';
const args=process.argv.slice(2); const get=(name)=>args[args.indexOf(name)+1]; const d=JSON.parse(fs.readFileSync(get('--descriptor'),'utf8')); const output=get('--output');
if('GH_TOKEN' in process.env||'GITHUB_TOKEN' in process.env||'CLOUDFLARE_API_TOKEN' in process.env)throw new Error('Credentials reached builder');
if(process.cwd()!==path.resolve(import.meta.dirname,'../..'))throw new Error('Wrong working directory');
const raw=Buffer.from('const frozen = true;'), encoded=gzipSync(raw); const hash=(b)=>createHash('sha256').update(b).digest('hex'); const sha=hash(raw);
fs.mkdirSync(path.join(output,'artifacts'),{recursive:true}); fs.writeFileSync(path.join(output,'artifacts',sha+'.gz'),encoded);
const m={...JSON.parse(fs.readFileSync(path.join(process.cwd(),'protocol.json'),'utf8')),bridgeVersion:2,buildId:d.buildId,packageName:d.packageName,repoId:'fixture',version:d.versionName,storageSchema:'1',sourceIds:['1'],hostScripts:[],resources:[],bundle:{sha256:sha,path:'/extensions/artifacts/'+sha+'.gz',size:raw.length,contentType:'text/javascript',encoding:'gzip',encodedSha256:hash(encoded),encodedSize:encoded.length}};
fs.writeFileSync(path.join(output,'manifest.json'),JSON.stringify(m));fs.writeFileSync(path.join(output,'provenance.json'),JSON.stringify({descriptor:d}));
`;
function fixture(t: TestContext) {
  const root = realpathSync(
      mkdtempSync(path.join(tmpdir(), 'karuyomi-frozen-')),
    ),
    checkout = path.join(root, 'builder');
  mkdirSync(checkout);
  t.after(() => rmSync(root, { recursive: true, force: true }));
  git(checkout, 'init', '-q');
  const put = (name: string, text: string) => {
    mkdirSync(path.dirname(path.join(checkout, name)), { recursive: true });
    writeFileSync(path.join(checkout, name), text);
  };
  const commit = () => {
    git(
      checkout,
      'add',
      'host.txt',
      'tools/extensions/builder.ts',
      'protocol.json',
      'package.json',
    );
    git(
      checkout,
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.invalid',
      'commit',
      '-qm',
      'frozen fixture',
    );
  };
  put('host.txt', 'frozen host');
  put('tools/extensions/builder.ts', builder);
  put('protocol.json', JSON.stringify(protocol));
  put('package.json', '{"type":"module"}');
  commit();
  addHostTestSubmodules(checkout);
  const upstream = path.join(checkout, 'vendor/extensions-source');
  mkdirSync(upstream, { recursive: true });
  git(upstream, 'init', '-q');
  writeFileSync(path.join(upstream, 'source.txt'), 'source');
  git(upstream, 'add', '.');
  git(
    upstream,
    '-c',
    'user.name=Fixture',
    '-c',
    'user.email=fixture@example.invalid',
    'commit',
    '-qm',
    'source',
  );
  const descriptor: ExtensionDescriptor = {
    schemaVersion: 1,
    packageName: 'example.frozen',
    sourcePath: 'src/en/frozen',
    buildId: 'frozen-build',
    versionCode: 106001,
    declaredVersionCode: 1,
    effectiveVersionCode: 1,
    versionName: '1.6.1',
    hostRepositoryCommit: git(checkout, 'rev-parse', 'HEAD'),
    hostSubmodules: hostSubmodules(checkout),
    hostInputs: {},
    hostFingerprint: '',
    sourceFingerprint: 'a'.repeat(64),
    inputFingerprint: 'f'.repeat(64),
    upstreamCommit: git(upstream, 'rev-parse', 'HEAD'),
    sourceInputs: {},
    sharedInputs: {},
  };
  const refresh = () => {
    descriptor.hostRepositoryCommit = git(checkout, 'rev-parse', 'HEAD');
    descriptor.hostInputs = Object.fromEntries(
      [
        'host.txt',
        'tools/extensions/builder.ts',
        'protocol.json',
        'package.json',
      ].map((name) => [name, treeHash(checkout, name)]),
    );
    descriptor.hostFingerprint = createHash('sha256')
      .update(
        stableStringify({
          schemaVersion: 1,
          inputs: descriptor.hostInputs,
          pinnedSubmodules: descriptor.hostSubmodules,
        }) ?? assert.fail('Fixture must be valid JSON'),
      )
      .digest('hex');
  };
  refresh();
  const plan = (entries = [descriptor]): ExtensionPlan => {
    const catalog: Catalog = {
      schemaVersion: 1,
      entries,
      upstreamCommit: descriptor.upstreamCommit,
      hostFingerprint: descriptor.hostFingerprint,
      catalogFingerprint: 'c'.repeat(64),
      discoveryFailures: [],
    };
    return {
      ...catalog,
      repositoryCommit: descriptor.hostRepositoryCommit ?? '',
      selected: entries,
      pendingCount: entries.length,
      remainingCount: 0,
      ci: false,
      baseRevision: null,
      snapshotNeeded: true,
    };
  };
  return {
    root,
    checkout,
    descriptor,
    put,
    commit,
    refresh,
    plan,
    pipeline: new ExtensionPipeline({ materials: async () => materials }),
  };
}
test('runner executes frozen same-layer builder, strips credentials and reuses validated local output', async (t) => {
  const f = fixture(t),
    output = path.join(f.root, 'delivery'),
    keys = ['GH_TOKEN', 'GITHUB_TOKEN', 'CLOUDFLARE_API_TOKEN'];
  const previous = Object.fromEntries(
    keys.map((key) => [key, process.env[key]]),
  );
  for (const key of keys) process.env[key] = 'must-not-reach-builder';
  try {
    const first = await f.pipeline.buildOne(f.descriptor, output, {
      checkout: f.checkout,
    });
    assert.equal(
      resultOf(first).status,
      'built',
      JSON.stringify(resultOf(first)),
    );
    const log = readFileSync(path.join(output, 'build.log'));
    const second = await f.pipeline.buildOne(f.descriptor, output, {
      checkout: f.checkout,
    });
    assert.deepEqual(resultOf(second), resultOf(first));
    assert.deepEqual(readFileSync(path.join(output, 'build.log')), log);
  } finally {
    for (const key of keys) {
      const value = previous[key];
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
  assert.equal(
    git(
      f.checkout,
      'status',
      '--porcelain',
      '--',
      ...Object.keys(f.descriptor.hostInputs),
    ),
    '',
  );
});
test('builder preserves Unicode and shell metacharacter arguments and streams large logs without inheriting credentials', async (t) => {
  const f = fixture(t);
  const processes = new BuilderProcesses();
  const argsFile = path.join(f.root, 'arguments.json');
  const log = path.join(f.root, 'large-builder.log');
  const sentinel = path.join(f.root, 'must-not-be-created');
  const arguments_ = [
    '漫画 🍵 with spaces',
    `$(touch ${sentinel})`,
    '`echo shell-expansion`',
    'quote" and apostrophe\' and ; * ? $HOME',
  ];
  const previous = process.env.KARUYOMI_TEST_CREDENTIAL;
  process.env.KARUYOMI_TEST_CREDENTIAL = 'must-not-be-inherited';
  try {
    await processes.run(
      process.execPath,
      [
        '-e',
        `const fs=require('node:fs');
if(process.env.KARUYOMI_TEST_CREDENTIAL)throw Error('Environment was merged');
if(process.env.BUILDER_FIXTURE!=='allowed')throw Error('Explicit environment missing');
fs.writeFileSync(process.argv[1],JSON.stringify(process.argv.slice(2)));
process.stdout.write(Buffer.alloc(5*1024*1024,97),()=>process.stderr.write(Buffer.alloc(5*1024*1024,98)));`,
        argsFile,
        ...arguments_,
      ],
      {
        cwd: f.root,
        env: { BUILDER_FIXTURE: 'allowed' },
        stdout: { file: log, append: true },
        stderr: { file: log, append: true },
      },
    );
    assert.deepEqual(JSON.parse(readFileSync(argsFile, 'utf8')), arguments_);
    assert.equal(existsSync(sentinel), false);
    const bytes = readFileSync(log);
    assert.equal(bytes.length, 10 * 1024 * 1024);
    assert.equal(
      bytes.subarray(0, 5 * 1024 * 1024).every((byte) => byte === 97),
      true,
    );
    assert.equal(
      bytes.subarray(5 * 1024 * 1024).every((byte) => byte === 98),
      true,
    );
  } finally {
    await processes.close();
    if (previous === undefined) delete process.env.KARUYOMI_TEST_CREDENTIAL;
    else process.env.KARUYOMI_TEST_CREDENTIAL = previous;
  }
});
test('frozen checkout rejects wrong commits and dirty host input', (t) => {
  const f = fixture(t);
  assert.throws(
    () =>
      validateBuildCheckout(f.checkout, {
        ...f.descriptor,
        hostRepositoryCommit: '0'.repeat(40),
      }),
    /commit/,
  );
  f.put('host.txt', 'changed');
  assert.throws(() => validateBuildCheckout(f.checkout, f.descriptor), /clean/);
});
test('resume preserves frozen descriptors, refuses CI and rejects mixed host identities', (t) => {
  const f = fixture(t),
    plan = f.plan();
  assert.deepEqual(
    resumePlan(plan, emptyState(), 10000, false, false).selected,
    [f.descriptor],
  );
  assert.throws(() => resumePlan(plan, emptyState(), 10000, false, true), /CI/);
  assert.throws(
    () =>
      resumePlan(
        f.plan([
          f.descriptor,
          { ...f.descriptor, hostFingerprint: '1'.repeat(64) },
        ]),
        emptyState(),
        10000,
        false,
        false,
      ),
    /mixes/,
  );
});
test('typed plan writes complete GitHub matrix outputs without an embedded script', (t) => {
  const f = fixture(t),
    output = path.join(f.root, 'github-output');
  writeGithubOutput(output, f.plan());
  const text = readFileSync(output, 'utf8');
  assert.match(text, /count=1/);
  assert.match(text, /snapshot_needed=true/);
  const line = text.split('\n').find((line) => line.startsWith('matrix='));
  assert.ok(line);
  assert.deepEqual(JSON.parse(line.slice(7)), {
    include: [{ key: f.descriptor.inputFingerprint }],
  });
});
async function until(
  check: () => boolean,
  diagnostic: () => string,
): Promise<void> {
  const deadline = Date.now() + 15_000;
  while (!check()) {
    if (Date.now() > deadline)
      throw new Error('Fixture timed out: ' + diagnostic());
    await delay(20);
  }
}
test(
  'SIGINT/SIGTERM stop the real sleeping builder tree before checkpoint lock release',
  { skip: process.platform === 'win32', timeout: 40_000 },
  async (t) => {
    const f = fixture(t);
    f.put(
      'tools/extensions/builder.ts',
      `import fs from 'node:fs';import path from 'node:path';import {spawn} from 'node:child_process';
const args=process.argv.slice(2),output=args[args.indexOf('--output')+1];
const child=spawn(process.execPath,['-e',"const fs=require('node:fs');process.on('SIGTERM',()=>{});process.on('SIGINT',()=>{});setInterval(()=>fs.writeFileSync(process.argv[1],String(Date.now())),25)",path.join(output,'heartbeat')],{stdio:'ignore'});
fs.writeFileSync(path.join(output,'pids.json'),JSON.stringify([process.pid,child.pid]));setInterval(()=>{},1000);
`,
    );
    f.commit();
    f.refresh();
    const pending: ExtensionDescriptor = {
        ...f.descriptor,
        packageName: 'example.pending',
        inputFingerprint: 'e'.repeat(64),
        buildId: 'pending-build',
      },
      planFile = path.join(f.root, 'plan.json');
    writeFileAtomic.sync(
      planFile,
      JSON.stringify(f.plan([f.descriptor, pending])) + '\n',
    );
    for (const [signal, number] of [
      ['SIGINT', 2],
      ['SIGTERM', 15],
    ] as const) {
      const runRoot = path.join(f.root, signal),
        state = path.join(runRoot, 'state.json'),
        output = path.join(runRoot, 'resume-plan.json'),
        delivery = path.join(runRoot, 'builds', f.descriptor.inputFingerprint);
      const runner = execa(
        process.execPath,
        [
          fileURLToPath(new URL('./pipeline.ts', import.meta.url)),
          'bootstrap',
          '--plan',
          planFile,
          '--build-checkout',
          f.checkout,
          '--state',
          state,
          '--output',
          output,
          '--jobs',
          '1',
        ],
        {
          stdin: 'ignore',
          env: { ...process.env, CI: 'false', GITHUB_ACTIONS: 'false' },
          extendEnv: false,
          stdout: 'pipe',
          stderr: 'pipe',
          buffer: false,
          reject: false,
        },
      );
      let log = '',
        exitCode: number | null | undefined;
      runner.stdout.on('data', (data: Buffer) => {
        log += data.toString();
      });
      runner.stderr.on('data', (data: Buffer) => {
        log += data.toString();
      });
      const exited = runner.then((result) => {
        exitCode = result.exitCode ?? null;
      });
      let pids: number[] = [];
      try {
        await until(
          () => {
            if (exitCode !== undefined)
              throw new Error('Runner exited early: ' + log);
            return existsSync(path.join(delivery, 'heartbeat'));
          },
          () => log,
        );
        const input = JSON.parse(
          readFileSync(path.join(delivery, 'pids.json'), 'utf8'),
        );
        assert.ok(
          Array.isArray(input) &&
            input.every((pid): pid is number => typeof pid === 'number'),
        );
        pids = input;
        const lockOptions = {
          realpath: false,
          lockfilePath: path.join(runRoot, 'state.lock'),
          retries: 0,
        };
        await assert.rejects(
          lockfile.lock(state, lockOptions),
          /already being held/,
        );
        runner.kill(signal);
        const timeout = new AbortController();
        try {
          await Promise.race([
            exited,
            delay(15_000, undefined, { signal: timeout.signal }).then(() => {
              throw new Error('Runner failed to stop: ' + log);
            }),
          ]);
        } finally {
          timeout.abort();
        }
        assert.equal(exitCode, 128 + number, log);
        const release = await lockfile.lock(state, lockOptions);
        await release();
        const heartbeat = readFileSync(path.join(delivery, 'heartbeat'));
        await delay(100);
        assert.deepEqual(
          readFileSync(path.join(delivery, 'heartbeat')),
          heartbeat,
        );
        for (const pid of pids) {
          const result = execaSync('ps', ['-p', String(pid), '-o', 'stat='], {
            stdin: 'ignore',
            encoding: 'utf8',
            reject: false,
          });
          if (result.failed && result.exitCode !== 1) throw result;
          const status = result.stdout.trim();
          assert.ok(
            !status || status.startsWith('Z'),
            'live child ' + pid + ': ' + status,
          );
        }
        assert.equal(
          existsSync(
            path.join(runRoot, 'builds', pending.inputFingerprint, 'build.log'),
          ),
          false,
        );
        assert.equal(existsSync(state), false);
      } finally {
        if (exitCode === undefined) {
          runner.kill('SIGKILL');
          await exited;
        }
        for (const pid of pids)
          try {
            process.kill(pid, 'SIGKILL');
          } catch (error) {
            if (
              !(error instanceof Error) ||
              !('code' in error) ||
              error.code !== 'ESRCH'
            )
              throw error;
          }
      }
    }
  },
);

for (const stdio of ['ignore', 'inherit'] as const)
  test(
    `successful builder exit stops descendants with ${stdio} stdio before releasing the checkpoint lock`,
    { skip: process.platform === 'win32', timeout: 15000 },
    async (t) => {
      const f = fixture(t);
      const heartbeat = path.join(f.root, 'orphan-heartbeat');
      const pidFile = path.join(f.root, 'orphan-pid');
      const logFile = path.join(f.root, 'orphan-build.log');
      const processes = new BuilderProcesses();
      const state = path.join(f.root, 'orphan-state.json');
      const childScript =
        "const fs=require('node:fs');process.on('SIGTERM',()=>{});" +
        "setInterval(()=>{fs.writeFileSync(process.argv[1],String(Date.now()));process.stdout.write('still running\\n')},10);";
      const builderScript =
        "const fs=require('node:fs');const {spawn}=require('node:child_process');" +
        `const child=spawn(process.execPath,['-e',${JSON.stringify(childScript)},${JSON.stringify(heartbeat)}],{stdio:${JSON.stringify(stdio)}});` +
        `fs.writeFileSync(${JSON.stringify(pidFile)},String(child.pid));` +
        `setInterval(()=>{if(fs.existsSync(${JSON.stringify(heartbeat)}))process.exit(0)},10);`;
      let pid: number | undefined;
      try {
        await withStateLock(state, processes, async () => {
          await processes.run(process.execPath, ['-e', builderScript], {
            stdout: { file: logFile, append: true },
            stderr: { file: logFile, append: true },
          });
        });
        pid = Number(readFileSync(pidFile, 'utf8'));
        assert.ok(Number.isSafeInteger(pid) && pid > 0);
        const release = await lockfile.lock(state, {
          realpath: false,
          lockfilePath: path.join(f.root, 'orphan-state.lock'),
          retries: 0,
        });
        try {
          const stopped = readFileSync(heartbeat, 'utf8');
          const log = readFileSync(logFile, 'utf8');
          if (stdio === 'inherit') assert.ok(log.includes('still running\n'));
          await delay(100);
          assert.equal(readFileSync(heartbeat, 'utf8'), stopped);
          assert.equal(readFileSync(logFile, 'utf8'), log);
          const result = execaSync('ps', ['-p', String(pid), '-o', 'stat='], {
            stdin: 'ignore',
            reject: false,
          });
          assert.ok(
            result.exitCode === 1 || result.stdout.trim().startsWith('Z'),
          );
        } finally {
          await release();
        }
      } finally {
        await processes.close();
        if (pid !== undefined)
          try {
            process.kill(pid, 'SIGKILL');
          } catch (error) {
            if (
              !(error instanceof Error) ||
              !('code' in error) ||
              error.code !== 'ESRCH'
            )
              throw error;
          }
      }
    },
  );

test(
  'a compromised real checkpoint lock stops the builder before any later state write',
  { timeout: 20_000 },
  async (t) => {
    const directory = mkdtempSync(path.join(tmpdir(), 'karuyomi-lock-loss-'));
    t.after(() => rmSync(directory, { recursive: true, force: true }));
    const state = path.join(directory, 'state.json');
    const heartbeat = path.join(directory, 'heartbeat');
    writeFileSync(state, 'previous checkpoint\n');
    const processes = new BuilderProcesses();
    try {
      const running = withStateLock(state, processes, async () => {
        await processes.run(
          process.execPath,
          [
            '-e',
            "const fs=require('node:fs');fs.writeFileSync(process.argv[1],'ready');setInterval(()=>fs.appendFileSync(process.argv[1],'.'),20);",
            heartbeat,
          ],
          { stdout: 'ignore', stderr: 'ignore' },
        );
        writeFileSync(state, 'must never be committed\n');
      });
      const failed = assert.rejects(
        running,
        (error: unknown) =>
          error instanceof Error &&
          'code' in error &&
          error.code === 'ECOMPROMISED',
      );
      const started = performance.now();
      while (!existsSync(heartbeat)) {
        if (performance.now() - started > 3000)
          assert.fail('Builder did not start');
        await delay(10);
      }
      rmSync(path.join(directory, 'state.lock'), { recursive: true });
      await failed;
      const stopped = readFileSync(heartbeat, 'utf8');
      await delay(100);
      assert.equal(readFileSync(heartbeat, 'utf8'), stopped);
      assert.equal(readFileSync(state, 'utf8'), 'previous checkpoint\n');
      await assert.rejects(
        processes.run(process.execPath, [
          '-e',
          "throw new Error('must not run')",
        ]),
        /ENOENT|compromised|lock/i,
      );
    } finally {
      await processes.close();
    }
  },
);

test('cached builds validate required repositories and Source HEAD before reuse in default and frozen modes', async (t) => {
  for (const frozen of [false, true]) {
    for (const change of [
      'uninitialized host dependency',
      'changed Source HEAD',
    ]) {
      await t.test(`${frozen ? 'frozen' : 'default'}: ${change}`, async (t) => {
        const f = fixture(t);
        for (const name of HOST_PATHS) {
          if (!existsSync(path.join(f.checkout, name)))
            f.put(
              path.basename(name).includes('.') ? name : name + '/fixture.txt',
              'fixed host input\n',
            );
        }
        git(f.checkout, 'add', '--', ...HOST_PATHS);
        f.commit();
        const identity = hostFingerprint(f.checkout);
        f.descriptor.hostRepositoryCommit = git(
          f.checkout,
          'rev-parse',
          'HEAD',
        );
        f.descriptor.hostFingerprint = identity.fingerprint;
        f.descriptor.hostInputs = identity.inputs;
        const pipeline = new ExtensionPipeline({
          root: f.checkout,
          materials: async () => materials,
        });
        const output = path.join(f.root, 'cached-delivery');
        const options = frozen ? { checkout: f.checkout } : {};
        assert.equal(
          resultOf(await pipeline.buildOne(f.descriptor, output, options))
            .status,
          'built',
        );
        assert.equal(
          resultOf(await pipeline.buildOne(f.descriptor, output, options))
            .status,
          'built',
        );
        const log = readFileSync(path.join(output, 'build.log'));
        if (change === 'uninitialized host dependency') {
          git(f.checkout, 'submodule', 'deinit', '-f', '--', 'vendor/teavm');
        } else {
          const upstream = path.join(f.checkout, 'vendor/extensions-source');
          writeFileSync(path.join(upstream, 'source.txt'), 'changed Source');
          git(upstream, 'add', 'source.txt');
          git(
            upstream,
            '-c',
            'user.name=Fixture',
            '-c',
            'user.email=fixture@example.invalid',
            'commit',
            '-qm',
            'changed Source',
          );
        }
        const result = resultOf(
          await pipeline.buildOne(f.descriptor, output, options),
        );
        assert.equal(result.status, 'failed');
        assert.match(
          result.failure?.message ?? '',
          change === 'uninitialized host dependency'
            ? /not initialized/
            : /[Ss]ource checkout/,
        );
        assert.deepEqual(readFileSync(path.join(output, 'build.log')), log);
      });
    }
  }
});
