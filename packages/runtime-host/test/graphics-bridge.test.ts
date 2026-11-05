/** Controlled codec timing tests; real Canvas semantics run in browser/bridges.browser.test.ts. */
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { createGraphicsBridge } from '../../../runtime/teavm/bridge/graphics-bridge.js';
import { deferred, pngHeader } from './image-fixtures.js';

class Canvas {
  width: number;
  height: number;
  constructor(width: number, height: number) {
    this.width = width;
    this.height = height;
  }
  getContext() {
    return {
      drawImage() {},
      getImageData: (
        _x: number,
        _y: number,
        width: number,
        height: number,
      ) => ({ data: new Uint8ClampedArray(width * height * 4) }),
    };
  }
  convertToBlob() {
    return Promise.resolve(
      new Blob([pngHeader(this.width, this.height)], { type: 'image/png' }),
    );
  }
}
beforeEach(() => vi.stubGlobal('OffscreenCanvas', Canvas));
afterEach(() => vi.unstubAllGlobals());
const identity = { requestId: 'graphics', generation: 'generation' };
function opened(options: Parameters<typeof createGraphicsBridge>[0] = {}) {
  const bridge = createGraphicsBridge(options);
  bridge.teaGraphicsBegin(identity);
  return bridge;
}
function upload(
  bridge: ReturnType<typeof createGraphicsBridge>,
  data: Uint8Array,
) {
  const id = bridge.teaGraphicsBytesOpen(Math.max(1, data.length));
  for (let i = 0; i < data.length; i += 65536)
    bridge.teaGraphicsBytesWrite(id, data.subarray(i, i + 65536));
  return id;
}
function handle(result: Record<string, unknown>) {
  if (typeof result.bytes !== 'string') throw Error('Missing handle');
  return result.bytes;
}

