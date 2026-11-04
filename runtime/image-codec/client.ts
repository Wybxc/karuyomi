import {
  CODEC_WORKER_LIMITS,
  codecStartSchema,
  codecResponseSchema,
  type CodecModule,
  type CodecRequest,
  type ImageTileMetadata,
  type ImageTileTerminal,
} from './worker-protocol.ts';
import type { ImageHeader } from './decoder.ts';

export interface CodecWorkerEndpoint {
  onmessage: ((event: MessageEvent<unknown>) => void) | null;
  onerror: ((event: ErrorEvent) => void) | null;
  onmessageerror: ((event: MessageEvent<unknown>) => void) | null;
  postMessage(message: CodecRequest, transfer: ArrayBuffer[]): void;
  terminate(): void;
}
export interface ImageTileOptions {
  workerUrl: URL;
  blob: Blob;
  format: 'png' | 'jpeg';
  decoder: CodecModule;
  encoder: CodecModule;
  requestId: string;
  generation: string;
  denominator?: 1 | 2 | 4;
  signal?: AbortSignal;
  timeoutMs?: number;
  cancelGraceMs?: number;
}
export interface ImageTileDependencies {
  createWorker?: (url: URL) => CodecWorkerEndpoint;
  /** Called after Worker termination; the host owns/revokes verified module URLs. */
  releaseModules?: () => void;
}
export type ImageTileEvent =
  | ({ kind: 'header' } & ImageHeader)
  | ({ kind: 'tile'; png: Blob } & ImageTileMetadata)
  | ({ kind: 'terminal' } & ImageTileTerminal);
const describe = (error: unknown) =>
  error instanceof Error
    ? { name: error.name, message: error.message }
    : { name: 'Error', message: String(error) };
function stopped(
  status: 'cancelled' | 'failed',
  forced: boolean,
  error?: unknown,
): ImageTileTerminal {
  return {
    status,
    invalidatesTiles: true,
    decoder: null,
    encoder: null,
    error: status === 'failed' ? describe(error) : null,
    forced,
  };
}

