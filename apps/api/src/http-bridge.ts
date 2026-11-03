import { Hono } from 'hono';
import type { AppEnv } from './app.js';

const requestLimit = 12 * 1024 * 1024;
// Bounded original text bridge for P0-A semantic baseline. P0-B replaces it with
// framed binary streams; this limit deliberately avoids a 64MiB Base64 string.
const bodyLimit = 8 * 1024 * 1024;
const blockedHeaders =
  /^(?:cf-|x-app-|x-runtime-|host$|connection$|content-length$|transfer-encoding$|upgrade$|expect$|te$|trailer$|proxy-)/i;
const methods = new Set([
  'GET',
  'HEAD',
  'POST',
  'PUT',
  'PATCH',
  'DELETE',
  'OPTIONS',
]);

export function allowedTarget(value: string, hosts: string[]): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new Error('target_not_allowed');
  }
  if (
    !['https:', 'http:'].includes(url.protocol) ||
    url.username ||
    url.password ||
    url.port ||
    !/^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/.test(url.hostname) ||
    /^\d+(?:\.\d+)*$/.test(url.hostname) ||
    /(?:^|\.)(?:localhost|local|internal|home|invalid|test)$/.test(
      url.hostname,
    ) ||
    !url.hostname.includes('.') ||
    !hosts.includes(url.hostname)
  ) {
    throw new Error('target_not_allowed');
  }
  return url;
}

async function boundedBytes(
  stream: ReadableStream<Uint8Array> | null,
  limit: number,
): Promise<Uint8Array> {
  if (!stream) return new Uint8Array();
  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > limit) throw new Error('body_limit_exceeded');
      chunks.push(value);
    }
  } catch (error) {
    await reader.cancel().catch(() => {});
    throw error;
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}

export function encodeBase64(bytes: Uint8Array): string {
  const chunks: string[] = [];
  for (let start = 0; start < bytes.length; start += 16_384) {
    chunks.push(String.fromCharCode(...bytes.subarray(start, start + 16_384)));
  }
  return btoa(chunks.join(''));
}

export interface LegacyRequest {
  url: string;
  method: string;
  headers: [string, string][];
  body?: string;
}

function validBase64(value: string): boolean {
  if (value.length % 4 !== 0) return false;
  const padding = value.endsWith('==') ? 2 : value.endsWith('=') ? 1 : 0;
  // Avoid a repeated capture group: V8 can overflow its regexp stack for a
  // valid multi-megabyte body before the bridge's configured limit is reached.
  return !/[^A-Za-z0-9+/]/.test(value.slice(0, value.length - padding));
}

export function parseLegacyRequest(value: unknown): LegacyRequest {
  if (!value || typeof value !== 'object')
    throw new Error('invalid_bridge_request');
  const data = value as Record<string, unknown>;
  if (
    typeof data.url !== 'string' ||
    data.url.length > 16_384 ||
    typeof data.method !== 'string' ||
    !methods.has(data.method) ||
    !Array.isArray(data.headers) ||
    data.headers.length > 200 ||
    !data.headers.every(
      (p: unknown) =>
        Array.isArray(p) &&
        p.length === 2 &&
        p.every((s) => typeof s === 'string' && s.length <= 16_384),
    ) ||
    (data.body !== undefined &&
      (typeof data.body !== 'string' ||
        data.body.length > Math.ceil(bodyLimit / 3) * 4 ||
        !validBase64(data.body)))
  ) {
    throw new Error('invalid_bridge_request');
  }
  if (
    (data.method === 'HEAD' || data.method === 'GET') &&
    data.body !== undefined
  )
    throw new Error('body_not_allowed');
  if (typeof data.body === 'string') {
    const padding = data.body.endsWith('==')
      ? 2
      : data.body.endsWith('=')
        ? 1
        : 0;
    if ((data.body.length / 4) * 3 - padding > bodyLimit)
      throw new Error('body_limit_exceeded');
  }
  return data as unknown as LegacyRequest;
}

