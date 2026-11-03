/** Deterministic application-level gzip, distinct from HTTP Content-Encoding. */
import { gzipSync } from 'node:zlib';
import type { BundleArtifact } from '../../packages/contracts/src/index.ts';
import { digest } from '../lib/json.ts';
export { decodeBundleBytes as decodeBundle } from './verify-manifest.ts';
export const MAX_RAW = 64 * 1024 * 1024;
export const MAX_ENCODED = 25 * 1024 * 1024;
export const MAX_METADATA = 32 * 1024 * 1024;
export function encodeBundle(
  data: Uint8Array,
  contentType: 'application/javascript' | 'text/javascript' = 'text/javascript',
  maximum = MAX_ENCODED,
): { encoded: Buffer; reference: BundleArtifact } {
  if (!data.length || data.length > MAX_RAW)
    throw new Error('Invalid canonical bundle size');
  const encoded = gzipSync(data, { level: 9 });
  // Node's OS byte is platform dependent; the gzip format reserves 255 for unknown.
  encoded[9] = 255;
  if (encoded.length > maximum)
    throw new Error('Encoded bundle exceeds Static Assets 25 MiB limit');
  const sha256 = digest(data);
  return {
    encoded,
    reference: {
      path: '/extensions/artifacts/' + sha256 + '.gz',
      sha256,
      size: data.length,
      contentType,
      encoding: 'gzip',
      encodedSha256: digest(encoded),
      encodedSize: encoded.length,
    },
  };
}
export function originUrl(origin: string, pathname: string): string {
  const url = new URL(origin);
  if (
    url.protocol !== 'https:' ||
    !url.hostname ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    url.pathname !== '/'
  )
    throw new Error('Static origin must be an HTTPS origin');
  if (
    !pathname.startsWith('/extensions/') ||
    pathname.split('/').includes('..') ||
    /[?#\\]/.test(pathname)
  )
    throw new Error('Invalid static extension path');
  return url.origin + pathname;
}
export class StaticHttpError extends Error {
  readonly status: number;
  constructor(status: number) {
    super('Static extension response unavailable: ' + status);
    this.status = status;
  }
}
export async function fetchBytes(
  origin: string,
  pathname: string,
  maximum = MAX_METADATA,
): Promise<Buffer> {
  const url = originUrl(origin, pathname);
  const response = await fetch(url, {
    headers: { 'Accept-Encoding': 'identity', 'Cache-Control': 'no-cache' },
    redirect: 'error',
    credentials: 'omit',
    signal: AbortSignal.timeout(120_000),
  });
  if (!response.ok) {
    await response.body?.cancel();
    throw new StaticHttpError(response.status);
  }
  if (
    response.headers.get('content-encoding') &&
    response.headers.get('content-encoding')?.toLowerCase() !== 'identity'
  ) {
    await response.body?.cancel();
    throw new Error('Static transport must expose the declared gzip bytes');
  }
  const reader = response.body?.getReader();
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (reader) {
      const result = await reader.read();
      if (result.done) break;
      length += result.value.length;
      if (length > maximum) throw new Error('Oversized static response');
      chunks.push(result.value);
    }
  } catch (error) {
    void reader?.cancel(error).catch(() => {});
    throw error;
  } finally {
    reader?.releaseLock();
  }
  return Buffer.concat(chunks, length);
}
export async function fetchJson(
  origin: string,
  pathname: string,
  maximum = MAX_METADATA,
): Promise<unknown> {
  return JSON.parse(
    (await fetchBytes(origin, pathname, maximum)).toString('utf8'),
  ) as unknown;
}
