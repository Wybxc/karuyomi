import { z } from 'zod';

export const HTTP_BRIDGE_MEDIA_TYPE = 'application/vnd.karuyomi.http.v2';
export const HTTP_FRAME_LIMIT = 65_536;
export const HTTP_REQUEST_BODY_LIMIT = 8 * 1024 * 1024;
export const HTTP_RESPONSE_BODY_LIMIT = 64 * 1024 * 1024;
export const HTTP_ERROR_FRAME_LIMIT = 4096;
export const HTTP_FRAME_MAX_BYTES = HTTP_FRAME_LIMIT;
export const HTTP_REQUEST_MAX_BYTES = HTTP_REQUEST_BODY_LIMIT;
export const HTTP_RESPONSE_MAX_BYTES = HTTP_RESPONSE_BODY_LIMIT;

const preamble = new Uint8Array([75, 82, 89, 72, 84, 84, 80, 2]);
const META = 1;
const DATA = 2;
const END = 3;
const ERROR = 4;
const headerLength = 5;
const encoder = new TextEncoder();

const headersSchema = z
  .array(z.tuple([z.string().min(1).max(16_384), z.string().max(16_384)]))
  .max(200);
const identityFields = {
  requestId: z.string().min(1).max(200),
  runtimeGeneration: z.string().min(1).max(200),
};
const urlSchema = z
  .string()
  .min(1)
  .max(16_384)
  .refine((value) => {
    try {
      return ['http:', 'https:'].includes(new URL(value).protocol);
    } catch {
      return false;
    }
  }, 'Expected an absolute HTTP(S) URL');

export const httpRequestMetaSchema = z
  .object({
    ...identityFields,
    url: urlSchema,
    method: z.enum([
      'GET',
      'HEAD',
      'POST',
      'PUT',
      'PATCH',
      'DELETE',
      'OPTIONS',
    ]),
    headers: headersSchema,
    hasBody: z.boolean(),
    bodyLength: z
      .number()
      .int()
      .nonnegative()
      .max(HTTP_REQUEST_BODY_LIMIT)
      .nullable(),
    timeoutMs: z.number().int().positive().max(300_000),
  })
  .strict()
  .refine((meta) => meta.hasBody || meta.bodyLength === 0, {
    message: 'A missing body must have length zero',
    path: ['bodyLength'],
  });

export const httpResponseMetaSchema = z
  .object({
    ...identityFields,
    upstreamStatus: z.number().int().min(100).max(599),
    message: z.string().max(1000),
    url: urlSchema,
    headers: headersSchema,
    hasBody: z.boolean(),
    bodyLength: z
      .number()
      .int()
      .nonnegative()
      .max(HTTP_RESPONSE_BODY_LIMIT)
      .nullable(),
    decoded: z.boolean(),
  })
  .strict()
  .refine((meta) => meta.hasBody || meta.bodyLength === 0, {
    message: 'A missing body must have length zero',
    path: ['bodyLength'],
  });

export type HttpRequestMeta = z.infer<typeof httpRequestMetaSchema>;
export type HttpResponseMeta = z.infer<typeof httpResponseMetaSchema>;

const errorSchema = z
  .object({
    code: z.string().min(1).max(200),
    message: z.string().max(HTTP_ERROR_FRAME_LIMIT),
  })
  .strict();
export type HttpErrorPayload = z.infer<typeof errorSchema>;

export class HttpFrameError extends Error {
  readonly code: string;
  readonly remote: boolean;
  constructor(code: string, message: string, remote = false) {
    super(message);
    this.code = code;
    this.remote = remote;
    this.name = 'HttpFrameError';
  }
}

function protocolError(message: string): HttpFrameError {
  return new HttpFrameError('protocol_error', message);
}

function frame(type: number, payload: Uint8Array): Uint8Array<ArrayBuffer> {
  const bytes = new Uint8Array(headerLength + payload.byteLength);
  bytes[0] = type;
  new DataView(bytes.buffer).setUint32(1, payload.byteLength, false);
  bytes.set(payload, headerLength);
  return bytes;
}

function jsonBytes(value: unknown, limit: number): Uint8Array<ArrayBuffer> {
  let json: string | undefined;
  try {
    json = JSON.stringify(value);
  } catch {
    throw protocolError('Frame payload must be JSON serializable');
  }
  if (json === undefined) throw protocolError('Frame payload must be JSON');
  if (json.length > limit)
    throw new HttpFrameError(
      'limit_exceeded',
      'JSON frame exceeds its byte limit',
    );
  const bytes = new Uint8Array(encoder.encode(json));
  if (bytes.byteLength > limit)
    throw new HttpFrameError(
      'limit_exceeded',
      'JSON frame exceeds its byte limit',
    );
  return bytes;
}

