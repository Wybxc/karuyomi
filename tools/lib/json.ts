import { createHash, randomUUID } from 'node:crypto';
import {
  mkdirSync,
  readFileSync,
  renameSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import path from 'node:path';

/** Stable JSON identities are independent of object insertion order. */
export function canonical(value: unknown): Buffer {
  function compare(a: string, b: string): number {
    const left = Array.from(a, (part) => part.codePointAt(0) ?? 0);
    const right = Array.from(b, (part) => part.codePointAt(0) ?? 0);
    for (let index = 0; index < Math.min(left.length, right.length); index++) {
      const difference = (left[index] ?? 0) - (right[index] ?? 0);
      if (difference) return difference;
    }
    return left.length - right.length;
  }
  function encode(input: unknown): string {
    if (Array.isArray(input))
      return '[' + input.map((item) => encode(item ?? null)).join(',') + ']';
    if (input !== null && typeof input === 'object') {
      return (
        '{' +
        Object.entries(input)
          .filter(([, item]) => item !== undefined)
          .sort(([a], [b]) => compare(a, b))
          .map(([key, item]) => JSON.stringify(key) + ':' + encode(item))
          .join(',') +
        '}'
      );
    }
    const encoded = JSON.stringify(input);
    if (encoded === undefined)
      throw new Error('Value cannot be represented as JSON');
    return encoded;
  }
  return Buffer.from(encode(value));
}

export const digest = (bytes: Uint8Array): string =>
  createHash('sha256').update(bytes).digest('hex');

export function readJson(file: string, maximum = 2 * 1024 * 1024): unknown {
  if (statSync(file).size > maximum) throw new Error('Oversized JSON metadata');
  const bytes = readFileSync(file);
  if (bytes.length > maximum) throw new Error('Oversized JSON metadata');
  return JSON.parse(bytes.toString('utf8')) as unknown;
}

export function writeJson(file: string, value: unknown): void {
  mkdirSync(path.dirname(file), { recursive: true });
  const temporary = file + '.' + randomUUID() + '.tmp';
  writeFileSync(
    temporary,
    Buffer.concat([canonical(value), Buffer.from('\n')]),
  );
  renameSync(temporary, file);
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}
