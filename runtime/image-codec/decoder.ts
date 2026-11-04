import { z } from 'zod';
import {
  IMAGE_CODEC_LIMITS,
  loadImageCodec,
  type ImageCodec,
  type ImageCodecCleanup,
  type ImageCodecLease,
} from './codec-api.ts';

export type ImageCodecFormat = 'png' | 'jpeg';
export interface ImageDecodeOptions {
  bytes: Uint8Array;
  codecUrl: URL;
  format: ImageCodecFormat;
  denominator?: 1 | 2 | 4;
  signal?: AbortSignal;
}
export interface ImageHeader {
  format: ImageCodecFormat;
  sourceWidth: number;
  sourceHeight: number;
  width: number;
  height: number;
  rowBytes: number;
  denominator: 1 | 2 | 4;
}
export interface ImageDecodeTerminal {
  status: 'complete' | 'cancelled' | 'failed';
  header: ImageHeader | null;
  deliveredBytes: number;
  decodedRows: number;
  decodeErrorCode: number | null;
  decodeErrorPhase: number | null;
  error: { name: string; message: string } | null;
  closeSucceeded: boolean;
  liveBytes: number | null;
  allocations: number | null;
  peakBytes: number | null;
  heapBytes: number | null;
}
export type ImageDecodeEvent =
  | ({ kind: 'header' } & ImageHeader)
  | {
      kind: 'chunk';
      sequence: number;
      offset: number;
      stripStart: number;
      stripRows: number;
      bytes: Uint8Array<ArrayBuffer>;
    }
  | ({ kind: 'terminal' } & ImageDecodeTerminal);
export interface ImageDecodeDependencies {
  loadCodec?: (codecUrl: URL) => Promise<ImageCodec>;
}

function describeError(error: unknown) {
  return error instanceof Error
    ? { name: error.name, message: error.message }
    : { name: 'Error', message: String(error) };
}

function emptyTerminal(): ImageDecodeTerminal {
  return {
    status: 'cancelled',
    header: null,
    deliveredBytes: 0,
    decodedRows: 0,
    decodeErrorCode: null,
    decodeErrorPhase: null,
    error: null,
    closeSucceeded: false,
    liveBytes: null,
    allocations: null,
    peakBytes: null,
    heapBytes: null,
  };
}

