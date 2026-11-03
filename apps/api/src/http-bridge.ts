import { Hono } from 'hono';
import type { AppEnv } from './app.js';
import {
  HTTP_BRIDGE_MEDIA_TYPE,
  HTTP_FRAME_LIMIT,
  HTTP_REQUEST_BODY_LIMIT,
  HTTP_RESPONSE_BODY_LIMIT,
  HttpFrameReader,
  encodePreamble,
  encodeMetaFrame,
  encodeDataFrame,
  encodeEndFrame,
  encodeErrorFrame,
  httpRequestMetaSchema,
  httpResponseMetaSchema,
} from '@karuyomi/contracts';

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

class BinaryBridgeError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status = 502,
  ) {
    super(message);
  }
}

const hopByHopHeaders =
  /^(?:connection|keep-alive|proxy-authenticate|proxy-authorization|te|trailer|transfer-encoding|upgrade)$/i;

/** Connection-nominated headers are hop-by-hop even when their names are custom. */
function connectionHeaders(headers: Iterable<[string, string]>): Set<string> {
  const names = new Set<string>();
  for (const [name, value] of headers) {
    if (name.toLowerCase() === 'connection') {
      for (const token of value.split(','))
        names.add(token.trim().toLowerCase());
    }
  }
  return names;
}

/**
 * The request is bounded binary input; the response only reads upstream when its
 * consumer pulls. Its deadline and abort linkage live until END, ERROR or cancel.
 */