/** One consumer, one PNG strip in flight. Delivered strips are provisional until completion. */
export class ImageTileSession implements AsyncIterable<ImageTileEvent> {
  readonly completion: Promise<ImageTileTerminal>;
  readonly #options: ImageTileOptions;
  readonly #dependencies: ImageTileDependencies;
  readonly #resolve: (terminal: ImageTileTerminal) => void;
  #worker: CodecWorkerEndpoint | undefined;
  #started = false;
  #iterated = false;
  #done = false;
  #pending = false;
  #waiting: ((event: ImageTileEvent) => void) | undefined;
  #queued: ImageTileEvent | undefined;
  #header: ImageHeader | undefined;
  #canPull = false;
  #pulling = false;
  #nextTile = 0;
  #nextRow = 0;
  #sequence = 0;
  #assembly:
    | { tile: ImageTileMetadata; parts: ArrayBuffer[]; received: number }
    | undefined;
  #terminal: ImageTileTerminal | undefined;
  #stopping: { status: 'cancelled' | 'failed'; error?: unknown } | undefined;
  #deadline: ReturnType<typeof setTimeout> | undefined;
  #grace: ReturnType<typeof setTimeout> | undefined;
  readonly #abort = () => {
    void this.cancel();
  };

  constructor(
    options: ImageTileOptions,
    dependencies: ImageTileDependencies = {},
  ) {
    this.#options = options;
    this.#dependencies = dependencies;
    const callbacks: { resolve?: (terminal: ImageTileTerminal) => void } = {};
    this.completion = new Promise((resolve) => {
      callbacks.resolve = resolve;
    });
    if (!callbacks.resolve)
      throw new Error('Cannot initialize codec tile completion');
    this.#resolve = callbacks.resolve;
    if (options.signal?.aborted) void this.cancel();
    else options.signal?.addEventListener('abort', this.#abort, { once: true });
  }
  [Symbol.asyncIterator](): AsyncIterator<ImageTileEvent, void, void> {
    if (this.#iterated)
      throw new Error('Codec tile session already has a consumer');
    this.#iterated = true;
    return {
      next: async () => {
        if (this.#pending)
          throw new Error('Concurrent codec tile next is invalid');
        if (this.#done) return { done: true, value: undefined };
        this.#pending = true;
        try {
          let event = this.#queued;
          this.#queued = undefined;
          if (!event) {
            const pending = new Promise<ImageTileEvent>((resolve) => {
              this.#waiting = resolve;
            });
            if (!this.#started) this.#start();
            else if (this.#canPull && !this.#stopping) {
              this.#canPull = false;
              this.#pulling = true;
              this.#post({ ...this.#identity(), type: 'pull' });
            }
            event = await pending;
          }
          if (event.kind === 'terminal') this.#done = true;
          return { done: false, value: event };
        } finally {
          this.#pending = false;
        }
      },
      return: async () => {
        await this.cancel();
        this.#done = true;
        return { done: true, value: undefined };
      },
    };
  }
  async cancel(): Promise<void> {
    this.#stop('cancelled');
    await this.completion;
  }
  #identity() {
    return {
      version: 1 as const,
      requestId: this.#options.requestId,
      generation: this.#options.generation,
    };
  }
  #start() {
    this.#started = true;
    try {
      const options = this.#options;
      const timeout = options.timeoutMs ?? CODEC_WORKER_LIMITS.timeoutMs;
      const grace = options.cancelGraceMs ?? CODEC_WORKER_LIMITS.cancelGraceMs;
      if (
        options.workerUrl.protocol !== 'blob:' ||
        !Number.isSafeInteger(timeout) ||
        timeout < 1 ||
        timeout > 300000 ||
        !Number.isSafeInteger(grace) ||
        grace < 1 ||
        grace > 30000
      )
        throw new Error('Invalid codec Worker URL or timeout');
      if (
        !options.blob.size ||
        options.blob.size > CODEC_WORKER_LIMITS.inputBytes
      )
        throw new Error('Encoded Blob exceeds the 8 MiB codec input budget');
      const request = codecStartSchema.parse({
        ...this.#identity(),
        type: 'start',
        blob: options.blob,
        format: options.format,
        denominator: options.denominator ?? 1,
        decoder: options.decoder,
        encoder: options.encoder,
      });
      const decoderBuffer = request.decoder.wasmBinary.buffer;
      const encoderBuffer = request.encoder.wasmBinary.buffer;
      if (
        !(decoderBuffer instanceof ArrayBuffer) ||
        !(encoderBuffer instanceof ArrayBuffer)
      )
        throw new Error('Shared codec WASM is not supported');
      const worker = (
        this.#dependencies.createWorker ??
        ((url) => new Worker(url, { type: 'module' }))
      )(options.workerUrl);
      this.#worker = worker;
      worker.onmessage = (event) => this.#receive(event.data);
      worker.onmessageerror = () =>
        this.#finish(
          stopped(
            'failed',
            true,
            new Error('Codec Worker message could not be decoded'),
          ),
        );
      worker.onerror = (event) =>
        this.#finish(
          stopped(
            'failed',
            true,
            new Error(event.message || 'Codec Worker failed'),
          ),
        );
      this.#deadline = setTimeout(
        () => this.#stop('failed', new Error('Codec tile session timed out')),
        timeout,
      );
      worker.postMessage(
        request,
        decoderBuffer === encoderBuffer
          ? [decoderBuffer]
          : [decoderBuffer, encoderBuffer],
      );
    } catch (error) {
      this.#finish(stopped('failed', this.#worker !== undefined, error));
    }
  }
  #post(message: CodecRequest) {
    try {
      this.#worker?.postMessage(message, []);
    } catch (error) {
      this.#finish(stopped('failed', true, error));
    }
  }
  #emit(event: ImageTileEvent) {
    if (this.#waiting) {
      const resolve = this.#waiting;
      this.#waiting = undefined;
      resolve(event);
    } else this.#queued = event;
  }
  #receive(input: unknown) {
    if (this.#terminal) return;
    const parsed = codecResponseSchema.safeParse(input);
    if (!parsed.success) {
      this.#finish(
        stopped('failed', true, new Error('Invalid codec Worker response')),
      );
      return;
    }
    const response = parsed.data;
    if (
      response.requestId !== this.#options.requestId ||
      response.generation !== this.#options.generation
    )
      return;
    if (this.#stopping && response.type !== 'terminal') return;
    try {
      if (response.type === 'terminal') {
        if (response.terminal.forced)
          throw new Error('Worker cannot attest forced termination');
        if (
          response.terminal.status === 'complete' &&
          (!this.#header ||
            this.#assembly ||
            this.#nextRow !== this.#header.height ||
            response.terminal.decoder?.status !== 'complete' ||
            !response.terminal.decoder.closeSucceeded ||
            response.terminal.decoder.liveBytes !== 0 ||
            response.terminal.decoder.allocations !== 0 ||
            !response.terminal.encoder?.succeeded ||
            response.terminal.encoder.liveBytes !== 0 ||
            response.terminal.encoder.allocations !== 0)
        )
          throw new Error('Incomplete codec tile success');
        const terminal =
          this.#stopping && response.terminal.status !== 'failed'
            ? {
                ...response.terminal,
                status: this.#stopping.status,
                invalidatesTiles: true,
                error:
                  this.#stopping.status === 'failed'
                    ? describe(this.#stopping.error)
                    : null,
              }
            : response.terminal;
        this.#finish(terminal);
      } else if (response.type === 'header') {
        const header = response.header;
        if (
          this.#header ||
          header.format !== this.#options.format ||
          header.denominator !== (this.#options.denominator ?? 1) ||
          header.width !== Math.ceil(header.sourceWidth / header.denominator) ||
          header.height !==
            Math.ceil(header.sourceHeight / header.denominator) ||
          header.rowBytes !== header.width * 4
        )
          throw new Error('Invalid codec image header');
        this.#header = header;
        this.#canPull = true;
        this.#emit({ kind: 'header', ...header });
      } else if (response.type === 'tile-start') {
        const header = this.#header;
        const tile = response.tile;
        if (
          !header ||
          !this.#pulling ||
          this.#assembly ||
          tile.index !== this.#nextTile ||
          tile.id !== `${this.#options.requestId}:${tile.index}` ||
          tile.y !== this.#nextRow ||
          tile.width !== header.width ||
          tile.height > header.height - tile.y ||
          tile.sourceRect.y !== tile.y * header.denominator ||
          tile.sourceRect.width !== header.sourceWidth ||
          tile.sourceRect.height !==
            Math.min(
              tile.height * header.denominator,
              header.sourceHeight - tile.sourceRect.y,
            )
        )
          throw new Error('Invalid codec tile geometry');
        this.#assembly = { tile, parts: [], received: 0 };
      } else if (response.type === 'data') {
        const assembly = this.#assembly;
        if (
          !assembly ||
          response.seq !== this.#sequence + 1 ||
          response.buffer.byteLength >
            assembly.tile.byteLength - assembly.received
        )
          throw new Error('Invalid codec PNG data sequence');
        this.#sequence = response.seq;
        assembly.parts.push(response.buffer);
        assembly.received += response.buffer.byteLength;
        this.#post({ ...this.#identity(), type: 'ack', seq: response.seq });
      } else {
        const assembly = this.#assembly;
        if (
          !assembly ||
          response.index !== assembly.tile.index ||
          assembly.received !== assembly.tile.byteLength
        )
          throw new Error('Incomplete codec PNG tile');
        this.#assembly = undefined;
        this.#nextTile++;
        this.#nextRow += assembly.tile.height;
        this.#pulling = false;
        this.#canPull = true;
        this.#emit({
          kind: 'tile',
          ...assembly.tile,
          png: new Blob(assembly.parts, { type: 'image/png' }),
        });
      }
    } catch (error) {
      this.#finish(stopped('failed', true, error));
    }
  }
  #stop(status: 'cancelled' | 'failed', error?: unknown) {
    if (this.#terminal || this.#stopping) return;
    if (!this.#worker) {
      this.#finish(stopped(status, false, error));
      return;
    }
    this.#stopping = { status, error };
    this.#queued = undefined;
    this.#assembly = undefined;
    this.#canPull = false;
    this.#grace = setTimeout(
      () => this.#finish(stopped(status, true, error)),
      this.#options.cancelGraceMs ?? CODEC_WORKER_LIMITS.cancelGraceMs,
    );
    this.#post({ ...this.#identity(), type: 'cancel' });
  }
  #finish(terminal: ImageTileTerminal) {
    if (this.#terminal) return;
    if (this.#deadline !== undefined) clearTimeout(this.#deadline);
    if (this.#grace !== undefined) clearTimeout(this.#grace);
    this.#options.signal?.removeEventListener('abort', this.#abort);
    const worker = this.#worker;
    this.#worker = undefined;
    if (worker) {
      worker.onmessage = worker.onerror = worker.onmessageerror = null;
      worker.terminate();
    }
    try {
      this.#dependencies.releaseModules?.();
    } catch (error) {
      terminal = {
        ...terminal,
        status: 'failed',
        invalidatesTiles: true,
        error: describe(error),
      };
    }
    this.#terminal = terminal;
    this.#assembly = undefined;
    this.#queued = undefined;
    this.#emit({ kind: 'terminal', ...terminal });
    this.#resolve(terminal);
  }
}
export function decodeImageTiles(
  options: ImageTileOptions,
  dependencies: ImageTileDependencies = {},
): ImageTileSession {
  return new ImageTileSession(options, dependencies);
}
