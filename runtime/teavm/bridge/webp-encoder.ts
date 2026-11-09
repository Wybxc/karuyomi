import { workerScope } from './bridge-common.js';

const PAGE_BYTES = 64 * 1024;
// The full 96 MiB heap cap is charged to the graphics budgets before encoding.
const MAX_MEMORY_PAGES = 1536;
export const WEBP_HEAP_BYTES = MAX_MEMORY_PAGES * PAGE_BYTES;
export const WEBP_MAX_DIMENSION = 16_383;

export async function compileWebpEncoder(): Promise<WebAssembly.Module> {
  const url = workerScope().karuyomiResources?.['webp-encoder.wasm'];
  if (!url?.startsWith('blob:'))
    throw Object.assign(Error('Verified WebP encoder is unavailable'), {
      code: 'unsupported_capability',
    });
  const response = await fetch(url, { credentials: 'omit' });
  if (!response.ok) throw Error('Cannot read verified WebP encoder');
  return WebAssembly.compile(await response.arrayBuffer());
}

/** The caller reserves the entire heap and consumes the borrowed output inline. */
export function encodeWebp<T>(
  module: WebAssembly.Module,
  pixels: Uint8ClampedArray<ArrayBuffer>,
  width: number,
  height: number,
  quality: number,
  outputLimit: number,
  consume: (output: Uint8Array<ArrayBuffer>) => T,
): T | undefined {
  const memory = new WebAssembly.Memory({
    initial: 32,
    maximum: MAX_MEMORY_PAGES,
  });
  const { _initialize, webp_alloc, webp_free, webp_encode } =
    new WebAssembly.Instance(module, { env: { memory } }).exports;
  if (
    typeof _initialize !== 'function' ||
    typeof webp_alloc !== 'function' ||
    typeof webp_free !== 'function' ||
    typeof webp_encode !== 'function'
  )
    throw Error('Invalid WebP encoder exports');
  _initialize();

  // A lossy raster rarely needs as many encoded bytes as its input. Give
  // small images headroom for headers without allocating a full body buffer.
  const capacity = Math.min(outputLimit, pixels.byteLength + PAGE_BYTES);
  const input: unknown = webp_alloc(pixels.byteLength);
  if (input === 0) return;
  if (typeof input !== 'number' || !Number.isSafeInteger(input) || input < 0)
    throw Error('Invalid WebP encoder input address');
  try {
    const output: unknown = webp_alloc(capacity);
    if (output === 0) return;
    if (
      typeof output !== 'number' ||
      !Number.isSafeInteger(output) ||
      output < 0
    )
      throw Error('Invalid WebP encoder output address');
    try {
      // Allocation and encoding can both grow memory and detach old views.
      new Uint8Array(memory.buffer, input, pixels.byteLength).set(pixels);
      const length: unknown = webp_encode(
        input,
        width,
        height,
        output,
        capacity,
        quality,
      );
      if (length === 0) return;
      if (
        typeof length !== 'number' ||
        !Number.isSafeInteger(length) ||
        length < 12 ||
        length > capacity
      )
        throw Error('Invalid WebP encoder output length');
      const bytes = new Uint8Array(memory.buffer, output, length);
      const header = new DataView(bytes.buffer, bytes.byteOffset, 12);
      if (
        header.getUint32(0) !== 0x52494646 ||
        header.getUint32(4, true) !== length - 8 ||
        header.getUint32(8) !== 0x57454250
      )
        throw Error('Invalid WebP encoder output format');
      return consume(bytes);
    } finally {
      webp_free(output);
    }
  } finally {
    webp_free(input);
  }
}
