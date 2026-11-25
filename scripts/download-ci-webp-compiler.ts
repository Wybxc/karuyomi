import { createHash } from 'node:crypto';
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execa } from 'execa';
import lock from '../runtime/teavm/toolchain/webp/toolchain.lock.json' with { type: 'json' };

const archive = lock.zig.archives['linux-x64'];
const name = path.basename(new URL(archive.url).pathname);
const downloads = fileURLToPath(
  new URL('../runtime/teavm/.local/webp/downloads/', import.meta.url),
);
const destination = path.join(downloads, name);

function matchesLock(file: string): boolean {
  return (
    existsSync(file) &&
    statSync(file).size === archive.size &&
    createHash('sha256').update(readFileSync(file)).digest('hex') ===
      archive.sha256
  );
}

if (!matchesLock(destination)) {
  rmSync(destination, { force: true });
  const temporary = mkdtempSync(path.join(tmpdir(), 'karuyomi.'));
  try {
    const download = path.join(temporary, name);
    // These mirrors are registered with Zig. Verify the archive before putting
    // it where the regular build can find it.
    for (const mirror of [
      'https://zig.linus.dev/zig/',
      'https://zig.squirl.dev/',
    ]) {
      const url = new URL(name, mirror);
      url.searchParams.set('source', 'karuyomi-github-actions');
      const result = await execa(
        'curl',
        [
          '--fail',
          '--location',
          '--silent',
          '--show-error',
          '--connect-timeout',
          '10',
          '--max-time',
          '90',
          '--max-filesize',
          String(archive.size),
          '--output',
          download,
          url.href,
        ],
        { stdin: 'ignore', stdout: 'ignore', stderr: 'inherit', reject: false },
      );
      if (result.failed || !matchesLock(download)) continue;
      mkdirSync(downloads, { recursive: true });
      copyFileSync(download, destination);
      console.log(`Downloaded pinned Zig archive from ${url.hostname}`);
      break;
    }
    if (!existsSync(destination)) {
      console.warn(
        'Zig mirrors unavailable. The WebP build will use the locked upstream URL.',
      );
    }
  } finally {
    rmSync(temporary, { recursive: true, force: true });
  }
}
