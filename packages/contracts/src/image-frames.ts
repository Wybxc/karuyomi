import { z } from 'zod';
import { processedImageSchema } from './image-control.ts';

export const imageFrameSchema = z.discriminatedUnion('type', [
  z
    .object({
      type: z.literal('meta'),
      seq: z.literal(0),
      mimeType: z.string().max(128),
    })
    .strict(),
  z
    .object({
      type: z.literal('data'),
      seq: z.number().int().positive(),
      buffer: z.instanceof(ArrayBuffer),
    })
    .strict(),
  z
    .object({
      type: z.literal('end'),
      seq: z.number().int().positive(),
      totalBytes: z.number().int().nonnegative(),
    })
    .strict(),
  z
    .object({
      type: z.literal('ack'),
      seq: z.number().int().nonnegative(),
      resource: processedImageSchema.optional(),
    })
    .strict(),
  // Runtime error schema is checked by the receiver, avoiding a schema cycle.
  z.object({ type: z.literal('abort'), error: z.unknown() }).strict(),
]);
export type ImageFrame = z.infer<typeof imageFrameSchema>;
