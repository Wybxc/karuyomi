import {
  IMAGE_BODY_LIMIT,
  ENCODED_IMAGE_BODY_LIMIT,
  ENCODED_IMAGE_WIDTH_LIMIT,
  ENCODED_IMAGE_HEIGHT_LIMIT,
  ENCODED_JPEG_HEIGHT_LIMIT,
  IMAGE_CHUNK_LIMIT,
  IMAGE_HEADER_LIMIT,
  IMAGE_PIXEL_LIMIT,
  IMAGE_RESIDENT_PIXEL_LIMIT,
  IMAGE_RESOURCE_LIMIT,
  imageFrameSchema,
  encodeImageFrame,
  imageMimeTypeSchema,
  processedImageSchema,
  type ImageResource,
  type ProcessedImage,
  encodedImageSchema,
  type EncodedImage,
} from '@karuyomi/contracts';
import { imageDimensionsFromData } from 'image-dimensions';
import { orientation } from 'exifr';
import { RuntimeFailure, runtimeFailure } from './errors.js';
import { imageFailure } from './image-channel.js';

type Decoder = (
  blob: Blob,
) => Promise<{ width: number; height: number; close(): void }>;
export interface ImageBudgets {
  maxBytes?: number;
  maxImageBytes?: number;
  maxPixels?: number;
  maxResidentPixels?: number;
  maxResources?: number;
  decode?: Decoder;
  orientation?: (bytes: Uint8Array) => Promise<number | undefined>;
}

export interface EncodedImageLease {
  readonly descriptor: EncodedImage;
  readonly blob: Blob;
  release(): void;
}

/** Main-page ownership, independent from the HTTP operation's lifetime. */
export class ImageResourceStore {
  private readonly images = new Map<string, ImageCollector>();
  private bytes = 0;
  private pixels = 0;
  readonly limits;

  constructor(budgets: ImageBudgets = {}) {
    this.limits = {
      maxBytes: budgets.maxBytes ?? IMAGE_BODY_LIMIT,
      maxImageBytes: budgets.maxImageBytes ?? IMAGE_BODY_LIMIT,
      maxPixels: budgets.maxPixels ?? IMAGE_PIXEL_LIMIT,
      maxResidentPixels:
        budgets.maxResidentPixels ?? IMAGE_RESIDENT_PIXEL_LIMIT,
      maxResources: budgets.maxResources ?? IMAGE_RESOURCE_LIMIT,
      orientation: budgets.orientation ?? orientation,
      decode:
        budgets.decode ??
        ((blob: Blob) =>
          createImageBitmap(blob, { imageOrientation: 'from-image' })),
    };
    for (const value of [
      this.limits.maxBytes,
      this.limits.maxImageBytes,
      this.limits.maxPixels,
      this.limits.maxResidentPixels,
      this.limits.maxResources,
    ])
      if (!Number.isSafeInteger(value) || value < 1)
        throw new Error('Invalid image budget');
  }

  get snapshot() {
    return {
      resources: this.images.size,
      bytes: this.bytes,
      pixels: this.pixels,
    };
  }

  create(
    generation: string,
    options: { encodedOnly?: boolean } = {},
  ): ImageCollector {
    if (this.images.size >= this.limits.maxResources)
      throw new RuntimeFailure(
        'limit_exceeded',
        'Image resource window is full',
      );
    const collector = new ImageCollector(
      this,
      generation,
      options.encodedOnly ?? false,
    );
    this.images.set(collector.resourceId, collector);
    return collector;
  }

  borrowEncoded(resourceId: string, generation: string): EncodedImageLease {
    const image = this.images.get(resourceId);
    if (!image || image.generation !== generation)
      throw new RuntimeFailure(
        'runtime_lost',
        'Encoded image resource expired',
      );
    return image.borrowEncoded();
  }

