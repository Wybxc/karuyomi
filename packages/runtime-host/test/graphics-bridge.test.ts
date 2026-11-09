/** Controlled codec timing tests; real Canvas semantics run in browser/bridges.browser.test.ts. */
import { readFile } from 'node:fs/promises';
import { runtimeMaterialCatalogSchema } from '@karuyomi/contracts';
import { imageDimensionsFromData } from 'image-dimensions';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { createGraphicsBridge } from '../../../runtime/teavm/bridge/graphics-bridge.js';
import { WEBP_HEAP_BYTES } from '../../../runtime/teavm/bridge/webp-encoder.js';
import { deferred, pngHeader } from './image-fixtures.js';

const readPixels = vi.fn(
  (_x: number, _y: number, width: number, height: number) => ({
    data: new Uint8ClampedArray(width * height * 4),
  }),
);
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
      fillRect() {},
      getImageData: readPixels,
    };
  }
  convertToBlob(_options?: ImageEncodeOptions) {
    return Promise.resolve(
      new Blob([pngHeader(this.width, this.height)], { type: 'image/png' }),
    );
  }
}
beforeEach(() => vi.stubGlobal('OffscreenCanvas', Canvas));
afterEach(() => {
  readPixels.mockReset();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});
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
test('Canvas keeps its native encode path and probes lossy WebP once', async () => {
  const native = vi
      .spyOn(Canvas.prototype, 'convertToBlob')
      .mockImplementation(async (options) => new Blob(['test'], options)),
    compile = vi.spyOn(WebAssembly, 'compile');
  const b = opened(),
    image = b.teaGraphicsSync({ op: 'create', width: 2, height: 3 });
  for (const [format, mime] of [
    ['JPEG', 'image/jpeg'],
    ['PNG', 'image/png'],
    ['WEBP', 'image/webp'],
    ['WEBP_LOSSY', 'image/webp'],
  ]) {
    const encoded = await b.teaGraphicsAsync({
      op: 'encode',
      id: image.id,
      format,
      quality: 45,
    });
    expect(encoded).toMatchObject({ ok: true, mime });
    b.teaGraphicsBytesClose(handle(encoded));
  }
  expect(
    await b.teaGraphicsAsync({ op: 'encode', format: 'WEBP_LOSSLESS' }),
  ).toEqual({ ok: false });
  expect(native.mock.calls.map(([options]) => options)).toEqual([
    { type: 'image/jpeg', quality: 0.45 },
    { type: 'image/png', quality: 0.45 },
    { type: 'image/webp', quality: 0.8 },
    { type: 'image/webp', quality: 0.45 },
    { type: 'image/webp', quality: 0.45 },
  ]);
  expect(compile).not.toHaveBeenCalled();
  expect(readPixels).not.toHaveBeenCalled();
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
});

