import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  HTTP_BRIDGE_MEDIA_TYPE,
  HTTP_FRAME_LIMIT,
  HTTP_REQUEST_BODY_LIMIT,
  HTTP_RESPONSE_BODY_LIMIT,
  HttpFrameReader,
  encodeDataFrame,
  encodeEndFrame,
  encodeMetaFrame,
  encodePreamble,
  httpResponseMetaSchema,
  type HttpRequestMeta,
} from '@karuyomi/contracts';
import { createHttpBridge, forwardBinary } from '../src/http-bridge.js';
import { createApp, type Bindings } from '../src/app.js';

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

function metadata(overrides: Partial<HttpRequestMeta> = {}): HttpRequestMeta {
  return {
    requestId: 'request-17',
    runtimeGeneration: 'generation-3',
    url: 'https://example.org/source?token=private-source-token',
    method: 'GET',
    headers: [],
    hasBody: false,
    bodyLength: 0,
    timeoutMs: 30_000,
    ...overrides,
  };
}

function concat(chunks: Uint8Array[]): Uint8Array {
  const bytes = new Uint8Array(
    chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0),
  );
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function frames(meta: unknown, body: Uint8Array[] = []): Uint8Array[] {
  return [
    encodePreamble(),
    encodeMetaFrame(meta),
    ...body.map(encodeDataFrame),
    encodeEndFrame(body.reduce((sum, chunk) => sum + chunk.byteLength, 0)),
  ];
}

function chunksStream(
  chunks: Uint8Array[],
  cancel = vi.fn(),
): ReadableStream<Uint8Array> {
  let index = 0;
  return new ReadableStream(
    {
      pull(controller) {
        if (index < chunks.length) controller.enqueue(chunks[index++]!);
        else controller.close();
      },
      cancel,
    },
    { highWaterMark: 0 },
  );
}

function request(
  meta: HttpRequestMeta = metadata(),
  body: Uint8Array[] = [],
  options: {
    signal?: AbortSignal;
    wire?: Uint8Array[];
    cancel?: ReturnType<typeof vi.fn>;
  } = {},
): Request {
  return new Request('https://read.example.com/api/bridge/http', {
    method: 'POST',
    headers: {
      'Content-Type': HTTP_BRIDGE_MEDIA_TYPE,
      Accept: HTTP_BRIDGE_MEDIA_TYPE,
      'X-Runtime-Build': 'verified-build',
      'X-App-Request': '1',
      Origin: 'https://read.example.com',
    },
    body: chunksStream(options.wire ?? frames(meta, body), options.cancel),
    ...(options.signal ? { signal: options.signal } : {}),
    duplex: 'half',
  } as RequestInit);
}

function responseReader(response: Response): HttpFrameReader {
  expect(response.status).toBe(200);
  expect(response.headers.get('content-type')).toBe(HTTP_BRIDGE_MEDIA_TYPE);
  expect(response.headers.get('set-cookie')).toBeNull();
  return new HttpFrameReader(response.body!, HTTP_RESPONSE_BODY_LIMIT);
}

async function readAll(reader: HttpFrameReader): Promise<Uint8Array> {
  const chunks: Uint8Array[] = [];
  for (;;) {
    const value = await reader.read(HTTP_FRAME_LIMIT);
    if (value === null) return concat(chunks);
    chunks.push(value);
  }
}

async function readUpload(init: RequestInit): Promise<Uint8Array | undefined> {
  if (init.body === undefined) return undefined;
  expect(init.body).toBeInstanceOf(ReadableStream);
  const reader = (init.body as ReadableStream<Uint8Array>).getReader();
  const chunks: Uint8Array[] = [];
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    expect(value.byteLength).toBeLessThanOrEqual(HTTP_FRAME_LIMIT);
    chunks.push(value);
  }
  return concat(chunks);
}