export async function forwardBinary(
  request: Request,
  hosts: string[],
  fetcher: typeof fetch = (...args) => fetch(...args),
): Promise<Response> {
  const started = Date.now();
  const abort = new AbortController();
  let input: HttpFrameReader | undefined;
  let upstreamReader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  let remaining: Uint8Array | undefined;
  let failure: BinaryBridgeError | undefined;
  let finished = false;
  let cancelled = false;
  let timer: ReturnType<typeof setTimeout>;
  let resolveInterruption!: (error: BinaryBridgeError) => void;
  const interruption = new Promise<BinaryBridgeError>((resolve) => {
    resolveInterruption = resolve;
  });
  const cleanup = () => {
    clearTimeout(timer);
    request.signal.removeEventListener('abort', onAbort);
  };
  const stop = (error: BinaryBridgeError) => {
    if (finished || failure) return;
    failure = error;
    remaining = undefined;
    cleanup();
    abort.abort();
    resolveInterruption(error);
    // A broken upstream cancel implementation must not hold up cancellation of
    // the response. Fetch is also aborted independently of its reader.
    void input?.cancel(error).catch(() => {});
    if (upstreamReader) {
      const reader = upstreamReader;
      void reader
        .cancel(error)
        .catch(() => {})
        .finally(() => reader.releaseLock());
    }
  };
  const onAbort = () =>
    stop(
      new BinaryBridgeError('cancelled', 'HTTP bridge request was cancelled'),
    );
  const deadline = (milliseconds: number) => {
    clearTimeout(timer);
    timer = setTimeout(
      () =>
        stop(
          new BinaryBridgeError(
            'timeout',
            'HTTP bridge deadline exceeded',
            504,
          ),
        ),
      milliseconds,
    );
  };
  async function active<T>(operation: Promise<T>): Promise<T> {
    if (failure) {
      void operation.catch(() => {});
      throw failure;
    }
    const result = await Promise.race([
      operation.then((value) => ({ value })),
      interruption.then((error) => ({ error })),
    ]);
    if ('error' in result) throw result.error;
    if (failure) throw failure;
    return result.value;
  }
  const safeFailure = (error: unknown, body = false): BinaryBridgeError => {
    if (failure) return failure;
    if (error instanceof BinaryBridgeError) return error;
    return new BinaryBridgeError(
      body ? 'upstream_body_error' : 'upstream_network_error',
      body
        ? 'Upstream response body could not be read'
        : 'Upstream request failed',
    );
  };
  request.signal.addEventListener('abort', onAbort, { once: true });
  deadline(30_000);
  if (request.signal.aborted) onAbort();
  try {
    if (failure) {
      void request.body?.cancel().catch(() => {});
      throw failure;
    }
    if (!request.body)
      throw new BinaryBridgeError(
        'invalid_bridge_request',
        'Framed request body is required',
        400,
      );
    input = new HttpFrameReader(request.body, HTTP_REQUEST_BODY_LIMIT);
    let descriptor;
    let bytes: Uint8Array | undefined;
    let url: URL;
    const headers = new Headers();
    try {
      const parsed = httpRequestMetaSchema.safeParse(
        await active(input.meta()),
      );
      if (!parsed.success)
        throw new BinaryBridgeError(
          'invalid_bridge_request',
          'Invalid request metadata',
          400,
        );
      descriptor = parsed.data;
      const timeLeft = descriptor.timeoutMs - (Date.now() - started);
      if (timeLeft <= 0)
        throw new BinaryBridgeError(
          'timeout',
          'HTTP bridge deadline exceeded',
          504,
        );
      deadline(timeLeft);
      if (
        !methods.has(descriptor.method) ||
        (['GET', 'HEAD'].includes(descriptor.method) && descriptor.hasBody)
      )
        throw new BinaryBridgeError(
          'invalid_bridge_request',
          'Request method does not allow this body',
          400,
        );
      try {
        url = allowedTarget(descriptor.url, hosts);
      } catch {
        throw new BinaryBridgeError(
          'target_not_allowed',
          'Upstream target is not allowed',
          403,
        );
      }
      const nominated = connectionHeaders(descriptor.headers);
      const cookies: string[] = [];
      for (const [name, value] of descriptor.headers) {
        if (
          blockedHeaders.test(name) ||
          hopByHopHeaders.test(name) ||
          nominated.has(name.toLowerCase())
        )
          continue;
        if (name.toLowerCase() === 'cookie') cookies.push(value);
        else headers.append(name, value);
      }
      if (cookies.length) headers.set('cookie', cookies.join('; '));
      const buffer = descriptor.hasBody
        ? new Uint8Array(descriptor.bodyLength ?? HTTP_REQUEST_BODY_LIMIT)
        : undefined;
      let size = 0;
      for (;;) {
        const chunk = await active(input.read(HTTP_FRAME_LIMIT));
        if (chunk === null) break;
        if (!buffer || size + chunk.byteLength > buffer.byteLength)
          throw new BinaryBridgeError(
            'invalid_bridge_request',
            'Request body length does not match metadata',
            400,
          );
        buffer.set(chunk, size);
        size += chunk.byteLength;
      }
      if (descriptor.bodyLength !== null && size !== descriptor.bodyLength)
        throw new BinaryBridgeError(
          'invalid_bridge_request',
          'Request body length does not match metadata',
          400,
        );
      if (buffer) bytes = buffer.subarray(0, size);
    } catch (error) {
      if (failure || error instanceof BinaryBridgeError) throw error;
      if (
        error &&
        typeof error === 'object' &&
        'code' in error &&
        error.code === 'limit_exceeded'
      )
        throw new BinaryBridgeError(
          'body_limit_exceeded',
          'Request body exceeds the byte budget',
          413,
        );
      throw new BinaryBridgeError(
        'invalid_bridge_request',
        'Invalid framed request',
        400,
      );
    }
    const init: RequestInit = {
      method: descriptor.method,
      headers,
      redirect: 'manual',
      cache: 'no-store',
      signal: abort.signal,
    };
    if (bytes !== undefined) init.body = bytes;
    const fetching = fetcher(url, init).then((response) => {
      // A fetch implementation may resolve after it was aborted. Such a body
      // must never escape into this or a later runtime generation.
      if (failure) {
        void response.body?.cancel().catch(() => {});
        throw failure;
      }
      return response;
    });
    const upstream = await active(fetching);
    const hasBody =
      descriptor.method !== 'HEAD' &&
      ![204, 205, 304].includes(upstream.status) &&
      upstream.body !== null;
    const encoded = Boolean(
      upstream.headers.get('content-encoding')?.trim() &&
      upstream.headers.get('content-encoding')?.trim().toLowerCase() !==
        'identity',
    );
    const declaredLength = upstream.headers.get('content-length');
    const bodyLength = !hasBody
      ? 0
      : !encoded && declaredLength !== null && /^\d+$/.test(declaredLength)
        ? Number(declaredLength)
        : null;
    if (hasBody) upstreamReader = upstream.body!.getReader();
    else void upstream.body?.cancel().catch(() => {});
    if (
      bodyLength !== null &&
      (!Number.isSafeInteger(bodyLength) ||
        bodyLength > HTTP_RESPONSE_BODY_LIMIT)
    )
      throw new BinaryBridgeError(
        'body_limit_exceeded',
        'Upstream body exceeds the byte budget',
        413,
      );
    const responseHeaders: [string, string][] = [];
    const nominated = connectionHeaders(upstream.headers);
    for (const [name, value] of upstream.headers) {
      const lower = name.toLowerCase();
      if (
        lower === 'set-cookie' ||
        hopByHopHeaders.test(name) ||
        nominated.has(lower)
      )
        continue;
      if (hasBody && ['content-encoding', 'content-length'].includes(lower))
        continue;
      responseHeaders.push([name, value]);
    }
    for (const cookie of upstream.headers.getSetCookie())
      responseHeaders.push(['set-cookie', cookie]);
    const meta = httpResponseMetaSchema.safeParse({
      requestId: descriptor.requestId,
      runtimeGeneration: descriptor.runtimeGeneration,
      upstreamStatus: upstream.status,
      message: upstream.statusText,
      url: upstream.url || url.href,
      headers: responseHeaders,
      hasBody,
      bodyLength,
      decoded: hasBody,
    });
    if (!meta.success)
      throw new BinaryBridgeError(
        'upstream_metadata_error',
        'Upstream response metadata is invalid',
      );
    let metadataFrame: Uint8Array;
    try {
      metadataFrame = encodeMetaFrame(meta.data);
    } catch {
      throw new BinaryBridgeError(
        'upstream_metadata_error',
        'Upstream response metadata exceeds the framing budget',
      );
    }
    const preamble = encodePreamble();
    const prefix = new Uint8Array(
      preamble.byteLength + metadataFrame.byteLength,
    );
    prefix.set(preamble);
    prefix.set(metadataFrame, preamble.byteLength);
    let metadataOffset = 0;
    let frameTail: Uint8Array | undefined;
    let total = 0;
    const body = new ReadableStream<Uint8Array>(
      {
        async pull(controller) {
          if (cancelled || finished) return;
          try {
            if (metadataOffset < prefix.byteLength) {
              const part = prefix.subarray(
                metadataOffset,
                metadataOffset + HTTP_FRAME_LIMIT,
              );
              metadataOffset += part.byteLength;
              controller.enqueue(part);
              return;
            }
            if (frameTail) {
              const tail = frameTail;
              frameTail = undefined;
              controller.enqueue(tail);
              return;
            }
            if (failure) throw failure;
            while (!remaining && upstreamReader) {
              const result = await active(upstreamReader.read());
              if (cancelled) return;
              if (result.done) break;
              if (!result.value.byteLength) continue;
              if (total + result.value.byteLength > HTTP_RESPONSE_BODY_LIMIT)
                throw new BinaryBridgeError(
                  'limit_exceeded',
                  'Upstream body exceeds the byte budget',
                );
              if (
                bodyLength !== null &&
                total + result.value.byteLength > bodyLength
              )
                throw new BinaryBridgeError(
                  'upstream_body_error',
                  'Upstream body length does not match metadata',
                );
              remaining = result.value;
            }
            if (!remaining) {
              if (bodyLength !== null && total !== bodyLength)
                throw new BinaryBridgeError(
                  'upstream_body_error',
                  'Upstream body length does not match metadata',
                );
              controller.enqueue(encodeEndFrame(total));
              controller.close();
              finished = true;
              cleanup();
              upstreamReader?.releaseLock();
              return;
            }
            const chunk = remaining.subarray(0, HTTP_FRAME_LIMIT);
            remaining =
              remaining.byteLength > chunk.byteLength
                ? remaining.subarray(chunk.byteLength)
                : undefined;
            total += chunk.byteLength;
            const frame = encodeDataFrame(chunk);
            if (frame.byteLength > HTTP_FRAME_LIMIT)
              frameTail = frame.subarray(HTTP_FRAME_LIMIT);
            controller.enqueue(frame.subarray(0, HTTP_FRAME_LIMIT));
          } catch (error) {
            if (cancelled) return;
            const safe = safeFailure(error, true);
            stop(safe);
            finished = true;
            controller.enqueue(
              encodeErrorFrame({ code: safe.code, message: safe.message }),
            );
            controller.close();
          }
        },
        cancel() {
          cancelled = true;
          frameTail = undefined;
          stop(
            new BinaryBridgeError(
              'cancelled',
              'HTTP bridge consumer cancelled',
            ),
          );
          finished = true;
        },
      },
      { highWaterMark: 0 },
    );
    return new Response(body, {
      headers: {
        'Content-Type': HTTP_BRIDGE_MEDIA_TYPE,
        'Cache-Control': 'private, no-store',
        'X-Content-Type-Options': 'nosniff',
      },
    });
  } catch (error) {
    const safe = safeFailure(error);
    stop(safe);
    finished = true;
    return new Response(JSON.stringify({ error: safe.code }), {
      status: safe.status,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'private, no-store',
      },
    });
  }
}

export function createHttpBridge() {
  const app = new Hono<AppEnv>();
  app.post('/http', async (c) => {
    const contentType = c.req.header('content-type')?.trim().toLowerCase();
    const accept = c.req.header('accept')?.trim().toLowerCase();
    const binary = contentType === HTTP_BRIDGE_MEDIA_TYPE;
    if (
      (binary && accept !== HTTP_BRIDGE_MEDIA_TYPE) ||
      (!binary &&
        contentType?.startsWith('application/json') &&
        accept === HTTP_BRIDGE_MEDIA_TYPE)
    )
      return c.json({ error: 'unsupported_bridge_response_protocol' }, 406);
    if (!binary && !contentType?.startsWith('application/json'))
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
    if (binary) return forwardBinary(c.req.raw, hosts);
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
