import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import * as tar from 'tar';
import { unzipSync, zipSync } from 'fflate';
import { safeName } from './io.ts';

export function readZip(file: string): Record<string, Uint8Array> {
  return unzipSync(readFileSync(file));
}

export function writeZip(
  file: string,
  entries: Record<string, Uint8Array>,
): void {
  for (const name of Object.keys(entries)) safeName(name);
  writeFileSync(
    file,
    zipSync(entries, { level: 6, mtime: new Date(1980, 0, 1) }),
  );
}

export async function extractTar(
  file: string,
  destination: string,
  expectedNames?: ReadonlySet<string>,
): Promise<void> {
  mkdirSync(destination, { recursive: true });
  const seen = new Set<string>();
  let validationError: Error | undefined;
  await tar.x({
    file,
    cwd: destination,
    strict: true,
    preserveOwner: false,
    filter(name, entry) {
      if (validationError) return false;
      try {
        safeName(name);
        if (!('type' in entry)) throw new Error('Expected tar archive entry');
        if (
          expectedNames &&
          (!expectedNames.has(name) || entry.type !== 'File' || seen.has(name))
        ) {
          throw new Error(`Unexpected seed member: ${name}`);
        }
        if (entry.type === 'SymbolicLink' || entry.type === 'Link') {
          if (!expectedNames) {
            const link = entry.linkpath;
            if (link === undefined)
              throw new Error(`Missing archive link target: ${name}`);
            const target = path.posix.normalize(
              path.posix.join(
                entry.type === 'Link' ? '' : path.posix.dirname(name),
                link,
              ),
            );
            if (
              path.posix.isAbsolute(link) ||
              target === '..' ||
              target.startsWith('../')
            ) {
              throw new Error(`Unsafe archive link: ${name}`);
            }
          }
        }
        seen.add(name);
        return true;
      } catch (error) {
        validationError =
          error instanceof Error ? error : new Error(String(error));
        return false;
      }
    },
  });
  if (validationError) throw validationError;
  if (
    expectedNames &&
    (seen.size !== expectedNames.size ||
      [...expectedNames].some((name) => !seen.has(name)))
  ) {
    throw new Error('Seed member set is incomplete');
  }
}

/** Stream one SDK ZIP entry at a time and preserve upstream Unix permissions. */
export async function extractZip(
  file: string,
  destination: string,
  stripFirstDirectory = false,
): Promise<void> {
  const { open } = await import('yauzl');
  const archive = await new Promise<import('yauzl').ZipFile>(
    (resolve, reject) =>
      open(file, { lazyEntries: true, autoClose: false }, (error, zip) =>
        error ? reject(error) : resolve(zip),
      ),
  );
  let prefix: string | undefined;
  try {
    while (true) {
      const entry = await new Promise<import('yauzl').Entry | undefined>(
        (resolve, reject) => {
          const onEntry = (value: import('yauzl').Entry) => {
            cleanup();
            resolve(value);
          };
          const onEnd = () => {
            cleanup();
            resolve(undefined);
          };
          const onError = (error: Error) => {
            cleanup();
            reject(error);
          };
          const cleanup = () => {
            archive.off('entry', onEntry);
            archive.off('end', onEnd);
            archive.off('error', onError);
          };
          archive.once('entry', onEntry);
          archive.once('end', onEnd);
          archive.once('error', onError);
          archive.readEntry();
        },
      );
      if (!entry) break;
      safeName(entry.fileName);
      prefix ??= (entry.fileName.split('/')[0] ?? '') + '/';
      const relative =
        stripFirstDirectory && entry.fileName.startsWith(prefix)
          ? entry.fileName.slice(prefix.length)
          : entry.fileName;
      if (!relative || entry.fileName.endsWith('/')) continue;
      const stream = await new Promise<import('node:stream').Readable>(
        (resolve, reject) =>
          archive.openReadStream(entry, (error, stream) =>
            error
              ? reject(error)
              : stream
                ? resolve(stream)
                : reject(new Error('ZIP entry lacks a stream')),
          ),
      );
      const output = path.join(destination, relative);
      mkdirSync(path.dirname(output), { recursive: true });
      const { createWriteStream, chmodSync } = await import('node:fs');
      const { pipeline } = await import('node:stream/promises');
      await pipeline(stream, createWriteStream(output));
      const mode = entry.externalFileAttributes >>> 16;
      if (mode) chmodSync(output, mode & 0o777);
    }
  } finally {
    archive.close();
  }
}
