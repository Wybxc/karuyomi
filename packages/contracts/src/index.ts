import { z } from 'zod';
import { hostAbi, protocolVersion, runtimeBaseline } from './generated.js';

export { hostAbi, protocolVersion, runtimeBaseline };

export const runtimeHelloSchema = z.object({
  protocolVersion: z.literal(protocolVersion),
  hostAbi: z.literal(hostAbi),
  runtimeBaseline: z.literal(runtimeBaseline),
  generation: z.string().min(1),
  capabilities: z.array(z.string()),
  sourceReady: z.literal(false),
});

export const bootstrapSchema = z.object({
  protocolVersion: z.literal(protocolVersion),
  identity: z.object({ subject: z.string().min(1) }),
  expiresAt: z.number().int().positive(),
  stage: z.literal('scaffold'),
});

export type RuntimeHello = z.infer<typeof runtimeHelloSchema>;
export type Bootstrap = z.infer<typeof bootstrapSchema>;
