import { randomFillSync } from 'node:crypto';
import { afterEach, expect, test, vi } from 'vitest';
import sharp from 'sharp';
import { IMAGE_CHUNK_LIMIT, encodedImageSchema } from '@karuyomi/contracts';
import { ImageSink } from '../src/image-channel.js';
import {
  ImageResourceStore,
  type EncodedImageLease,
} from '../src/image-resources.js';
import { RuntimeFailure } from '../src/errors.js';
import { deferred, pngHeader } from './image-fixtures.js';

const stores: ImageResourceStore[] = [];
const sinks: ImageSink[] = [];
const leases: EncodedImageLease[] = [];
afterEach(() => {
  for (const store of stores.splice(0))
    store.clear(new RuntimeFailure('runtime_lost', 'test teardown'));
  for (const lease of leases.splice(0)) lease.release();
  for (const sink of sinks.splice(0)) sink.dispose();
  vi.restoreAllMocks();
});
function setup(
  options: ConstructorParameters<typeof ImageResourceStore>[0] = {},
  producerEncoded = true,
) {
  const decode = vi.fn(async () => {
    throw new Error('encoded reception must never allocate a bitmap');
  });
  const store = new ImageResourceStore({ decode, ...options });
  stores.push(store);
  const image = store.create('generation', { encodedOnly: true });
  const channel = new MessageChannel();
  image.attach(channel.port1);
  const cancelled = vi.fn();
  const sink = new ImageSink(
    channel.port2,
    image.resourceId,
    cancelled,
    producerEncoded,
  );
  sinks.push(sink);
  return { store, image, sink, decode, cancelled };
}
async function transfer(
  sink: ImageSink,
  bytes: Uint8Array,
  mimeType = 'image/png',
) {
  const handle = sink.open(mimeType);
  for (let offset = 0; offset < bytes.byteLength; offset += IMAGE_CHUNK_LIMIT)
    await sink.write(
      handle,
      bytes.subarray(offset, offset + IMAGE_CHUNK_LIMIT),
    );
  return encodedImageSchema.parse(JSON.parse(await sink.close(handle)));
}

test('long encoded pages are admitted without raster decode, and END alone cannot lend the Blob', async () => {
  const create = vi.spyOn(URL, 'createObjectURL');
  const { store, image, sink, decode } = setup();
  const bytes = pngHeader(4096, 100000);
  const receipt = await transfer(sink, bytes);
  expect(receipt).toMatchObject({
    rawWidth: 4096,
    rawHeight: 100000,
    orientation: 1,
  });
  expect(store.snapshot).toEqual({
    resources: 1,
    bytes: bytes.length,
    pixels: 0,
  });
  expect(() => store.borrowEncoded(image.resourceId, 'generation')).toThrow(
    'not published',
  );
  expect(decode).not.toHaveBeenCalled();
  expect(create).not.toHaveBeenCalled();
  await image.publishEncoded(receipt);
  const one = store.borrowEncoded(image.resourceId, 'generation');
  const two = store.borrowEncoded(image.resourceId, 'generation');
  leases.push(one, two);
  expect(new Uint8Array(await one.blob.arrayBuffer())).toEqual(bytes);
  one.descriptor.orientation = 8;
  expect(two.descriptor.orientation).toBe(1);
  store.release(image.resourceId, 'generation');
  expect(() => store.borrowEncoded(image.resourceId, 'generation')).toThrow(
    'not published',
  );
  expect(store.snapshot).toEqual({
    resources: 1,
    bytes: bytes.length,
    pixels: 0,
  });
  one.release();
  one.release();
  expect(store.snapshot.resources).toBe(1);
  two.release();
  expect(store.snapshot).toEqual({ resources: 0, bytes: 0, pixels: 0 });
});

test('real JPEG EXIF orientations are preserved as metadata without swapping raw geometry', async () => {
  for (let orientation = 1; orientation <= 8; orientation++) {
    const bytes = await sharp({
      create: { width: 2, height: 3, channels: 3, background: '#346789' },
    })
      .withMetadata({ orientation })
      .jpeg()
      .toBuffer();
    const { image, sink, decode } = setup();
    const receipt = await transfer(sink, bytes, 'image/jpeg');
    expect(receipt).toMatchObject({ rawWidth: 2, rawHeight: 3, orientation });
    await image.publishEncoded(receipt);
    expect(decode).not.toHaveBeenCalled();
    image.release();
  }
});