  reserve(bytes: number, pixels = 0): void {
    if (
      bytes + this.bytes > this.limits.maxBytes ||
      pixels + this.pixels > this.limits.maxResidentPixels
    )
      throw new RuntimeFailure(
        'limit_exceeded',
        'Image resources exceed the total budget',
      );
    this.bytes += bytes;
    this.pixels += pixels;
  }

  forget(image: ImageCollector): void {
    if (this.images.get(image.resourceId) !== image) return;
    this.images.delete(image.resourceId);
    this.bytes -= image.byteLength;
    this.pixels -= image.pixelCount;
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
  readonly result: Promise<ProcessedImage | EncodedImage>;
  byteLength = 0;
  pixelCount = 0;
  private resolve!: (value: ProcessedImage | EncodedImage) => void;
  private reject!: (error: unknown) => void;
  private port: MessagePort | undefined;
  private parts: ArrayBuffer[] = [];
  private mimeType: string | undefined;
  private next = 0;
  private receiving = false;
  private terminal = false;
  private released = false;
  private sealing = false;
  private blob: Blob | undefined;
  private url: string | undefined;
  private publishedEncoded: EncodedImage | undefined;
  private borrowers = 0;

  constructor(
    private readonly store: ImageResourceStore,
    readonly generation: string,
    readonly encodedOnly = false,
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
    port.onmessage = (event) => {
      void this.receive(event.data);
    };
    port.onmessageerror = () =>
      this.abort(
        new RuntimeFailure(
          'protocol_error',
          'Image message could not be decoded',
        ),
      );
  }

  private async receive(input: unknown): Promise<void> {
    if (this.released) return;
    const parsed = imageFrameSchema.safeParse(input);
    if (!parsed.success)
      return this.abort(
        new RuntimeFailure('protocol_error', 'Invalid image frame'),
      );
    const frame = parsed.data;
    if (frame.type === 'abort')
      return this.abort(imageFailure(frame.error), false);
    if (
      this.receiving ||
      this.terminal ||
      !('seq' in frame) ||
      frame.seq !== this.next
    )
      return this.abort(
        new RuntimeFailure(
          'protocol_error',
          'Image frames must wait for their ACK',
        ),
      );
    this.receiving = true;
    try {
      let resource: ProcessedImage | EncodedImage | undefined;
      if (frame.type === 'meta' && this.next === 0)
        this.mimeType = frame.mimeType.split(';')[0]?.trim().toLowerCase();
      else if (frame.type === 'data' && this.mimeType !== undefined) {
        const size = frame.buffer.byteLength;
        if (!size || size > IMAGE_CHUNK_LIMIT)
          throw new RuntimeFailure(
            'protocol_error',
            'Image chunk exceeds the frame budget',
          );
        if (
          size + this.byteLength >
          Math.min(
            this.store.limits.maxImageBytes,
            this.encodedOnly ? ENCODED_IMAGE_BODY_LIMIT : IMAGE_BODY_LIMIT,
          )
        )
          throw new RuntimeFailure(
            'limit_exceeded',
            'Image exceeds its encoded byte budget',
          );
        this.store.reserve(size);
        this.byteLength += size;
        this.parts.push(frame.buffer);
      } else if (frame.type === 'end' && this.mimeType !== undefined) {
        if (!this.byteLength || frame.totalBytes !== this.byteLength)
          throw new RuntimeFailure(
            'protocol_error',
            'Image END length mismatch',
          );
        this.terminal = true;
        this.sealing = true;
        try {
          resource = this.encodedOnly
            ? await this.sealEncoded()
            : await this.seal();
        } finally {
          this.sealing = false;
          if (this.released && !this.borrowers) this.store.forget(this);
        }
      } else
        throw new RuntimeFailure('protocol_error', 'Unexpected image frame');
      if (this.released) return;
      this.next++;
      this.port?.postMessage(
        encodeImageFrame({
          type: 'ack',
          seq: frame.seq,
          ...(resource
            ? this.encodedOnly
              ? { encoded: encodedImageSchema.parse(resource) }
              : { resource: processedImageSchema.parse(resource) }
            : {}),
        }),
      );
      if (resource) {
        this.resolve(resource);
      }
    } catch (error) {
      this.abort(runtimeFailure(error));
    } finally {
      this.receiving = false;
    }
  }

  private async sealEncoded(): Promise<EncodedImage> {
    const initial = new Blob(this.parts);
    this.parts = [];
    const header = new Uint8Array(
      await initial.slice(0, IMAGE_HEADER_LIMIT).arrayBuffer(),
    );
    if (this.released)
      throw new RuntimeFailure('cancelled', 'Encoded image was released');
    const raw = imageDimensionsFromData(header);
    if (!raw || (raw.type !== 'png' && raw.type !== 'jpeg'))
      throw new RuntimeFailure(
        'unsupported_capability',
        'Encoded pages require PNG or JPEG headers',
      );
    const mimeType = `image/${raw.type}`;
    this.checkMime(mimeType);
    if (
      !Number.isSafeInteger(raw.width) ||
      !Number.isSafeInteger(raw.height) ||
      raw.width < 1 ||
      raw.width > ENCODED_IMAGE_WIDTH_LIMIT ||
      raw.height < 1 ||
      raw.height >
        (raw.type === 'jpeg'
          ? ENCODED_JPEG_HEIGHT_LIMIT
          : ENCODED_IMAGE_HEIGHT_LIMIT)
    )
      throw new RuntimeFailure(
        'limit_exceeded',
        'Encoded page geometry exceeds its budget',
      );
    // Read metadata from the complete owned Blob: PNG eXIf may follow IDAT.
    // This receives bytes only; stream validity and raster allocation belong to the codec.
    const blob = initial.slice(0, initial.size, mimeType);
    const metadata = new Uint8Array(await blob.arrayBuffer());
    if (this.released)
      throw new RuntimeFailure('cancelled', 'Encoded image was released');
    const value = await this.store.limits.orientation(metadata);
    if (this.released)
      throw new RuntimeFailure('cancelled', 'Encoded image was released');
    const descriptor = encodedImageSchema.parse({
      resourceId: this.resourceId,
      generation: this.generation,
      mimeType,
      byteLength: this.byteLength,
      rawWidth: raw.width,
      rawHeight: raw.height,
      orientation: value ?? 1,
    });
    this.blob = blob;
    return descriptor;
  }

  private checkMime(mimeType: string): void {
    if (
      this.mimeType &&
      ![
        'application/octet-stream',
        'binary/octet-stream',
        mimeType,
        mimeType === 'image/jpeg' ? 'image/jpg' : '',
        mimeType === 'image/heic' ? 'image/heif' : '',
      ].includes(this.mimeType)
    )
      throw new RuntimeFailure(
        'protocol_error',
        'Image MIME does not match its content',
      );
  }

  private async seal(): Promise<ProcessedImage> {
    const initial = new Blob(this.parts);
    this.parts = [];
    const header = new Uint8Array(
      await initial.slice(0, IMAGE_HEADER_LIMIT).arrayBuffer(),
    );
    if (this.released)
      throw new RuntimeFailure('cancelled', 'Image resource was released');
    const raw = imageDimensionsFromData(header);
    if (
      !raw ||
      !Number.isSafeInteger(raw.width) ||
      !Number.isSafeInteger(raw.height)
    )
      throw new RuntimeFailure(
        'unsupported_capability',
        'Unsupported or invalid image headers',
      );
    const pixels = raw.width * raw.height;
    if (raw.width < 1 || raw.height < 1 || pixels > this.store.limits.maxPixels)
      throw new RuntimeFailure(
        'limit_exceeded',
        'Image exceeds its decoded pixel budget',
      );
    this.store.reserve(0, pixels);
    this.pixelCount = pixels;
    const mimeType = `image/${raw.type}`;
    const parsedMime = imageMimeTypeSchema.safeParse(mimeType);
    if (!parsedMime.success)
      throw new RuntimeFailure(
        'unsupported_capability',
        'Image format is not supported',
      );
    this.checkMime(parsedMime.data);
    this.blob = initial.slice(0, initial.size, parsedMime.data);
    // Header limits precede decoding. This temporary bitmap is always closed;
    // its dimensions include the browser's EXIF/irot handling, unlike raw headers.
    const bitmap = await this.store.limits.decode(this.blob);
    try {
      if (this.released)
        throw new RuntimeFailure('cancelled', 'Image resource was released');
      if (
        bitmap.width * bitmap.height !== pixels ||
        !(
          (bitmap.width === raw.width && bitmap.height === raw.height) ||
          (bitmap.width === raw.height && bitmap.height === raw.width)
        )
      )
        throw new RuntimeFailure(
          'protocol_error',
          'Decoded image dimensions differ from its headers',
        );
      return processedImageSchema.parse({
        resourceId: this.resourceId,
        generation: this.generation,
        mimeType: parsedMime.data,
        byteLength: this.byteLength,
        width: bitmap.width,
        height: bitmap.height,
      });
    } finally {
      bitmap.close();
    }
  }

  async publish(javaResult: unknown): Promise<ImageResource> {
    if (this.encodedOnly)
      throw new RuntimeFailure(
        'protocol_error',
        'Encoded pages need explicit publication',
      );
    const descriptor = processedImageSchema.parse(await this.result);
    if (this.released || !this.blob)
      throw new RuntimeFailure('cancelled', 'Image resource was released');
    const parsed = processedImageSchema.safeParse(javaResult);
    if (
      !parsed.success ||
      Object.entries(descriptor).some(
        ([key, value]) =>
          !Object.entries(parsed.data).some(
            ([other, candidate]) => key === other && value === candidate,
          ),
      )
    )
      throw new RuntimeFailure(
        'protocol_error',
        'Java result does not match the sealed image',
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

  async publishEncoded(javaResult: unknown): Promise<EncodedImage> {
    if (!this.encodedOnly)
      throw new RuntimeFailure(
        'protocol_error',
        'Image resource is not an encoded page',
      );
    const descriptor = encodedImageSchema.parse(await this.result);
    if (this.released || !this.blob)
      throw new RuntimeFailure('cancelled', 'Encoded image was released');
    const java = encodedImageSchema.safeParse(javaResult);
    if (
      !java.success ||
      Object.entries(descriptor).some(
        ([key, value]) =>
          !Object.entries(java.data).some(
            ([other, candidate]) => key === other && value === candidate,
          ),
      )
    )
      throw new RuntimeFailure(
        'protocol_error',
        'Java result does not match the sealed encoded image',
      );
    this.publishedEncoded = Object.freeze({ ...descriptor });
    this.port?.close();
    return { ...descriptor };
  }

  borrowEncoded(): EncodedImageLease {
    if (this.released || !this.publishedEncoded || !this.blob)
      throw new RuntimeFailure(
        'runtime_lost',
        'Encoded image is not published',
      );
    this.borrowers++;
    let released = false;
    return {
      descriptor: { ...this.publishedEncoded },
      blob: this.blob,
      release: () => {
        if (released) return;
        released = true;
        this.borrowers--;
        if (this.released && !this.sealing && !this.borrowers)
          this.store.forget(this);
      },
    };
  }

  abort(error: RuntimeFailure, notify = true): void {
    if (this.released) return;
    if (notify)
      this.port?.postMessage(
        encodeImageFrame({ type: 'abort', error: error.toJSON() }),
      );
    this.drop(error);
    // Keep the port until Java unwinds so the cancellation can reach its sink.
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
    // Pending metadata reads and createImageBitmap cannot be interrupted. Keep
    // the charge until sealing settles and any temporary bitmap is closed.
    // Existing codec borrowers keep their separate encoded ownership lease.
    if (!this.sealing && !this.borrowers) this.store.forget(this);
    this.parts = [];
    this.blob = undefined;
    this.publishedEncoded = undefined;
    if (this.url) URL.revokeObjectURL(this.url);
    this.url = undefined;
    this.reject(error);
  }
}
