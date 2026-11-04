import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import test, { type TestContext } from 'node:test';
import { fileURLToPath } from 'node:url';
import lockfile from 'proper-lockfile';
import { main, serveImageOwnersBrowser } from './verify-owners-browser.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));
async function output(context: TestContext): Promise<string> {
  await mkdir(path.join(ROOT, '.local'), { recursive: true });
  const directory = await mkdtemp(
    path.join(ROOT, '.local/image-owners-lock-test-'),
  );
  context.after(() => rm(directory, { recursive: true, force: true }));
  await mkdir(path.join(directory, 'public'));
  return directory;
}

test('a second CLI owner rejects before preparation and cannot overwrite an active run', async (context) => {
  const directory = await output(context);
  const sentinel = JSON.stringify({ runId: randomUUID(), active: true });
  const filename = path.join(directory, 'public/config.json');
  await writeFile(filename, sentinel);
  const release = await lockfile.lock(directory, { retries: 0 });
  try {
    await assert.rejects(
      main([
        '--prepare-only',
        '--output',
        directory,
        '--fixtures',
        path.join(directory, 'missing-fixtures'),
      ]),
      (error: unknown) =>
        error instanceof Error && 'code' in error && error.code === 'ELOCKED',
    );
    assert.equal(await readFile(filename, 'utf8'), sentinel);
    assert.equal(await lockfile.check(directory), true);
  } finally {
    await release();
  }
});

test('a failed preparation releases the CLI output lock without changing an existing config', async (context) => {
  const directory = await output(context);
  const filename = path.join(directory, 'public/config.json');
  await writeFile(filename, 'previous run');
  await assert.rejects(
    main([
      '--prepare-only',
      '--output',
      directory,
      '--fixtures',
      path.join(directory, 'missing-fixtures'),
    ]),
    (error: unknown) =>
      error instanceof Error && 'code' in error && error.code === 'ENOENT',
  );
  assert.equal(await lockfile.check(directory), false);
  assert.equal(await readFile(filename, 'utf8'), 'previous run');
});

test('shutdown without an accepted report returns no success evidence', async (context) => {
  const directory = await output(context);
  const controller = new AbortController();
  context.after(() => controller.abort());
  const completion = serveImageOwnersBrowser(
    {
      directory,
      publicDirectory: path.join(directory, 'public'),
      contentTypes: new Map(),
      config: {
        schemaVersion: 1,
        runId: randomUUID(),
        materialVersion: 'fixture',
        referenceMaterialVersion: 'fixture',
        codecSource: {
          buildIdentity: 'fixture',
          abi: 'fixture',
          encoderAbi: 'fixture',
        },
        imageCodecs: [],
        cases: [],
        scope: {
          input: 'test',
          owners: 'test',
          oracle: 'test',
          excluded: 'test',
        },
      },
    },
    { port: 0, signal: controller.signal },
  );
  // listen() schedules its callback before the next immediate; no HTTP request or long server.
  await new Promise<void>((resolve) => setImmediate(resolve));
  controller.abort();
  assert.deepEqual(await completion, { reportPassed: undefined });
});
