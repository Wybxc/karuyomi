import { z } from 'zod';
import {
  instantiateCodecModule,
  type ImageCodecLoadOptions,
  type ImageCodecCleanup,
  type ImageCodecMetrics,
} from './codec-api.ts';

export const PNG_ENCODER_LIMITS = Object.freeze({
  width: 4096,
  height: 256,
  rgbaBytes: 4 * 1024 * 1024,
  pngBytes: 8 * 1024 * 1024,
  payloadBytes: 16 * 1024 * 1024,
  heapBytes: 32 * 1024 * 1024,
});
const integer = z.int();
const numberFunction = () => z.function({ input: [], output: integer });
const encoderApiSchema = z
  .object({
    _encoder_input: z.function({ input: [integer], output: integer }),
    _encoder_encode: z.function({ input: [integer, integer], output: integer }),
    _encoder_output: numberFunction(),
    _encoder_length: numberFunction(),
    _encoder_error_code: numberFunction(),
    _encoder_live_bytes: numberFunction(),
    _encoder_peak_bytes: numberFunction(),
    _encoder_allocations: numberFunction(),
    _encoder_close: z.function({ input: [], output: z.void() }),
  })
  .transform((raw) => ({
    encoder_input: raw._encoder_input,
    encoder_encode: raw._encoder_encode,
    encoder_output: raw._encoder_output,
    encoder_length: raw._encoder_length,
    encoder_error_code: raw._encoder_error_code,
    encoder_live_bytes: raw._encoder_live_bytes,
    encoder_peak_bytes: raw._encoder_peak_bytes,
    encoder_allocations: raw._encoder_allocations,
    encoder_close: raw._encoder_close,
  }));
const heapSchema = z.object({ HEAPU8: z.instanceof(Uint8Array) });
const owners = new WeakSet<object>();
const unusable = new WeakSet<object>();
export type PngEncoderApi = z.infer<typeof encoderApiSchema>;
export interface PngEncoderLease {
  readonly api: PngEncoderApi;
  encode(
    rgba: Uint8Array,
    width: number,
    height: number,
  ): Uint8Array<ArrayBuffer>;
  metrics(): ImageCodecMetrics;
  close(): ImageCodecCleanup;
}

/** One bounded RGBA strip to PNG; no full-page raster or PNG implementation in TS. */
export class PngEncoder {
  readonly #raw: object;
  readonly #api: PngEncoderApi;
  constructor(raw: unknown) {
    if (typeof raw !== 'object' || raw === null)
      throw new Error('Expected a PNG encoder module object');
    this.#api = encoderApiSchema.parse(raw);
    heapSchema.parse(raw);
    this.#raw = raw;
  }
  acquire(): PngEncoderLease {
    if (unusable.has(this.#raw))
      throw new Error('PNG encoder instance failed cleanup');
    if (owners.has(this.#raw))
      throw new Error('PNG encoder instance already has an owner');
    owners.add(this.#raw);
    let closed: ImageCodecCleanup | undefined;
    let encoded = false;
    const active = () => {
      if (closed) throw new Error('PNG encoder lease is closed');
    };
    const owned =
      <Args extends unknown[], Result>(operation: (...args: Args) => Result) =>
      (...args: Args): Result => {
        active();
        return operation(...args);
      };
    const api: PngEncoderApi = {
      encoder_input: owned(this.#api.encoder_input),
      encoder_encode: owned(this.#api.encoder_encode),
      encoder_output: owned(this.#api.encoder_output),
      encoder_length: owned(this.#api.encoder_length),
      encoder_error_code: owned(this.#api.encoder_error_code),
      encoder_live_bytes: owned(this.#api.encoder_live_bytes),
      encoder_peak_bytes: owned(this.#api.encoder_peak_bytes),
      encoder_allocations: owned(this.#api.encoder_allocations),
      encoder_close: owned(this.#api.encoder_close),
    };
    const heap = () => {
      const bytes = heapSchema.parse(this.#raw).HEAPU8;
      if (
        !(bytes.buffer instanceof ArrayBuffer) ||
        bytes.byteLength > PNG_ENCODER_LIMITS.heapBytes
      )
        throw new Error('Invalid PNG encoder heap');
      return bytes;
    };
    const range = (pointer: number, length: number) => {
      const bytes = heap();
      if (
        !Number.isSafeInteger(pointer) ||
        !Number.isSafeInteger(length) ||
        pointer <= 0 ||
        length < 1 ||
        pointer > bytes.length ||
        length > bytes.length - pointer
      )
        throw new Error('PNG encoder buffer is outside its heap');
      return bytes;
    };
    const metrics = (): ImageCodecMetrics => {
      const liveBytes = this.#api.encoder_live_bytes();
      const peakBytes = this.#api.encoder_peak_bytes();
      const allocations = this.#api.encoder_allocations();
      if (
        liveBytes < 0 ||
        peakBytes < liveBytes ||
        peakBytes > PNG_ENCODER_LIMITS.payloadBytes ||
        allocations < 0
      )
        throw new Error('PNG encoder allocation accounting exceeds its limit');
      return {
        liveBytes,
        peakBytes,
        allocations,
        heapBytes: heap().byteLength,
      };
    };
    return {
      api,
      encode: (rgba, width, height) => {
        active();
        if (encoded)
          throw new Error('PNG encoder lease already encoded a strip');
        if (
          !(rgba instanceof Uint8Array) ||
          !(rgba.buffer instanceof ArrayBuffer) ||
          !Number.isSafeInteger(width) ||
          !Number.isSafeInteger(height) ||
          width < 1 ||
          width > PNG_ENCODER_LIMITS.width ||
          height < 1 ||
          height > PNG_ENCODER_LIMITS.height ||
          rgba.byteLength !== width * height * 4 ||
          rgba.byteLength > PNG_ENCODER_LIMITS.rgbaBytes
        )
          throw new Error('Invalid bounded RGBA strip');
        encoded = true;
        const pointer = api.encoder_input(rgba.byteLength);
        range(pointer, rgba.byteLength).set(rgba, pointer);
        const result = api.encoder_encode(width, height);
        if (result !== 0 || api.encoder_error_code() !== 0)
          throw new Error(
            'PNG strip encoding failed: ' + api.encoder_error_code(),
          );
        metrics();
        const length = api.encoder_length();
        if (length < 1 || length > PNG_ENCODER_LIMITS.pngBytes)
          throw new Error('Encoded PNG exceeds its strip budget');
        const output = api.encoder_output();
        return new Uint8Array(
          range(output, length).subarray(output, output + length),
        );
      },
      metrics: () => {
        active();
        return metrics();
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
          this.#api.encoder_close();
          Object.assign(result, metrics());
          if (result.liveBytes !== 0 || result.allocations !== 0)
            throw new Error('PNG encoder retained allocations after close');
          result.succeeded = true;
        } catch (error) {
          result.error = error instanceof Error ? error.message : String(error);
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

export async function loadPngEncoder(
  moduleUrl: URL,
  options: ImageCodecLoadOptions = {},
): Promise<PngEncoder> {
  return new PngEncoder(await instantiateCodecModule(moduleUrl, options));
}
