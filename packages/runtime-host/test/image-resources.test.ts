import { afterEach, expect, test, vi } from 'vitest';
import {
  IMAGE_BODY_LIMIT,
  IMAGE_CHUNK_LIMIT,
  IMAGE_RESOURCE_LIMIT,
  processedImageSchema,
  encodeImageFrame,
  imageFrameSchema,
} from '@karuyomi/contracts';
import { ImageSink } from '../src/image-channel.js';
import { ImageResourceStore } from '../src/image-resources.js';
import { RuntimeFailure } from '../src/errors.js';

const stores: ImageResourceStore[] = [];
const sinks: ImageSink[] = [];
afterEach(() => {
  for (const store of stores.splice(0))
    store.clear(new RuntimeFailure('runtime_lost', 'test teardown'));
  for (const sink of sinks.splice(0)) sink.dispose();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});
function setup(
  options: ConstructorParameters<typeof ImageResourceStore>[0] = {},
) {
  const store = new ImageResourceStore(options);
  stores.push(store);
  return attach(store);
}
function attach(store: ImageResourceStore) {
  const image = store.create('generation');
  const channel = new MessageChannel();
  image.attach(channel.port1);
  const cancelled = vi.fn();
  const sink = new ImageSink(channel.port2, image.resourceId, cancelled);
  sinks.push(sink);
  const handle = sink.open();
  return { store, image, sink, handle, cancelled };
}
async function prepare(
  value: ReturnType<typeof setup>,
  bytes = new Uint8Array([0, 255, 7]),
) {
  await value.sink.write(value.handle, bytes);
  return processedImageSchema.parse(
    JSON.parse(await value.sink.close(value.handle)),
  );
}

test('opaque bytes publish only after matching Java completion and reuse one revocable URL', async () => {
  const create = vi.spyOn(URL, 'createObjectURL');
  const revoke = vi.spyOn(URL, 'revokeObjectURL');
  const decode = vi.fn(() => {
    throw new Error('host must not decode');
  });
  vi.stubGlobal('createImageBitmap', decode);
  const value = setup();
  const data = new Uint8Array(200_000).fill(173);
  for (let offset = 0; offset < data.length; offset += IMAGE_CHUNK_LIMIT)
    await value.sink.write(
      value.handle,
      data.subarray(offset, offset + IMAGE_CHUNK_LIMIT),
    );
  const prepared = processedImageSchema.parse(
    JSON.parse(await value.sink.close(value.handle)),
  );
  expect(prepared).toEqual({
    resourceId: value.image.resourceId,
    generation: 'generation',
    byteLength: data.length,
  });
  expect(create).not.toHaveBeenCalled();
  expect(value.store.snapshot).toEqual({ resources: 1, bytes: data.length });
  const resource = await value.image.publish(prepared);
  expect(await value.image.publish(prepared)).toEqual(resource);
  expect(create).toHaveBeenCalledOnce();
  const response = await fetch(resource.url);
  expect(response.headers.get('content-type')).toBe('');
  expect(new Uint8Array(await response.arrayBuffer())).toEqual(data);
  expect(data.buffer.byteLength).toBe(data.length);
  expect(decode).not.toHaveBeenCalled();
  value.store.release(resource.resourceId, 'other-generation');
  expect(revoke).not.toHaveBeenCalled();
  value.store.release(resource.resourceId, 'generation');
  value.store.release(resource.resourceId, 'generation');
  expect(revoke).toHaveBeenCalledOnce();
  expect(value.store.snapshot).toEqual({ resources: 0, bytes: 0 });
});