describe('HTTP bridge v2 request validation', () => {
  it('preserves binary request bytes, an empty body, and an absent body across fragmented transport', async () => {
    const bytes = new Uint8Array([0, 255, 128, 0, 13, 10]);
    const meta = metadata({ method: 'POST', hasBody: true, bodyLength: null });
    const encoded = concat(frames(meta, [bytes]));
    const wire = Array.from(encoded, (byte) => new Uint8Array([byte]));
    const fetcher = vi.fn(async (_url, init: RequestInit) => {
      expect(await readUpload(init)).toEqual(bytes);
      return new Response(null);
    });
    await readAll(
      responseReader(
        await forwardBinary(
          request(meta, [], { wire }),
          ['example.org'],
          fetcher as typeof fetch,
        ),
      ),
    );
    for (const hasBody of [true, false]) {
      const fetchEmpty = vi.fn(async (_url, init: RequestInit) => {
        expect(await readUpload(init)).toEqual(
          hasBody ? new Uint8Array() : undefined,
        );
        return new Response(null);
      });
      await readAll(
        responseReader(
          await forwardBinary(
            request(metadata({ method: 'POST', hasBody })),
            ['example.org'],
            fetchEmpty as typeof fetch,
          ),
        ),
      );
    }
  });

  it('strips app and hop headers while preserving Source auth and repeated cookies', async () => {
    const fetcher = vi.fn(async (_url, init: RequestInit) => {
      const headers = new Headers(init.headers);
      expect(init.redirect).toBe('manual');
      expect(init.cache).toBe('no-store');
      expect(headers.get('authorization')).toBe('Bearer source-token');
      expect(headers.get('cookie')).toBe('one=1; two=2');
      for (const name of [
        'cf-access-jwt-assertion',
        'x-app-request',
        'x-runtime-build',
        'connection',
        'x-hop',
        'keep-alive',
        'content-length',
      ])
        expect(headers.get(name)).toBeNull();
      return new Response(null);
    });
    const response = await forwardBinary(
      request(
        metadata({
          headers: [
            ['Cf-Access-Jwt-Assertion', 'app-secret'],
            ['X-App-Request', '1'],
            ['X-Runtime-Build', 'private-build'],
            ['Authorization', 'Bearer source-token'],
            ['Cookie', 'one=1'],
            ['Cookie', 'two=2'],
            ['Connection', 'x-hop'],
            ['X-Hop', 'remove'],
            ['Keep-Alive', 'timeout=5'],
            ['Content-Length', '111'],
          ],
        }),
      ),
      ['example.org'],
      fetcher as typeof fetch,
    );
    await readAll(responseReader(response));
  });

  it.each([
    { method: 'GET', hasBody: true, bodyLength: 0 },
    { method: 'HEAD', hasBody: true, bodyLength: 0 },
    { hasBody: false, bodyLength: null },
    { timeoutMs: 300_001 },
    { runtimeGeneration: '' },
    { headers: [['Bad Header', 'value']] },
    { headers: [['x-source', 'value\r\nsecret']] },
  ])('rejects invalid metadata before fetch: %j', async (overrides) => {
    const fetcher = vi.fn();
    const response = await forwardBinary(
      request(metadata(overrides as Partial<HttpRequestMeta>)),
      ['example.org'],
      fetcher,
    );
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: 'invalid_bridge_request' });
    expect(fetcher).not.toHaveBeenCalled();
  });

  it.each([
    'http://127.0.0.1/private?secret=password',
    'https://user:password@example.org/',
    'https://undeclared.org/private',
  ])(
    'rejects undeclared or unsafe target without reflecting it: %s',
    async (url) => {
      const fetcher = vi.fn();
      const response = await forwardBinary(
        request(metadata({ url })),
        ['example.org'],
        fetcher,
      );
      expect(response.status).toBe(403);
      expect(await response.json()).toEqual({ error: 'target_not_allowed' });
      expect(fetcher).not.toHaveBeenCalled();
    },
  );

  it.each([
    'truncated',
    'trailing',
    'wrong-total',
    'missing-end',
    'wrong-magic',
    'duplicate-meta',
  ])('rejects malformed framing: %s', async (kind) => {
    const meta = metadata();
    let wire = frames(meta);
    if (kind === 'truncated') wire = [concat(wire).subarray(0, -1)];
    if (kind === 'trailing') wire.push(new Uint8Array([99]));
    if (kind === 'wrong-total') wire[2] = encodeEndFrame(1);
    if (kind === 'missing-end') wire.pop();
    if (kind === 'wrong-magic') wire[0] = new Uint8Array(8);
    if (kind === 'duplicate-meta') wire.splice(2, 0, encodeMetaFrame(meta));
    const fetcher = vi.fn();
    const response = await forwardBinary(
      request(meta, [], { wire }),
      ['example.org'],
      fetcher,
    );
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: 'invalid_bridge_request' });
    expect(fetcher).not.toHaveBeenCalled();
  });

  it.each([
    { hasBody: false, bodyLength: 0 },
    { hasBody: true, bodyLength: 0 },
    { hasBody: true, bodyLength: 2 },
  ])(
    'requires DATA byte count to match body presence and declared length: %j',
    async (overrides) => {
      const response = await forwardBinary(
        request(metadata({ method: 'POST', ...overrides }), [
          new Uint8Array([0]),
        ]),
        ['example.org'],
        (async (_url, init) => {
          await readUpload(init!);
          return new Response(null);
        }) as typeof fetch,
      );
      expect(response.status).toBe(400);
      expect(await response.json()).toEqual({
        error: 'invalid_bridge_request',
      });
    },
  );

  it('accepts exactly 8MiB request bytes and cancels a request exceeding that budget', async () => {
    const block = new Uint8Array(HTTP_FRAME_LIMIT).fill(255);
    const blocks = Array.from(
      { length: HTTP_REQUEST_BODY_LIMIT / HTTP_FRAME_LIMIT },
      () => block,
    );
    const meta = metadata({ method: 'POST', hasBody: true, bodyLength: null });
    const fetcher = vi.fn(async (_url, init: RequestInit) => {
      let total = 0;
      const reader = (init.body as ReadableStream<Uint8Array>).getReader();
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        expect(value.byteLength).toBeLessThanOrEqual(HTTP_FRAME_LIMIT);
        total += value.byteLength;
      }
      expect(total).toBe(HTTP_REQUEST_BODY_LIMIT);
      return new Response(null);
    });
    await readAll(
      responseReader(
        await forwardBinary(
          request(meta, blocks),
          ['example.org'],
          fetcher as typeof fetch,
        ),
      ),
    );
    const cancel = vi.fn();
    const over = await forwardBinary(
      request(meta, [...blocks, new Uint8Array([1])], { cancel }),
      ['example.org'],
      fetcher as typeof fetch,
    );
    expect(over.status).toBe(413);
    expect(await over.json()).toEqual({ error: 'body_limit_exceeded' });
    expect(cancel).toHaveBeenCalledOnce();
    expect(fetcher).toHaveBeenCalledTimes(2);
  });
});

