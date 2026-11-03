import { describe, expect, test, vi } from 'vitest';
import {
  HTTP_BRIDGE_MEDIA_TYPE,
  HTTP_ERROR_FRAME_LIMIT,
  HTTP_FRAME_LIMIT,
  HTTP_REQUEST_BODY_LIMIT,
  HTTP_RESPONSE_BODY_LIMIT,
  HttpFrameError,
  HttpFrameReader,
  encodeDataFrame,
  encodeEndFrame,
  encodeErrorFrame,
  encodeMetaFrame,
  encodePreamble,
  httpRequestMetaSchema,
  httpResponseMetaSchema,
} from '../src/index.js';

function join(...chunks: Uint8Array[]): Uint8Array<ArrayBuffer> {
  const bytes = new Uint8Array(
    chunks.reduce((sum, part) => sum + part.length, 0),
  );
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return bytes;
}

function header(type: number, length: number): Uint8Array<ArrayBuffer> {
  const bytes = new Uint8Array(5);
  bytes[0] = type;
  new DataView(bytes.buffer).setUint32(1, length, false);
  return bytes;
}

function framed(...frames: Uint8Array[]): Uint8Array<ArrayBuffer> {
  return join(encodePreamble(), encodeMetaFrame({ ok: true }), ...frames);
}

function input(chunks: Uint8Array[]) {
  let pulls = 0;
  let offset = 0;
  const cancel = vi.fn();
  const stream = new ReadableStream<Uint8Array>(
    {
      pull(controller) {
        pulls += 1;
        if (offset === chunks.length) controller.close();
        else controller.enqueue(chunks[offset++]!);
      },
      cancel,
    },
    { highWaterMark: 0 },
  );
  return {
    stream,
    cancel,
    get pulls() {
      return pulls;
    },
  };
}

async function drain(reader: HttpFrameReader): Promise<number[]> {
  const result: number[] = [];
  while (true) {
    const chunk = await reader.read(HTTP_FRAME_LIMIT);
    if (chunk === null) return result;
    result.push(...chunk);
  }
}

const request = {
  requestId: 'request-1',
  runtimeGeneration: 'generation-1',
  url: 'https://example.com/manga',
  method: 'GET',
  headers: [['Accept', 'image/*']],
  hasBody: false,
  bodyLength: 0,
  timeoutMs: 30_000,
};
const response = {
  requestId: 'request-1',
  runtimeGeneration: 'generation-1',
  upstreamStatus: 200,
  message: '',
  url: 'https://example.com/manga',
  headers: [
    ['Set-Cookie', 'one=1; HttpOnly'],
    ['Set-Cookie', 'two=2; Secure'],
  ],
  hasBody: true,
  bodyLength: null,
  decoded: true,
};

