import assert from 'node:assert/strict';
import { spawn, execFileSync } from 'node:child_process';
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
import {
  canonical,
  digest,
  isRecord,
  readJson,
  writeJson,
} from '../lib/json.ts';
import { ROOT, git, treeHash } from './catalog.ts';
import {
  ExtensionPipeline,
  emptyState,
  resultOf,
  resumePlan,
  validateBuildCheckout,
  writeGithubOutput,
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
    hostSubmodules: [],
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
    descriptor.hostFingerprint = digest(
      canonical({
        schemaVersion: 1,
        inputs: descriptor.hostInputs,
        pinnedSubmodules: [],
      }),
    );
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
    writeJson(planFile, f.plan([f.descriptor, pending]));
    for (const [signal, number] of [
      ['SIGINT', 2],
      ['SIGTERM', 15],
    ] as const) {
      const runRoot = path.join(f.root, signal),
        state = path.join(runRoot, 'state.json'),
        output = path.join(runRoot, 'resume-plan.json'),
        delivery = path.join(runRoot, 'builds', f.descriptor.inputFingerprint);
      const runner = spawn(
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
          env: { ...process.env, CI: 'false', GITHUB_ACTIONS: 'false' },
          stdio: ['ignore', 'pipe', 'pipe'],
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
      const exited = new Promise<void>((resolve) =>
        runner.on('exit', (code) => {
          exitCode = code;
          resolve();
        }),
      );
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
        const input = readJson(path.join(delivery, 'pids.json'));
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
          let status = '';
          try {
            status = execFileSync('ps', ['-p', String(pid), '-o', 'stat='], {
              encoding: 'utf8',
            }).trim();
          } catch (error) {
            if (!isRecord(error) || error.status !== 1) throw error;
          }
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
            if (!isRecord(error) || error.code !== 'ESRCH') throw error;
          }
      }
    }
  },
);
