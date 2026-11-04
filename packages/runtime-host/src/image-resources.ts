import {
  IMAGE_BODY_LIMIT,
  IMAGE_CHUNK_LIMIT,
  IMAGE_RESOURCE_LIMIT,
  imageFrameSchema,
  encodeImageFrame,
  processedImageSchema,
  type ImageResource,
  type ProcessedImage,
} from '@karuyomi/contracts';
import { RuntimeFailure, runtimeFailure } from './errors.js';
import { imageFailure } from './image-channel.js';

export interface ImageBudgets {
  maxBytes?: number;
  maxImageBytes?: number;
  maxResources?: number;
}

/** Source output is opaque encoded data. Image interpretation belongs to the UI. */
export class ImageResourceStore {
  private readonly images = new Map<string, ImageCollector>();
  private bytes = 0;
  readonly limits;

  constructor(budgets: ImageBudgets = {}) {
    this.limits = {
      maxBytes: budgets.maxBytes ?? IMAGE_BODY_LIMIT,
      maxImageBytes: budgets.maxImageBytes ?? IMAGE_BODY_LIMIT,
      maxResources: budgets.maxResources ?? IMAGE_RESOURCE_LIMIT,
    };
    if (
      Object.values(this.limits).some(
        (value) => !Number.isSafeInteger(value) || value < 1,
      ) ||
      this.limits.maxBytes > IMAGE_BODY_LIMIT ||
      this.limits.maxImageBytes > IMAGE_BODY_LIMIT ||
      this.limits.maxResources > IMAGE_RESOURCE_LIMIT
    )
      throw new Error('Invalid image byte budget');
  }

  get snapshot() {
    return { resources: this.images.size, bytes: this.bytes };
  }

  create(generation: string): ImageCollector {
    if (this.images.size >= this.limits.maxResources)
      throw new RuntimeFailure(
        'limit_exceeded',
        'Image resource window is full',
      );
    const collector = new ImageCollector(this, generation);
    this.images.set(collector.resourceId, collector);
    return collector;
  }

  reserve(bytes: number): void {
    if (bytes + this.bytes > this.limits.maxBytes)
      throw new RuntimeFailure(
        'limit_exceeded',
        'Image resources exceed the total byte budget',
      );
    this.bytes += bytes;
  }

  forget(image: ImageCollector): void {
    if (this.images.get(image.resourceId) !== image) return;
    this.images.delete(image.resourceId);
    this.bytes -= image.byteLength;
  }

  release(resourceId: string, generation: string): void {
    const image = this.images.get(resourceId);
    if (image?.generation === generation) image.release();
  }

  clear(error: RuntimeFailure): void {
    for (const image of [...this.images.values()]) image.release(error);
  }
}

export class ImageCollector {
  readonly resourceId = crypto.randomUUID();
  readonly result: Promise<ProcessedImage>;
  byteLength = 0;
  private resolve!: (value: ProcessedImage) => void;
  private reject!: (error: unknown) => void;
  private port: MessagePort | undefined;
  private parts: ArrayBuffer[] = [];
  private opened = false;
  private next = 0;
  private terminal = false;
  private released = false;
  private blob: Blob | undefined;
  private url: string | undefined;

  constructor(
    private readonly store: ImageResourceStore,
    readonly generation: string,
  ) {
    this.result = new Promise((resolve, reject) => {
      this.resolve = resolve;
      this.reject = reject;
    });
    void this.result.catch(() => {});
  }

  attach(port: MessagePort): void {
    if (this.port || this.released)
      throw new RuntimeFailure(
        'protocol_error',
        'Image receiver cannot be attached',
      );
    this.port = port;
    port.onmessage = (event) => this.receive(event.data);
    port.onmessageerror = () =>
      this.abort(
        new RuntimeFailure(
          'protocol_error',
          'Image message could not be decoded',
        ),
      );
  }

  private receive(input: unknown): void {
    if (this.released) return;
    const parsed = imageFrameSchema.safeParse(input);
    if (!parsed.success)
      return this.abort(
        new RuntimeFailure('protocol_error', 'Invalid image frame'),
      );
    const frame = parsed.data;
    if (frame.type === 'abort')
      return this.abort(imageFailure(frame.error), false);
    if (this.terminal || frame.seq !== this.next)
      return this.abort(
        new RuntimeFailure(
          'protocol_error',
          'Image frames must wait for their ACK',
        ),
      );
    try {
      let resource: ProcessedImage | undefined;
      if (frame.type === 'meta' && this.next === 0) this.opened = true;
      else if (frame.type === 'data' && this.opened) {
        const size = frame.buffer.byteLength;
        if (!size || size > IMAGE_CHUNK_LIMIT)
          throw new RuntimeFailure(
            'protocol_error',
            'Image chunk exceeds the frame budget',
          );
        if (size + this.byteLength > this.store.limits.maxImageBytes)
          throw new RuntimeFailure(
            'limit_exceeded',
            'Image exceeds its encoded byte budget',
          );
        this.store.reserve(size);
        this.byteLength += size;
        this.parts.push(frame.buffer);
      } else if (frame.type === 'end' && this.opened) {
        if (!this.byteLength || frame.totalBytes !== this.byteLength)
          throw new RuntimeFailure(
            'protocol_error',
            'Image END length mismatch',
          );
        this.terminal = true;
        this.blob = new Blob(this.parts);
        this.parts = [];
        resource = {
          resourceId: this.resourceId,
          generation: this.generation,
          byteLength: this.byteLength,
        };
      } else
        throw new RuntimeFailure('protocol_error', 'Unexpected image frame');
      this.next++;
      this.port?.postMessage(
        encodeImageFrame({
          type: 'ack',
          seq: frame.seq,
          ...(resource ? { resource } : {}),
        }),
      );
      if (resource) this.resolve(resource);
    } catch (error) {
      this.abort(runtimeFailure(error));
    }
  }

  async publish(javaResult: unknown): Promise<ImageResource> {
    const descriptor = await this.result;
    if (this.released || !this.blob)
      throw new RuntimeFailure('cancelled', 'Image resource was released');
    const parsed = processedImageSchema.safeParse(javaResult);
    if (
      !parsed.success ||
      parsed.data.resourceId !== descriptor.resourceId ||
      parsed.data.generation !== descriptor.generation ||
      parsed.data.byteLength !== descriptor.byteLength
    )
      throw new RuntimeFailure(
        'protocol_error',
        'Java result does not match the transferred image',
      );
    if (!this.url) {
      const url = URL.createObjectURL(this.blob);
      if (this.released) {
        URL.revokeObjectURL(url);
        throw new RuntimeFailure('cancelled', 'Image resource was released');
      }
      this.url = url;
    }
    this.port?.close();
    return { ...descriptor, url: this.url };
  }

  abort(error: RuntimeFailure, notify = true): void {
    if (this.released) return;
    if (notify)
      this.port?.postMessage(
        encodeImageFrame({ type: 'abort', error: error.toJSON() }),
      );
    this.drop(error);
    // Keep the channel until Java unwinds so cancellation still reaches its sink.
  }

  release(
    error = new RuntimeFailure('cancelled', 'Image resource was released'),
  ): void {
    if (!this.released) {
      this.port?.postMessage(
        encodeImageFrame({ type: 'abort', error: error.toJSON() }),
      );
      this.drop(error);
    }
    this.port?.close();
  }

  private drop(error: RuntimeFailure): void {
    if (this.released) return;
    this.released = true;
    this.store.forget(this);
    this.parts = [];
    this.blob = undefined;
    if (this.url) URL.revokeObjectURL(this.url);
    this.url = undefined;
    this.reject(error);
  }
}