test('only one data frame can wait for an ACK and source buffers retain ownership', async () => {
  const channel = new MessageChannel();
  let received!: (value: { seq: number; buffer: ArrayBuffer }) => void;
  const next = new Promise<{ seq: number; buffer: ArrayBuffer }>((resolve) => {
    received = resolve;
  });
  channel.port1.onmessage = (event) => {
    const value = imageFrameSchema.parse(event.data);
    if (value.type === 'meta')
      channel.port1.postMessage(encodeImageFrame({ type: 'ack', seq: 0 }));
    else if (value.type === 'data')
      received({ seq: value.seq, buffer: value.buffer });
  };
  const sink = new ImageSink(channel.port2, crypto.randomUUID(), () => {});
  sinks.push(sink);
  const handle = sink.open();
  const bytes = new Uint8Array([1, 2, 3]);
  const write = sink.write(handle, bytes);
  const frame = await next;
  await expect(sink.write(handle, bytes)).rejects.toMatchObject({
    code: 'protocol_error',
  });
  expect(bytes.byteLength).toBe(3);
  expect(new Uint8Array(frame.buffer)).toEqual(bytes);
  channel.port1.postMessage(encodeImageFrame({ type: 'ack', seq: frame.seq }));
  await write;
  channel.port1.close();
});

test('default byte, resource and chunk budgets apply without image metadata', async () => {
  const store = new ImageResourceStore();
  stores.push(store);
  expect(store.limits).toEqual({
    maxBytes: IMAGE_BODY_LIMIT,
    maxImageBytes: IMAGE_BODY_LIMIT,
    maxResources: IMAGE_RESOURCE_LIMIT,
  });
  for (let index = 0; index < IMAGE_RESOURCE_LIMIT; index++)
    store.create('generation');
  expect(() => store.create('generation')).toThrow('window is full');
  const value = setup({ maxImageBytes: 2 });
  await expect(
    value.sink.write(value.handle, new Uint8Array(3)),
  ).rejects.toMatchObject({ code: 'limit_exceeded' });
  expect(value.store.snapshot).toEqual({ resources: 0, bytes: 0 });
  const chunk = setup();
  await expect(
    chunk.sink.write(chunk.handle, new Uint8Array(IMAGE_CHUNK_LIMIT + 1)),
  ).rejects.toMatchObject({ code: 'protocol_error' });
});

test('aggregate encoded bytes include resident resources and return on release', async () => {
  const value = setup({ maxBytes: 5 });
  await value.image.publish(await prepare(value));
  const second = value.store.create('generation');
  const channel = new MessageChannel();
  second.attach(channel.port1);
  const other = new ImageSink(channel.port2, second.resourceId, () => {});
  sinks.push(other);
  const handle = other.open();
  await expect(other.write(handle, new Uint8Array(3))).rejects.toMatchObject({
    code: 'limit_exceeded',
  });
  expect(value.store.snapshot).toEqual({ resources: 1, bytes: 3 });
  value.image.release();
  expect(value.store.snapshot).toEqual({ resources: 0, bytes: 0 });
});

test.each(['uploading', 'ended'] as const)(
  'Access retention keeps published bytes charged while discarding an %s resource',
  async (phase) => {
    const value = setup({ maxBytes: 5 });
    const resource = await value.image.publish(await prepare(value));
    const revoke = vi.spyOn(URL, 'revokeObjectURL');
    const pending = attach(value.store);
    await pending.sink.write(pending.handle, new Uint8Array([1, 2]));
    const prepared =
      phase === 'ended'
        ? processedImageSchema.parse(
            JSON.parse(await pending.sink.close(pending.handle)),
          )
        : undefined;
    const expired = new RuntimeFailure('access_required', 'Session expired');
    value.store.retainPublished(expired);
    expect(value.store.snapshot).toEqual({ resources: 1, bytes: 3 });
    if (prepared)
      await expect(pending.image.publish(prepared)).rejects.toMatchObject({
        code: 'cancelled',
      });
    else await expect(pending.image.result).rejects.toBe(expired);
    value.store.clear(new RuntimeFailure('runtime_lost', 'Reconnect'), true);
    expect(revoke).not.toHaveBeenCalled();
    expect(
      new Uint8Array(await (await fetch(resource.url)).arrayBuffer()),
    ).toEqual(new Uint8Array([0, 255, 7]));
    const replacement = attach(value.store);
    await expect(
      replacement.sink.write(replacement.handle, new Uint8Array(3)),
    ).rejects.toMatchObject({ code: 'limit_exceeded' });
    expect(value.store.snapshot).toEqual({ resources: 1, bytes: 3 });
    value.store.release(resource.resourceId, 'foreign-generation');
    expect(revoke).not.toHaveBeenCalled();
    value.store.release(resource.resourceId, resource.generation);
    expect(revoke).toHaveBeenCalledExactlyOnceWith(resource.url);
    expect(value.store.snapshot).toEqual({ resources: 0, bytes: 0 });
  },
);