describe('HTTP v2 metadata and encoders', () => {
  test('writes the exact magic, big-endian lengths and binary bytes', () => {
    expect(HTTP_BRIDGE_MEDIA_TYPE).toBe('application/vnd.karuyomi.http.v2');
    expect([...encodePreamble()]).toEqual([75, 82, 89, 72, 84, 84, 80, 2]);
    const changed = encodePreamble();
    changed[0] = 0;
    expect(encodePreamble()[0]).toBe(75);
    expect([...encodeDataFrame(new Uint8Array([0, 128, 255]))]).toEqual([
      2, 0, 0, 0, 3, 0, 128, 255,
    ]);
    expect([...encodeEndFrame(256)]).toEqual([
      3, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0, 1, 0,
    ]);
    expect(
      new DataView(encodeEndFrame(0xffff_ffff_ffff_ffffn).buffer).getBigUint64(
        5,
      ),
    ).toBe(0xffff_ffff_ffff_ffffn);
  });

  test('validates metadata budgets and preserves ordered duplicate headers', () => {
    expect(httpRequestMetaSchema.parse(request)).toEqual(request);
    expect(httpResponseMetaSchema.parse(response).headers).toEqual(
      response.headers,
    );
    expect(
      httpRequestMetaSchema.parse({
        ...request,
        hasBody: true,
        bodyLength: null,
      }),
    ).toMatchObject({ bodyLength: null });
    expect(
      httpRequestMetaSchema.parse({
        ...request,
        hasBody: true,
        bodyLength: HTTP_REQUEST_BODY_LIMIT,
      }).bodyLength,
    ).toBe(8 * 1024 * 1024);
    expect(
      httpResponseMetaSchema.parse({
        ...response,
        bodyLength: HTTP_RESPONSE_BODY_LIMIT,
      }).bodyLength,
    ).toBe(64 * 1024 * 1024);
    for (const bodyLength of [null, 1, -1, 1.5, HTTP_REQUEST_BODY_LIMIT + 1]) {
      expect(
        httpRequestMetaSchema.safeParse({ ...request, bodyLength }).success,
      ).toBe(false);
    }
    for (const bodyLength of [null, 1]) {
      expect(
        httpResponseMetaSchema.safeParse({
          ...response,
          hasBody: false,
          bodyLength,
        }).success,
      ).toBe(false);
    }
    expect(
      httpResponseMetaSchema.safeParse({
        ...response,
        bodyLength: HTTP_RESPONSE_BODY_LIMIT + 1,
      }).success,
    ).toBe(false);
    expect(
      httpResponseMetaSchema.parse({
        ...response,
        hasBody: false,
        bodyLength: 0,
      }).message,
    ).toBe('');
  });

  test('rejects malformed metadata identities, methods, tuples and timeouts', () => {
    for (const patch of [
      { requestId: '' },
      { runtimeGeneration: '' },
      { url: 'file:///tmp/image' },
      { method: 'CONNECT' },
      { headers: [['name', 'value', 'extra']] },
      { headers: Array.from({ length: 201 }, () => ['x', 'y']) },
      { timeoutMs: 0 },
      { timeoutMs: 300_001 },
      { timeoutMs: 0.5 },
      { extra: 'unknown' },
    ]) {
      expect(
        httpRequestMetaSchema.safeParse({ ...request, ...patch }).success,
      ).toBe(false);
    }
    expect(
      httpRequestMetaSchema.parse({ ...request, timeoutMs: 300_000 }).timeoutMs,
    ).toBe(300_000);
  });

  test('enforces JSON UTF-8 byte limits and does not serialize body data', () => {
    const meta = encodeMetaFrame('x'.repeat(HTTP_FRAME_LIMIT - 2));
    expect(meta.byteLength).toBe(5 + HTTP_FRAME_LIMIT);
    expect(() => encodeMetaFrame('x'.repeat(HTTP_FRAME_LIMIT - 1))).toThrow(
      HttpFrameError,
    );
    expect(() => encodeMetaFrame('中'.repeat(21_845))).toThrow(HttpFrameError);
    expect(() => encodeMetaFrame(undefined)).toThrow(HttpFrameError);
    expect(() => encodeMetaFrame({ cyclic: 1n })).toThrow(HttpFrameError);
    expect(encodeDataFrame(new Uint8Array(HTTP_FRAME_LIMIT)).byteLength).toBe(
      HTTP_FRAME_LIMIT + 5,
    );
    expect(() => encodeDataFrame(new Uint8Array())).toThrow(HttpFrameError);
    expect(() => encodeDataFrame(new Uint8Array(HTTP_FRAME_LIMIT + 1))).toThrow(
      HttpFrameError,
    );
    for (const total of [
      -1,
      0.5,
      Infinity,
      Number.MAX_SAFE_INTEGER + 1,
      -1n,
      1n << 64n,
    ]) {
      expect(() => encodeEndFrame(total)).toThrow(HttpFrameError);
    }
  });

  test('bounds the whole ERROR JSON payload, including UTF-8 and JSON overhead', () => {
    const overhead = new TextEncoder().encode(
      JSON.stringify({ code: 'x', message: '' }),
    ).length;
    expect(
      encodeErrorFrame({
        code: 'x',
        message: 'x'.repeat(HTTP_ERROR_FRAME_LIMIT - overhead),
      }).length,
    ).toBe(5 + HTTP_ERROR_FRAME_LIMIT);
    expect(() =>
      encodeErrorFrame({
        code: 'x',
        message: 'x'.repeat(HTTP_ERROR_FRAME_LIMIT - overhead + 1),
      }),
    ).toThrow(HttpFrameError);
    expect(() => encodeErrorFrame({ code: '', message: '' })).toThrow(
      HttpFrameError,
    );
    expect(() =>
      encodeErrorFrame({ code: 'timeout', message: '中'.repeat(2000) }),
    ).toThrow(HttpFrameError);
  });
});