async function webpMaterial(): Promise<string> {
  const catalog = runtimeMaterialCatalogSchema.parse(
    JSON.parse(
      await readFile(
        new URL('../dist/materials.json', import.meta.url),
        'utf8',
      ),
    ),
  );
  const artifact = catalog.resources.find(
    (entry) => entry.logicalName === 'webp-encoder.wasm',
  );
  if (!artifact) throw Error('Missing generated WebP encoder');
  const wasm = await readFile(
    new URL('../dist/materials/' + artifact.sha256, import.meta.url),
  );
  const url = URL.createObjectURL(
    new Blob([wasm], { type: artifact.contentType }),
  );
  vi.stubGlobal('karuyomiResources', { 'webp-encoder.wasm': url });
  return url;
}
test.each([false, true])(
  'encodes real pixels with the bundled codec when Canvas reports WebP=%s but returns PNG',
  async (reportsWebp) => {
    const url = await webpMaterial();
    try {
      const native = vi
          .spyOn(Canvas.prototype, 'convertToBlob')
          .mockImplementation(function (this: Canvas) {
            const type =
              reportsWebp && this.width === 1 ? 'image/webp' : 'image/png';
            return Promise.resolve(new Blob(['test'], { type }));
          }),
        compile = vi.spyOn(WebAssembly, 'compile');
      const b = opened(),
        width = 64,
        height = 49,
        image = b.teaGraphicsSync({ op: 'create', width, height });
      const baseline = b.teaGraphicsSnapshot().totalBytes;
      const pixels = Uint8ClampedArray.from(
        { length: width * height * 4 },
        (_, i) =>
          i % 4 === 3 ? 255 : (i * 31 + Math.floor(i / 37) * 53) % 256,
      );
      readPixels.mockImplementation(() => {
        expect(b.teaGraphicsSnapshot().rasterBytes).toBe(
          WEBP_HEAP_BYTES + 2 * pixels.length,
        );
        return { data: pixels };
      });
      const outputs: Uint8Array[] = [];
      for (const quality of [10, 90]) {
        const encoded = await b.teaGraphicsAsync({
          op: 'encode',
          id: image.id,
          format: 'WEBP_LOSSY',
          quality,
        });
        expect(encoded).toMatchObject({ ok: true, mime: 'image/webp' });
        const id = handle(encoded),
          bytes = b.teaGraphicsBytesRead(id, 65536);
        if (!bytes) throw Error('Missing WebP output');
        expect(bytes.length).toBe(encoded.length);
        expect(imageDimensionsFromData(bytes)).toMatchObject({
          width,
          height,
          type: 'webp',
        });
        expect(b.teaGraphicsBytesRead(id, 65536)).toBeNull();
        expect(b.teaGraphicsSnapshot().totalBytes).toBe(
          baseline + bytes.length,
        );
        outputs.push(bytes);
        b.teaGraphicsBytesClose(id);
        expect(b.teaGraphicsSnapshot().totalBytes).toBe(baseline);
      }
      expect(outputs[0]).not.toEqual(outputs[1]);
      expect(native).toHaveBeenCalledTimes(reportsWebp ? 3 : 1);
      expect(compile).toHaveBeenCalledOnce();
      expect(readPixels).toHaveBeenCalledTimes(2);
      b.teaGraphicsEnd(identity.requestId, identity.generation);
      expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
    } finally {
      URL.revokeObjectURL(url);
    }
  },
);

test('the bundled codec cannot publish output when the byte handle has no remaining budget', async () => {
  const url = await webpMaterial();
  try {
    const rasterBytes = 2 * 3 * 4,
      b = opened({ totalBytes: 2 * 65536 + WEBP_HEAP_BYTES + 2 * rasterBytes }),
      image = b.teaGraphicsSync({ op: 'create', width: 2, height: 3 });
    const baseline = b.teaGraphicsSnapshot();
    await expect(
      b.teaGraphicsAsync({ op: 'encode', id: image.id, format: 'WEBP' }),
    ).rejects.toMatchObject({ code: 'limit_exceeded' });
    expect(readPixels).toHaveBeenCalledOnce();
    expect(b.teaGraphicsSnapshot()).toEqual(baseline);
    b.teaGraphicsEnd(identity.requestId, identity.generation);
    expect(b.teaGraphicsSnapshot().totalBytes).toBe(0);
  } finally {
    URL.revokeObjectURL(url);
  }
});

test('the bundled codec encodes and transfers a tall 720 × 5000 raster within the default budgets', async () => {
  const url = await webpMaterial();
  try {
    const b = opened(),
      width = 720,
      height = 5000,
      image = b.teaGraphicsSync({ op: 'create', width, height });
    const pixels = new Uint8ClampedArray(width * height * 4);
    let noise = 1;
    for (let i = 0; i < pixels.length; i += 4) {
      noise ^= noise << 13;
      noise ^= noise >>> 17;
      noise ^= noise << 5;
      // Banded tones with independent texture in each color channel.
      const tone = Math.floor(i / 4 / width) % 256;
      pixels[i] = (tone + (noise & 15)) & 255;
      pixels[i + 1] = (tone + ((noise >>> 8) & 15)) & 255;
      pixels[i + 2] = (tone + ((noise >>> 16) & 15)) & 255;
      pixels[i + 3] = 255;
    }
    readPixels.mockReturnValue({ data: pixels });
    const baseline = b.teaGraphicsSnapshot().totalBytes;
    const result = await b.teaGraphicsAsync({
      op: 'encode',
      id: image.id,
      format: 'WEBP_LOSSY',
      quality: 90,
    });
    expect(result).toMatchObject({ ok: true, mime: 'image/webp' });
    const id = handle(result),
      first = b.teaGraphicsBytesRead(id, 65536);
    if (!first) throw Error('Missing WebP output');
    expect(imageDimensionsFromData(first)).toMatchObject({
      width,
      height,
      type: 'webp',
    });
    let transferred = first.length;
    for (
      let chunk = b.teaGraphicsBytesRead(id, 65536);
      chunk;
      chunk = b.teaGraphicsBytesRead(id, 65536)
    )
      transferred += chunk.length;
    expect(transferred).toBe(result.length);
    expect(b.teaGraphicsSnapshot().totalBytes).toBe(baseline + transferred);
    b.teaGraphicsBytesClose(id);
    b.teaGraphicsEnd(identity.requestId, identity.generation);
    expect(b.teaGraphicsSnapshot()).toMatchObject({
      totalBytes: 0,
      handles: 0,
    });
  } finally {
    URL.revokeObjectURL(url);
  }
});

