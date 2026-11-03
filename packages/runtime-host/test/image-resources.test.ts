import { afterEach, expect, test, vi } from 'vitest';
import { IMAGE_CHUNK_LIMIT, processedImageSchema } from '@karuyomi/contracts';
import { ImageSink } from '../src/image-channel.js';
import { ImageResourceStore } from '../src/image-resources.js';
import { RuntimeFailure } from '../src/errors.js';
import { pngHeader } from './image-fixtures.js';

// Header fixtures exercise the channel. The injected decoder is deliberately
// separate from the real browser decode gate, which must reject corrupt images.
const stores: ImageResourceStore[] = [];
const sinks: ImageSink[] = [];
afterEach(() => {
  for (const store of stores.splice(0))
    store.clear(new RuntimeFailure('runtime_lost', 'test teardown'));
  for (const sink of sinks.splice(0)) sink.dispose();
  vi.restoreAllMocks();
});
function setup(
  options: ConstructorParameters<typeof ImageResourceStore>[0] = {},
) {
  const close = vi.fn();
  const store = new ImageResourceStore({
    decode: async () => ({ width: 2, height: 3, close }),
    ...options,
  });
  stores.push(store);
  const image = store.create('generation');
  const channel = new MessageChannel();
  image.attach(channel.port1);
  const cancelled = vi.fn();
  const sink = new ImageSink(channel.port2, image.resourceId, cancelled);
  sinks.push(sink);
  const handle = sink.open('image/png');
  return { store, image, sink, handle, close, cancelled };
}

test('prepared binary image is published only after matching Java completion and is revocable', async () => {
  const create = vi.spyOn(URL, 'createObjectURL');
  const revoke = vi.spyOn(URL, 'revokeObjectURL');
  const { store, image, sink, handle, close } = setup();
  const data = pngHeader(2, 3, 200_000);
  for (let offset = 0; offset < data.length; offset += IMAGE_CHUNK_LIMIT)
    await sink.write(handle, data.subarray(offset, offset + IMAGE_CHUNK_LIMIT));
  const prepared = processedImageSchema.parse(
    JSON.parse(await sink.close(handle)),
  );
  expect(close).toHaveBeenCalledOnce();
  expect(create).not.toHaveBeenCalled();
  expect(store.snapshot).toEqual({
    resources: 1,
    bytes: data.length,
    pixels: 6,
  });
  const resource = await image.publish(prepared);
  expect(resource).toMatchObject({
    ...prepared,
    url: expect.stringMatching(/^blob:/),
  });
  const received = new Uint8Array(
    await (await fetch(resource.url)).arrayBuffer(),
  );
  expect(received).toEqual(data);
  expect(data.buffer.byteLength).toBe(data.length);
  store.release(resource.resourceId, 'other-generation');
  expect(revoke).not.toHaveBeenCalled();
  store.release(resource.resourceId, 'generation');
  store.release(resource.resourceId, 'generation');
  expect(revoke).toHaveBeenCalledOnce();
  expect(store.snapshot).toEqual({ resources: 0, bytes: 0, pixels: 0 });
});

test('only one data frame can wait for an ACK and source buffers retain ownership', async () => {
  const channel = new MessageChannel();
  let received!: (value: { seq: number; buffer: ArrayBuffer }) => void;
  const next = new Promise<{ seq: number; buffer: ArrayBuffer }>((resolve) => {
    received = resolve;
  });
  channel.port1.onmessage = (event) => {
    const value: unknown = event.data;
    if (
      value &&
      typeof value === 'object' &&
      'type' in value &&
      value.type === 'meta'
    )
      channel.port1.postMessage({ type: 'ack', seq: 0 });
    else if (
      value &&
      typeof value === 'object' &&
      'seq' in value &&
      typeof value.seq === 'number' &&
      'buffer' in value &&
      value.buffer instanceof ArrayBuffer
    )
      received({ seq: value.seq, buffer: value.buffer });
  };
  const sink = new ImageSink(channel.port2, crypto.randomUUID(), () => {});
  sinks.push(sink);
  const handle = sink.open('image/png');
  const bytes = pngHeader();
  const write = sink.write(handle, bytes);
  const frame = await next;
  await expect(sink.write(handle, bytes)).rejects.toMatchObject({
    code: 'protocol_error',
  });
  expect(bytes.byteLength).toBe(33);
  expect(new Uint8Array(frame.buffer)).toEqual(bytes);
  channel.port1.postMessage({ type: 'ack', seq: frame.seq });
  await write;
  sink.dispose();
  channel.port1.close();
});