describe('HTTP v2 demand-driven reader', () => {
  test('accepts every boundary split, raw binary and an explicit empty END', async () => {
    const bytes = new Uint8Array([0, 128, 255, 13, 10]);
    const wire = framed(encodeDataFrame(bytes), encodeEndFrame(bytes.length));
    for (let split = 0; split <= wire.length; split += 1) {
      const source = input([wire.subarray(0, split), wire.subarray(split)]);
      const reader = new HttpFrameReader(source.stream, 5);
      expect(await reader.meta()).toEqual({ ok: true });
      expect(await drain(reader)).toEqual([...bytes]);
      expect(reader.bytesRead).toBe(5);
      expect(source.stream.locked).toBe(false);
      expect(await reader.read(1)).toBeNull();
    }
    const reader = new HttpFrameReader(
      input([framed(encodeEndFrame(0))]).stream,
      0,
    );
    expect(await reader.read(1)).toBeNull();
    expect(reader.bytesRead).toBe(0);
  });

  test('decodes multibyte META split one byte at a time', async () => {
    const meta = { title: '阅读 🐱', headers: response.headers };
    const wire = join(
      encodePreamble(),
      encodeMetaFrame(meta),
      encodeEndFrame(0),
    );
    const reader = new HttpFrameReader(
      input([...wire].map((byte) => Uint8Array.of(byte))).stream,
      0,
    );
    expect(await reader.meta()).toEqual(meta);
    expect(await reader.read(1)).toBeNull();
  });

  test('does not pull DATA before demand or prefetch a second DATA frame', async () => {
    const source = input([
      join(encodePreamble(), encodeMetaFrame(request)),
      encodeDataFrame(Uint8Array.of(1, 2, 3)),
      encodeDataFrame(Uint8Array.of(4)),
      encodeEndFrame(4),
    ]);
    const reader = new HttpFrameReader(source.stream, 4);
    expect(source.pulls).toBe(0);
    expect(await reader.meta()).toEqual(request);
    expect(await reader.meta()).toEqual(request);
    expect(source.pulls).toBe(1);
    expect([...(await reader.read(1))!]).toEqual([1]);
    expect(reader.bytesRead).toBe(1);
    await Promise.resolve();
    expect(source.pulls).toBe(2);
    expect([...(await reader.read(2))!]).toEqual([2, 3]);
    expect(source.pulls).toBe(2);
    expect([...(await reader.read(HTTP_FRAME_LIMIT))!]).toEqual([4]);
    expect(source.pulls).toBe(3);
    expect(await reader.read(1)).toBeNull();
    expect(reader.bytesRead).toBe(4);
  });

  test('keeps a large input chunk as a view while returning bounded frames', async () => {
    const data = new Uint8Array(HTTP_FRAME_LIMIT).fill(173);
    const wire = framed(
      encodeDataFrame(data),
      encodeDataFrame(data),
      encodeEndFrame(data.length * 2),
    );
    const source = input([wire]);
    const reader = new HttpFrameReader(source.stream, data.length * 2);
    await reader.meta();
    expect(source.pulls).toBe(1);
    for (let i = 0; i < 2; i += 1) {
      const bytes = await reader.read(HTTP_FRAME_LIMIT);
      expect(bytes).toEqual(data);
      expect(bytes!.buffer.byteLength).toBe(HTTP_FRAME_LIMIT);
      expect(source.pulls).toBe(1);
    }
    expect(await reader.read(HTTP_FRAME_LIMIT)).toBeNull();
  });

  test('a consumer may transfer a partial result without detaching its remainder', async () => {
    const reader = new HttpFrameReader(
      input([
        framed(encodeDataFrame(Uint8Array.of(1, 2, 3)), encodeEndFrame(3)),
      ]).stream,
      3,
    );
    const first = (await reader.read(1))!;
    expect(first.buffer.byteLength).toBe(1);
    expect(structuredClone(first, { transfer: [first.buffer] })).toEqual(
      Uint8Array.of(1),
    );
    expect(first.byteLength).toBe(0);
    expect(await reader.read(2)).toEqual(Uint8Array.of(2, 3));
    expect(await reader.read(1)).toBeNull();
  });

  test('validates requested read sizes and constructor limits without pulling', async () => {
    const source = input([framed(encodeEndFrame(0))]);
    for (const limit of [-1, 0.5, Infinity, HTTP_RESPONSE_BODY_LIMIT + 1]) {
      expect(() => new HttpFrameReader(source.stream, limit)).toThrow(
        HttpFrameError,
      );
    }
    const reader = new HttpFrameReader(source.stream, 0);
    for (const size of [0, -1, 0.5, Infinity, HTTP_FRAME_LIMIT + 1]) {
      await expect(reader.read(size)).rejects.toMatchObject({
        code: 'limit_exceeded',
      });
    }
    expect(source.pulls).toBe(0);
    expect(await reader.read(1)).toBeNull();
  });
});