test('a missing verified WebP resource never triggers a network fetch or publishes bytes', async () => {
  vi.stubGlobal('karuyomiResources', {
    'webp-encoder.wasm': 'https://example.invalid/webp-encoder.wasm',
  });
  const fetch = vi.spyOn(globalThis, 'fetch');
  const b = opened(),
    image = b.teaGraphicsSync({ op: 'create', width: 2, height: 3 });
  await expect(
    b.teaGraphicsAsync({ op: 'encode', id: image.id, format: 'WEBP' }),
  ).rejects.toMatchObject({ code: 'unsupported_capability' });
  expect(fetch).not.toHaveBeenCalled();
  expect(readPixels).not.toHaveBeenCalled();
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot()).toMatchObject({ totalBytes: 0, handles: 0 });
});

test('WebP cancellation holds the recycled source during compilation and discards the late result', async () => {
  const compiling = deferred<void>(),
    compiled = deferred<WebAssembly.Module>();
  vi.stubGlobal('karuyomiResources', { 'webp-encoder.wasm': 'blob:verified' });
  vi.stubGlobal('fetch', () => Promise.resolve(new Response()));
  vi.spyOn(WebAssembly, 'compile').mockImplementation(() => {
    compiling.resolve();
    return compiled.promise;
  });
  const b = opened(),
    image = b.teaGraphicsSync({ op: 'create', width: 2, height: 3 }),
    operation = b.teaGraphicsAsync({
      op: 'encode',
      id: image.id,
      format: 'WEBP',
    }),
    rejected = expect(operation).rejects.toMatchObject({ code: 'cancelled' });
  await compiling.promise;
  b.teaGraphicsSync({ op: 'recycle', id: image.id });
  b.teaGraphicsCancel(identity.requestId, identity.generation);
  b.teaGraphicsEnd(identity.requestId, identity.generation);
  expect(b.teaGraphicsSnapshot().rasterBytes).toBe(24);
  compiled.resolve(
    new WebAssembly.Module(new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0])),
  );
  await rejected;
  expect(readPixels).not.toHaveBeenCalled();
  expect(b.teaGraphicsSnapshot()).toMatchObject({ totalBytes: 0, handles: 0 });
});

test('WebP reserves the imported heap and Canvas readback before touching pixels', async () => {
  vi.stubGlobal('karuyomiResources', { 'webp-encoder.wasm': 'blob:verified' });
  vi.stubGlobal('fetch', () => Promise.resolve(new Response()));
  vi.spyOn(WebAssembly, 'compile').mockResolvedValue(
    new WebAssembly.Module(new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0])),
  );
  const b = opened({ rasterBytes: WEBP_HEAP_BYTES + 2 * 24 - 1 }),
    image = b.teaGraphicsSync({ op: 'create', width: 2, height: 3 });
  await expect(
    b.teaGraphicsAsync({ op: 'encode', id: image.id, format: 'WEBP' }),
  ).rejects.toMatchObject({ code: 'limit_exceeded' });
  expect(readPixels).not.toHaveBeenCalled();
  expect(b.teaGraphicsSnapshot()).toMatchObject({
    rasterBytes: 24,
    handles: 0,
  });
  b.teaGraphicsEnd(identity.requestId, identity.generation);
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
