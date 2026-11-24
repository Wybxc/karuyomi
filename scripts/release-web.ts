import assert from 'node:assert/strict';
import { appendFile, readFile } from 'node:fs/promises';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { execa } from 'execa';
import { runtimeMaterialCatalogSchema } from '../packages/contracts/src/index.ts';
import {
  assertWebSnapshotCurrent,
  prepareWebSnapshot,
  recordWebRelease,
  verifyWebRelease,
} from '../tools/cloudflare/web-release.ts';

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { 'require-latest': { type: 'boolean', default: false } },
});
const command = positionals[0];
const root = process.cwd();
const directory = path.join(root, '.local/web-release');
const origin = 'https://karuyomi.wybxc.cc';
async function isLatest(): Promise<boolean> {
  const expected = process.env.GITHUB_SHA;
  assert(
    expected && /^[a-f0-9]{40}$/.test(expected),
    'GITHUB_SHA must identify the checked main commit',
  );
  assert.equal(
    (await execa('git', ['rev-parse', 'HEAD'])).stdout.trim(),
    expected,
  );
  const remote = (
    await execa('git', [
      'ls-remote',
      '--exit-code',
      'origin',
      'refs/heads/main',
    ])
  ).stdout
    .trim()
    .split(/\s+/)[0];
  assert(remote && /^[a-f0-9]{40}$/.test(remote), 'Cannot read current main');
  const current = remote === expected;
  if (process.env.GITHUB_OUTPUT)
    await appendFile(process.env.GITHUB_OUTPUT, `current=${current}\n`);
  if (!current)
    console.log(
      'A newer main commit exists; skipping this obsolete publication.',
    );
  if (values['require-latest'])
    assert(
      current,
      'A newer main commit exists; refusing to replace its Web client',
    );
  return current;
}
if (command === 'latest') {
  await isLatest();
} else if (command === 'prepare') {
  const catalog = runtimeMaterialCatalogSchema.parse(
    JSON.parse(
      await readFile(
        path.join(root, 'packages/runtime-host/dist/materials.json'),
        'utf8',
      ),
    ),
  );
  await prepareWebSnapshot({
    origin,
    destination: path.join(directory, 'assets'),
    catalog,
  });
} else if (command === 'check') {
  if (await isLatest()) {
    await assertWebSnapshotCurrent(origin, path.join(directory, 'assets'));
    await recordWebRelease(root, directory, process.env.GITHUB_SHA ?? '');
  }
} else if (command === 'verify') {
  await assertWebSnapshotCurrent(origin, path.join(directory, 'assets'));
  const verified = await verifyWebRelease(directory);
  console.log(JSON.stringify(verified, null, 2));
  if (process.env.GITHUB_STEP_SUMMARY) {
    await appendFile(
      process.env.GITHUB_STEP_SUMMARY,
      `Published ${verified.origin}\n\nSource: \`${verified.sourceCommit}\`\n\nReused ${verified.extensionCount} extensions at \`${verified.extensionRevision}\`. Verified ${verified.publicAssetsVerified} public assets and the anonymous Access gate.\n\nEvidence: \`web-release-${verified.sourceCommit}\` artifact.\n`,
    );
  }
} else {
  throw new Error(
    'Usage: node scripts/release-web.ts latest|prepare|check|verify [--require-latest]',
  );
}
