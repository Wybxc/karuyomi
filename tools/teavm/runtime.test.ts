import assert from 'node:assert/strict';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { gzipSync } from 'node:zlib';
import { Header } from 'tar';
import { zipSync } from 'fflate';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { LOCK, prepareRuntime, installAndroidSdkArchive } from './runtime.ts';
import type { RuntimeLock } from './runtime.ts';

const ROOT = fileURLToPath(new URL('../../', import.meta.url));

function archive(
  root: string,
  names: string[],
  symlink = false,
): { seed: string; lock: RuntimeLock } {
  const blocks: Buffer[] = [];
  for (const name of names) {
    const data = Buffer.from('data'),
      header = new Header({
        path: name,
        size: symlink ? 0 : data.length,
        type: symlink ? 'SymbolicLink' : 'File',
        linkpath: symlink ? '../escape' : '',
        mode: 0o644,
      });
    header.encode();
    if (!header.block) throw new Error('Tar header was not encoded');
    blocks.push(header.block);
    if (!symlink)
      blocks.push(data, Buffer.alloc((512 - (data.length % 512)) % 512));
  }
  blocks.push(Buffer.alloc(1024));
  const encoded = gzipSync(Buffer.concat(blocks)),
    seed = path.join(root, 'seed.tar.gz');
  writeFileSync(seed, encoded);
  const lock = structuredClone(LOCK);
  lock.seed = {
    ...lock.seed,
    size: encoded.length,
    sha256: createHash('sha256').update(encoded).digest('hex'),
    members: Object.fromEntries(
      names.map((name) => [
        name,
        createHash('sha256').update('data').digest('hex'),
      ]),
    ),
  };
  return { seed, lock };
}
function temporary() {
  return mkdtempSync(path.join(os.tmpdir(), 'karuyomi-seed-'));
}

test('Android metadata is bound to locked hashes', () => {
  for (const entry of Object.values(LOCK.android.metadata))
    assert.equal(
      createHash('sha256')
        .update(readFileSync(path.join(ROOT, 'runtime/teavm', entry.path)))
        .digest('hex'),
      entry.sha256,
    );
});
for (const [name, names, symlink, error] of [
  ['traversal', ['../escape'], false, /Unsafe archive path|TAR_ENTRY_ERROR/],
  [
    'duplicate',
    ['public/file', 'public/file'],
    false,
    /Unexpected seed member/,
  ],
  ['symlink', ['public/file'], true, /Unexpected seed member/],
] as const) {
  test(`seed rejects ${name} even with matching archive and member hashes`, async () => {
    const root = temporary();
    try {
      const fixture = archive(root, [...names], symlink);
      await assert.rejects(prepareRuntime({ root, ...fixture }), error);
      assert.equal(existsSync(path.join(root, 'escape')), false);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
}
test('archive hash failure precedes extraction', async () => {
  const root = temporary();
  try {
    const { seed, lock } = archive(root, ['public/file']);
    lock.seed.sha256 = 'a'.repeat(64);
    await assert.rejects(
      prepareRuntime({ root, seed, lock }),
      /checksum\/size mismatch/,
    );
    assert.equal(
      existsSync(
        path.join(root, 'runtime/teavm/.local/runtime-seed.extracting'),
      ),
      false,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
test('SDK ZIP extraction preserves upstream executable modes', async () => {
  const root = temporary();
  try {
    const file = path.join(root, 'sdk.zip');
    writeFileSync(
      file,
      zipSync({
        'sdk/tool': [
          Buffer.from('binary'),
          { os: 3, attrs: (0o100755 << 16) >>> 0 },
        ],
        'sdk/config.xml': [
          Buffer.from('config'),
          { os: 3, attrs: (0o100644 << 16) >>> 0 },
        ],
      }),
    );
    await installAndroidSdkArchive(file, path.join(root, 'sdk'));
    assert.equal(statSync(path.join(root, 'sdk/tool')).mode & 0o777, 0o755);
    assert.equal(
      statSync(path.join(root, 'sdk/config.xml')).mode & 0o777,
      0o644,
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
