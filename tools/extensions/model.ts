import { z } from 'zod';
import {
  hostScriptListSchema,
  resourceListSchema,
} from '../../packages/contracts/src/index.ts';

export const sha256Schema = z.string().regex(/^[a-f0-9]{64}$/);
const commitSchema = z.string().regex(/^[a-f0-9]{40,64}$/);
export const submodulePinSchema = z.object({
  path: z.string().min(1),
  gitlink: commitSchema,
  checkout: commitSchema,
});
export type SubmodulePin = z.infer<typeof submodulePinSchema>;
export const extensionDescriptorSchema = z.object({
  schemaVersion: z.literal(1),
  packageName: z.string().min(1).max(200),
  sourcePath: z.string().regex(/^src\/[^/]+\/[^/]+$/),
  versionName: z.string().min(1).max(100),
  versionCode: z.number().int().nonnegative(),
  declaredVersionCode: z.number().int().nonnegative(),
  effectiveVersionCode: z.number().int().nonnegative(),
  upstreamCommit: commitSchema,
  sourceFingerprint: sha256Schema,
  hostFingerprint: sha256Schema,
  inputFingerprint: sha256Schema,
  buildId: z.string().regex(/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,199}$/),
  sourceInputs: z.record(z.string(), sha256Schema),
  sharedInputs: z.record(z.string(), sha256Schema),
  hostInputs: z.record(z.string(), sha256Schema),
  hostRepositoryCommit: commitSchema.optional(),
  hostSubmodules: z.array(submodulePinSchema).optional(),
});
export type ExtensionDescriptor = z.infer<typeof extensionDescriptorSchema>;
export const discoveryFailureSchema = z.object({
  sourcePath: z.string(),
  status: z.literal('discovery_failed'),
  message: z.string(),
});
export const catalogSchema = z.object({
  schemaVersion: z.literal(1),
  upstreamCommit: commitSchema,
  hostFingerprint: sha256Schema,
  catalogFingerprint: sha256Schema,
  entries: z.array(extensionDescriptorSchema),
  discoveryFailures: z.array(discoveryFailureSchema),
});
export type Catalog = z.infer<typeof catalogSchema>;
export const extensionPlanSchema = catalogSchema.extend({
  repositoryCommit: commitSchema,
  selected: z.array(extensionDescriptorSchema),
  pendingCount: z.number().int().nonnegative(),
  remainingCount: z.number().int().nonnegative(),
  ci: z.boolean(),
  baseRevision: z
    .string()
    .regex(/^[a-f0-9]{32}$/)
    .nullable(),
  snapshotNeeded: z.boolean(),
});
export type ExtensionPlan = z.infer<typeof extensionPlanSchema>;
export const buildFailureSchema = z.object({
  stage: z.string(),
  code: z.string(),
  message: z.string(),
});
export const runtimeIdentitySchema = z.object({
  protocolVersion: z.number().int().positive(),
  hostAbi: z.string().min(1),
  runtimeBaseline: z.string().min(1),
  bridgeVersion: z.number().int().positive(),
  hostScripts: z
    .unknown()
    .transform((value) => hostScriptListSchema.parse(value)),
  resources: z.unknown().transform((value) => resourceListSchema.parse(value)),
});
export type RuntimeIdentity = z.infer<typeof runtimeIdentitySchema>;
export const pipelineResultSchema = z.object({
  schemaVersion: z.literal(1),
  descriptor: extensionDescriptorSchema,
  status: z.enum(['built', 'failed']),
  validationStatus: z
    .enum(['browser_verified', 'compiled_unverified'])
    .optional(),
  failure: buildFailureSchema.optional(),
});
export type PipelineResult = z.infer<typeof pipelineResultSchema>;
export const buildRecordSchema = z.object({
  descriptor: extensionDescriptorSchema,
  status: z.enum(['published', 'failed']),
  attempts: z.number().int().positive(),
  available: z.boolean().optional(),
  runtimeIdentity: runtimeIdentitySchema.optional(),
  runtimeReady: z.boolean().optional(),
  validationStatus: z
    .enum(['browser_verified', 'compiled_unverified'])
    .optional(),
  stale: z.boolean().optional(),
  availability: z
    .enum(['available', 'stale_host', 'rebuild_required', 'discovery_failed'])
    .optional(),
  failure: buildFailureSchema.optional(),
  rebuildFailure: buildFailureSchema.optional(),
});
export type BuildRecord = z.infer<typeof buildRecordSchema>;
export const extensionStateSchema = z
  .object({
    schemaVersion: z.literal(1),
    kind: z.literal('static-extension-build-state'),
    revision: z
      .string()
      .regex(/^[a-f0-9]{32}$/)
      .nullable(),
    bootstrap: z.object({
      complete: z.boolean(),
      upstreamCommit: commitSchema.optional(),
      catalogFingerprint: sha256Schema.optional(),
      published: z.number().int().nonnegative().optional(),
      failed: z.number().int().nonnegative().optional(),
      discoveryFailed: z.number().int().nonnegative().optional(),
    }),
    attempts: z.record(sha256Schema, buildRecordSchema),
    active: z.record(z.string(), sha256Schema),
    discoveryFailures: z.array(discoveryFailureSchema).optional(),
    upstreamCommit: commitSchema.optional(),
    hostFingerprint: sha256Schema.optional(),
    catalogFingerprint: sha256Schema.optional(),
    parentRevision: z
      .string()
      .regex(/^[a-f0-9]{32}$/)
      .nullable()
      .optional(),
    indexSha256: sha256Schema.optional(),
    summary: z
      .object({
        available: z.number(),
        unavailable: z.number(),
        failed: z.number(),
        pending: z.number(),
      })
      .optional(),
  })
  .superRefine((state, context) => {
    for (const [key, record] of Object.entries(state.attempts)) {
      if (key !== record.descriptor.inputFingerprint)
        context.addIssue({
          code: 'custom',
          message: 'Invalid build result record',
          path: ['attempts', key],
        });
    }
    for (const [packageName, key] of Object.entries(state.active)) {
      const record = state.attempts[key];
      if (
        record?.status !== 'published' ||
        record.descriptor.packageName !== packageName
      )
        context.addIssue({
          code: 'custom',
          message: 'Invalid successful build pointer',
          path: ['active', packageName],
        });
    }
  });
export type ExtensionState = z.infer<typeof extensionStateSchema>;
