import { z } from 'zod';

export const IMAGE_CODEC_LIMITS = Object.freeze({
  inputBytes: 8 * 1024 * 1024,
  payloadBytes: 16 * 1024 * 1024,
  heapBytes: 32 * 1024 * 1024,
  stripRows: 256,
  chunkBytes: 64 * 1024,
  sourceWidth: 4096,
  pngHeight: 100000,
  jpegHeight: 65500,
});

const integer = z.int();
const numberFunction = () => z.function({ input: [], output: integer });
const apiSchema = z
  .object({
    _image_input: z.function({ input: [integer], output: integer }),
    _image_open: z.function({
      input: [integer, integer, integer],
      output: integer,
    }),
    _image_next: numberFunction(),
    _image_strip: numberFunction(),
    _image_width: numberFunction(),
    _image_height: numberFunction(),
    _image_source_width: numberFunction(),
    _image_source_height: numberFunction(),
    _image_strip_start: numberFunction(),
    _image_error_code: numberFunction(),
    _image_error_phase: numberFunction(),
    _image_live_bytes: numberFunction(),
    _image_peak_bytes: numberFunction(),
    _image_allocations: numberFunction(),
    _image_close: z.function({ input: [], output: z.void() }),
  })
  .transform((raw) => ({
    image_input: raw._image_input,
    image_open: raw._image_open,
    image_next: raw._image_next,
    image_strip: raw._image_strip,
    image_width: raw._image_width,
    image_height: raw._image_height,
    image_source_width: raw._image_source_width,
    image_source_height: raw._image_source_height,
    image_strip_start: raw._image_strip_start,
    image_error_code: raw._image_error_code,
    image_error_phase: raw._image_error_phase,
    image_live_bytes: raw._image_live_bytes,
    image_peak_bytes: raw._image_peak_bytes,
    image_allocations: raw._image_allocations,
    image_close: raw._image_close,
  }));
const heapSchema = z.object({ HEAPU8: z.instanceof(Uint8Array) });
const factorySchema = z.object({
  default: z.function({ input: [], output: z.promise(z.unknown()) }),
});

export type ImageCodecApi = z.infer<typeof apiSchema>;
export interface ImageCodecMetrics {
  liveBytes: number;
  peakBytes: number;
  allocations: number;
  heapBytes: number;
}
export interface ImageCodecCleanup {
  succeeded: boolean;
  liveBytes: number | null;
  peakBytes: number | null;
  allocations: number | null;
  heapBytes: number | null;
  error: string | null;
}
export interface ImageCodecLease {
  readonly api: ImageCodecApi;
  writeInput(pointer: number, bytes: Uint8Array): void;
  copy(pointer: number, length: number): Uint8Array<ArrayBuffer>;
  metrics(): ImageCodecMetrics;
  error(): { code: number; phase: number };
  close(): ImageCodecCleanup;
}

const owners = new WeakSet<object>();
const unusable = new WeakSet<object>();

function failureMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}

/** Validates one independent, single-owner Emscripten codec instance. */
export class ImageCodec {
  readonly #raw: object;
  readonly #api: ImageCodecApi;

  constructor(raw: unknown) {
    if (typeof raw !== 'object' || raw === null)
      throw new Error('Expected an image codec module object');
    this.#api = apiSchema.parse(raw);
    heapSchema.parse(raw);
    this.#raw = raw;
  }

  acquire(): ImageCodecLease {
    if (unusable.has(this.#raw))
      throw new Error(
        'Image codec instance failed cleanup and cannot be reused',
      );
    if (owners.has(this.#raw))
      throw new Error('Image codec instance already has an owner');
    owners.add(this.#raw);
    let closed: ImageCodecCleanup | undefined;
    const active = () => {
      if (closed) throw new Error('Image codec lease is closed');
    };
    const owned =
      <Args extends unknown[], Result>(operation: (...args: Args) => Result) =>
      (...args: Args): Result => {
        active();
        return operation(...args);
      };
    const api: ImageCodecApi = {
      image_input: owned(this.#api.image_input),
      image_open: owned(this.#api.image_open),
      image_next: owned(this.#api.image_next),
      image_strip: owned(this.#api.image_strip),
      image_width: owned(this.#api.image_width),
      image_height: owned(this.#api.image_height),
      image_source_width: owned(this.#api.image_source_width),
      image_source_height: owned(this.#api.image_source_height),
      image_strip_start: owned(this.#api.image_strip_start),
      image_error_code: owned(this.#api.image_error_code),
      image_error_phase: owned(this.#api.image_error_phase),
      image_live_bytes: owned(this.#api.image_live_bytes),
      image_peak_bytes: owned(this.#api.image_peak_bytes),
      image_allocations: owned(this.#api.image_allocations),
      image_close: owned(this.#api.image_close),
    };
    const heap = () => {
      // Memory growth replaces this view. Never retain it across a yield.
      const view = heapSchema.parse(this.#raw).HEAPU8;
      if (!(view.buffer instanceof ArrayBuffer))
        throw new Error('Shared image codec memory is not supported');
      if (view.byteLength > IMAGE_CODEC_LIMITS.heapBytes)
        throw new Error('Image codec heap exceeds its configured limit');
      return view;
    };
    const range = (pointer: number, length: number) => {
      active();
      const view = heap();
      if (
        !Number.isSafeInteger(pointer) ||
        !Number.isSafeInteger(length) ||
        pointer <= 0 ||
        length < 0 ||
        pointer > view.byteLength ||
        length > view.byteLength - pointer
      )
        throw new Error('Image codec buffer range is outside its heap');
      return view;
    };
    const metrics = (): ImageCodecMetrics => {
      const liveBytes = this.#api.image_live_bytes();
      const peakBytes = this.#api.image_peak_bytes();
      const allocations = this.#api.image_allocations();
      if (
        liveBytes < 0 ||
        peakBytes < liveBytes ||
        allocations < 0 ||
        peakBytes > IMAGE_CODEC_LIMITS.payloadBytes
      )
        throw new Error('Image codec allocation accounting exceeds its limit');
      return {
        liveBytes,
        peakBytes,
        allocations,
        heapBytes: heap().byteLength,
      };
    };
    return {
      api,
      writeInput: (pointer, bytes) => {
        range(pointer, bytes.byteLength).set(bytes, pointer);
      },
      copy: (pointer, length) => {
        const view = range(pointer, length);
        const result = new Uint8Array(length);
        result.set(view.subarray(pointer, pointer + length));
        return result;
      },
      metrics: () => {
        active();
        return metrics();
      },
      error: () => {
        active();
        const code = this.#api.image_error_code();
        const phase = this.#api.image_error_phase();
        if (phase < 0) throw new Error('Invalid image codec error phase');
        return { code, phase };
      },
      close: () => {
        if (closed) return closed;
        const result: ImageCodecCleanup = {
          succeeded: false,
          liveBytes: null,
          peakBytes: null,
          allocations: null,
          heapBytes: null,
          error: null,
        };
        try {
          this.#api.image_close();
          Object.assign(result, metrics());
          if (result.liveBytes !== 0 || result.allocations !== 0)
            throw new Error('Image codec retained allocations after close');
          result.succeeded = true;
        } catch (error) {
          result.error = failureMessage(error);
          unusable.add(this.#raw);
        } finally {
          closed = result;
          owners.delete(this.#raw);
        }
        return result;
      },
    };
  }
}

export async function loadImageCodec(codecUrl: URL): Promise<ImageCodec> {
  const imported: unknown = await import(codecUrl.href);
  const raw = await factorySchema.parse(imported).default();
  return new ImageCodec(raw);
}
