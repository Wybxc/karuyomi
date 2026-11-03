// Upstream Emscripten glue comes from the exact locked npm dependency.
import { init, compress, decompress } from '@bokuweb/zstd-wasm';
import { decodeBase64, encodeBase64, workerScope } from './bridge-common.js';

export const ZSTD_PLAIN_LIMIT = 8 * 1024 * 1024;
export const ZSTD_COMPRESSED_LIMIT = 9 * 1024 * 1024;
const ZSTD_FRAME_LIMIT = 1024;

export interface ZstdFrame {
  bytes: Uint8Array;
  size: number | undefined;
}

/** Validate frame boundaries and output budgets before calling upstream WASM. */
export function frames(input: Uint8Array): ZstdFrame[] {
  const view = new DataView(input.buffer, input.byteOffset, input.byteLength);
  const result: ZstdFrame[] = [];
  let offset = 0,
    count = 0;
  function requireBytes(length: number) {
    if (length > input.length - offset) throw Error('Truncated Zstd frame');
  }
  while (offset < input.length) {
    if (++count > ZSTD_FRAME_LIMIT)
      throw Error('Zstd frame count limit exceeded');
    const start = offset;
    requireBytes(4);
    const magic = view.getUint32(offset, true);
    offset += 4;
    if (magic >= 0x184d2a50 && magic <= 0x184d2a5f) {
      requireBytes(4);
      const length = view.getUint32(offset, true);
      offset += 4;
      requireBytes(length);
      offset += length;
      continue;
    }
    if (magic !== 0xfd2fb528) throw Error('Invalid Zstd magic');
    requireBytes(1);
    const descriptor = input[offset++]!;
    if (descriptor & 8) throw Error('Reserved Zstd header bit');
    const single = (descriptor & 32) !== 0,
      checksum = (descriptor & 4) !== 0;
    if (!single) {
      requireBytes(1);
      offset++;
    }
    const dictionaryBytes = [0, 1, 2, 4][descriptor & 3]!;
    requireBytes(dictionaryBytes);
    for (let index = 0; index < dictionaryBytes; index++)
      if (input[offset + index] !== 0)
        throw Error('Zstd dictionaries are unsupported');
    offset += dictionaryBytes;
    const flag = descriptor >>> 6;
    const sizeBytes = flag === 0 ? (single ? 1 : 0) : 1 << flag;
    requireBytes(sizeBytes);
    let size: number | undefined;
    if (sizeBytes) {
      let value = 0n;
      for (let index = 0; index < sizeBytes; index++)
        value |= BigInt(input[offset + index]!) << BigInt(index * 8);
      if (sizeBytes === 2) value += 256n;
      if (value > BigInt(ZSTD_PLAIN_LIMIT))
        throw Error('Zstd output limit exceeded');
      size = Number(value);
    }
    offset += sizeBytes;
    let last = false;
    while (!last) {
      requireBytes(3);
      const block =
        input[offset]! | (input[offset + 1]! << 8) | (input[offset + 2]! << 16);
      offset += 3;
      last = (block & 1) !== 0;
      const type = (block >>> 1) & 3,
        length = block >>> 3;
      if (type === 3 || length > 128 * 1024) throw Error('Invalid Zstd block');
      const stored = type === 1 ? 1 : length;
      requireBytes(stored);
      offset += stored;
    }
    if (checksum) {
      requireBytes(4);
      offset += 4;
    }
    result.push({ bytes: input.subarray(start, offset), size });
  }
  if (!count) throw Error('Empty input is not a Zstd stream');
  return result;
}

export interface ZstdApi {
  compress(input: Uint8Array, level: number): Uint8Array;
  decompress(
    input: Uint8Array,
    options: { defaultHeapSize: number },
  ): Uint8Array;
}

export function createZstdCodec(wasm: ZstdApi) {
  return {
    compress(input: Uint8Array): Uint8Array {
      if (input.length > ZSTD_PLAIN_LIMIT)
        throw Error('Zstd input limit exceeded');
      return wasm.compress(input, 3);
    },
    decompress(input: Uint8Array): Uint8Array {
      if (input.length > ZSTD_COMPRESSED_LIMIT)
        throw Error('Zstd compressed input limit exceeded');
      const chunks: Uint8Array[] = [];
      let length = 0;
      for (const frame of frames(input)) {
        const remaining = ZSTD_PLAIN_LIMIT - length;
        if (frame.size !== undefined && frame.size > remaining)
          throw Error('Zstd output limit exceeded');
        const chunk = wasm.decompress(frame.bytes, {
          defaultHeapSize: Math.max(1, remaining),
        });
        if (chunk.length > remaining) throw Error('Zstd output limit exceeded');
        if (frame.size !== undefined && chunk.length !== frame.size)
          throw Error('Zstd content size mismatch');
        chunks.push(chunk);
        length += chunk.length;
      }
      const output = new Uint8Array(length);
      let offset = 0;
      for (const chunk of chunks) {
        output.set(chunk, offset);
        offset += chunk.length;
      }
      return output;
    },
  };
}

declare global {
  var teaZstd: typeof zstdBridge | undefined;
}

const scope = workerScope();
let initialized: Promise<void> | undefined;
const codec = createZstdCodec({ compress, decompress });
async function initialize(): Promise<void> {
  const url = scope.karuyomiResources?.['zstd.wasm'];
  if (!url || !url.startsWith('blob:'))
    throw Error('Verified zstd.wasm resource is missing');
  return new Promise<void>((resolve, reject) => {
    const timer = setTimeout(
      () => reject(Error('Zstd WASM initialization timed out')),
      30_000,
    );
    init(url).then(
      () => {
        clearTimeout(timer);
        resolve();
      },
      (error: unknown) => {
        clearTimeout(timer);
        reject(error);
      },
    );
  });
}
const zstdBridge = async (
  operation: string,
  payload: string,
): Promise<string> => {
  try {
    if (operation !== 'compress' && operation !== 'decompress')
      throw Error('Unknown Zstd operation');
    if (
      typeof payload !== 'string' ||
      payload.length > Math.ceil(ZSTD_COMPRESSED_LIMIT / 3) * 4
    )
      throw Error('Zstd bridge input limit exceeded');
    await (initialized ??= initialize());
    return JSON.stringify({
      body: encodeBase64(codec[operation](decodeBase64(payload))),
    });
  } catch (error) {
    return JSON.stringify({
      error: error instanceof Error ? error.message : String(error),
    });
  }
};
scope.teaZstd = zstdBridge;