function parseJson(bytes: Uint8Array): unknown {
  try {
    // Keep a leading BOM so JSON.parse rejects it instead of silently changing
    // the wire representation. Decoding is fatal on malformed UTF-8.
    return JSON.parse(
      new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes),
    );
  } catch {
    throw protocolError('Invalid UTF-8 JSON frame');
  }
}

/** The preamble is separate; frame helpers never prepend it implicitly. */
export function encodePreamble(): Uint8Array<ArrayBuffer> {
  return preamble.slice();
}

export function encodeMetaFrame(meta: unknown): Uint8Array<ArrayBuffer> {
  return frame(META, jsonBytes(meta, HTTP_FRAME_LIMIT));
}

export function encodeDataFrame(data: Uint8Array): Uint8Array<ArrayBuffer> {
  if (data.byteLength === 0)
    throw protocolError('DATA frames must not be empty');
  if (data.byteLength > HTTP_FRAME_LIMIT)
    throw new HttpFrameError('limit_exceeded', 'DATA frame exceeds 64 KiB');
  return frame(DATA, data);
}

export function encodeEndFrame(
  total: number | bigint,
): Uint8Array<ArrayBuffer> {
  if (typeof total === 'number' && (!Number.isSafeInteger(total) || total < 0))
    throw protocolError('END total must be a nonnegative safe integer or u64');
  const count = BigInt(total);
  if (count < 0n || count > 0xffff_ffff_ffff_ffffn)
    throw protocolError('END total is outside the u64 range');
  const payload = new Uint8Array(8);
  new DataView(payload.buffer).setBigUint64(0, count, false);
  return frame(END, payload);
}

export function encodeErrorFrame(
  error: HttpErrorPayload,
): Uint8Array<ArrayBuffer> {
  const result = errorSchema.safeParse(error);
  if (!result.success) throw protocolError('Invalid ERROR payload');
  return frame(ERROR, jsonBytes(result.data, HTTP_ERROR_FRAME_LIMIT));
}

// Framing only requires the default reader. Depending on BYOB or pipeThrough
// would unnecessarily couple this boundary to browser versus Node stream types.
type FrameInputReader = Pick<
  ReadableStreamDefaultReader<Uint8Array>,
  'read' | 'cancel' | 'releaseLock'
>;

/** A demand-driven reader with one bounded DATA frame and one input view. */
export class HttpFrameReader {
  private readonly source: FrameInputReader;
  private input: Uint8Array | undefined;
  private inputOffset = 0;
  private sourceDone = false;
  private remainder: Uint8Array<ArrayBuffer> | undefined;
  private metaPromise: Promise<unknown> | undefined;
  private failure: HttpFrameError | undefined;
  private stopPromise: Promise<void> | undefined;
  private complete = false;
  private released = false;
  private reading = false;
  private dataTotal = 0;
  private delivered = 0;
  private readonly limit: number;

  constructor(stream: { getReader(): FrameInputReader }, limit: number) {
    if (
      !Number.isSafeInteger(limit) ||
      limit < 0 ||
      limit > HTTP_RESPONSE_BODY_LIMIT
    )
      throw new HttpFrameError(
        'limit_exceeded',
        'Invalid HTTP body byte limit',
      );
    this.source = stream.getReader();
    this.limit = limit;
  }

  /** DATA bytes already returned to the consumer, excluding all framing. */
  get bytesRead(): number {
    return this.delivered;
  }

  meta(): Promise<unknown> {
    if (this.failure) return Promise.reject(this.failure);
    this.metaPromise ??= this.parseMeta().catch((error: unknown) =>
      this.reject(error),
    );
    return this.metaPromise;
  }