export async function forwardLegacy(
  descriptor: LegacyRequest,
  hosts: string[],
  signal: AbortSignal,
  fetcher: typeof fetch = fetch,
) {
  const url = allowedTarget(descriptor.url, hosts);
  const headers = new Headers();
  for (const [name, value] of descriptor.headers) {
    if (!blockedHeaders.test(name)) {
      try {
        headers.append(name, value);
      } catch {
        throw new Error('invalid_bridge_request');
      }
    }
  }
  // Application request headers are never copied. Explicit Source Cookie and
  // Authorization values remain part of that Source's own request semantics.
  const init: RequestInit = {
    method: descriptor.method,
    headers,
    redirect: 'manual',
    cache: 'no-store',
    signal,
  };
  if (descriptor.body !== undefined)
    init.body = Uint8Array.from(atob(descriptor.body), (c) => c.charCodeAt(0));
  const upstream = await fetcher(url, init);
  const bytes = await boundedBytes(upstream.body, bodyLimit);
  const responseHeaders: [string, string][] = [];
  for (const [name, value] of upstream.headers) {
    // Workers fetch delivers decoded bytes. Do not tell OkHttp to decode again.
    const noBody =
      descriptor.method === 'HEAD' || [204, 304].includes(upstream.status);
    if (
      name.toLowerCase() !== 'set-cookie' &&
      (noBody ||
        !['content-encoding', 'content-length'].includes(name.toLowerCase()))
    )
      responseHeaders.push([name, value]);
  }
  for (const cookie of upstream.headers.getSetCookie())
    responseHeaders.push(['set-cookie', cookie]);
  if (descriptor.method !== 'HEAD' && ![204, 304].includes(upstream.status))
    responseHeaders.push(['content-length', String(bytes.length)]);
  return {
    status: upstream.status,
    message: upstream.statusText,
    headers: responseHeaders,
    body: encodeBase64(bytes),
  };
}

export function createHttpBridge() {
  const app = new Hono<AppEnv>();
  app.post('/http', async (c) => {
    if (!c.req.header('content-type')?.startsWith('application/json'))
      return c.json({ error: 'unsupported_bridge_protocol' }, 415);
    const buildId = c.req.header('X-Runtime-Build');
    if (!buildId || buildId.length > 200)
      return c.json({ error: 'runtime_build_required' }, 400);
    const row = await c.env.DB.prepare(
      'SELECT allowed_hosts_json FROM extension_builds WHERE build_id = ? AND status = ?',
    )
      .bind(buildId, 'verified')
      .first<{ allowed_hosts_json: string }>();
    if (!row) return c.json({ error: 'build_not_found' }, 404);
    let hosts: unknown;
    try {
      hosts = JSON.parse(row.allowed_hosts_json);
    } catch {
      return c.json({ error: 'invalid_network_policy' }, 503);
    }
    if (!Array.isArray(hosts) || !hosts.every((h) => typeof h === 'string'))
      return c.json({ error: 'invalid_network_policy' }, 503);
    const abort = new AbortController();
    const onAbort = () => abort.abort();
    c.req.raw.signal.addEventListener('abort', onAbort, { once: true });
    if (c.req.raw.signal.aborted) abort.abort();
    const timeout = setTimeout(onAbort, 30_000);
    try {
      const body = await boundedBytes(c.req.raw.body, requestLimit);
      const descriptor = parseLegacyRequest(
        JSON.parse(
          new TextDecoder('utf-8', { fatal: true, ignoreBOM: false }).decode(
            body,
          ),
        ),
      );
      return c.json(await forwardLegacy(descriptor, hosts, abort.signal));
    } catch (error) {
      const message = error instanceof Error ? error.message : 'bridge_failed';
      // Do not reflect upstream URLs, credentials, response bodies or stack traces.
      if (message === 'target_not_allowed')
        return c.json({ error: message }, 403);
      if (message === 'body_limit_exceeded')
        return c.json({ error: message }, 413);
      if (
        message === 'invalid_bridge_request' ||
        message === 'body_not_allowed' ||
        error instanceof SyntaxError
      )
        return c.json({ error: 'invalid_bridge_request' }, 400);
      return c.json(
        {
          error: abort.signal.aborted
            ? 'bridge_cancelled_or_timed_out'
            : 'upstream_network_error',
        },
        502,
      );
    } finally {
      clearTimeout(timeout);
      c.req.raw.signal.removeEventListener('abort', onAbort);
    }
  });
  return app;
}
