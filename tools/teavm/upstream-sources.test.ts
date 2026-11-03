import assert from 'node:assert/strict';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { PACKAGE, PATCHES, prepareSources } from './upstream-sources.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));

test(
  'source drift, patch context drift and changed patch output fail the pinned TeaVM gates',
  {
    skip: !existsSync(path.join(ROOT, 'vendor/teavm/classlib')),
  },
  () => {
    const root = mkdtempSync(
      path.join(os.tmpdir(), 'karuyomi-upstream-drift-'),
    );
    try {
      const name = PATCHES[0][0];
      const relative = path.join(
        'vendor/teavm/classlib/src/main/java',
        PACKAGE,
        `T${name}.java`,
      );
      const original = readFileSync(path.join(ROOT, relative), 'utf8');
      const patchPath = path.join(
        'runtime/teavm/patches/teavm',
        `${name}.patch`,
      );
      const patch = readFileSync(path.join(ROOT, patchPath), 'utf8');
      mkdirSync(path.dirname(path.join(root, relative)), { recursive: true });
      mkdirSync(path.dirname(path.join(root, patchPath)), { recursive: true });
      writeFileSync(path.join(root, relative), original + '\n// drift\n');
      writeFileSync(path.join(root, patchPath), patch);
      assert.throws(
        () => prepareSources(path.join(root, 'out'), root),
        /Pinned TeaVM source differs/,
      );
      writeFileSync(path.join(root, relative), original);
      writeFileSync(
        path.join(root, patchPath),
        patch.replace('-final class TEOLSet', '-final class DifferentSet'),
      );
      assert.throws(
        () => prepareSources(path.join(root, 'out'), root),
        /Patch context differs/,
      );
      writeFileSync(
        path.join(root, patchPath),
        patch.replace(
          '+final class PatchedEOLSet',
          '+final class ChangedEOLSet',
        ),
      );
      assert.throws(
        () => prepareSources(path.join(root, 'out'), root),
        /Patched TeaVM source differs/,
      );
      assert.equal(
        existsSync(path.join(root, 'out', PACKAGE, `Patched${name}.java`)),
        false,
      );
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  },
);
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