test('retained resources still occupy the resource budget and explicit teardown revokes them', async () => {
  const value = setup({ maxResources: 1 });
  const resource = await value.image.publish(await prepare(value));
  const revoke = vi.spyOn(URL, 'revokeObjectURL');
  value.store.retainPublished(new RuntimeFailure('access_denied', 'Denied'));
  expect(() => value.store.create('replacement-generation')).toThrow(
    'window is full',
  );
  value.store.clear(new RuntimeFailure('runtime_lost', 'Identity changed'));
  expect(revoke).toHaveBeenCalledExactlyOnceWith(resource.url);
  expect(value.store.snapshot).toEqual({ resources: 0, bytes: 0 });
  expect(() => value.store.create('replacement-generation')).not.toThrow();
});

test.each(['resourceId', 'generation', 'byteLength'] as const)(
  'Java %s mismatch cannot publish a URL',
  async (field) => {
    const create = vi.spyOn(URL, 'createObjectURL');
    const value = setup();
    const prepared = await prepare(value);
    await expect(
      value.image.publish({
        ...prepared,
        [field]: field === 'byteLength' ? 4 : 'foreign',
      }),
    ).rejects.toMatchObject({ code: 'protocol_error' });
    expect(create).not.toHaveBeenCalled();
    value.image.release();
    expect(value.store.snapshot).toEqual({ resources: 0, bytes: 0 });
  },
);

test('cancellation before and after END returns bytes and prevents late publication', async () => {
  const create = vi.spyOn(URL, 'createObjectURL');
  const pending = setup();
  await pending.sink.write(pending.handle, new Uint8Array(3));
  pending.image.abort(new RuntimeFailure('cancelled', 'cancel'));
  await expect(pending.sink.close(pending.handle)).rejects.toMatchObject({
    code: 'cancelled',
  });
  expect(pending.store.snapshot).toEqual({ resources: 0, bytes: 0 });
  const ended = setup();
  const descriptor = await prepare(ended);
  ended.image.release();
  await expect(ended.image.publish(descriptor)).rejects.toMatchObject({
    code: 'cancelled',
  });
  expect(ended.store.snapshot).toEqual({ resources: 0, bytes: 0 });
  expect(create).not.toHaveBeenCalled();
});

test('URL creation failure is recoverable and cancellation during publication revokes the new URL', async () => {
  const value = setup();
  const descriptor = await prepare(value);
  const original = URL.createObjectURL;
  const create = vi.spyOn(URL, 'createObjectURL').mockImplementationOnce(() => {
    throw new Error('URL unavailable');
  });
  await expect(value.image.publish(descriptor)).rejects.toThrow(
    'URL unavailable',
  );
  await expect(value.image.publish(descriptor)).resolves.toHaveProperty('url');
  expect(create).toHaveBeenCalledTimes(2);
  const second = setup();
  const other = await prepare(second);
  const revoke = vi.spyOn(URL, 'revokeObjectURL');
  create.mockImplementationOnce((blob) => {
    const url = original(blob);
    second.image.release();
    return url;
  });
  await expect(second.image.publish(other)).rejects.toMatchObject({
    code: 'cancelled',
  });
  expect(revoke).toHaveBeenCalledOnce();
  expect(second.store.snapshot).toEqual({ resources: 0, bytes: 0 });
});

test('wrong sequence and END truncation abort the receiver', async () => {
  for (const frames of [
    [encodeImageFrame({ type: 'data', seq: 1, buffer: new ArrayBuffer(1) })],
    [
      encodeImageFrame({ type: 'meta', seq: 0 }),
      encodeImageFrame({ type: 'end', seq: 1, totalBytes: 10 }),
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
    expect(store.snapshot).toEqual({ resources: 0, bytes: 0 });
    image.release();
    channel.port2.close();
  }
});