describe('HTTP v2 malformed and terminal frames', () => {
  test('rejects all truncated prefixes, including absent END on empty bodies', async () => {
    const wire = framed(encodeDataFrame(Uint8Array.of(1)), encodeEndFrame(1));
    for (let cut = 0; cut < wire.length; cut += 1) {
      const reader = new HttpFrameReader(
        input([wire.subarray(0, cut)]).stream,
        1,
      );
      await expect(drain(reader)).rejects.toMatchObject({
        code: 'protocol_error',
        remote: false,
      });
    }
    const reader = new HttpFrameReader(input([framed()]).stream, 0);
    await reader.meta();
    await expect(reader.read(1)).rejects.toThrow(/Truncated/);
  });

  test('rejects bad magic, versions and non-META first frames', async () => {
    const badMagic = encodePreamble();
    badMagic[0] = 0;
    const oldVersion = encodePreamble();
    oldVersion[7] = 1;
    const futureVersion = encodePreamble();
    futureVersion[7] = 3;
    for (const wire of [
      join(badMagic, encodeMetaFrame({})),
      join(oldVersion, encodeMetaFrame({})),
      join(futureVersion, encodeMetaFrame({})),
      join(encodePreamble(), encodeDataFrame(Uint8Array.of(1))),
      join(encodePreamble(), encodeEndFrame(0)),
      join(encodePreamble(), encodeErrorFrame({ code: 'x', message: 'x' })),
    ]) {
      await expect(
        new HttpFrameReader(input([wire]).stream, 1).meta(),
      ).rejects.toMatchObject({ code: 'protocol_error' });
    }
  });

  test('rejects invalid UTF-8, JSON and duplicate META', async () => {
    for (const bytes of [
      new Uint8Array(),
      Uint8Array.of(0xc0, 0xaf),
      new TextEncoder().encode('{'),
      Uint8Array.of(0xef, 0xbb, 0xbf, 123, 125),
    ]) {
      const wire = join(encodePreamble(), header(1, bytes.length), bytes);
      await expect(
        new HttpFrameReader(input([wire]).stream, 0).meta(),
      ).rejects.toMatchObject({ code: 'protocol_error' });
    }
    await expect(
      drain(
        new HttpFrameReader(
          input([framed(encodeMetaFrame({}), encodeEndFrame(0))]).stream,
          0,
        ),
      ),
    ).rejects.toThrow(/Duplicate META/);
  });

  test.each([
    ['META', join(encodePreamble(), header(1, 0xffff_ffff)), 'limit_exceeded'],
    ['DATA', framed(header(2, HTTP_FRAME_LIMIT + 1)), 'limit_exceeded'],
    ['empty DATA', framed(header(2, 0)), 'protocol_error'],
    ['ERROR', framed(header(4, HTTP_ERROR_FRAME_LIMIT + 1)), 'limit_exceeded'],
    ['short END', framed(header(3, 7)), 'protocol_error'],
    ['long END', framed(header(3, 9)), 'protocol_error'],
    ['unknown type', framed(header(255, 0xffff_ffff)), 'protocol_error'],
  ])(
    'rejects %s header before requesting its payload',
    async (_label, wire, code) => {
      let pulls = 0;
      const cancel = vi.fn();
      const source = new ReadableStream<Uint8Array>(
        {
          pull(controller) {
            pulls += 1;
            if (pulls === 1) controller.enqueue(wire);
            else throw new Error('Parser must not request an invalid payload');
          },
          cancel,
        },
        { highWaterMark: 0 },
      );
      await expect(
        drain(new HttpFrameReader(source, HTTP_RESPONSE_BODY_LIMIT)),
      ).rejects.toMatchObject({ code });
      expect(pulls).toBe(1);
      expect(cancel).toHaveBeenCalledOnce();
    },
  );

  test('applies the cumulative body budget before reading another payload', async () => {
    const source = input([
      framed(encodeDataFrame(Uint8Array.of(1, 2))),
      header(2, 2),
      Uint8Array.of(3, 4),
    ]);
    const reader = new HttpFrameReader(source.stream, 3);
    expect(await reader.read(2)).toEqual(Uint8Array.of(1, 2));
    await expect(reader.read(2)).rejects.toMatchObject({
      code: 'limit_exceeded',
    });
    expect(source.pulls).toBe(2);
    expect(reader.bytesRead).toBe(2);
  });

  test.each([0, 2, 0xffff_ffff_ffff_ffffn])(
    'checks END total %s without lossy number conversion',
    async (count) => {
      const reader = new HttpFrameReader(
        input([
          framed(encodeDataFrame(Uint8Array.of(1)), encodeEndFrame(count)),
        ]).stream,
        1,
      );
      await expect(drain(reader)).rejects.toThrow(/END total/);
    },
  );

  test('ERROR is a distinct terminal failure after META or DATA', async () => {
    for (const frames of [[], [encodeDataFrame(Uint8Array.of(1))]]) {
      const source = input([
        framed(
          ...frames,
          encodeErrorFrame({
            code: 'timeout',
            message: 'Upstream deadline exceeded',
          }),
        ),
      ]);
      const reader = new HttpFrameReader(source.stream, 1);
      await expect(drain(reader)).rejects.toMatchObject({
        name: 'HttpFrameError',
        code: 'timeout',
        message: 'Upstream deadline exceeded',
        remote: true,
      });
      expect(reader.bytesRead).toBe(frames.length);
      expect(source.stream.locked).toBe(false);
    }
  });

  test.each([
    new TextEncoder().encode('{'),
    Uint8Array.of(0xc0, 0xaf),
    new TextEncoder().encode('null'),
    new TextEncoder().encode('{"code":"x"}'),
    new TextEncoder().encode('{"code":"","message":""}'),
    new TextEncoder().encode('{"code":"x","message":"x","extra":1}'),
  ])('rejects malformed ERROR payload %#', async (payload) => {
    const reader = new HttpFrameReader(
      input([framed(join(header(4, payload.length), payload))]).stream,
      0,
    );
    await expect(reader.read(1)).rejects.toMatchObject({
      code: 'protocol_error',
      remote: false,
    });
  });

  test('requires EOF after either terminal frame and rejects trailing bytes', async () => {
    for (const terminal of [
      encodeEndFrame(0),
      encodeErrorFrame({ code: 'timeout', message: 'x' }),
    ]) {
      for (const trailing of [
        Uint8Array.of(0),
        encodeEndFrame(0),
        encodeMetaFrame({}),
      ]) {
        const reader = new HttpFrameReader(
          input([framed(terminal), trailing]).stream,
          0,
        );
        await expect(reader.read(1)).rejects.toMatchObject({
          code: 'protocol_error',
          remote: false,
        });
      }
    }
    let controller!: ReadableStreamDefaultController<Uint8Array>;
    const source = new ReadableStream<Uint8Array>(
      {
        start(value) {
          controller = value;
        },
      },
      { highWaterMark: 0 },
    );
    const reader = new HttpFrameReader(source, 0);
    controller.enqueue(framed(encodeEndFrame(0)));
    let resolved = false;
    const pending = reader.read(1).then((value) => {
      resolved = true;
      return value;
    });
    await reader.meta();
    await Promise.resolve();
    expect(resolved).toBe(false);
    controller.close();
    expect(await pending).toBeNull();
  });
});

