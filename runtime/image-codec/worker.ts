import { loadImageCodec, type ImageCodecCleanup } from './codec-api.ts';
import {
  decodeImage,
  type ImageDecodeSession,
  type ImageHeader,
} from './decoder.ts';
import { loadPngEncoder, type PngEncoder } from './encoder.ts';
import {
  CODEC_WORKER_LIMITS,
  codecRequestSchema,
  codecResponseSchema,
  type CodecResponse,
  type CodecStart,
  type ImageTileTerminal,
} from './worker-protocol.ts';
type ResponseBody<Value = CodecResponse> = Value extends CodecResponse
  ? Omit<Value, 'version' | 'requestId' | 'generation'>
  : never;

export interface CodecWorkerDependencies {
  loadDecoder?: typeof loadImageCodec;
  loadEncoder?: typeof loadPngEncoder;
  ackTimeoutMs?: number;
}
interface Job {
  request: CodecStart;
  controller: AbortController;
  encoder?: PngEncoder;
  encoderCleanup: ImageCodecCleanup | null;
  session?: ImageDecodeSession;
  iterator?: AsyncIterator<import('./decoder.ts').ImageDecodeEvent, void, void>;
  header?: ImageHeader;
  initialized: boolean;
  pulling: boolean;
  queuedPull: boolean;
  tileIndex: number;
  sequence: number;
  ack?: { seq: number; resolve(): void; reject(error: unknown): void };
  finishing?: Promise<void>;
}

async function cancellable<Value>(
  pending: Promise<Value>,
  signal: AbortSignal,
): Promise<Value> {
  let abort: (() => void) | undefined;
  try {
    return await Promise.race([
      pending,
      new Promise<never>((_resolve, reject) => {
        abort = () =>
          reject(
            new DOMException('Codec Worker operation cancelled', 'AbortError'),
          );
        signal.addEventListener('abort', abort, { once: true });
        if (signal.aborted) abort();
      }),
    ]);
  } finally {
    if (abort) signal.removeEventListener('abort', abort);
  }
}
const describe = (error: unknown) =>
  error instanceof Error
    ? { name: error.name, message: error.message }
    : { name: 'Error', message: String(error) };

/** Dedicated to one decode job; never owns or terminates a Source Worker. */
export class CodecWorkerRuntime {
  #job: Job | undefined;
  readonly send: (message: CodecResponse, transfer: ArrayBuffer[]) => void;
  readonly dependencies: CodecWorkerDependencies;
  constructor(
    send: (message: CodecResponse, transfer: ArrayBuffer[]) => void,
    dependencies: CodecWorkerDependencies = {},
  ) {
    this.send = send;
    this.dependencies = dependencies;
  }

