import { afterEach, expect, test, vi } from 'vitest';
import { createServer } from 'node:http';
import {
  HTTP_BRIDGE_MEDIA_TYPE,
  HTTP_FRAME_LIMIT,
  HttpFrameReader,
  encodePreamble,
  encodeMetaFrame,
  encodeDataFrame,
  encodeEndFrame,
  httpRequestMetaSchema,
  type HttpRequestMeta,
} from '@karuyomi/contracts';
import {
  BinaryHttpTransport,
  HttpOwnerFailure,
} from '../src/http-transport.js';

const buildIdentity = {
  buildId: 'test-build',
  catalog: {
    catalogUrl: 'https://read.example/extensions/index.json',
    repoId: 'test-repo',
  },
  bundleSha256: 'a'.repeat(64),
};
const transports: BinaryHttpTransport[] = [];
afterEach(() => {
  for (const transport of transports.splice(0)) transport.dispose();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

function metadata(
  transport: BinaryHttpTransport,
  overrides: Record<string, unknown> = {},
) {
  return JSON.stringify({
    operationRequestId: 'operation-1',
    operationGeneration: 'generation-1',
    operationToken: transport.operationToken,
    url: 'https://source.example/chapter',
    method: 'GET',
    headers: [['Cookie', 'source=private']],
    hasBody: false,
    bodyLength: 0,
    timeoutMs: 30_000,
    ...overrides,
  });
}

function setup(fetcher?: typeof fetch) {
  const transport = new BinaryHttpTransport(
    'https://read.example',
    buildIdentity,
    fetcher,
  );
  transports.push(transport);
  transport.begin({ requestId: 'operation-1', generation: 'generation-1' });
  return transport;
}

function framedResponse(
  request: HttpRequestMeta,
  chunks: Uint8Array[],
  overrides: Record<string, unknown> = {},
  cancel = () => {},
) {
  const frames = [
    encodePreamble(),
    encodeMetaFrame({
      requestId: request.requestId,
      runtimeGeneration: request.runtimeGeneration,
      upstreamStatus: 200,
      message: 'OK',
      url: request.url,
      headers: [['set-cookie', 'source=new']],
      hasBody: true,
      bodyLength: null,
      decoded: true,
      ...overrides,
    }),
    ...chunks.map(encodeDataFrame),
    encodeEndFrame(chunks.reduce((sum, chunk) => sum + chunk.byteLength, 0)),
  ];
  return new Response(
    new ReadableStream<Uint8Array>(
      {
        pull(controller) {
          const next = frames.shift();
          if (next) controller.enqueue(next);
          else controller.close();
        },
        cancel,
      },
      { highWaterMark: 0 },
    ),
    { headers: { 'Content-Type': HTTP_BRIDGE_MEDIA_TYPE } },
  );
}

test('binary upload retains exact bytes, local identities and Source headers', async () => {
  const upload = Uint8Array.from(
    { length: HTTP_FRAME_LIMIT + 17 },
    (_, i) => i % 256,
  );
  const expected = upload.slice();
  let actual!: HttpRequestMeta;
  const transport = setup((async (url, init) => {
    expect(String(url)).toBe('https://read.example/api/bridge/http');
    expect(init).toMatchObject({
      credentials: 'same-origin',
      redirect: 'manual',
      cache: 'no-store',
    });
    const headers = new Headers(init?.headers);
    expect(headers.get('x-runtime-build')).toBe('test-build');
    expect(headers.get('x-runtime-catalog')).toBe(
      buildIdentity.catalog.catalogUrl,
    );
    expect(headers.get('x-runtime-repo')).toBe(buildIdentity.catalog.repoId);
    expect(headers.get('x-runtime-bundle')).toBe(buildIdentity.bundleSha256);
    expect(headers.get('accept')).toBe(HTTP_BRIDGE_MEDIA_TYPE);
    expect(headers.get('cookie')).toBeNull();
    const reader = new HttpFrameReader(
      (init!.body as Blob).stream(),
      8 * 1024 * 1024,
    );
    actual = (await reader.meta()) as HttpRequestMeta;
    expect(actual.runtimeGeneration).toBe('generation-1');
    expect(actual.requestId).not.toBe('forged');
    expect(actual.headers).toEqual([['Cookie', 'source=private']]);
    const received = new Uint8Array(upload.byteLength);
    let offset = 0;
    for (;;) {
      const chunk = await reader.read(37_000);
      if (chunk === null) break;
      received.set(chunk, offset);
      offset += chunk.byteLength;
    }
    expect(received).toEqual(expected);
    return framedResponse(actual, [new Uint8Array([0, 255, 42])], {
      upstreamStatus: 403,
    });
  }) as typeof fetch);
  const handle = transport.open(
    metadata(transport, {
      method: 'POST',
      hasBody: true,
      bodyLength: upload.byteLength,
      requestId: 'forged',
      runtimeGeneration: 'forged',
    }),
  );
  transport.write(handle, upload.subarray(0, HTTP_FRAME_LIMIT));
  transport.write(handle, upload.subarray(HTTP_FRAME_LIMIT));
  // The transport owns a copy rather than a mutable Java/JSO view.
  upload.fill(0);
  const response = JSON.parse(await transport.finish(handle));
  expect(response).toMatchObject({ handle, upstreamStatus: 403 });
  expect(await transport.read(handle, 2)).toEqual(new Uint8Array([0, 255]));
  expect(await transport.read(handle, 2)).toEqual(new Uint8Array([42]));
  expect(await transport.read(handle, 2)).toBeNull();
});

test('the production fetch default is called without binding the transport as its receiver', async () => {
  const fetcher = vi.fn(async function (
    this: unknown,
    _url: Parameters<typeof fetch>[0],
    init?: Parameters<typeof fetch>[1],
  ) {
    expect(this).not.toBeInstanceOf(BinaryHttpTransport);
    if (!(init?.body instanceof Blob)) throw Error('Expected framed upload');
    const reader = new HttpFrameReader(init.body.stream(), 8 * 1024 * 1024);
    return framedResponse(httpRequestMetaSchema.parse(await reader.meta()), []);
  });
  vi.stubGlobal('fetch', fetcher);
  const transport = setup();
  const handle = transport.open(metadata(transport));
  await transport.finish(handle);
  expect(await transport.read(handle, 1)).toBeNull();
  expect(fetcher).toHaveBeenCalledOnce();
});

test('a real connection drop before response headers carries the controlled retryable flag', async () => {
  const server = createServer((request) => {
    request.resume();
    request.on('end', () => request.socket.destroy());
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  try {
    const address = server.address();
    if (!address || typeof address === 'string')
      throw Error('Expected TCP server');
    const transport = new BinaryHttpTransport(
      `http://127.0.0.1:${address.port}`,
      buildIdentity,
    );
    transports.push(transport);
    transport.begin({
      requestId: 'connection-drop',
      generation: 'generation-1',
    });
    await expect(
      transport.finish(
        transport.open(
          metadata(transport, { operationRequestId: 'connection-drop' }),
        ),
      ),
    ).rejects.toMatchObject({
      code: 'source_error',
      message: 'Source bridge connection failed',
      retryable: true,
    });
  } finally {
    server.closeAllConnections();
    await new Promise<void>((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  }
});

test.each([
  { error: { error: 'upstream_network_error' }, retryable: true },
  { error: { error: 'cancelled' }, retryable: false },
  { error: { error: 'upstream_metadata_error' }, retryable: false },
  { error: { error: 'upstream_network_error', extra: true }, retryable: false },
  {
    error: { error: 'upstream_network_error', padding: 'x'.repeat(4096) },
    retryable: false,
  },
])(
  'only the bounded API pre-header network error authorizes retry: $error.error/$retryable',
  async ({ error, retryable }) => {
    const transport = setup(async () => Response.json(error, { status: 502 }));
    await expect(
      transport.finish(transport.open(metadata(transport))),
    ).rejects.toMatchObject({ code: 'source_error', retryable });
  },
);

test('a broken META stream does not turn a received response into a retryable connection failure', async () => {
  const transport = setup(
    async () =>
      new Response(
        new ReadableStream<Uint8Array>({
          start(controller) {
            controller.error(new TypeError('Network connection lost'));
          },
        }),
        { headers: { 'Content-Type': HTTP_BRIDGE_MEDIA_TYPE } },
      ),
  );
  await expect(
    transport.finish(transport.open(metadata(transport))),
  ).rejects.toMatchObject({ retryable: false });
});

test('error text alone cannot authorize a retry', async () => {
  const transport = setup(async () => {
    throw Error('Network connection lost ECONNRESET');
  });
  await expect(
    transport.finish(transport.open(metadata(transport))),
  ).rejects.toMatchObject({ retryable: false });
});

test('an API timeout before response META stays a non-retryable timeout', async () => {
  const transport = setup(async () =>
    Response.json({ error: 'timeout' }, { status: 504 }),
  );
  await expect(
    transport.finish(transport.open(metadata(transport))),
  ).rejects.toMatchObject({ code: 'timeout', retryable: false });
});

test('a stalled API error body remains bounded by the timeout and is never retryable', async () => {
  vi.useFakeTimers();
  const cancelled = vi.fn();
  const transport = setup(
    async () =>
      new Response(
        new ReadableStream<Uint8Array>(
          {
            pull: () => new Promise<void>(() => {}),
            cancel: cancelled,
          },
          { highWaterMark: 0 },
        ),
        { status: 502, headers: { 'Content-Type': 'application/json' } },
      ),
  );
  const handle = transport.open(metadata(transport, { timeoutMs: 50 }));
  const pending = expect(transport.finish(handle)).rejects.toMatchObject({
    code: 'timeout',
    retryable: false,
  });
  await vi.advanceTimersByTimeAsync(300_000);
  await pending;
  expect(cancelled).toHaveBeenCalledOnce();
  expect(vi.getTimerCount()).toBe(0);
});

test('a network drop after returned metadata and partial DATA is never retryable', async () => {
  const transport = setup(async (_url, init) => {
    if (!(init?.body instanceof Blob)) throw Error('Expected framed upload');
    const requestReader = new HttpFrameReader(
      init.body.stream(),
      8 * 1024 * 1024,
    );
    const request = httpRequestMetaSchema.parse(await requestReader.meta());
    const frames = [
      encodePreamble(),
      encodeMetaFrame({
        requestId: request.requestId,
        runtimeGeneration: request.runtimeGeneration,
        upstreamStatus: 200,
        message: 'OK',
        url: request.url,
        headers: [],
        hasBody: true,
        bodyLength: null,
        decoded: true,
      }),
      encodeDataFrame(new Uint8Array([1])),
    ];
    return new Response(
      new ReadableStream<Uint8Array>(
        {
          pull(controller) {
            const frame = frames.shift();
            if (frame) controller.enqueue(frame);
            else controller.error(new TypeError('ECONNRESET'));
          },
        },
        { highWaterMark: 0 },
      ),
      { headers: { 'Content-Type': HTTP_BRIDGE_MEDIA_TYPE } },
    );
  });
  const handle = transport.open(metadata(transport));
  await transport.finish(handle);
  expect(await transport.read(handle, 1)).toEqual(new Uint8Array([1]));
  await expect(transport.read(handle, 1)).rejects.toMatchObject({
    retryable: false,
  });
});

test.each([401, 403, 302])(
  'outer status %s is an Access failure',
  async (status) => {
    const cancelled = vi.fn();
    const transport = setup(
      (async () =>
        new Response(new ReadableStream({ cancel: cancelled }), {
          status,
        })) as typeof fetch,
    );
    const handle = transport.open(metadata(transport));
    await expect(transport.finish(handle)).rejects.toMatchObject({
      code: status === 403 ? 'access_denied' : 'access_required',
    });
    expect(cancelled).toHaveBeenCalledOnce();
  },
);

test('a disallowed Source target stays a nonretryable Source error', async () => {
  const transport = setup(async () =>
    Response.json({ error: 'target_not_allowed' }, { status: 422 }),
  );
  await expect(
    transport.finish(transport.open(metadata(transport))),
  ).rejects.toMatchObject({
    code: 'source_error',
    retryable: false,
  });
});

test('login HTML and a different framed response identity are rejected before DATA', async () => {
  const transport = setup((async (_url, init) => {
    const reader = new HttpFrameReader(
      (init!.body as Blob).stream(),
      8 * 1024 * 1024,
    );
    return framedResponse((await reader.meta()) as HttpRequestMeta, [], {
      runtimeGeneration: 'old',
    });
  }) as typeof fetch);
  await expect(
    transport.finish(transport.open(metadata(transport))),
  ).rejects.toMatchObject({ code: 'protocol_error' });
  const login = setup(
    (async () =>
      new Response('<html>login</html>', {
        headers: { 'Content-Type': 'text/html' },
      })) as typeof fetch,
  );
  await expect(login.finish(login.open(metadata(login)))).rejects.toMatchObject(
    {
      code: 'access_required',
    },
  );
});

test('cancel, operation completion and generation changes release upstream streams', async () => {
  const cancelled = vi.fn();
  let signal!: AbortSignal;
  const transport = setup((async (_url, init) => {
    signal = init!.signal!;
    const reader = new HttpFrameReader(
      (init!.body as Blob).stream(),
      8 * 1024 * 1024,
    );
    return framedResponse(
      (await reader.meta()) as HttpRequestMeta,
      [new Uint8Array([1])],
      {},
      cancelled,
    );
  }) as typeof fetch);
  const handle = transport.open(metadata(transport));
  await transport.finish(handle);
  transport.begin({ requestId: 'operation-2', generation: 'generation-2' });
  expect(signal.aborted).toBe(true);
  await expect(transport.read(handle, 1)).rejects.toMatchObject({
    code: 'cancelled',
  });
  expect(cancelled).toHaveBeenCalledOnce();
  transport.close(handle);
});

test('timeout retains its cause and cancels a late response', async () => {
  vi.useFakeTimers();
  let resolve!: (response: Response) => void;
  const cancelled = vi.fn();
  const transport = setup(
    (async () =>
      new Promise<Response>((yes) => {
        resolve = yes;
      })) as typeof fetch,
  );
  const handle = transport.open(metadata(transport, { timeoutMs: 50 }));
  const pending = transport.finish(handle);
  const failure = expect(pending).rejects.toMatchObject({
    code: 'timeout',
    name: 'TimeoutError',
    retryable: false,
  });
  await vi.advanceTimersByTimeAsync(300_000);
  await failure;
  resolve(new Response(new ReadableStream({ cancel: cancelled })));
  await vi.advanceTimersByTimeAsync(0);
  expect(cancelled).toHaveBeenCalledOnce();
});

test('the handle uses its absolute cap, not the upstream idle budget, between body reads', async () => {
  vi.useFakeTimers();
  const cancelled = vi.fn();
  let signal: AbortSignal | undefined;
  const transport = setup(async (_url, init) => {
    signal = init?.signal ?? undefined;
    if (!(init?.body instanceof Blob)) throw Error('Expected framed upload');
    const reader = new HttpFrameReader(init.body.stream(), 8 * 1024 * 1024);
    const request = httpRequestMetaSchema.parse(await reader.meta());
    expect(request.timeoutMs).toBe(50);
    return framedResponse(
      request,
      [new Uint8Array([1]), new Uint8Array([2]), new Uint8Array([3])],
      {},
      cancelled,
    );
  });
  const handle = transport.open(metadata(transport, { timeoutMs: 50 }));
  await transport.finish(handle);
  expect(await transport.read(handle, 1)).toEqual(new Uint8Array([1]));
  await vi.advanceTimersByTimeAsync(51);
  expect(signal?.aborted).toBe(false);
  expect(await transport.read(handle, 1)).toEqual(new Uint8Array([2]));
  await vi.advanceTimersByTimeAsync(300_000 - 51);
  expect(signal?.aborted).toBe(true);
  expect(cancelled).toHaveBeenCalledOnce();
  expect(vi.getTimerCount()).toBe(0);
  await expect(transport.read(handle, 1)).rejects.toMatchObject({
    code: 'timeout',
    name: 'TimeoutError',
  });
  // Idempotent Java cleanup cannot replace the terminal cause with cancellation.
  transport.close(handle);
  await expect(transport.read(handle, 1)).rejects.toMatchObject({
    code: 'timeout',
  });
  transport.begin({ requestId: 'operation-2', generation: 'generation-2' });
  await expect(transport.read(handle, 1)).rejects.toMatchObject({
    code: 'cancelled',
  });
});

test('timeout during a pending body read cancels it with timeout rather than reader cancellation', async () => {
  vi.useFakeTimers();
  const cancelled = vi.fn();
  let waiting: (() => void) | undefined;
  const stalled = new Promise<void>((resolve) => {
    waiting = resolve;
  });
  const transport = setup(async (_url, init) => {
    if (!(init?.body instanceof Blob)) throw Error('Expected framed upload');
    const reader = new HttpFrameReader(init.body.stream(), 8 * 1024 * 1024);
    const request = httpRequestMetaSchema.parse(await reader.meta());
    const initial = [
      encodePreamble(),
      encodeMetaFrame({
        requestId: request.requestId,
        runtimeGeneration: request.runtimeGeneration,
        upstreamStatus: 200,
        message: 'OK',
        url: request.url,
        headers: [],
        hasBody: true,
        bodyLength: null,
        decoded: true,
      }),
    ];
    return new Response(
      new ReadableStream<Uint8Array>(
        {
          pull(controller) {
            const next = initial.shift();
            if (next) controller.enqueue(next);
            else {
              waiting?.();
              return new Promise<void>(() => {});
            }
          },
          cancel: cancelled,
        },
        { highWaterMark: 0 },
      ),
      { headers: { 'Content-Type': HTTP_BRIDGE_MEDIA_TYPE } },
    );
  });
  const handle = transport.open(metadata(transport, { timeoutMs: 50 }));
  await transport.finish(handle);
  const pending = transport.read(handle, 1);
  const failed = expect(pending).rejects.toMatchObject({
    code: 'timeout',
    name: 'TimeoutError',
  });
  await stalled;
  await vi.advanceTimersByTimeAsync(300_000);
  await failed;
  expect(cancelled).toHaveBeenCalledOnce();
  expect(vi.getTimerCount()).toBe(0);
});

test('terminal failure history is bounded, releases handle slots, and ends with its operation', async () => {
  vi.useFakeTimers();
  const fetcher = vi.fn();
  const transport = setup(fetcher);
  const expired: string[] = [];
  for (let index = 0; index < 20; index++) {
    expired.push(
      transport.open(
        metadata(transport, {
          timeoutMs: 1,
          method: 'POST',
          hasBody: true,
          bodyLength: 1,
        }),
      ),
    );
    transport.write(expired[index]!, new Uint8Array([index]));
    await vi.advanceTimersByTimeAsync(300_000);
  }
  expect(vi.getTimerCount()).toBe(0);
  await expect(transport.finish(expired[0]!)).rejects.toMatchObject({
    code: 'cancelled',
  });
  await expect(transport.finish(expired[4]!)).rejects.toMatchObject({
    code: 'timeout',
  });
  await expect(transport.finish(expired[19]!)).rejects.toMatchObject({
    code: 'timeout',
  });
  // Released uploads do not consume the four active-body slots or trigger fetch.
  for (let index = 0; index < 4; index++) transport.open(metadata(transport));
  expect(() => transport.open(metadata(transport))).toThrow(
    'Too many open HTTP bodies',
  );
  expect(fetcher).not.toHaveBeenCalled();
  transport.end();
  expect(vi.getTimerCount()).toBe(0);
  await expect(transport.read(expired[19]!, 1)).rejects.toMatchObject({
    code: 'cancelled',
  });
});

test('no DATA is pulled until read, and one pending read excludes another', async () => {
  let pulled = 0;
  let deliver!: () => void;
  const transport = setup((async (_url, init) => {
    const reader = new HttpFrameReader(
      (init!.body as Blob).stream(),
      8 * 1024 * 1024,
    );
    const request = (await reader.meta()) as HttpRequestMeta;
    const initial = [
      encodePreamble(),
      encodeMetaFrame({
        requestId: request.requestId,
        runtimeGeneration: request.runtimeGeneration,
        upstreamStatus: 200,
        message: 'OK',
        url: request.url,
        headers: [],
        hasBody: true,
        bodyLength: null,
        decoded: true,
      }),
    ];
    return new Response(
      new ReadableStream<Uint8Array>(
        {
          pull(controller) {
            const frame = initial.shift();
            if (frame) {
              controller.enqueue(frame);
              return;
            }
            pulled++;
            return new Promise<void>((yes) => {
              deliver = () => {
                controller.enqueue(encodeDataFrame(new Uint8Array([3])));
                yes();
              };
            });
          },
        },
        { highWaterMark: 0 },
      ),
      { headers: { 'Content-Type': HTTP_BRIDGE_MEDIA_TYPE } },
    );
  }) as typeof fetch);
  const handle = transport.open(metadata(transport));
  await transport.finish(handle);
  expect(pulled).toBe(0);
  const pending = transport.read(handle, 1);
  await vi.waitFor(() => expect(pulled).toBe(1));
  await expect(transport.read(handle, 1)).rejects.toMatchObject({
    code: 'protocol_error',
  });
  deliver();
  expect(await pending).toEqual(new Uint8Array([3]));
  expect(pulled).toBe(1);
});

test('upload lengths, frame size and active handle budget are checked before fetch', async () => {
  const fetcher = vi.fn();
  const transport = setup(fetcher as typeof fetch);
  const handle = transport.open(
    metadata(transport, { method: 'POST', hasBody: true, bodyLength: 10 }),
  );
  expect(() =>
    transport.write(handle, new Uint8Array(HTTP_FRAME_LIMIT + 1)),
  ).toThrow();
  transport.write(handle, new Uint8Array(9));
  await expect(transport.finish(handle)).rejects.toMatchObject({
    code: 'protocol_error',
  });
  for (let i = 0; i < 4; i++) transport.open(metadata(transport));
  expect(() => transport.open(metadata(transport))).toThrow(
    'Too many open HTTP bodies',
  );
  expect(fetcher).not.toHaveBeenCalled();
});

test('an entry token fences late opens and handles even when control request identities repeat', async () => {
  const transport = setup();
  const oldMetadata = metadata(transport);
  const handle = transport.open(oldMetadata);
  const oldToken = transport.operationToken;
  transport.begin({ requestId: 'operation-1', generation: 'generation-1' });
  expect(transport.operationToken).not.toBe(oldToken);
  expect(() => transport.open(oldMetadata)).toThrow(HttpOwnerFailure);
  expect(() => transport.write(handle, new Uint8Array([1]))).toThrow(
    HttpOwnerFailure,
  );
  await expect(transport.finish(handle)).rejects.toBeInstanceOf(
    HttpOwnerFailure,
  );
  expect(() => transport.open(metadata(transport))).not.toThrow();
});

test.each(['operationRequestId', 'operationGeneration', 'operationToken'])(
  'HTTP metadata requires its exact %s and strips ownership before the wire META',
  async (field) => {
    const transport = setup(async (_url, init) => {
      if (!(init?.body instanceof Blob)) throw Error('Expected framed upload');
      const reader = new HttpFrameReader(init.body.stream(), 8 * 1024 * 1024);
      const wire = await reader.meta();
      expect(wire).not.toHaveProperty('operationToken');
      expect(wire).not.toHaveProperty('operationRequestId');
      expect(wire).not.toHaveProperty('operationGeneration');
      return framedResponse(httpRequestMetaSchema.parse(wire), []);
    });
    expect(() =>
      transport.open(metadata(transport, { [field]: 'expired' })),
    ).toThrow(HttpOwnerFailure);
    const handle = transport.open(metadata(transport));
    await transport.finish(handle);
  },
);