test('PNG eXIf after a large IDAT remains visible beyond the header prefix', async () => {
  const raw = randomFillSync(Buffer.alloc(1024 * 1024 * 3));
  const png = await sharp(raw, {
    raw: { width: 1024, height: 1024, channels: 3 },
  })
    .withMetadata({ orientation: 6 })
    .png({ compressionLevel: 0 })
    .toBuffer();
  const chunks: Buffer[] = [];
  let exif: Buffer | undefined;
  let end: Buffer | undefined;
  for (let offset = 8; offset < png.length;) {
    const size = png.readUInt32BE(offset) + 12;
    const chunk = png.subarray(offset, offset + size);
    const kind = png.toString('ascii', offset + 4, offset + 8);
    if (kind === 'eXIf') exif = chunk;
    else if (kind === 'IEND') end = chunk;
    else chunks.push(chunk);
    offset += size;
  }
  expect(exif).toBeDefined();
  expect(end).toBeDefined();
  if (!exif || !end) throw new Error('Sharp PNG must carry EXIF and IEND');
  const bytes = Buffer.concat([png.subarray(0, 8), ...chunks, exif, end]);
  expect(bytes.indexOf(exif)).toBeGreaterThan(1024 * 1024);
  const { image, sink, decode } = setup();
  const receipt = await transfer(sink, bytes);
  expect(receipt).toMatchObject({
    rawWidth: 1024,
    rawHeight: 1024,
    orientation: 6,
  });
  await image.publishEncoded(receipt);
  expect(decode).not.toHaveBeenCalled();
});

test('encoded byte and geometry budgets reject before metadata or raster work', async () => {
  const metadata = vi.fn(async () => 1);
  const large = setup({ orientation: metadata });
  const handle = large.sink.open('image/png');
  for (let index = 0; index < 128; index++)
    await large.sink.write(handle, new Uint8Array(IMAGE_CHUNK_LIMIT));
  await expect(
    large.sink.write(handle, new Uint8Array([1])),
  ).rejects.toMatchObject({ code: 'limit_exceeded' });
  expect(large.store.snapshot).toEqual({ resources: 0, bytes: 0, pixels: 0 });
  for (const [width, height] of [
    [4097, 100],
    [100, 100001],
  ]) {
    const invalid = setup({ orientation: metadata });
    await expect(
      transfer(invalid.sink, pngHeader(width, height)),
    ).rejects.toMatchObject({ code: 'limit_exceeded' });
    expect(invalid.store.snapshot).toEqual({
      resources: 0,
      bytes: 0,
      pixels: 0,
    });
  }
  expect(metadata).not.toHaveBeenCalled();
});

test('Java mismatch, ACK mode mismatch and non PNG/JPEG content cannot publish an encoded resource', async () => {
  const mismatch = setup();
  const receipt = await transfer(mismatch.sink, pngHeader());
  await expect(
    mismatch.image.publishEncoded({ ...receipt, orientation: 8 }),
  ).rejects.toMatchObject({ code: 'protocol_error' });
  expect(() =>
    mismatch.store.borrowEncoded(receipt.resourceId, receipt.generation),
  ).toThrow('not published');
  const wrongMode = setup({}, false);
  await expect(transfer(wrongMode.sink, pngHeader())).rejects.toMatchObject({
    code: 'protocol_error',
  });
  const unsupported = setup();
  const webp = await sharp({
    create: { width: 2, height: 3, channels: 3, background: '#123456' },
  })
    .webp()
    .toBuffer();
  await expect(
    transfer(unsupported.sink, webp, 'image/webp'),
  ).rejects.toMatchObject({ code: 'unsupported_capability' });
  expect(unsupported.store.snapshot).toEqual({
    resources: 0,
    bytes: 0,
    pixels: 0,
  });
});

test('cancellation retains encoded ownership until metadata work settles and then frees the resource', async () => {
  const pending = deferred<number | undefined>();
  const metadata = vi.fn(() => pending.promise);
  const { image, sink, store, decode } = setup({ orientation: metadata });
  const closing = expect(transfer(sink, pngHeader())).rejects.toMatchObject({
    code: 'cancelled',
  });
  await vi.waitFor(() => expect(metadata).toHaveBeenCalledOnce());
  image.abort(new RuntimeFailure('cancelled', 'cancel metadata'));
  await closing;
  expect(store.snapshot).toEqual({ resources: 1, bytes: 33, pixels: 0 });
  pending.resolve(1);
  await vi.waitFor(() => expect(store.snapshot.resources).toBe(0));
  expect(decode).not.toHaveBeenCalled();
});