test('binary blocks copy input, reject >64KiB, and return exact bytes through EOF', () => {
  const b = opened(),
    input = new Uint8Array(65543);
  for (let i = 0; i < input.length; i++) input[i] = i & 255;
  const id = upload(b, input);
  input.fill(0);
  expect(() => b.teaGraphicsBytesWrite(id, new Uint8Array(65537))).toThrow();
  const first = b.teaGraphicsBytesRead(id, 65536),
    last = b.teaGraphicsBytesRead(id, 65536);
  expect(first?.length).toBe(65536);
  expect(first?.[255]).toBe(255);
  expect(last?.length).toBe(7);
  expect(last?.[1]).toBe(1);
  expect(b.teaGraphicsBytesRead(id, 65536)).toBeNull();
  b.teaGraphicsBytesClose(id);
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
});
test('bounds parses dimensions with no decode or Canvas allocation', async () => {
  const decode = vi.fn(() => {
    throw Error('must not decode');
  });
  vi.stubGlobal('createImageBitmap', decode);
  vi.stubGlobal(
    'OffscreenCanvas',
    vi.fn(() => {
      throw Error('must not allocate');
    }),
  );
  const b = opened(),
    id = upload(b, pngHeader(50000, 60000));
  expect(
    await b.teaGraphicsAsync({ op: 'decode', bytes: id, bounds: true }),
  ).toEqual({
    ok: true,
    originalWidth: 50000,
    originalHeight: 60000,
    mime: 'image/png',
  });
  expect(decode).not.toHaveBeenCalled();
  b.teaGraphicsBytesClose(id);
  expect(
    await b.teaGraphicsAsync({
      op: 'decode',
      bytes: upload(b, pngHeader()),
      bounds: true,
    }),
  ).toMatchObject({ ok: true });
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
});
test('aggregate raster budget preserves Source bitmaps across operations and rejects allocation before Canvas', () => {
  const allocation = vi.spyOn(Canvas.prototype, 'getContext');
  const b = opened({ rasterBytes: 32 }),
    first = b.teaGraphicsSync({ op: 'create', width: 2, height: 2 }),
    second = b.teaGraphicsSync({ op: 'create', width: 2, height: 2 });
  if (typeof first.id !== 'number' || typeof second.id !== 'number')
    throw Error('Missing surface ID');
  const firstOwner = b.teaGraphicsBitmapClaim(first.id),
    secondOwner = b.teaGraphicsBitmapClaim(second.id);
  expect(() =>
    b.teaGraphicsSync({ op: 'create', width: 1, height: 1 }),
  ).toThrow('budget');
  expect(allocation).toHaveBeenCalledTimes(2);
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot()).toMatchObject({
    surfaces: 2,
    rasterBytes: 32,
    totalBytes: 32,
  });
  b.teaGraphicsBegin({ requestId: 'next', generation: 'generation' });
  expect(b.teaGraphicsBitmapId(firstOwner)).toBe(first.id);
  expect(b.teaGraphicsBitmapId(secondOwner)).toBe(second.id);
  b.teaGraphicsBitmapRecycle(firstOwner);
  expect(
    b.teaGraphicsSync({ op: 'create', width: 2, height: 2 }),
  ).toMatchObject({ width: 2 });
  expect(allocation).toHaveBeenCalledTimes(3);
  b.teaGraphicsEnd('next', 'generation');
  // The replacement was never adopted; the still-held second owner survives.
  expect(b.teaGraphicsSnapshot()).toMatchObject({
    surfaces: 1,
    rasterBytes: 16,
    totalBytes: 16,
  });
  expect(b.teaGraphicsBitmapId(secondOwner)).toBe(second.id);
  b.teaGraphicsBitmapRecycle(secondOwner);
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
});
test('cancelled decode retains input and working reservations until non-interruptible codec settles', async () => {
  const gate = deferred<{ width: number; height: number; close(): void }>(),
    close = vi.fn();
  vi.stubGlobal('createImageBitmap', () => gate.promise);
  const b = opened(),
    id = upload(b, pngHeader()),
    operation = b.teaGraphicsAsync({ op: 'decode', bytes: id });
  const rejected = expect(operation).rejects.toMatchObject({
    code: 'cancelled',
  });
  const reserved = b.teaGraphicsSnapshot().totalBytes;
  b.teaGraphicsCancel(identity.requestId, identity.generation);
  b.teaGraphicsBytesClose(id);
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(reserved);
  expect(() =>
    b.teaGraphicsBegin({ requestId: 'next', generation: 'generation' }),
  ).toThrow('overlap');
  gate.resolve({ width: 2, height: 3, close });
  await rejected;
  expect(close).toHaveBeenCalledOnce();
  expect(b.teaGraphicsSnapshot()).toMatchObject({
    totalBytes: 0,
    surfaces: 0,
    handles: 0,
  });
});
test('encoding pins recycled source until pending browser work finishes, cancellation discards output', async () => {
  const gate = deferred<Blob>();
  vi.spyOn(Canvas.prototype, 'convertToBlob').mockImplementation(
    () => gate.promise,
  );
  const b = opened(),
    image = b.teaGraphicsSync({ op: 'create', width: 2, height: 3 }),
    operation = b.teaGraphicsAsync({
      op: 'encode',
      id: image.id,
      format: 'PNG',
    });
  const rejected = expect(operation).rejects.toMatchObject({
    code: 'cancelled',
  });
  b.teaGraphicsSync({ op: 'recycle', id: image.id });
  b.teaGraphicsCancel(identity.requestId, identity.generation);
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot().rasterBytes).toBe(24);
  gate.resolve(new Blob([pngHeader()], { type: 'image/png' }));
  await rejected;
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
});
test('decoder and detached Java frame have independent persistent leases', async () => {
  const closed = vi.fn();
  class Decoder {
    tracks = { ready: Promise.resolve(), selectedTrack: { frameCount: 1 } };
    decode() {
      return Promise.resolve({
        image: {
          displayWidth: 2,
          displayHeight: 3,
          colorSpace: { transfer: 'srgb' },
          close: closed,
        },
      });
    }
    close = vi.fn();
  }
  vi.stubGlobal('ImageDecoder', Decoder);
  const b = opened(),
    id = upload(b, pngHeader()),
    decoder = await b.teaGraphicsAsync({ op: 'openDecoder', bytes: id });
  b.teaGraphicsBytesClose(id);
  const frame = await b.teaGraphicsAsync({ op: 'nextFrame', id: decoder.id }),
    frameId = handle(frame);
  expect(b.teaGraphicsBytesRead(frameId, 65536)?.length).toBe(24);
  expect(b.teaGraphicsBytesRead(frameId, 65536)).toBeNull();
  b.teaGraphicsBytesDetach(frameId);
  b.teaGraphicsSync({ op: 'closeDecoder', id: decoder.id });
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(closed).toHaveBeenCalledTimes(2);
  expect(b.teaGraphicsSnapshot()).toMatchObject({
    decoders: 0,
    handles: 1,
    totalBytes: 24,
    rasterBytes: 24,
  });
  b.teaGraphicsBytesClose(frameId);
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
});
test('late decoder completion cannot publish a frame after close/cancel', async () => {
  const gate = deferred<{
      image: {
        displayWidth: number;
        displayHeight: number;
        colorSpace: { transfer: string };
        close(): void;
      };
    }>(),
    frameClose = vi.fn();
  let index = 0;
  class Decoder {
    tracks = { ready: Promise.resolve(), selectedTrack: { frameCount: 2 } };
    decode() {
      if (index++ === 0)
        return Promise.resolve({
          image: {
            displayWidth: 2,
            displayHeight: 3,
            colorSpace: { transfer: 'srgb' },
            close() {},
          },
        });
      return gate.promise;
    }
    close() {}
  }
  vi.stubGlobal('ImageDecoder', Decoder);
  const b = opened(),
    id = upload(b, pngHeader()),
    decoder = await b.teaGraphicsAsync({ op: 'openDecoder', bytes: id });
  b.teaGraphicsBytesClose(id);
  const operation = b.teaGraphicsAsync({ op: 'nextFrame', id: decoder.id }),
    rejected = expect(operation).rejects.toMatchObject({ code: 'cancelled' });
  b.teaGraphicsCancel(identity.requestId, identity.generation);
  b.teaGraphicsSync({ op: 'closeDecoder', id: decoder.id });
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot().totalBytes).toBeGreaterThan(0);
  gate.resolve({
    image: {
      displayWidth: 2,
      displayHeight: 3,
      colorSpace: { transfer: 'srgb' },
      close: frameClose,
    },
  });
  await rejected;
  expect(frameClose).toHaveBeenCalledOnce();
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
});
test('malformed image returns decode failure while dimensions/aggregate failures retain limit classification', async () => {
  const b = opened(),
    id = upload(b, new Uint8Array([1, 2, 3]));
  expect(await b.teaGraphicsAsync({ op: 'decode', bytes: id })).toEqual({
    ok: false,
  });
  await expect(
    b.teaGraphicsAsync({
      op: 'decode',
      bytes: upload(b, pngHeader(50000, 60000)),
    }),
  ).rejects.toMatchObject({ code: 'limit_exceeded' });
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
});

