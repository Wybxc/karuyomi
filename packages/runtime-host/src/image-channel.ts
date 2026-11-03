import {
  IMAGE_CHUNK_LIMIT,
  imageFrameSchema,
  encodeImageFrame,
  type RuntimeErrorData,
  type ImageFrame,
  type ProcessedImage,
} from '@karuyomi/contracts';
import { RuntimeFailure } from './errors.js';

export function imageFailure(input: RuntimeErrorData): RuntimeFailure {
  return new RuntimeFailure(
    input.code,
    input.message,
    input.retryable,
    input.javaClass,
  );
}

/** Worker producer: one transferred chunk and one ACK outstanding at most. */
export class ImageSink {
  private handle: string | undefined;
  private sequence = 0;
  private total = 0;
  private failure: RuntimeFailure | undefined;
  private pending:
    | {
        seq: number;
        resolve(value: ProcessedImage | undefined): void;
        reject(error: unknown): void;
      }
    | undefined;
  private opened: Promise<ProcessedImage | undefined> | undefined;
  private writing = false;
  private finished = false;
  private readonly writer: WritableStreamDefaultWriter<Uint8Array>;

  constructor(
    private readonly port: MessagePort,
    private readonly resourceId: string,
    private readonly cancelled: (error: RuntimeFailure) => void,
  ) {
    port.onmessage = (event) => {
      const parsed = imageFrameSchema.safeParse(event.data);
      if (!parsed.success)
        return this.abort(
          new RuntimeFailure('protocol_error', 'Invalid image acknowledgement'),
        );
      const message = parsed.data;
      if (message.type === 'abort') {
        const error = imageFailure(message.error);
        this.abort(error, false);
        this.cancelled(error);
      } else if (message.type === 'ack' && this.pending?.seq === message.seq) {
        const pending = this.pending;
        this.pending = undefined;
        pending.resolve(message.resource);
      } else
        this.abort(
          new RuntimeFailure(
            'protocol_error',
            'Unexpected image acknowledgement',
          ),
        );
    };
    port.onmessageerror = () =>
      this.abort(
        new RuntimeFailure(
          'protocol_error',
          'Image message could not be decoded',
        ),
      );
    this.writer = new WritableStream<Uint8Array>(
      {
        write: async (bytes) => {
          const copy = new Uint8Array(bytes);
          await this.exchange(
            { type: 'data', seq: ++this.sequence, buffer: copy.buffer },
            [copy.buffer],
          );
          this.total += bytes.byteLength;
        },
      },
      { highWaterMark: 1 },
    ).getWriter();
  }

  open(mimeType: string): string {
    if (this.handle || this.finished || this.failure)
      throw (
        this.failure ??
        new RuntimeFailure('protocol_error', 'Image sink was already opened')
      );
    if (typeof mimeType !== 'string' || mimeType.length > 128)
      throw new RuntimeFailure('protocol_error', 'Invalid image MIME metadata');
    this.handle = this.resourceId;
    this.opened = this.exchange({ type: 'meta', seq: 0, mimeType });
    void this.opened.catch(() => {});
    return this.handle;
  }

  async write(handle: string, bytes: Uint8Array): Promise<void> {
    this.check(handle);
    if (
      !(bytes instanceof Uint8Array) ||
      !bytes.byteLength ||
      bytes.byteLength > IMAGE_CHUNK_LIMIT ||
      this.writing
    )
      throw new RuntimeFailure(
        'protocol_error',
        'Invalid or concurrent image write',
      );
    this.writing = true;
    try {
      await this.opened;
      this.check(handle);
      await this.writer.write(bytes);
    } finally {
      this.writing = false;
    }
  }

  async close(handle: string): Promise<string> {
    this.check(handle);
    if (this.writing)
      throw new RuntimeFailure(
        'protocol_error',
        'Image write is still pending',
      );
    await this.opened;
    this.check(handle);
    this.finished = true;
    await this.writer.close();
    const resource = await this.exchange({
      type: 'end',
      seq: ++this.sequence,
      totalBytes: this.total,
    });
    if (
      !resource ||
      resource.resourceId !== this.resourceId ||
      resource.byteLength !== this.total
    )
      throw new RuntimeFailure(
        'protocol_error',
        'Invalid final image acknowledgement',
      );
    return JSON.stringify(resource);
  }

  abort(error: RuntimeFailure, notify = true): void {
    if (this.failure) return;
    this.failure = error;
    this.pending?.reject(error);
    this.pending = undefined;
    if (notify)
      this.port.postMessage(
        encodeImageFrame({ type: 'abort', error: error.toJSON() }),
      );
    void this.writer.abort(error).catch(() => {});
  }

  dispose(): void {
    this.port.close();
  }

  cancel(handle: string): void {
    if (handle === this.handle)
      this.abort(
        new RuntimeFailure('source_error', 'Image production did not complete'),
      );
  }

  private check(handle: string): void {
    if (this.failure) throw this.failure;
    if (!this.handle || handle !== this.handle || this.finished)
      throw new RuntimeFailure(
        'protocol_error',
        'Image handle expired or does not belong to this operation',
      );
  }

  private exchange(
    frame: ImageFrame,
    transfer: Transferable[] = [],
  ): Promise<ProcessedImage | undefined> {
    if (this.failure) return Promise.reject(this.failure);
    if (this.pending)
      return Promise.reject(
        new RuntimeFailure('protocol_error', 'Image ACK is still pending'),
      );
    return new Promise((resolve, reject) => {
      this.pending = {
        seq: frame.type === 'abort' ? -1 : frame.seq,
        resolve,
        reject,
      };
      try {
        this.port.postMessage(encodeImageFrame(frame), transfer);
      } catch {
        this.abort(
          new RuntimeFailure('runtime_lost', 'Image channel delivery failed'),
          false,
        );
      }
    });
  }
}