describe('HTTP bridge v2 response semantics and backpressure', () => {
  it.each([200, 302, 403])(
    'an early Source %i cannot turn a truncated or mismatched upload into successful END',
    async (status) => {
      for (const malformed of ['missing-end', 'short', 'long', 'trailing']) {
        const meta = metadata({ method: 'POST', hasBody: true, bodyLength: 2 });
        const bytes = new Uint8Array(malformed === 'long' ? [1, 2, 3] : [1]);
        let wire = frames(meta, [bytes]);
        if (malformed === 'missing-end') wire.pop();
        if (malformed === 'trailing')
          wire = [
            ...frames(meta, [new Uint8Array([1, 2])]),
            new Uint8Array([0]),
          ];
        const fetcher = vi.fn(async () => new Response('early', { status }));
        const reader = responseReader(
          await forwardBinary(
            request(meta, [], { wire }),
            ['example.org'],
            fetcher as typeof fetch,
          ),
        );
        expect(
          httpResponseMetaSchema.parse(await reader.meta()).upstreamStatus,
        ).toBe(status);
        await expect(readAll(reader)).rejects.toMatchObject({
          code: 'invalid_bridge_request',
          remote: true,
        });
        expect(fetcher).toHaveBeenCalledOnce();
      }
    },
  );

  it.each([200, 302, 403])(
    'validates a valid upload after early Source %i without sending more bytes upstream',
    async (status) => {
      const bytes = new Uint8Array(HTTP_FRAME_LIMIT).fill(255);
      const meta = metadata({
        method: 'POST',
        hasBody: true,
        bodyLength: bytes.byteLength * 2,
      });
      let uploadReader: ReadableStreamDefaultReader<Uint8Array> | undefined;
      const fetcher = vi.fn(async (_url, init: RequestInit) => {
        uploadReader = (init.body as ReadableStream<Uint8Array>).getReader();
        expect(await uploadReader.read()).toEqual({
          done: false,
          value: bytes,
        });
        // Some peers cancel their unread upload before returning an early reply.
        await uploadReader.cancel();
        return new Response('early', { status });
      });
      const reader = responseReader(
        await forwardBinary(
          request(meta, [bytes, bytes]),
          ['example.org'],
          fetcher as typeof fetch,
        ),
      );
      expect(
        httpResponseMetaSchema.parse(await reader.meta()).upstreamStatus,
      ).toBe(status);
      expect(new TextDecoder().decode(await readAll(reader))).toBe('early');
      expect(await uploadReader!.read()).toEqual({
        done: true,
        value: undefined,
      });
    },
  );

  it('does not consume DATA before the upstream upload asks for it', async () => {
    let pulls = 0;
    const meta = metadata({ method: 'POST', hasBody: true, bodyLength: 2 });
    const wire = frames(meta, [new Uint8Array([1]), new Uint8Array([2])]);
    const source = new ReadableStream<Uint8Array>(
      {
        pull(controller) {
          ++pulls;
          const chunk = wire.shift();
          if (chunk) controller.enqueue(chunk);
          else controller.close();
        },
      },
      { highWaterMark: 0 },
    );
    const incoming = new Request('https://read.example.com/api/bridge/http', {
      method: 'POST',
      body: source,
      duplex: 'half',
    } as RequestInit);
    const fetcher = vi.fn(async (_url, init: RequestInit) => {
      expect(pulls).toBe(2); // preamble + META only
      const reader = (init.body as ReadableStream<Uint8Array>).getReader();
      expect((await reader.read()).value).toEqual(new Uint8Array([1]));
      expect(pulls).toBe(3);
      await Promise.resolve();
      expect(pulls).toBe(3);
      return new Response('early');
    });
    expect(
      new TextDecoder().decode(
        await readAll(
          responseReader(
            await forwardBinary(
              incoming,
              ['example.org'],
              fetcher as typeof fetch,
            ),
          ),
        ),
      ),
    ).toBe('early');
  });

  it('performs no upstream read for metadata or slow consumers, retaining at most one DATA frame', async () => {
    let pulls = 0;
    const cancel = vi.fn();
    const source = new ReadableStream<Uint8Array>(
      {
        pull(controller) {
          ++pulls;
          controller.enqueue(new Uint8Array(HTTP_FRAME_LIMIT).fill(pulls));
        },
        cancel,
      },
      { highWaterMark: 0 },
    );
    const response = await forwardBinary(
      request(),
      ['example.org'],
      (async () => new Response(source)) as typeof fetch,
    );
    expect(pulls).toBe(0);
    const reader = responseReader(response);
    const meta = httpResponseMetaSchema.parse(await reader.meta());
    expect(meta).toMatchObject({
      requestId: 'request-17',
      runtimeGeneration: 'generation-3',
      hasBody: true,
      bodyLength: null,
      decoded: true,
    });
    expect(pulls).toBe(0);
    expect(await reader.read(1)).toEqual(new Uint8Array([1]));
    expect(pulls).toBe(1);
    for (let index = 0; index < 8; ++index)
      expect((await reader.read(1))![0]).toBe(1);
    await Promise.resolve();
    expect(pulls).toBe(1);
    await reader.cancel();
    expect(cancel).toHaveBeenCalledOnce();
  });

  it('preserves duplicate Set-Cookie and a manual redirect as Source metadata only', async () => {
    const headers = new Headers({
      location: 'http://127.0.0.1/private',
      connection: 'x-hop',
      'x-hop': 'remove',
    });
    headers.append('set-cookie', 'one=1; Path=/');
    headers.append('set-cookie', 'two=2; Path=/');
    const fetcher = vi.fn(
      async () =>
        new Response(new Uint8Array([0, 255]), { status: 302, headers }),
    );
    const reader = responseReader(
      await forwardBinary(request(), ['example.org'], fetcher as typeof fetch),
    );
    const meta = httpResponseMetaSchema.parse(await reader.meta());
    expect(meta.upstreamStatus).toBe(302);
    expect(meta.headers).toContainEqual([
      'location',
      'http://127.0.0.1/private',
    ]);
    expect(meta.headers.filter(([name]) => name === 'set-cookie')).toEqual([
      ['set-cookie', 'one=1; Path=/'],
      ['set-cookie', 'two=2; Path=/'],
    ]);
    expect(
      meta.headers.some(([name]) => ['connection', 'x-hop'].includes(name)),
    ).toBe(false);
    expect(await readAll(reader)).toEqual(new Uint8Array([0, 255]));
    expect(fetcher).toHaveBeenCalledOnce();
  });

  it.each([
    { method: 'HEAD', status: 200 },
    { method: 'GET', status: 204 },
    { method: 'GET', status: 304 },
  ])(
    'preserves bodyless representation headers for $method $status',
    async ({ method, status }) => {
      const reader = responseReader(
        await forwardBinary(
          request(metadata({ method })),
          ['example.org'],
          (async () =>
            new Response(null, {
              status,
              headers: {
                'content-length': '1234',
                'content-encoding': 'gzip',
                etag: 'source-etag',
              },
            })) as typeof fetch,
        ),
      );
      const meta = httpResponseMetaSchema.parse(await reader.meta());
      expect(meta).toMatchObject({
        upstreamStatus: status,
        hasBody: false,
        bodyLength: 0,
        decoded: false,
      });
      expect(meta.headers).toContainEqual(['content-length', '1234']);
      expect(meta.headers).toContainEqual(['content-encoding', 'gzip']);
      expect(await reader.read(1)).toBeNull();
    },
  );

  it.each([200, 206, 403])(
    'keeps Source status %i and decoded binary bytes without transport length/encoding',
    async (status) => {
      const headers = new Headers({
        'content-encoding': 'gzip',
        'content-length': '999',
        'content-range': 'bytes 0-2/40',
        'content-type': 'image/jpeg',
      });
      const reader = responseReader(
        await forwardBinary(
          request(),
          ['example.org'],
          (async () =>
            new Response(new Uint8Array([0, 255, 128]), {
              status,
              headers,
            })) as typeof fetch,
        ),
      );
      const meta = httpResponseMetaSchema.parse(await reader.meta());
      expect(meta).toMatchObject({
        upstreamStatus: status,
        decoded: true,
        hasBody: true,
        bodyLength: null,
      });
      expect(
        meta.headers.some(([name]) =>
          ['content-encoding', 'content-length'].includes(name),
        ),
      ).toBe(false);
      expect(meta.headers).toContainEqual(['content-range', 'bytes 0-2/40']);
      expect(await readAll(reader)).toEqual(new Uint8Array([0, 255, 128]));
    },
  );

  it.each([1, 3])(
    'terminates a mismatched declared response length %i with ERROR',
    async (length) => {
      const reader = responseReader(
        await forwardBinary(
          request(),
          ['example.org'],
          (async () =>
            new Response(new Uint8Array([1, 2]), {
              headers: { 'content-length': String(length) },
            })) as typeof fetch,
        ),
      );
      const meta = httpResponseMetaSchema.parse(await reader.meta());
      expect(meta.bodyLength).toBe(length);
      await expect(readAll(reader)).rejects.toMatchObject({
        code: 'upstream_body_error',
        remote: true,
      });
    },
  );

  it('streams 64MiB without aggregation, then cancels at the first extra byte', async () => {
    let pulls = 0;
    let upstreamSignal: AbortSignal | undefined;
    const cancel = vi.fn();
    const block = new Uint8Array(HTTP_FRAME_LIMIT);
    const source = new ReadableStream<Uint8Array>(
      {
        pull(controller) {
          ++pulls;
          controller.enqueue(
            pulls <= HTTP_RESPONSE_BODY_LIMIT / HTTP_FRAME_LIMIT
              ? block
              : new Uint8Array([1]),
          );
        },
        cancel,
      },
      { highWaterMark: 0 },
    );
    const reader = responseReader(
      await forwardBinary(request(), ['example.org'], (async (
        _url,
        init: RequestInit,
      ) => {
        upstreamSignal = init.signal!;
        return new Response(source);
      }) as typeof fetch),
    );
    await reader.meta();
    let size = 0;
    for (
      let index = 0;
      index < HTTP_RESPONSE_BODY_LIMIT / HTTP_FRAME_LIMIT;
      ++index
    )
      size += (await reader.read(HTTP_FRAME_LIMIT))!.byteLength;
    expect(size).toBe(HTTP_RESPONSE_BODY_LIMIT);
    expect(pulls).toBe(1024);
    await expect(reader.read(1)).rejects.toMatchObject({
      code: 'limit_exceeded',
      remote: true,
    });
    expect(cancel).toHaveBeenCalledOnce();
    expect(upstreamSignal?.aborted).toBe(true);
  });

  it('rejects an advertised oversized response before reading a single body chunk', async () => {
    const pull = vi.fn();
    const cancel = vi.fn();
    const source = new ReadableStream<Uint8Array>(
      { pull, cancel },
      { highWaterMark: 0 },
    );
    const response = await forwardBinary(
      request(),
      ['example.org'],
      (async () =>
        new Response(source, {
          headers: { 'content-length': String(HTTP_RESPONSE_BODY_LIMIT + 1) },
        })) as typeof fetch,
    );
    expect(response.status).toBe(413);
    expect(await response.json()).toEqual({ error: 'body_limit_exceeded' });
    expect(pull).not.toHaveBeenCalled();
    expect(cancel).toHaveBeenCalledOnce();
  });

  it('returns only fixed error text for upstream exceptions containing credentials', async () => {
    const response = await forwardBinary(
      request(),
      ['example.org'],
      (async () => {
        throw new Error('https://user:password@example.org/?token=secret');
      }) as typeof fetch,
    );
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: 'upstream_network_error' });
  });
});

