import { z } from 'zod';

export const CODEC_WORKER_LIMITS = Object.freeze({
  inputBytes: 8 * 1024 * 1024,
  stripBytes: 4 * 1024 * 1024,
  pngBytes: 8 * 1024 * 1024,
  chunkBytes: 64 * 1024,
  combinedHeapBytes: 64 * 1024 * 1024,
  combinedPayloadBytes: 32 * 1024 * 1024,
  timeoutMs: 30000,
  cancelGraceMs: 1000,
});
const id = z.string().min(1).max(200);
const integer = z.int().nonnegative();
const envelope = { version: z.literal(1), requestId: id, generation: id };
const ownedBytes = z
  .instanceof(Uint8Array)
  .refine(
    (bytes) =>
      bytes.buffer instanceof ArrayBuffer &&
      bytes.byteOffset === 0 &&
      bytes.byteLength === bytes.buffer.byteLength &&
      bytes.byteLength > 0 &&
      bytes.byteLength <= CODEC_WORKER_LIMITS.inputBytes,
    'Verified WASM must own its complete bounded ArrayBuffer',
  );
export const codecModuleSchema = z
  .object({
    moduleUrl: z.string().startsWith('blob:').max(4096),
    wasmBinary: ownedBytes,
  })
  .strict();
export type CodecModule = z.infer<typeof codecModuleSchema>;
export const codecStartSchema = z
  .object({
    ...envelope,
    type: z.literal('start'),
    blob: z.instanceof(Blob),
    format: z.enum(['png', 'jpeg']),
    denominator: z.union([z.literal(1), z.literal(2), z.literal(4)]),
    decoder: codecModuleSchema,
    encoder: codecModuleSchema,
  })
  .strict();
export const codecRequestSchema = z.discriminatedUnion('type', [
  codecStartSchema,
  z.object({ ...envelope, type: z.literal('pull') }).strict(),
  z.object({ ...envelope, type: z.literal('ack'), seq: integer }).strict(),
  z.object({ ...envelope, type: z.literal('cancel') }).strict(),
]);
export type CodecRequest = z.infer<typeof codecRequestSchema>;
export type CodecStart = z.infer<typeof codecStartSchema>;
export const imageHeaderSchema = z
  .object({
    format: z.enum(['png', 'jpeg']),
    sourceWidth: z.int().min(1).max(4096),
    sourceHeight: z.int().min(1).max(100000),
    width: z.int().min(1).max(4096),
    height: z.int().min(1).max(100000),
    rowBytes: z.int().min(4).max(16384),
    denominator: z.union([z.literal(1), z.literal(2), z.literal(4)]),
  })
  .strict();
const errorSchema = z
  .object({ name: z.string(), message: z.string() })
  .strict();
const metric = integer.nullable();
export const codecCleanupSchema = z
  .object({
    succeeded: z.boolean(),
    liveBytes: metric,
    peakBytes: metric,
    allocations: metric,
    heapBytes: metric,
    error: z.string().nullable(),
  })
  .strict();
export const decoderTerminalSchema = z
  .object({
    status: z.enum(['complete', 'cancelled', 'failed']),
    header: imageHeaderSchema.nullable(),
    deliveredBytes: integer,
    decodedRows: integer,
    decodeErrorCode: z.int().nullable(),
    decodeErrorPhase: metric,
    error: errorSchema.nullable(),
    closeSucceeded: z.boolean(),
    liveBytes: metric,
    allocations: metric,
    peakBytes: metric,
    heapBytes: metric,
  })
  .strict();
export const tileMetadataSchema = z
  .object({
    id: z.string().min(1).max(256),
    index: integer,
    x: z.literal(0),
    y: integer,
    width: z.int().min(1).max(4096),
    height: z.int().min(1).max(256),
    sourceRect: z
      .object({
        x: z.literal(0),
        y: integer,
        width: z.int().min(1).max(4096),
        height: z.int().min(1).max(1024),
      })
      .strict(),
    byteLength: z.int().min(1).max(CODEC_WORKER_LIMITS.pngBytes),
    mimeType: z.literal('image/png'),
    provisional: z.literal(true),
  })
  .strict();
export type ImageTileMetadata = z.infer<typeof tileMetadataSchema>;
export const tileTerminalSchema = z
  .object({
    status: z.enum(['complete', 'cancelled', 'failed']),
    invalidatesTiles: z.boolean(),
    decoder: decoderTerminalSchema.nullable(),
    encoder: codecCleanupSchema.nullable(),
    error: errorSchema.nullable(),
    forced: z.boolean(),
  })
  .strict()
  .superRefine((value, context) => {
    if (
      value.invalidatesTiles !== (value.status !== 'complete') ||
      (value.forced && value.status === 'complete')
    )
      context.addIssue({
        code: 'custom',
        message: 'Inconsistent tile terminal',
      });
  });
export type ImageTileTerminal = z.infer<typeof tileTerminalSchema>;
export const codecResponseSchema = z.discriminatedUnion('type', [
  z
    .object({
      ...envelope,
      type: z.literal('header'),
      header: imageHeaderSchema,
    })
    .strict(),
  z
    .object({
      ...envelope,
      type: z.literal('tile-start'),
      tile: tileMetadataSchema,
    })
    .strict(),
  z
    .object({
      ...envelope,
      type: z.literal('data'),
      seq: integer,
      buffer: z
        .instanceof(ArrayBuffer)
        .refine(
          (buffer) =>
            buffer.byteLength > 0 &&
            buffer.byteLength <= CODEC_WORKER_LIMITS.chunkBytes,
        ),
    })
    .strict(),
  z
    .object({ ...envelope, type: z.literal('tile-end'), index: integer })
    .strict(),
  z
    .object({
      ...envelope,
      type: z.literal('terminal'),
      terminal: tileTerminalSchema,
    })
    .strict(),
]);
export type CodecResponse = z.infer<typeof codecResponseSchema>;
