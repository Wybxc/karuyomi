import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { ROOT } from '../lib/io.ts';
import { applyPatch, PATCHES, prepareSources } from './upstream-sources.ts';

test('exact replacement, insertion and deletion', () => {
  const patch =
    '--- a/file\n+++ b/file\n@@ -1,3 +1,3 @@\n first\n-old\n+new\n last\n';
  assert.equal(applyPatch('first\nold\nlast\n', patch), 'first\nnew\nlast\n');
  assert.equal(
    applyPatch('', '--- a/file\n+++ b/file\n@@ -0,0 +1 @@\n+new\n'),
    'new\n',
  );
  assert.equal(
    applyPatch('old\n', '--- a/file\n+++ b/file\n@@ -1 +0,0 @@\n-old\n'),
    '',
  );
});
test('context drift and malformed ranges fail', () => {
  const patch = '--- a/file\n+++ b/file\n@@ -1 +1 @@\n-old\n+new\n';
  assert.throws(() => applyPatch('changed\n', patch), /context/);
  assert.throws(
    () => applyPatch('old\n', patch.replace('@@ -1 +1 @@', '@@ -1,2 +1 @@')),
    /length/,
  );
  assert.throws(() => applyPatch('old\n', patch + patch));
});
test(
  'all pinned sources materialize',
  { skip: !existsSync(path.join(ROOT, 'vendor/teavm/classlib')) },
  () => {
    const folder = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-upstream-'));
    try {
      const outputs = prepareSources(folder);
      assert.equal(outputs.length, PATCHES.length);
      assert.ok(
        outputs.every((file) => !path.relative(folder, file).startsWith('..')),
      );
    } finally {
      rmSync(folder, { recursive: true, force: true });
    }
  },
);
test('missing submodule gives an actionable bootstrap instruction', () => {
  const folder = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-no-upstream-'));
  try {
    assert.throws(
      () => prepareSources(path.join(folder, 'out'), folder),
      /git submodule update/,
    );
  } finally {
    rmSync(folder, { recursive: true, force: true });
  }
});
