import { afterEach, expect, test, vi } from 'vitest';
import {
  HTTP_BRIDGE_MEDIA_TYPE,
  HTTP_FRAME_LIMIT,
  HttpFrameReader,
  encodePreamble,
  encodeMetaFrame,
  encodeDataFrame,
  encodeEndFrame,
  type HttpRequestMeta,
} from '@karuyomi/contracts';
import { BinaryHttpTransport } from '../src/http-transport.js';

const transports: BinaryHttpTransport[] = [];
afterEach(() => {
  for (const transport of transports.splice(0)) transport.dispose();
  vi.useRealTimers();
});

function metadata(overrides: Record<string, unknown> = {}) {
  return JSON.stringify({
    url: 'https://source.example/chapter',
    method: 'GET',
    headers: [['Cookie', 'source=private']],
    hasBody: false,
    bodyLength: 0,
    timeoutMs: 30_000,
    ...overrides,
  });
}

function setup(fetcher: typeof fetch) {
  const transport = new BinaryHttpTransport(
    'https://read.example',
    'test-build',
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
    metadata({
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
    const handle = transport.open(metadata());
    await expect(transport.finish(handle)).rejects.toMatchObject({
      code: status === 403 ? 'access_denied' : 'access_required',
    });
    expect(cancelled).toHaveBeenCalledOnce();
  },
);

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
    transport.finish(transport.open(metadata())),
  ).rejects.toMatchObject({ code: 'protocol_error' });
  const login = setup(
    (async () =>
      new Response('<html>login</html>', {
        headers: { 'Content-Type': 'text/html' },
      })) as typeof fetch,
  );
  await expect(login.finish(login.open(metadata()))).rejects.toMatchObject({
    code: 'access_required',
  });
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
  const handle = transport.open(metadata());
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
  const handle = transport.open(metadata({ timeoutMs: 50 }));
  const pending = transport.finish(handle);
  const failure = expect(pending).rejects.toMatchObject({
    code: 'timeout',
    name: 'TimeoutError',
  });
  await vi.advanceTimersByTimeAsync(51);
  resolve(new Response(new ReadableStream({ cancel: cancelled })));
  await failure;
  expect(cancelled).toHaveBeenCalledOnce();
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
  const handle = transport.open(metadata());
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
    metadata({ method: 'POST', hasBody: true, bodyLength: 10 }),
  );
  expect(() =>
    transport.write(handle, new Uint8Array(HTTP_FRAME_LIMIT + 1)),
  ).toThrow();
  transport.write(handle, new Uint8Array(9));
  await expect(transport.finish(handle)).rejects.toMatchObject({
    code: 'protocol_error',
  });
  for (let i = 0; i < 4; i++) transport.open(metadata());
  expect(() => transport.open(metadata())).toThrow('Too many open HTTP bodies');
  expect(fetcher).not.toHaveBeenCalled();
});