test('encoded and pixel budgets reject without publishing or leaking ownership', async () => {
  const create = vi.spyOn(URL, 'createObjectURL');
  const small = setup({ maxImageBytes: 32 });
  await expect(
    small.sink.write(small.handle, pngHeader()),
  ).rejects.toMatchObject({ code: 'limit_exceeded' });
  expect(small.store.snapshot.resources).toBe(0);
  const pixels = setup({ maxPixels: 5 });
  await pixels.sink.write(pixels.handle, pngHeader());
  await expect(pixels.sink.close(pixels.handle)).rejects.toMatchObject({
    code: 'limit_exceeded',
  });
  expect(pixels.close).not.toHaveBeenCalled();
  expect(pixels.store.snapshot).toEqual({ resources: 0, bytes: 0, pixels: 0 });
  expect(create).not.toHaveBeenCalled();
});

test('cancelled in-progress decode remains charged until its bitmap is closed', async () => {
  let finish!: (value: {
    width: number;
    height: number;
    close(): void;
  }) => void;
  const pending = new Promise<{ width: number; height: number; close(): void }>(
    (resolve) => {
      finish = resolve;
    },
  );
  const decode = vi.fn(() => pending);
  const { store, image, sink, handle } = setup({
    maxResources: 1,
    maxResidentPixels: 6,
    decode,
  });
  await sink.write(handle, pngHeader());
  const closing = expect(sink.close(handle)).rejects.toMatchObject({
    code: 'cancelled',
  });
  await vi.waitFor(() => expect(decode).toHaveBeenCalledOnce());
  image.abort(new RuntimeFailure('cancelled', 'cancel'));
  await closing;
  expect(store.snapshot).toEqual({ resources: 1, bytes: 33, pixels: 6 });
  expect(() => store.create('next')).toThrow('window is full');
  const close = vi.fn();
  finish({ width: 2, height: 3, close });
  await vi.waitFor(() => expect(store.snapshot.resources).toBe(0));
  expect(close).toHaveBeenCalledOnce();
  expect(store.snapshot).toEqual({ resources: 0, bytes: 0, pixels: 0 });
  image.release();
});

test('aggregate encoded bytes include resident images and are returned on release', async () => {
  const { store, image, sink, handle } = setup({ maxBytes: 65 });
  await sink.write(handle, pngHeader());
  const prepared = processedImageSchema.parse(
    JSON.parse(await sink.close(handle)),
  );
  await image.publish(prepared);
  const second = store.create('generation');
  const channel = new MessageChannel();
  second.attach(channel.port1);
  const other = new ImageSink(channel.port2, second.resourceId, () => {});
  sinks.push(other);
  const otherHandle = other.open('image/png');
  await expect(other.write(otherHandle, pngHeader())).rejects.toMatchObject({
    code: 'limit_exceeded',
  });
  expect(store.snapshot).toEqual({ resources: 1, bytes: 33, pixels: 6 });
  store.release(image.resourceId, 'generation');
  expect(store.snapshot).toEqual({ resources: 0, bytes: 0, pixels: 0 });
});

test('decode failure, metadata disagreement and Java mismatch cannot publish a URL', async () => {
  const create = vi.spyOn(URL, 'createObjectURL');
  const failed = setup({
    decode: async () => {
      throw new Error('invalid image');
    },
  });
  await failed.sink.write(failed.handle, pngHeader());
  await expect(failed.sink.close(failed.handle)).rejects.toMatchObject({
    code: 'source_error',
  });
  expect(failed.store.snapshot.resources).toBe(0);
  const rotated = setup({
    decode: async () => ({ width: 3, height: 2, close() {} }),
  });
  await rotated.sink.write(rotated.handle, pngHeader());
  const prepared = processedImageSchema.parse(
    JSON.parse(await rotated.sink.close(rotated.handle)),
  );
  expect(prepared).toMatchObject({ width: 3, height: 2 });
  await expect(
    rotated.image.publish({ ...prepared, byteLength: 34 }),
  ).rejects.toMatchObject({ code: 'protocol_error' });
  rotated.image.release();
  expect(rotated.store.snapshot.resources).toBe(0);
  expect(create).not.toHaveBeenCalled();
});

test('wrong sequence and END truncation abort the receiver', async () => {
  for (const frames of [
    [{ type: 'data', seq: 1, buffer: pngHeader().buffer }],
    [
      { type: 'meta', seq: 0, mimeType: 'image/png' },
      { type: 'end', seq: 1, totalBytes: 10 },
    ],
  ]) {
    const store = new ImageResourceStore();
    stores.push(store);
    const image = store.create('generation');
    const channel = new MessageChannel();
    image.attach(channel.port1);
    channel.port2.onmessage = () => {};
    const failure = expect(image.result).rejects.toMatchObject({
      code: 'protocol_error',
    });
    for (const frame of frames) channel.port2.postMessage(frame);
    await failure;
    expect(store.snapshot.resources).toBe(0);
    image.release();
    channel.port2.close();
  }
});