describe('HTTP bridge v2 response boundary failures', () => {
  it('ends an exact 64MiB response without buffering the whole body', async () => {
    let remaining = HTTP_RESPONSE_BODY_LIMIT;
    const block = new Uint8Array(HTTP_FRAME_LIMIT);
    const source = new ReadableStream<Uint8Array>(
      {
        pull(controller) {
          if (!remaining) controller.close();
          else {
            remaining -= block.byteLength;
            controller.enqueue(block);
          }
        },
      },
      { highWaterMark: 0 },
    );
    const reader = responseReader(
      await forwardBinary(
        request(),
        ['example.org'],
        (async () => new Response(source)) as typeof fetch,
      ),
    );
    let total = 0;
    for (;;) {
      const bytes = await reader.read(HTTP_FRAME_LIMIT);
      if (bytes === null) break;
      total += bytes.byteLength;
    }
    expect(total).toBe(HTTP_RESPONSE_BODY_LIMIT);
  });

  it('splits a large upstream chunk into bounded frames without another upstream read', async () => {
    let pulls = 0;
    const source = new ReadableStream<Uint8Array>(
      {
        pull(controller) {
          ++pulls;
          if (pulls === 1)
            controller.enqueue(new Uint8Array(HTTP_FRAME_LIMIT * 3).fill(255));
          else controller.close();
        },
      },
      { highWaterMark: 0 },
    );
    const reader = responseReader(
      await forwardBinary(
        request(),
        ['example.org'],
        (async () => new Response(source)) as typeof fetch,
      ),
    );
    for (let index = 0; index < 3; ++index) {
      const bytes = await reader.read(HTTP_FRAME_LIMIT);
      expect(bytes?.byteLength).toBe(HTTP_FRAME_LIMIT);
      expect(bytes?.[HTTP_FRAME_LIMIT - 1]).toBe(255);
      expect(pulls).toBe(1);
    }
    expect(await reader.read(1)).toBeNull();
    expect(pulls).toBe(2);
  });

  it('rejects metadata larger than 64KiB and cancels its unconsumed body', async () => {
    const cancel = vi.fn();
    const headers = new Headers();
    for (let index = 0; index < 5; ++index)
      headers.set('x-metadata-' + index, 'x'.repeat(16_000));
    const source = new ReadableStream<Uint8Array>(
      { cancel },
      { highWaterMark: 0 },
    );
    const response = await forwardBinary(
      request(),
      ['example.org'],
      (async () => new Response(source, { headers })) as typeof fetch,
    );
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: 'upstream_metadata_error' });
    expect(cancel).toHaveBeenCalledOnce();
  });

  it('terminates a failed upstream body with sanitized ERROR and aborts fetch', async () => {
    let signal: AbortSignal | undefined;
    const source = new ReadableStream<Uint8Array>(
      {
        pull(controller) {
          controller.error(
            new Error('https://user:password@example.org/private'),
          );
        },
      },
      { highWaterMark: 0 },
    );
    const reader = responseReader(
      await forwardBinary(request(), ['example.org'], (async (
        _url,
        init: RequestInit,
      ) => {
        signal = init.signal!;
        return new Response(source);
      }) as typeof fetch),
    );
    await reader.meta();
    await expect(reader.read(1)).rejects.toMatchObject({
      code: 'upstream_body_error',
      message: 'Upstream response body could not be read',
      remote: true,
    });
    expect(signal?.aborted).toBe(true);
  });
});

