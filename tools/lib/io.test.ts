import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { CommandError, run } from './io.ts';

test('child logs stream directly to disk and nonzero exits are reported', async () => {
  const work = mkdtempSync(path.join(os.tmpdir(), 'karuyomi-command-'));
  try {
    const log = path.join(work, 'nested/process.log');
    await run(
      process.execPath,
      [
        '-e',
        'process.stdout.write(Buffer.alloc(1024*1024,65));process.stderr.write("done")',
      ],
      { log },
    );
    const bytes = readFileSync(log);
    assert.equal(bytes.length, 1024 * 1024 + 4);
    assert.equal(bytes.subarray(-4).toString(), 'done');
    await assert.rejects(
      run(process.execPath, ['-e', 'process.exit(7)'], { log }),
      (error: unknown) => error instanceof CommandError && error.exitCode === 7,
    );
    await assert.rejects(
      run('karuyomi-nonexistent-command', [], { log }),
      /ENOENT/,
    );
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});