describe('HTTP v2 cancellation and source errors', () => {
  test('cancel before META is idempotent and forwards its reason without pulling', async () => {
    const source = input([framed(encodeEndFrame(0))]);
    const reader = new HttpFrameReader(source.stream, 0);
    const reason = new Error('Consumer left');
    await Promise.all([reader.cancel(reason), reader.cancel('second')]);
    expect(source.cancel).toHaveBeenCalledExactlyOnceWith(reason);
    expect(source.pulls).toBe(0);
    expect(source.stream.locked).toBe(false);
    await expect(reader.meta()).rejects.toMatchObject({ code: 'cancelled' });
    await expect(reader.read(1)).rejects.toMatchObject({ code: 'cancelled' });
  });

  test('cancel interrupts a pending read and concurrent reads cannot race frames', async () => {
    const cancel = vi.fn();
    const source = new ReadableStream<Uint8Array>(
      { cancel },
      { highWaterMark: 0 },
    );
    const reader = new HttpFrameReader(source, 1);
    const pending = reader.read(1);
    const rejected = expect(pending).rejects.toMatchObject({
      code: 'cancelled',
    });
    await expect(reader.read(1)).rejects.toThrow(/Concurrent/);
    await reader.cancel('done');
    await rejected;
    expect(cancel).toHaveBeenCalledExactlyOnceWith('done');
    expect(source.locked).toBe(false);
  });

  test('malformed input rejects even when a source cancellation hook never settles', async () => {
    const cancel = vi.fn(() => new Promise<void>(() => {}));
    const source = new ReadableStream<Uint8Array>(
      {
        start(controller) {
          controller.enqueue(new Uint8Array(8));
        },
        cancel,
      },
      { highWaterMark: 0 },
    );
    const reader = new HttpFrameReader(source, 0);
    await expect(reader.meta()).rejects.toMatchObject({
      code: 'protocol_error',
    });
    expect(cancel).toHaveBeenCalledOnce();
  });

  test('source failures are terminal without reflecting source exception text', async () => {
    const source = new ReadableStream<Uint8Array>({
      pull(controller) {
        controller.error(new Error('secret provider detail'));
      },
    });
    const reader = new HttpFrameReader(source, 0);
    await expect(reader.meta()).rejects.toMatchObject({
      code: 'protocol_error',
      message: 'HTTP frame input stream failed',
    });
    await expect(reader.read(1)).rejects.toMatchObject({
      code: 'protocol_error',
    });
    expect(source.locked).toBe(false);
  });

  test('rejects non-byte stream values', async () => {
    const source = new ReadableStream({
      start(controller) {
        controller.enqueue('not bytes');
      },
    }) as unknown as ReadableStream<Uint8Array>;
    await expect(new HttpFrameReader(source, 0).meta()).rejects.toThrow(
      /Uint8Array/,
    );
  });
});