  receive(input: unknown): void {
    const parsed = codecRequestSchema.safeParse(input);
    if (!parsed.success) {
      if (this.#job)
        void this.#finish(
          this.#job,
          'failed',
          new Error('Invalid codec Worker request'),
        );
      return;
    }
    const request = parsed.data;
    if (request.type === 'start') {
      if (this.#job) {
        void this.#finish(
          this.#job,
          'failed',
          new Error('Codec Worker already has an active job'),
        );
        return;
      }
      const job: Job = {
        request,
        controller: new AbortController(),
        encoderCleanup: null,
        initialized: false,
        pulling: false,
        queuedPull: false,
        tileIndex: 0,
        sequence: 0,
      };
      this.#job = job;
      void this.#initialize(job).catch((error) =>
        this.#finish(
          job,
          job.controller.signal.aborted ? 'cancelled' : 'failed',
          error,
        ),
      );
      return;
    }
    const job = this.#job;
    if (
      !job ||
      request.requestId !== job.request.requestId ||
      request.generation !== job.request.generation ||
      job.finishing
    )
      return;
    if (request.type === 'cancel') {
      void this.#finish(job, 'cancelled');
      return;
    }
    if (request.type === 'ack') {
      if (!job.ack || job.ack.seq !== request.seq) {
        void this.#finish(
          job,
          'failed',
          new Error('Unexpected codec DATA acknowledgement'),
        );
        return;
      }
      const ack = job.ack;
      delete job.ack;
      ack.resolve();
      return;
    }
    if (job.pulling || job.queuedPull) {
      void this.#finish(
        job,
        'failed',
        new Error('Only one codec tile pull may be outstanding'),
      );
      return;
    }
    job.queuedPull = true;
    if (job.initialized) void this.#pull(job);
  }

  async dispose(): Promise<void> {
    if (this.#job) await this.#finish(this.#job, 'cancelled');
  }

  #post(job: Job, response: ResponseBody, transfer: ArrayBuffer[] = []) {
    // Each concrete response is checked at the receiving boundary. This helper
    // adds identity without turning unknown module values into asserted types.
    const envelope = {
      version: 1,
      requestId: job.request.requestId,
      generation: job.request.generation,
    };
    const parsed = codecResponseSchema.parse({ ...envelope, ...response });
    this.send(parsed, transfer);
  }

  async #initialize(job: Job): Promise<void> {
    const { request, controller } = job;
    if (
      !request.blob.size ||
      request.blob.size > CODEC_WORKER_LIMITS.inputBytes
    )
      throw new Error('Encoded Blob exceeds the 8 MiB codec input budget');
    if (request.format === 'png' && request.denominator !== 1)
      throw new Error('PNG scaling is not supported');
    const bytes = new Uint8Array(
      await cancellable(request.blob.arrayBuffer(), controller.signal),
    );
    controller.signal.throwIfAborted();
    job.encoder = await cancellable(
      (this.dependencies.loadEncoder ?? loadPngEncoder)(
        new URL(request.encoder.moduleUrl),
        { wasmBinary: request.encoder.wasmBinary },
      ),
      controller.signal,
    );
    controller.signal.throwIfAborted();
    job.session = decodeImage(
      {
        bytes,
        codecUrl: new URL(request.decoder.moduleUrl),
        format: request.format,
        denominator: request.denominator,
        signal: controller.signal,
      },
      {
        loadCodec: (url) =>
          (this.dependencies.loadDecoder ?? loadImageCodec)(url, {
            wasmBinary: request.decoder.wasmBinary,
          }),
      },
    );
    job.iterator = job.session[Symbol.asyncIterator]();
    const first = await job.iterator.next();
    if (first.value?.kind !== 'header') {
      const terminal = await job.session.completion;
      throw new Error(
        terminal.error?.message ?? 'Codec did not produce an image header',
      );
    }
    controller.signal.throwIfAborted();
    const { kind: _kind, ...header } = first.value;
    job.header = header;
    job.initialized = true;
    this.#post(job, { type: 'header', header });
    if (job.queuedPull) await this.#pull(job);
  }

  async #pull(job: Job): Promise<void> {
    if (
      job.finishing ||
      !job.queuedPull ||
      !job.iterator ||
      !job.header ||
      !job.encoder
    )
      return;
    job.queuedPull = false;
    job.pulling = true;
    try {
      const { header, iterator } = job;
      const first = await iterator.next();
      job.controller.signal.throwIfAborted();
      if (first.value?.kind === 'terminal') {
        await this.#finish(
          job,
          first.value.status,
          first.value.error ? new Error(first.value.error.message) : undefined,
        );
        return;
      }
      if (first.value?.kind !== 'chunk')
        throw new Error('Codec ended without a terminal');
      const start = first.value.stripStart;
      const rows = first.value.stripRows;
      const length = rows * header.rowBytes;
      if (length > CODEC_WORKER_LIMITS.stripBytes)
        throw new Error('RGBA strip exceeds its assembly budget');
      const rgba = new Uint8Array(length);
      let received = 0;
      let chunk = first.value;
      while (true) {
        if (
          chunk.stripStart !== start ||
          chunk.stripRows !== rows ||
          chunk.offset !== start * header.rowBytes + received ||
          chunk.bytes.length > length - received
        )
          throw new Error('Invalid RGBA strip sequence');
        rgba.set(chunk.bytes, received);
        received += chunk.bytes.length;
        if (received === length) break;
        const next = await iterator.next();
        job.controller.signal.throwIfAborted();
        if (next.value?.kind !== 'chunk')
          throw new Error('Codec ended inside a strip');
        chunk = next.value;
      }
      const lease = job.encoder.acquire();
      let png: Uint8Array<ArrayBuffer>;
      try {
        png = lease.encode(rgba, header.width, rows);
      } finally {
        const cleanup = lease.close();
        job.encoderCleanup = {
          ...cleanup,
          peakBytes:
            cleanup.peakBytes === null
              ? null
              : Math.max(cleanup.peakBytes, job.encoderCleanup?.peakBytes ?? 0),
          heapBytes:
            cleanup.heapBytes === null
              ? null
              : Math.max(cleanup.heapBytes, job.encoderCleanup?.heapBytes ?? 0),
        };
        if (!cleanup.succeeded)
          throw new Error(cleanup.error ?? 'PNG encoder cleanup failed');
      }
      job.controller.signal.throwIfAborted();
      const index = job.tileIndex++;
      this.#post(job, {
        type: 'tile-start',
        tile: {
          id: `${job.request.requestId}:${index}`,
          index,
          x: 0,
          y: start,
          width: header.width,
          height: rows,
          sourceRect: {
            x: 0,
            y: start * header.denominator,
            width: header.sourceWidth,
            height: Math.min(
              rows * header.denominator,
              header.sourceHeight - start * header.denominator,
            ),
          },
          byteLength: png.length,
          mimeType: 'image/png',
          provisional: true,
        },
      });
      for (
        let offset = 0;
        offset < png.length;
        offset += CODEC_WORKER_LIMITS.chunkBytes
      ) {
        const buffer = png.slice(
          offset,
          offset + CODEC_WORKER_LIMITS.chunkBytes,
        ).buffer;
        await this.#data(job, buffer);
      }
      job.controller.signal.throwIfAborted();
      this.#post(job, { type: 'tile-end', index });
    } catch (error) {
      await this.#finish(
        job,
        job.controller.signal.aborted ? 'cancelled' : 'failed',
        error,
      );
    } finally {
      job.pulling = false;
    }
  }

  async #data(job: Job, buffer: ArrayBuffer): Promise<void> {
    const seq = ++job.sequence;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const acknowledged = new Promise<void>((resolve, reject) => {
      job.ack = { seq, resolve, reject };
      timer = setTimeout(
        () => reject(new Error('Codec DATA acknowledgement timed out')),
        this.dependencies.ackTimeoutMs ?? CODEC_WORKER_LIMITS.timeoutMs,
      );
    });
    try {
      job.controller.signal.throwIfAborted();
      this.#post(job, { type: 'data', seq, buffer }, [buffer]);
      await cancellable(acknowledged, job.controller.signal);
    } finally {
      if (timer !== undefined) clearTimeout(timer);
      delete job.ack;
    }
  }

  #finish(
    job: Job,
    status: ImageTileTerminal['status'],
    error?: unknown,
  ): Promise<void> {
    if (job.finishing) return job.finishing;
    job.finishing = this.#close(job, status, error);
    return job.finishing;
  }
  async #close(
    job: Job,
    status: ImageTileTerminal['status'],
    error?: unknown,
  ): Promise<void> {
    if (status !== 'complete') job.controller.abort();
    job.ack?.reject(new DOMException('Codec job stopped', 'AbortError'));
    let terminal: ImageTileTerminal = {
      status,
      invalidatesTiles: status !== 'complete',
      decoder: null,
      encoder: job.encoderCleanup,
      error: status === 'failed' ? describe(error) : null,
      forced: false,
    };
    if (job.session) {
      if (status !== 'complete') await job.session.cancel();
      terminal.decoder = await job.session.completion;
      if (
        terminal.decoder.status === 'failed' ||
        (status === 'complete' &&
          (terminal.decoder.status !== 'complete' ||
            !terminal.decoder.closeSucceeded))
      ) {
        terminal = {
          ...terminal,
          status: 'failed',
          invalidatesTiles: true,
          error: terminal.decoder.error ?? {
            name: 'Error',
            message: 'Decoder did not close successfully',
          },
        };
      }
    }
    if (this.#job === job) this.#job = undefined;
    try {
      this.#post(job, { type: 'terminal', terminal });
    } catch {
      /* A disconnected parent has its own timeout and Worker termination. */
    }
  }
}

if (!('document' in globalThis) && typeof postMessage === 'function') {
  const runtime = new CodecWorkerRuntime((message, transfer) =>
    postMessage(message, { transfer }),
  );
  addEventListener('message', (event: MessageEvent<unknown>) =>
    runtime.receive(event.data),
  );
}
