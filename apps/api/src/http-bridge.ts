import { Hono } from 'hono';
import type { AppEnv } from './env.js';
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
  type HttpRequestMeta,
} from '@karuyomi/contracts';

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
const HTTP_META_DEADLINE_MS = 30_000;
const HTTP_HARD_DEADLINE_MS = 300_000;

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
 * consumer pulls. META timeoutMs limits waiting on upstream reads; an independent
 * deadline and abort linkage live until END, ERROR or cancel.
 */
export async function forwardBinary(
  request: Request,
  fetcher: typeof fetch = (...args) => fetch(...args),
): Promise<Response> {
  const started = Date.now();
  const abort = new AbortController();
  let input: HttpFrameReader | undefined;
  let unclaimedUpstream: ReadableStream<Uint8Array> | null | undefined;
  let upstreamReader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  let remaining: Uint8Array | undefined;
  let failure: BinaryBridgeError | undefined;
  let finished = false;
  let cancelled = false;
  let deadlineTimer: ReturnType<typeof setTimeout>;
  let readIdleTimer: ReturnType<typeof setTimeout> | null = null;
  const cleanup = () => {
    clearTimeout(deadlineTimer);
    if (readIdleTimer !== null) clearTimeout(readIdleTimer);
    request.signal.removeEventListener('abort', onAbort);
  };
  const stop = (error: BinaryBridgeError) => {
    if (finished || failure) return;
    failure = error;
    remaining = undefined;
    cleanup();
    abort.abort(error);
    // A broken upstream cancel implementation must not hold up cancellation of
    // the response. Fetch is also aborted independently of its reader.
    void input?.cancel(error).catch(() => {});
    if (upstreamReader) {
      const reader = upstreamReader;
      upstreamReader = undefined;
      void reader.cancel(error).catch(() => {});
      reader.releaseLock();
    }
    void unclaimedUpstream?.cancel(error).catch(() => {});
    unclaimedUpstream = undefined;
  };
  const onAbort = () =>
    stop(
      new BinaryBridgeError('cancelled', 'HTTP bridge request was cancelled'),
    );
  const deadline = (milliseconds: number) => {
    clearTimeout(deadlineTimer);
    deadlineTimer = setTimeout(
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
  const startReadIdle = (milliseconds: number) => {
    if (failure || readIdleTimer !== null) return;
    readIdleTimer = setTimeout(
      () =>
        stop(
          new BinaryBridgeError('timeout', 'Upstream HTTP read timed out', 504),
        ),
      milliseconds,
    );
  };
  const stopReadIdle = () => {
    if (readIdleTimer !== null) clearTimeout(readIdleTimer);
    readIdleTimer = null;
  };
  async function active<T>(operation: Promise<T>): Promise<T> {
    if (failure) {
      void operation.catch(() => {});
      throw failure;
    }
    // Keep a listener only while this I/O is pending. A shared abort Promise
    // raced against every read would retain one reaction per DATA chunk.
    let interrupt!: () => void;
    try {
      const result = await new Promise<T>((resolve, reject) => {
        interrupt = () => reject(abort.signal.reason);
        abort.signal.addEventListener('abort', interrupt, { once: true });
        void operation.then(resolve, reject);
      });
      if (failure) throw failure;
      return result;
    } finally {
      abort.signal.removeEventListener('abort', interrupt);
    }
  }
  async function readUpstream(
    reader: ReadableStreamDefaultReader<Uint8Array>,
    readIdleMs: number,
  ): Promise<Uint8Array | undefined> {
    startReadIdle(readIdleMs);
    let emptyReadYield: ReturnType<typeof setTimeout> | null = null;
    try {
      for (;;) {
        const result = await active(reader.read());
        if (result.done) return undefined;
        if (result.value.byteLength) return result.value;
        // Empty reads aren't progress. Let either timer fire even if a peer
        // can supply empty chunks without ever waiting for network I/O.
        await active(
          new Promise<void>((resolve) => {
            emptyReadYield = setTimeout(resolve, 0);
          }),
        );
      }
    } finally {
      if (emptyReadYield !== null) clearTimeout(emptyReadYield);
      stopReadIdle();
    }
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
  const requestFailure = (error: unknown): BinaryBridgeError => {
    if (failure) return failure;
    if (error instanceof BinaryBridgeError) return error;
    if (
      error &&
      typeof error === 'object' &&
      'code' in error &&
      error.code === 'limit_exceeded'
    )
      return new BinaryBridgeError(
        'body_limit_exceeded',
        'Request body exceeds the byte budget',
        413,
      );
    return new BinaryBridgeError(
      'invalid_bridge_request',
      'Invalid framed request',
      400,
    );
  };
  request.signal.addEventListener('abort', onAbort, { once: true });
  deadline(HTTP_META_DEADLINE_MS);
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
    let descriptor: HttpRequestMeta;
    let upload: ReadableStream<Uint8Array> | undefined;
    let awaitingHeaders = true;
    let validateUpload = async () => {};
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
      const timeLeft = HTTP_HARD_DEADLINE_MS - (Date.now() - started);
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
        url = new URL(descriptor.url);
        if (
          !['https:', 'http:'].includes(url.protocol) ||
          url.username ||
          url.password
        )
          throw new Error(
            'Expected an HTTP(S) URL without embedded credentials',
          );
      } catch {
        throw new BinaryBridgeError(
          'invalid_bridge_request',
          'Invalid upstream HTTP URL',
          400,
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
      if (descriptor.hasBody) {
        const framed = input;
        const length = descriptor.bodyLength;
        let size = 0;
        let ended = false;
        let stopped = false;
        let uploadController: ReadableStreamDefaultController<Uint8Array>;
        let pendingPull: Promise<void> | undefined;
        const next = async () => {
          const chunk = await active(framed.read(HTTP_FRAME_LIMIT));
          if (chunk === null) {
            if (length !== null && size !== length)
              throw new BinaryBridgeError(
                'invalid_bridge_request',
                'Request body length does not match metadata',
                400,
              );
            ended = true;
          } else {
            if (length !== null && size + chunk.byteLength > length)
              throw new BinaryBridgeError(
                'invalid_bridge_request',
                'Request body length does not match metadata',
                400,
              );
            size += chunk.byteLength;
          }
          return chunk;
        };
        validateUpload = async () => {
          // An early upstream response may leave its upload unread/cancelled.
          // Stop forwarding to that peer and validate the same input reader to
          // END+EOF, discarding at most one bounded DATA chunk at a time.
          stopped = true;
          try {
            uploadController.close();
          } catch {
            /* already closed/cancelled */
          }
          if (pendingPull) await active(pendingPull);
          while (!ended) await next();
        };
        upload = new ReadableStream<Uint8Array>(
          {
            start(controller) {
              uploadController = controller;
            },
            pull(controller) {
              if (stopped) return;
              pendingPull = (async () => {
                try {
                  const chunk = await next();
                  if (stopped) return;
                  if (chunk === null) {
                    controller.close();
                    // The upstream request can now wait for response headers.
                    if (awaitingHeaders) startReadIdle(descriptor.timeoutMs);
                  } else controller.enqueue(chunk);
                } catch (error) {
                  const safe = requestFailure(error);
                  stop(safe);
                  if (!stopped) controller.error(safe);
                }
              })();
              return pendingPull;
            },
            cancel() {
              stopped = true;
              if (awaitingHeaders) startReadIdle(descriptor.timeoutMs);
            },
          },
          { highWaterMark: 0 },
        );
      } else if ((await active(input.read(HTTP_FRAME_LIMIT))) !== null) {
        throw new BinaryBridgeError(
          'invalid_bridge_request',
          'Unexpected request body bytes',
          400,
        );
      }
    } catch (error) {
      throw requestFailure(error);
    }
    const init: RequestInit = {
      method: descriptor.method,
      headers,
      redirect: 'manual',
      cache: 'no-store',
      signal: abort.signal,
    };
    if (upload !== undefined) init.body = upload;
    else startReadIdle(descriptor.timeoutMs);
    let upstream: Response;
    try {
      const fetching = fetcher(url, init).then((response) => {
        // A fetch implementation may resolve after it was aborted. Such a body
        // must never escape into this or a later runtime generation.
        if (failure) {
          void response.body?.cancel().catch(() => {});
          throw failure;
        }
        unclaimedUpstream = response.body;
        return response;
      });
      upstream = await active(fetching);
    } finally {
      awaitingHeaders = false;
      stopReadIdle();
    }
    if (failure) throw failure;
    const requestValidated = validateUpload().catch((error: unknown) => {
      stop(requestFailure(error));
    });
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
    unclaimedUpstream = undefined;
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
            if (!remaining && upstreamReader) {
              const chunk = await readUpstream(
                upstreamReader,
                descriptor.timeoutMs,
              );
              if (cancelled) return;
              if (failure) throw failure;
              if (chunk && total + chunk.byteLength > HTTP_RESPONSE_BODY_LIMIT)
                throw new BinaryBridgeError(
                  'limit_exceeded',
                  'Upstream body exceeds the byte budget',
                );
              if (
                chunk &&
                bodyLength !== null &&
                total + chunk.byteLength > bodyLength
              )
                throw new BinaryBridgeError(
                  'upstream_body_error',
                  'Upstream body length does not match metadata',
                );
              remaining = chunk;
            }
            if (!remaining) {
              await active(requestValidated);
              if (cancelled) return;
              if (failure) throw failure;
              if (bodyLength !== null && total !== bodyLength)
                throw new BinaryBridgeError(
                  'upstream_body_error',
                  'Upstream body length does not match metadata',
                );
              controller.enqueue(encodeEndFrame(total));
              controller.close();
              finished = true;
              cleanup();
              void input?.cancel().catch(() => {});
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
    if (contentType !== HTTP_BRIDGE_MEDIA_TYPE)
      return c.json({ error: 'unsupported_bridge_protocol' }, 415);
    if (accept !== HTTP_BRIDGE_MEDIA_TYPE)
      return c.json({ error: 'unsupported_bridge_response_protocol' }, 406);
    return forwardBinary(c.req.raw);
  });
  return app;
}
