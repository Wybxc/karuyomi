import { z } from 'zod';

export const IMAGE_CHUNK_LIMIT = 64 * 1024;
export const IMAGE_BODY_LIMIT = 64 * 1024 * 1024;
export const IMAGE_PIXEL_LIMIT = 16 * 1024 * 1024;
export const IMAGE_RESIDENT_PIXEL_LIMIT = 32 * 1024 * 1024;
export const IMAGE_RESOURCE_LIMIT = 6;
export const IMAGE_HEADER_LIMIT = 1024 * 1024;
const id = z.string().min(1).max(200);
export const acquireImageSchema = z
  .object({
    requestId: id,
    sourceId: z.string().regex(/^-?\d+$/),
    pageSessionId: id,
    pageKey: id,
    generation: id,
    timeoutMs: z.number().int().positive().max(300_000).optional(),
  })
  .strict();
export const cancelImageSchema = z
  .object({ requestId: id, generation: id })
  .strict();
export const releaseImageSchema = z
  .object({ resourceId: id, generation: id })
  .strict();
export const closePageSessionSchema = z
  .object({ pageSessionId: id, generation: id })
  .strict();
export const processedImageSchema = z
  .object({
    resourceId: id,
    generation: id,
    mimeType: z.enum([
      'image/png',
      'image/jpeg',
      'image/webp',
      'image/gif',
      'image/avif',
      'image/heic',
    ]),
    byteLength: z.number().int().positive().max(IMAGE_BODY_LIMIT),
    // Dimensions after browser decoding, including its image orientation handling.
    width: z.number().int().positive().max(1_000_000),
    height: z.number().int().positive().max(1_000_000),
  })
  .strict();
export const imageResourceSchema = processedImageSchema.extend({
  url: z.string().startsWith('blob:'),
});
export const pageListSchema = z
  .object({
    pageSessionId: id,
    pages: z
      .array(
        z
          .object({
            pageKey: id,
            index: z.number().int().nonnegative(),
            sourceIndex: z.number().int(),
            url: z.string(),
            imageUrl: z.string().nullable(),
          })
          .strict(),
      )
      .max(2048),
  })
  .strict()
  .refine(
    (value) =>
      new Set(value.pages.map((page) => page.pageKey)).size ===
      value.pages.length,
    'Duplicate page key',
  );
export type AcquireImage = z.infer<typeof acquireImageSchema>;
export type CancelImage = z.infer<typeof cancelImageSchema>;
export type ReleaseImage = z.infer<typeof releaseImageSchema>;
export type ClosePageSession = z.infer<typeof closePageSessionSchema>;
export type ProcessedImage = z.infer<typeof processedImageSchema>;
export type ImageResource = z.infer<typeof imageResourceSchema>;