describe('HTTP bridge v2 lifecycle', () => {
  it('keeps the deadline active after returning a Response and cancels pending reads', async () => {
    vi.useFakeTimers();
    const cancel = vi.fn();
    let signal: AbortSignal | undefined;
    const source = new ReadableStream<Uint8Array>(
      { cancel },
      { highWaterMark: 0 },
    );
    const response = await forwardBinary(
      request(metadata({ timeoutMs: 50 })),
      ['example.org'],
      (async (_url, init: RequestInit) => {
        signal = init.signal!;
        return new Response(source);
      }) as typeof fetch,
    );
    const reader = responseReader(response);
    await reader.meta();
    const reading = reader.read(1);
    const rejection = expect(reading).rejects.toMatchObject({
      code: 'timeout',
      remote: true,
    });
    await vi.advanceTimersByTimeAsync(50);
    await rejection;
    expect(cancel).toHaveBeenCalledOnce();
    expect(signal?.aborted).toBe(true);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('cancels upstream even if the response is never consumed', async () => {
    vi.useFakeTimers();
    const cancel = vi.fn();
    const source = new ReadableStream<Uint8Array>(
      { cancel },
      { highWaterMark: 0 },
    );
    const response = await forwardBinary(
      request(metadata({ timeoutMs: 10 })),
      ['example.org'],
      (async () => new Response(source)) as typeof fetch,
    );
    await vi.advanceTimersByTimeAsync(10);
    expect(cancel).toHaveBeenCalledOnce();
    const reader = responseReader(response);
    await reader.meta();
    await expect(reader.read(1)).rejects.toMatchObject({
      code: 'timeout',
      remote: true,
    });
    expect(vi.getTimerCount()).toBe(0);
  });

  it.each(['consumer', 'request'])(
    'aborts fetch and reader when %s cancels, including an in-flight read',
    async (mode) => {
      vi.useFakeTimers();
      const abort = new AbortController();
      const cancel = vi.fn();
      let signal: AbortSignal | undefined;
      const source = new ReadableStream<Uint8Array>(
        { cancel },
        { highWaterMark: 0 },
      );
      const response = await forwardBinary(
        request(metadata(), [], { signal: abort.signal }),
        ['example.org'],
        (async (_url, init: RequestInit) => {
          signal = init.signal!;
          return new Response(source);
        }) as typeof fetch,
      );
      const reader = responseReader(response);
      await reader.meta();
      const reading = reader.read(1);
      let rejection: Promise<void> | undefined;
      if (mode === 'request') {
        rejection = expect(reading).rejects.toMatchObject({
          code: 'cancelled',
          remote: true,
        });
        abort.abort(new Error('private cancellation reason'));
      } else {
        rejection = expect(reading).rejects.toMatchObject({
          code: 'cancelled',
        });
        await reader.cancel();
      }
      await rejection;
      expect(cancel).toHaveBeenCalledOnce();
      expect(signal?.aborted).toBe(true);
      expect(vi.getTimerCount()).toBe(0);
    },
  );

  it('includes metadata upload time in the declared timeout', async () => {
    vi.useFakeTimers();
    const cancel = vi.fn();
    const meta = metadata({ timeoutMs: 10 });
    let controller!: ReadableStreamDefaultController<Uint8Array>;
    const body = new ReadableStream<Uint8Array>(
      {
        start(value) {
          controller = value;
        },
        cancel,
      },
      { highWaterMark: 0 },
    );
    const incoming = new Request('https://read.example.com/api/bridge/http', {
      method: 'POST',
      body,
      duplex: 'half',
    } as RequestInit);
    const fetcher = vi.fn();
    const forwarding = forwardBinary(incoming, ['example.org'], fetcher);
    await vi.advanceTimersByTimeAsync(20);
    controller.enqueue(concat(frames(meta)));
    const response = await forwarding;
    expect(response.status).toBe(504);
    expect(await response.json()).toEqual({ error: 'timeout' });
    expect(cancel).toHaveBeenCalledOnce();
    expect(fetcher).not.toHaveBeenCalled();
  });

  it('cancels a stalled upload after META and aborts its in-flight upstream fetch', async () => {
    vi.useFakeTimers();
    const cancel = vi.fn();
    let first = true;
    const body = new ReadableStream<Uint8Array>(
      {
        pull(controller) {
          if (first) {
            first = false;
            controller.enqueue(
              concat([
                encodePreamble(),
                encodeMetaFrame(
                  metadata({
                    method: 'POST',
                    hasBody: true,
                    bodyLength: null,
                    timeoutMs: 10,
                  }),
                ),
              ]),
            );
          }
        },
        cancel,
      },
      { highWaterMark: 0 },
    );
    const incoming = new Request('https://read.example.com/api/bridge/http', {
      method: 'POST',
      body,
      duplex: 'half',
    } as RequestInit);
    const fetcher = vi.fn(async (_url, init: RequestInit) => {
      await readUpload(init);
      return new Response(null);
    });
    const forwarding = forwardBinary(incoming, ['example.org'], fetcher);
    await vi.advanceTimersByTimeAsync(10);
    const response = await forwarding;
    expect(response.status).toBe(504);
    expect(await response.json()).toEqual({ error: 'timeout' });
    expect(cancel).toHaveBeenCalledOnce();
    expect(fetcher).toHaveBeenCalledOnce();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('cancels an already-aborted incoming request without reading it', async () => {
    const abort = new AbortController();
    abort.abort(new Error('secret reason'));
    const cancel = vi.fn();
    const fetcher = vi.fn();
    const response = await forwardBinary(
      request(metadata(), [], { signal: abort.signal, cancel }),
      ['example.org'],
      fetcher,
    );
    expect(response.status).toBe(502);
    expect(await response.json()).toEqual({ error: 'cancelled' });
    expect(cancel).toHaveBeenCalledOnce();
    expect(fetcher).not.toHaveBeenCalled();
  });

  it('cancels a response body returned by a late fetch after request timeout', async () => {
    vi.useFakeTimers();
    let resolve!: (response: Response) => void;
    const fetching = new Promise<Response>((value) => {
      resolve = value;
    });
    const fetcher = vi.fn(() => fetching);
    const forwarding = forwardBinary(
      request(metadata({ timeoutMs: 5 })),
      ['example.org'],
      fetcher as typeof fetch,
    );
    await vi.advanceTimersByTimeAsync(0);
    expect(fetcher).toHaveBeenCalledOnce();
    await vi.advanceTimersByTimeAsync(5);
    const response = await forwarding;
    expect(response.status).toBe(504);
    const cancel = vi.fn();
    resolve(
      new Response(
        new ReadableStream<Uint8Array>({ cancel }, { highWaterMark: 0 }),
      ),
    );
    await vi.advanceTimersByTimeAsync(0);
    expect(cancel).toHaveBeenCalledOnce();
    expect(vi.getTimerCount()).toBe(0);
  });

  it('cleans up its deadline on successful END and rejects no later runtime generation', async () => {
    vi.useFakeTimers();
    let signal: AbortSignal | undefined;
    const reader = responseReader(
      await forwardBinary(request(), ['example.org'], (async (
        _url,
        init: RequestInit,
      ) => {
        signal = init.signal!;
        return new Response(new Uint8Array([9]));
      }) as typeof fetch),
    );
    expect(await readAll(reader)).toEqual(new Uint8Array([9]));
    expect(vi.getTimerCount()).toBe(0);
    await vi.advanceTimersByTimeAsync(60_000);
    expect(signal?.aborted).toBe(false);
  });
});

describe('HTTP bridge v2 route negotiation and existing Access boundary', () => {
  const env = {
    ACCESS_TEAM_DOMAIN: 'example.cloudflareaccess.com',
    ACCESS_AUD: 'audience',
    OWNER_EMAIL: 'owner@example.com',
    APP_ORIGIN: 'https://read.example.com',
    DB: {
      prepare: () => ({
        bind: () => ({
          first: async () => ({ allowed_hosts_json: '["example.org"]' }),
        }),
      }),
    },
  } as unknown as Bindings;

  it.each([
    { contentType: HTTP_BRIDGE_MEDIA_TYPE, accept: '*/*', status: 406 },
    {
      contentType: HTTP_BRIDGE_MEDIA_TYPE,
      accept: 'application/json',
      status: 406,
    },
    {
      contentType: 'application/json',
      accept: HTTP_BRIDGE_MEDIA_TYPE,
      status: 415,
    },
    {
      contentType: 'application/json',
      accept: 'application/json',
      status: 415,
    },
    {
      contentType: HTTP_BRIDGE_MEDIA_TYPE + '; charset=utf-8',
      accept: HTTP_BRIDGE_MEDIA_TYPE,
      status: 415,
    },
    {
      contentType: 'application/octet-stream',
      accept: HTTP_BRIDGE_MEDIA_TYPE,
      status: 415,
    },
  ])(
    'strictly negotiates framed request/response media types: %j',
    async ({ contentType, accept, status }) => {
      const response = await createHttpBridge().request(
        'https://read.example.com/http',
        { method: 'POST', headers: { 'content-type': contentType, accept } },
        env,
      );
      expect(response.status).toBe(status);
    },
  );

  it('uses the v2 handler only after the verified build network policy is loaded', async () => {
    const fetcher = vi.fn(async () => new Response(new Uint8Array([0, 255])));
    vi.stubGlobal('fetch', fetcher);
    const incoming = request();
    const response = await createHttpBridge().request(
      new Request('https://read.example.com/http', incoming),
      undefined,
      env,
    );
    expect(await readAll(responseReader(response))).toEqual(
      new Uint8Array([0, 255]),
    );
    expect(fetcher).toHaveBeenCalledOnce();
  });

  it('still rejects missing Access JWT or wrong Origin before the v2 handler', async () => {
    const verify = vi.fn(async () => ({
      subject: 'owner',
      email: 'owner@example.com',
      expiresAt: 1_900_000_000,
    }));
    const app = createApp(verify);
    const anonymous = await app.request(request(), undefined, env);
    expect(anonymous.status).toBe(401);
    expect(verify).not.toHaveBeenCalled();
    const incoming = request();
    incoming.headers.set('Cf-Access-Jwt-Assertion', 'test-token');
    incoming.headers.set('Origin', 'https://evil.example.org');
    const wrongOrigin = await app.request(incoming, undefined, env);
    expect(wrongOrigin.status).toBe(403);
    expect(await wrongOrigin.json()).toEqual({ error: 'invalid_origin' });
  });
});