test('failed or cancelled pending fonts keep upload leases until load settles', async () => {
  const gate = deferred<void>(),
    add = vi.fn(),
    remove = vi.fn();
  class Face {
    load() {
      return gate.promise;
    }
  }
  vi.stubGlobal('FontFace', Face);
  vi.stubGlobal('self', { fonts: { add, delete: remove } });
  const b = opened(),
    id = upload(b, new Uint8Array([0, 255, 8])),
    operation = b.teaGraphicsAsync({ op: 'font', bytes: id }),
    rejected = expect(operation).rejects.toMatchObject({ code: 'cancelled' });
  b.teaGraphicsBytesClose(id);
  b.teaGraphicsCancel(identity.requestId, identity.generation);
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot().totalBytes).toBeGreaterThan(0);
  gate.resolve();
  await rejected;
  expect(add).not.toHaveBeenCalled();
  expect(remove).toHaveBeenCalledOnce();
  expect(b.teaGraphicsSnapshot()).toMatchObject({ fonts: 0, totalBytes: 0 });
});
test('tiny surfaces have a count bound independent of pixel budgets', () => {
  const b = opened(),
    ids = [];
  for (let i = 0; i < 64; i++)
    ids.push(b.teaGraphicsSync({ op: 'create', width: 1, height: 1 }).id);
  expect(() =>
    b.teaGraphicsSync({ op: 'create', width: 1, height: 1 }),
  ).toThrow('count');
  for (const id of ids) b.teaGraphicsSync({ op: 'recycle', id });
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
});
test('Canvas constructor failure returns its reservation', () => {
  vi.stubGlobal(
    'OffscreenCanvas',
    class {
      constructor() {
        throw Error('allocation failed');
      }
    },
  );
  const b = opened(),
    before = b.teaGraphicsSnapshot().totalBytes;
  expect(() =>
    b.teaGraphicsSync({ op: 'create', width: 2, height: 3 }),
  ).toThrow('allocation');
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(before);
});

test('invalid operation identity cannot leak the scratch reservation', () => {
  const b = createGraphicsBridge();
  expect(() =>
    Reflect.apply(b.teaGraphicsBegin, undefined, [
      { requestId: 1, generation: 'generation' },
    ]),
  ).toThrow('string');
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
  b.teaGraphicsBegin(identity);
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
});
test('decoder slots include pending opens and reject before constructing another codec', async () => {
  let held = false;
  const gate = deferred<void>(),
    constructed = vi.fn();
  class Decoder {
    constructor() {
      constructed();
    }
    tracks = { ready: Promise.resolve(), selectedTrack: { frameCount: 1 } };
    async decode() {
      if (held) await gate.promise;
      return {
        image: {
          displayWidth: 2,
          displayHeight: 3,
          colorSpace: { transfer: 'srgb' },
          close() {},
        },
      };
    }
    close() {}
  }
  vi.stubGlobal('ImageDecoder', Decoder);
  const b = opened(),
    id = upload(b, pngHeader()),
    ids: unknown[] = [];
  for (let i = 0; i < 7; i++)
    ids.push((await b.teaGraphicsAsync({ op: 'openDecoder', bytes: id })).id);
  held = true;
  const pending = b.teaGraphicsAsync({ op: 'openDecoder', bytes: id });
  await expect(
    b.teaGraphicsAsync({ op: 'openDecoder', bytes: id }),
  ).rejects.toMatchObject({ code: 'limit_exceeded' });
  expect(constructed).toHaveBeenCalledTimes(8);
  gate.resolve();
  ids.push((await pending).id);
  for (const decoder of ids)
    b.teaGraphicsSync({ op: 'closeDecoder', id: decoder });
  b.teaGraphicsBytesClose(id);
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
});