  async read(maxBytes: number): Promise<Uint8Array<ArrayBuffer> | null> {
    if (
      !Number.isInteger(maxBytes) ||
      maxBytes < 1 ||
      maxBytes > HTTP_FRAME_LIMIT
    )
      throw new HttpFrameError('limit_exceeded', 'read size must be 1..65536');
    if (this.reading) throw protocolError('Concurrent HTTP frame reads');
    this.reading = true;
    try {
      await this.meta();
      this.checkFailure();
      if (this.complete) return null;
      if (!this.remainder) {
        const { type, length } = await this.readHeader();
        if (type === DATA) {
          if (length === 0)
            throw protocolError('DATA frames must not be empty');
          if (length > HTTP_FRAME_LIMIT || this.dataTotal + length > this.limit)
            throw new HttpFrameError(
              'limit_exceeded',
              'HTTP body byte limit exceeded',
            );
          this.remainder = await this.exact(length);
          this.dataTotal += length;
        } else if (type === END) {
          if (length !== 8)
            throw protocolError('END payload must be eight bytes');
          const total = await this.exact(8);
          if (
            new DataView(total.buffer).getBigUint64(0, false) !==
            BigInt(this.dataTotal)
          )
            throw protocolError('END total does not match DATA bytes');
          await this.requireEof();
          this.complete = true;
          this.release();
          return null;
        } else if (type === ERROR) {
          if (length > HTTP_ERROR_FRAME_LIMIT)
            throw new HttpFrameError(
              'limit_exceeded',
              'ERROR frame exceeds 4096 bytes',
            );
          const result = errorSchema.safeParse(
            parseJson(await this.exact(length)),
          );
          if (!result.success) throw protocolError('Invalid ERROR payload');
          await this.requireEof();
          throw new HttpFrameError(result.data.code, result.data.message, true);
        } else {
          throw protocolError(
            type === META ? 'Duplicate META frame' : 'Unknown HTTP frame type',
          );
        }
      }
      // A transferred result must not detach the still-unread part of a frame.
      const bytes =
        maxBytes >= this.remainder.byteLength && this.remainder.byteOffset === 0
          ? this.remainder
          : this.remainder.slice(0, maxBytes);
      this.remainder =
        bytes.byteLength === this.remainder.byteLength
          ? undefined
          : this.remainder.subarray(bytes.byteLength);
      this.delivered += bytes.byteLength;
      return bytes;
    } catch (error) {
      return this.reject(error);
    } finally {
      this.reading = false;
    }
  }

  cancel(reason?: unknown): Promise<void> {
    if (this.complete) return Promise.resolve();
    this.failure ??= new HttpFrameError(
      'cancelled',
      'HTTP frame stream cancelled',
    );
    this.input = undefined;
    this.remainder = undefined;
    return this.stop(reason);
  }

  private checkFailure(): void {
    if (this.failure) throw this.failure;
  }

  private async parseMeta(): Promise<unknown> {
    const magic = await this.exact(preamble.byteLength);
    if (!magic.every((byte, index) => byte === preamble[index]))
      throw protocolError('Unknown HTTP bridge magic or version');
    const { type, length } = await this.readHeader();
    if (type !== META) throw protocolError('The first HTTP frame must be META');
    if (length > HTTP_FRAME_LIMIT)
      throw new HttpFrameError('limit_exceeded', 'META frame exceeds 64 KiB');
    return parseJson(await this.exact(length));
  }

  private async readHeader(): Promise<{ type: number; length: number }> {
    const bytes = await this.exact(headerLength);
    return {
      type: bytes[0]!,
      length: new DataView(bytes.buffer).getUint32(1, false),
    };
  }

  private async available(): Promise<boolean> {
    this.checkFailure();
    while (!this.input || this.inputOffset >= this.input.byteLength) {
      this.input = undefined;
      this.inputOffset = 0;
      if (this.sourceDone) return false;
      const result = await this.source.read();
      this.checkFailure();
      if (result.done) {
        this.sourceDone = true;
        return false;
      }
      if (!(result.value instanceof Uint8Array))
        throw protocolError('HTTP frame input must contain Uint8Array chunks');
      this.input = result.value;
    }
    return true;
  }

  private async exact(length: number): Promise<Uint8Array<ArrayBuffer>> {
    // All callers validate wire lengths before reaching this allocation.
    const bytes = new Uint8Array(length);
    let offset = 0;
    while (offset < length) {
      if (!(await this.available()))
        throw protocolError('Truncated HTTP frame stream');
      const count = Math.min(
        length - offset,
        this.input!.byteLength - this.inputOffset,
      );
      bytes.set(
        this.input!.subarray(this.inputOffset, this.inputOffset + count),
        offset,
      );
      this.inputOffset += count;
      offset += count;
    }
    return bytes;
  }

  private async requireEof(): Promise<void> {
    if (await this.available())
      throw protocolError('Trailing bytes after terminal HTTP frame');
  }

  private release(): void {
    if (!this.released) {
      this.source.releaseLock();
      this.released = true;
    }
    this.input = undefined;
    this.remainder = undefined;
  }

  private stop(reason: unknown): Promise<void> {
    this.stopPromise ??= this.released
      ? Promise.resolve()
      : this.source
          .cancel(reason)
          .catch(() => {})
          .then(() => this.release());
    return this.stopPromise;
  }

  private reject(error: unknown): never {
    this.failure ??=
      error instanceof HttpFrameError
        ? error
        : protocolError('HTTP frame input stream failed');
    this.input = undefined;
    this.remainder = undefined;
    // Invalid input must reject even if a source's cancellation hook stalls.
    void this.stop(this.failure).catch(() => {});
    throw this.failure;
  }
}