/** Pull-driven byte chunks, not display tiles or a complete decoded raster. */
export class ImageDecodeSession implements AsyncIterable<ImageDecodeEvent> {
  readonly completion: Promise<ImageDecodeTerminal>;
  readonly #options: ImageDecodeOptions;
  readonly #load: (codecUrl: URL) => Promise<ImageCodec>;
  readonly #iterator: AsyncGenerator<ImageDecodeEvent, void, void>;
  readonly #resolve: (terminal: ImageDecodeTerminal) => void;
  readonly #cancellation = new AbortController();
  readonly #abort = () => {
    void this.cancel();
  };
  #started = false;
  #iterated = false;
  #cancelled = false;
  #terminal: ImageDecodeTerminal | undefined;

  constructor(
    options: ImageDecodeOptions,
    dependencies: ImageDecodeDependencies = {},
  ) {
    this.#options = options;
    this.#load = dependencies.loadCodec ?? loadImageCodec;
    const completion: {
      resolve?: (terminal: ImageDecodeTerminal) => void;
    } = {};
    this.completion = new Promise<ImageDecodeTerminal>((resolve) => {
      completion.resolve = resolve;
    });
    if (!completion.resolve) throw new Error('Cannot initialize image session');
    this.#resolve = completion.resolve;
    this.#iterator = this.#run();
    if (options.signal?.aborted) void this.cancel();
    else options.signal?.addEventListener('abort', this.#abort, { once: true });
  }

  [Symbol.asyncIterator](): AsyncIterator<ImageDecodeEvent, void, void> {
    if (this.#iterated)
      throw new Error('Image decode session already has a consumer');
    this.#iterated = true;
    let pending = false;
    return {
      next: async () => {
        if (pending) throw new Error('Concurrent image decode next is invalid');
        pending = true;
        try {
          return await this.#iterator.next();
        } finally {
          pending = false;
        }
      },
      return: async () => {
        await this.cancel();
        return this.#iterator.return(undefined);
      },
    };
  }

  async cancel(): Promise<void> {
    if (this.#terminal) return;
    this.#cancelled = true;
    this.#cancellation.abort();
    if (!this.#started) {
      this.#finish(emptyTerminal());
      return;
    }
    // Queues behind a running synchronous C call; it does not preempt C.
    await this.#iterator.return(undefined);
  }

  #finish(terminal: ImageDecodeTerminal) {
    if (this.#terminal) return;
    this.#terminal = terminal;
    this.#options.signal?.removeEventListener('abort', this.#abort);
    this.#resolve(terminal);
  }

  #checkCancellation() {
    if (this.#cancelled || this.#options.signal?.aborted)
      throw new DOMException('Image decode cancelled', 'AbortError');
  }

  async #loadCodec(codecUrl: URL): Promise<ImageCodec> {
    const signal = this.#cancellation.signal;
    signal.throwIfAborted();
    let abort: (() => void) | undefined;
    try {
      // Cancel the wait, not dynamic import or WASM initialization. Promise.race
      // consumes late rejection; a late module never reaches acquire below.
      return await Promise.race([
        this.#load(codecUrl),
        new Promise<never>((_resolve, reject) => {
          abort = () =>
            reject(new DOMException('Image decode cancelled', 'AbortError'));
          signal.addEventListener('abort', abort, { once: true });
          if (signal.aborted) abort();
        }),
      ]);
    } finally {
      if (abort) signal.removeEventListener('abort', abort);
    }
  }

  async *#run(): AsyncGenerator<ImageDecodeEvent, void, void> {
    this.#started = true;
    if (this.#terminal) {
      yield { kind: 'terminal', ...this.#terminal };
      return;
    }
    const terminal = emptyTerminal();
    let lease: ImageCodecLease | undefined;
    try {
      this.#checkCancellation();
      const { bytes, codecUrl, format } = this.#options;
      const denominator = this.#options.denominator ?? 1;
      z.instanceof(Uint8Array).parse(bytes);
      if (!bytes.byteLength || bytes.byteLength > IMAGE_CODEC_LIMITS.inputBytes)
        throw new Error('Encoded image must contain 1 through 8388608 bytes');
      if (!(bytes.buffer instanceof ArrayBuffer))
        throw new Error('Shared encoded image input is not supported');
      if (format !== 'png' && format !== 'jpeg')
        throw new Error('Unsupported image codec format');
      if (
        (denominator !== 1 && denominator !== 2 && denominator !== 4) ||
        (format === 'png' && denominator !== 1)
      )
        throw new Error('Unsupported image codec scale denominator');
      const codec = await this.#loadCodec(codecUrl);
      this.#checkCancellation();
      lease = codec.acquire();
      const api = lease.api;
      const pointer = api.image_input(bytes.byteLength);
      if (pointer <= 0) throw new Error('Image codec refused input allocation');
      lease.writeInput(pointer, bytes);
      const opened = api.image_open(
        bytes.byteLength,
        IMAGE_CODEC_LIMITS.stripRows,
        denominator,
      );
      if (opened !== 0) throw new Error('Image codec open failed: ' + opened);
      const sourceWidth = api.image_source_width();
      const sourceHeight = api.image_source_height();
      const width = api.image_width();
      const height = api.image_height();
      if (
        sourceWidth <= 0 ||
        sourceWidth > IMAGE_CODEC_LIMITS.sourceWidth ||
        sourceHeight <= 0 ||
        sourceHeight >
          (format === 'png'
            ? IMAGE_CODEC_LIMITS.pngHeight
            : IMAGE_CODEC_LIMITS.jpegHeight) ||
        width !== Math.ceil(sourceWidth / denominator) ||
        height !== Math.ceil(sourceHeight / denominator)
      )
        throw new Error('Invalid image codec source or output dimensions');
      const header: ImageHeader = {
        format,
        sourceWidth,
        sourceHeight,
        width,
        height,
        rowBytes: width * 4,
        denominator,
      };
      terminal.header = header;
      lease.metrics();
      this.#checkCancellation();
      yield { kind: 'header', ...header };
      let sequence = 0;
      while (true) {
        this.#checkCancellation();
        const count = api.image_next();
        if (count < 0) throw new Error('Image codec decode failed: ' + count);
        if (count === 0) {
          if (terminal.decodedRows !== height)
            throw new Error('Image codec completed before all output rows');
          terminal.status = 'complete';
          break;
        }
        if (
          count > IMAGE_CODEC_LIMITS.stripRows ||
          count > height - terminal.decodedRows ||
          api.image_strip_start() !== terminal.decodedRows
        )
          throw new Error('Invalid image codec strip bounds');
        lease.metrics();
        const stripStart = terminal.decodedRows;
        terminal.decodedRows += count;
        const stripBytes = count * header.rowBytes;
        const stripPointer = api.image_strip();
        for (
          let offset = 0;
          offset < stripBytes;
          offset += IMAGE_CODEC_LIMITS.chunkBytes
        ) {
          this.#checkCancellation();
          const length = Math.min(
            IMAGE_CODEC_LIMITS.chunkBytes,
            stripBytes - offset,
          );
          const chunk = lease.copy(stripPointer + offset, length);
          terminal.deliveredBytes += length;
          yield {
            kind: 'chunk',
            sequence: ++sequence,
            offset: stripStart * header.rowBytes + offset,
            stripStart,
            stripRows: count,
            bytes: chunk,
          };
        }
      }
    } catch (error) {
      terminal.status =
        this.#cancelled || this.#options.signal?.aborted
          ? 'cancelled'
          : 'failed';
      if (terminal.status === 'failed') terminal.error = describeError(error);
    } finally {
      if (lease) {
        try {
          const error = lease.error();
          terminal.decodeErrorCode = error.code;
          terminal.decodeErrorPhase = error.phase;
          if (terminal.status === 'complete' && error.code !== 0) {
            terminal.status = 'failed';
            terminal.error = {
              name: 'ImageCodecError',
              message: 'Image codec completed with an error: ' + error.code,
            };
          }
        } catch (error) {
          terminal.status = 'failed';
          terminal.error = describeError(error);
        }
        const cleanup: ImageCodecCleanup = lease.close();
        terminal.closeSucceeded = cleanup.succeeded;
        terminal.liveBytes = cleanup.liveBytes;
        terminal.allocations = cleanup.allocations;
        terminal.peakBytes = cleanup.peakBytes;
        terminal.heapBytes = cleanup.heapBytes;
        if (!cleanup.succeeded) {
          terminal.status = 'failed';
          terminal.error = {
            name: 'ImageCodecCleanupError',
            message: cleanup.error ?? 'Image codec cleanup failed',
          };
        }
      }
      this.#finish(terminal);
    }
    yield { kind: 'terminal', ...terminal };
  }
}

export function decodeImage(
  options: ImageDecodeOptions,
  dependencies: ImageDecodeDependencies = {},
): ImageDecodeSession {
  return new ImageDecodeSession(options, dependencies);
}
