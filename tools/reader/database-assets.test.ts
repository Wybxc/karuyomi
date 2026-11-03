import assert from 'node:assert/strict';
import {
  mkdir,
  mkdtemp,
  readFile,
  readdir,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test, { type TestContext } from 'node:test';
import { ExecaError } from 'execa';
import {
  DATABASE_ASSETS,
  prepareDatabaseAssets,
  verifyDatabaseAssets,
} from './database-assets.ts';

async function fixture(context: TestContext) {
  const root = await mkdtemp(path.join(tmpdir(), 'karuyomi-database-assets-'));
  context.after(() => rm(root, { recursive: true, force: true }));
  const cache = path.join(root, 'cache');
  const web = path.join(root, 'web');
  await mkdir(cache);
  await mkdir(web);
  return { root, cache, web };
}

test('Static Assets rejects missing and same-size corrupt official database files', async (context) => {
  const { web } = await fixture(context);
  await assert.rejects(
    verifyDatabaseAssets(web),
    /Missing or invalid.*sqlite3\.wasm/,
  );
  await writeFile(
    path.join(web, 'sqlite3.wasm'),
    Buffer.alloc(DATABASE_ASSETS[0].size),
  );
  await assert.rejects(
    verifyDatabaseAssets(web),
    /Missing or invalid.*sqlite3\.wasm/,
  );
});

test('a corrupt cache download cannot replace previously served database resources', async (context) => {
  const { root, cache, web } = await fixture(context);
  await writeFile(path.join(cache, 'sqlite3.wasm'), 'corrupt cache');
  await writeFile(path.join(web, 'sqlite3.wasm'), 'previous wasm');
  await writeFile(path.join(web, 'drift_worker.js'), 'previous worker');
  const executable = path.join(root, 'fixture-curl.mjs');
  const invocation = path.join(root, 'invocation.json');
  await writeFile(
    executable,
    `#!/usr/bin/env node
import { writeFileSync } from 'node:fs';
const args = process.argv.slice(2);
writeFileSync(${JSON.stringify(invocation)}, JSON.stringify(args));
const output = args[args.indexOf('--output') + 1];
const maximum = Number(args[args.indexOf('--max-filesize') + 1]);
writeFileSync(output, Buffer.alloc(maximum));
`,
    { mode: 0o755 },
  );
  await assert.rejects(
    prepareDatabaseAssets({
      cacheDirectory: cache,
      webDirectory: web,
      curl: executable,
    }),
    /Official Drift database asset size or checksum mismatch: sqlite3\.wasm/,
  );
  assert.equal(
    await readFile(path.join(cache, 'sqlite3.wasm'), 'utf8'),
    'corrupt cache',
  );
  assert.equal(
    await readFile(path.join(web, 'sqlite3.wasm'), 'utf8'),
    'previous wasm',
  );
  assert.equal(
    await readFile(path.join(web, 'drift_worker.js'), 'utf8'),
    'previous worker',
  );
  assert.deepEqual(await readdir(cache), ['sqlite3.wasm']);
  const args: unknown = JSON.parse(await readFile(invocation, 'utf8'));
  assert.ok(Array.isArray(args));
  assert.equal(
    args.at(-1),
    'https://github.com/simolus3/drift/releases/download/drift-2.35.3/sqlite3.wasm',
  );
  assert.ok(args.includes('--fail') && args.includes('--location'));
  assert.ok(!args.includes('--insecure'));
});

test('failed official downloads remove partial files and leave served assets intact', async (context) => {
  const { root, cache, web } = await fixture(context);
  await writeFile(path.join(web, 'sqlite3.wasm'), 'previous wasm');
  const executable = path.join(root, 'fixture-curl.mjs');
  await writeFile(
    executable,
    `#!/usr/bin/env node
import { writeFileSync } from 'node:fs';
const args = process.argv.slice(2);
writeFileSync(args[args.indexOf('--output') + 1], 'partial response');
process.exitCode = 7;
`,
    { mode: 0o755 },
  );
  await assert.rejects(
    prepareDatabaseAssets({
      cacheDirectory: cache,
      webDirectory: web,
      curl: executable,
    }),
    (error: unknown) => error instanceof ExecaError && error.exitCode === 7,
  );
  assert.deepEqual(await readdir(cache), []);
  assert.equal(
    await readFile(path.join(web, 'sqlite3.wasm'), 'utf8'),
    'previous wasm',
  );
});

test('non-regular cache assets fail before any download or served-file write', async (context) => {
  const { root, cache, web } = await fixture(context);
  const target = path.join(root, 'outside');
  await writeFile(target, 'keep');
  await symlink(target, path.join(cache, 'sqlite3.wasm'));
  await assert.rejects(
    prepareDatabaseAssets({
      cacheDirectory: cache,
      webDirectory: web,
      curl: path.join(root, 'must-not-run'),
    }),
    /must be a regular file/,
  );
  assert.equal(await readFile(target, 'utf8'), 'keep');
  assert.deepEqual(await readdir(web), []);
});
