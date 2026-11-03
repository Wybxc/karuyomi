import assert from 'node:assert/strict';
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test, type TestContext } from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
import {
  deployPermissionProbe,
  PermissionDeploymentFailure,
  type PermissionDeploymentOptions,
} from './deploy-permission-probe.ts';

const token = 'test-only-cloudflare-secret-that-must-not-leak';
const marker = 'Success! Uploaded 1 file\n';

function fixture(t: TestContext, source: string): PermissionDeploymentOptions {
  const directory = mkdtempSync(
    path.join(tmpdir(), 'karuyomi-permission-test-'),
  );
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const wranglerCli = path.join(directory, 'wrangler.cjs');
  const configuration = path.join(directory, 'check.wrangler.json');
  writeFileSync(configuration, '{}\n');
  writeFileSync(
    wranglerCli,
    `const assert=require('node:assert/strict');assert.deepEqual(process.argv.slice(2),['deploy','--config',${JSON.stringify(configuration)}]);\n${source}`,
  );
  return {
    wranglerCli,
    configuration,
    temporaryDirectory: directory,
    token,
    restoringBaseline: false,
  };
}

test('permission deploy reads the real merged stream without exposing credentials', async (t) => {
  const options = fixture(
    t,
    `process.stdout.write(process.env.CLOUDFLARE_API_TOKEN);process.stderr.write(${JSON.stringify(marker)});`,
  );
  assert.equal(await deployPermissionProbe(options), undefined);
});

test('permission deploy reports nonzero exit with API codes and redacted bounded diagnostics', async (t) => {
  const options = fixture(
    t,
    "process.stderr.write('[code: 10000] '+process.env.CLOUDFLARE_API_TOKEN);process.exitCode=9;",
  );
  await assert.rejects(deployPermissionProbe(options), (error: unknown) => {
    assert(error instanceof PermissionDeploymentFailure);
    assert.match(error.message, /exit 9/);
    assert.match(error.message, /API codes: 10000/);
    assert.match(error.message, /\[redacted\]/);
    assert(!error.message.includes(token));
    return true;
  });
});

test('permission deploy requires the unique upload confirmation', async (t) => {
  const options = fixture(t, "process.stdout.write('Worker uploaded');");
  await assert.rejects(deployPermissionProbe(options), /did not confirm/);
});

test('permission deploy accepts exactly 512 KiB combined UTF8 bytes', async (t) => {
  const options = fixture(
    t,
    `process.stdout.write('é'.repeat(150*1024));process.stderr.write('x'.repeat(512*1024-300*1024-${Buffer.byteLength(marker)})+${JSON.stringify(marker)});`,
  );
  await deployPermissionProbe(options);
});

test('permission deploy rejects combined output above 512 KiB and waits for producer shutdown', async (t) => {
  const options = fixture(
    t,
    "const fs=require('node:fs');fs.writeFileSync('heartbeat','ready');setInterval(()=>fs.appendFileSync('heartbeat','.'),10);process.stdout.write('x'.repeat(300*1024));process.stderr.write(process.env.CLOUDFLARE_API_TOKEN+'y'.repeat(300*1024));",
  );
  await assert.rejects(deployPermissionProbe(options), (error: unknown) => {
    assert(error instanceof PermissionDeploymentFailure);
    assert.match(error.message, /512 KiB merged output budget/);
    assert(!error.message.includes(token));
    return true;
  });
  const heartbeat = path.join(options.temporaryDirectory, 'heartbeat');
  const stopped = readFileSync(heartbeat, 'utf8');
  await delay(100);
  assert.equal(readFileSync(heartbeat, 'utf8'), stopped);
});

test('baseline restoration ignores the cancelled check and does not require an upload marker', async (t) => {
  const options = fixture(t, "process.stderr.write('baseline restored');");
  await deployPermissionProbe({
    ...options,
    restoringBaseline: true,
    signal: AbortSignal.abort(),
  });
});

for (const stdio of ['ignore', 'inherit'] as const)
  test(
    `successful permission CLI completion also stops TERM-resistant ${stdio} helpers`,
    { skip: process.platform === 'win32', timeout: 10_000 },
    async (t) => {
      const options = fixture(
        t,
        `const fs=require('node:fs');const {spawn}=require('node:child_process');const helper=spawn(process.execPath,['-e',"const fs=require('node:fs');process.on('SIGTERM',()=>{});fs.writeFileSync('heartbeat','ready');setInterval(()=>fs.appendFileSync('heartbeat','.'),10)"],{stdio:${JSON.stringify(stdio)}});fs.writeFileSync('helper-pid',String(helper.pid));const ready=setInterval(()=>{if(fs.existsSync('heartbeat')){clearInterval(ready);process.stdout.write(${JSON.stringify(marker)},()=>process.exit(0));}},10);`,
      );
      try {
        await deployPermissionProbe(options);
        const heartbeat = path.join(options.temporaryDirectory, 'heartbeat');
        const stopped = readFileSync(heartbeat, 'utf8');
        await delay(100);
        assert.equal(readFileSync(heartbeat, 'utf8'), stopped);
      } finally {
        const pidFile = path.join(options.temporaryDirectory, 'helper-pid');
        if (existsSync(pidFile)) {
          const pid = Number(readFileSync(pidFile, 'utf8'));
          assert(Number.isSafeInteger(pid) && pid > 0);
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

test(
  'cancelling permission deploy waits for the TERM-resistant helper tree before cleanup',
  { skip: process.platform === 'win32', timeout: 15_000 },
  async (t) => {
    const options = fixture(
      t,
      `const fs=require('node:fs');const {spawn}=require('node:child_process');const helper=spawn(process.execPath,['-e',"const fs=require('node:fs');process.on('SIGTERM',()=>{});fs.writeFileSync('heartbeat','ready');setInterval(()=>fs.appendFileSync('heartbeat','.'),10)"],{stdio:'inherit'});fs.writeFileSync('helper-pid',String(helper.pid));setInterval(()=>{},1000);`,
    );
    const controller = new AbortController();
    const heartbeat = path.join(options.temporaryDirectory, 'heartbeat');
    const running = deployPermissionProbe({
      ...options,
      signal: controller.signal,
    });
    const failed = assert.rejects(running, (error: unknown) => {
      assert(error instanceof PermissionDeploymentFailure);
      assert.match(error.message, /cancelled/);
      assert(!error.message.includes(token));
      return true;
    });
    try {
      const deadline = performance.now() + 3000;
      while (!existsSync(heartbeat)) {
        assert(performance.now() < deadline, 'helper did not start');
        await delay(10);
      }
      controller.abort();
      await failed;
      const stopped = readFileSync(heartbeat, 'utf8');
      await delay(100);
      assert.equal(readFileSync(heartbeat, 'utf8'), stopped);
    } finally {
      controller.abort();
      await running.catch(() => {});
      const pidFile = path.join(options.temporaryDirectory, 'helper-pid');
      if (existsSync(pidFile)) {
        const pid = Number(readFileSync(pidFile, 'utf8'));
        assert(Number.isSafeInteger(pid) && pid > 0);
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
