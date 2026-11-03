import { z } from 'zod';
import { hostAbi, protocolVersion, runtimeBaseline } from './generated.ts';

export { hostAbi, protocolVersion, runtimeBaseline };
export * from './http-frames.ts';

export const runtimeHelloSchema = z.object({
  protocolVersion: z.literal(protocolVersion),
  hostAbi: z.literal(hostAbi),
  runtimeBaseline: z.literal(runtimeBaseline),
  generation: z.string().min(1),
  capabilities: z.array(z.string()),
  sourceReady: z.boolean(),
});

export const bootstrapSchema = z.object({
  protocolVersion: z.literal(protocolVersion),
  identity: z.object({ subject: z.string().min(1), email: z.email() }),
  expiresAt: z.number().int().positive(),
  stage: z.enum(['scaffold', 'p0']),
});

const artifactFields = {
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
  size: z
    .number()
    .int()
    .positive()
    .max(64 * 1024 * 1024),
  contentType: z.string().max(128).optional(),
};
export const artifactSchema = z
  .object({
    ...artifactFields,
    path: z.string().regex(/^\/runtime\/materials\/[a-f0-9]{64}$/),
    logicalName: z.string().min(1).max(100).optional(),
  })
  .strict();
export const bundleArtifactSchema = z
  .object({
    ...artifactFields,
    path: z.string().regex(/^\/extensions\/artifacts\/[a-f0-9]{64}\.gz$/),
    contentType: z.enum(['application/javascript', 'text/javascript']),
    encoding: z.literal('gzip'),
    encodedSha256: z.string().regex(/^[a-f0-9]{64}$/),
    encodedSize: z
      .number()
      .int()
      .positive()
      .max(25 * 1024 * 1024),
  })
  .strict();
export const buildIdSchema = z.string().regex(/^[a-zA-Z0-9._-]{1,200}$/);
export const staticManifestPathSchema = z
  .string()
  .regex(/^\/extensions\/builds\/[a-zA-Z0-9._-]{1,200}\/manifest\.json$/);
export const extensionBuildDescriptorSchema = z
  .object({
    buildId: buildIdSchema,
    packageName: z.string().min(1).max(200),
    repoId: z.string().min(1).max(200),
    version: z.string().min(1).max(100),
    sourceIds: z
      .array(z.string().regex(/^-?\d+$/))
      .min(1)
      .max(500),
    manifestPath: staticManifestPathSchema,
  })
  .strict()
  .refine(
    (build) =>
      build.manifestPath ===
      `/extensions/builds/${build.buildId}/manifest.json`,
    'Manifest path must match its build',
  );
export const extensionIndexSchema = z
  .object({
    schemaVersion: z.literal(1),
    builds: z.array(extensionBuildDescriptorSchema).max(5000),
    nextCursor: z.null(),
  })
  .strict()
  .refine(
    (index) =>
      new Set(index.builds.map((build) => build.packageName)).size ===
        index.builds.length &&
      new Set(index.builds.map((build) => build.buildId)).size ===
        index.builds.length,
    'The static index must contain one current build per package',
  );

export const buildManifestSchema = z
  .object({
    protocolVersion: z.literal(protocolVersion),
    hostAbi: z.literal(hostAbi),
    runtimeBaseline: z.literal(runtimeBaseline),
    bridgeVersion: z.literal(2),
    buildId: buildIdSchema,
    packageName: z.string().min(1).max(200),
    repoId: z.string().min(1).max(200),
    version: z.string().min(1).max(100),
    storageSchema: z.string().min(1).max(100),
    sourceIds: z
      .array(z.string().regex(/^-?\d+$/))
      .min(1)
      .max(500),
    bundle: bundleArtifactSchema,
    hostScripts: z.array(artifactSchema).max(16),
    resources: z
      .array(artifactSchema.extend({ logicalName: z.string().min(1).max(100) }))
      .max(16)
      .default([]),
  })
  .superRefine((manifest, ctx) => {
    const artifacts = [
      manifest.bundle,
      ...manifest.hostScripts,
      ...manifest.resources,
    ];
    if (
      artifacts.reduce((sum, artifact) => sum + artifact.size, 0) >
      96 * 1024 * 1024
    ) {
      ctx.addIssue({
        code: 'custom',
        message: 'Build exceeds the runtime loading budget',
      });
    }
    if (
      manifest.bundle.path !==
      `/extensions/artifacts/${manifest.bundle.sha256}.gz`
    ) {
      ctx.addIssue({
        code: 'custom',
        message:
          'Extension programs must use static gzip delivery at their canonical digest',
      });
    }
    for (const artifact of [...manifest.hostScripts, ...manifest.resources]) {
      if (artifact.path !== `/runtime/materials/${artifact.sha256}`) {
        ctx.addIssue({
          code: 'custom',
          message: 'Shared runtime materials must use static delivery',
        });
      }
    }
  });

export const sourceInfoSchema = z.object({
  id: z.string().regex(/^-?\d+$/),
  name: z.string(),
  lang: z.string(),
  supportsLatest: z.boolean().optional(),
  baseUrl: z.string().optional(),
});
export const sourceOperationSchema = z.enum([
  'popular',
  'latest',
  'search',
  'details',
  'chapters',
  'pages',
]);
export const runtimeErrorCodeSchema = z.enum([
  'cancelled',
  'timeout',
  'access_required',
  'access_denied',
  'source_error',
  'unsupported_capability',
  'runtime_lost',
  'protocol_error',
  'integrity_error',
  'limit_exceeded',
]);
export const runtimeErrorSchema = z.object({
  code: runtimeErrorCodeSchema,
  message: z.string(),
  retryable: z.boolean(),
  javaClass: z.string().optional(),
});
export const rpcEnvelopeSchema = z.object({
  protocolVersion: z.literal(protocolVersion),
  workerInstanceId: z.string().min(1),
  generation: z.string().min(1),
  buildId: z.string().min(1),
  requestId: z.string().min(1),
});
export const sourceCallSchema = z.object({
  requestId: z.string().min(1).max(200),
  sourceId: z.string().regex(/^-?\d+$/),
  operation: sourceOperationSchema,
  args: z.record(z.string(), z.unknown()),
  timeoutMs: z.number().int().positive().max(300_000).optional(),
});
export const runtimeSessionSchema = z.object({
  protocolVersion: z.literal(protocolVersion),
  workerInstanceId: z.string().min(1),
  generation: z.string().min(1),
  buildId: z.string().min(1),
  sources: z.array(sourceInfoSchema),
  capabilities: z.array(z.string()),
});
const rpcFields = rpcEnvelopeSchema.shape;
export const workerCommandSchema = z.discriminatedUnion('type', [
  z.object({
    ...rpcFields,
    type: z.literal('open'),
    manifest: buildManifestSchema,
    userAgent: z.string().max(1000),
  }),
  z.object({
    ...rpcFields,
    type: z.literal('invoke'),
    sourceId: z.string().regex(/^-?\d+$/),
    operation: sourceOperationSchema,
    args: z.record(z.string(), z.unknown()),
  }),
  z.object({ ...rpcFields, type: z.literal('shutdown') }),
]);
export const workerResponseSchema = z.object({
  ...rpcFields,
  type: z.literal('response'),
  result: z.unknown().optional(),
  error: runtimeErrorSchema.optional(),
});
export type Artifact = z.infer<typeof artifactSchema>;
export type BundleArtifact = z.infer<typeof bundleArtifactSchema>;
export type ExtensionBuildDescriptor = z.infer<
  typeof extensionBuildDescriptorSchema
>;
export type ExtensionIndex = z.infer<typeof extensionIndexSchema>;
export type BuildManifest = z.infer<typeof buildManifestSchema>;
export type SourceInfo = z.infer<typeof sourceInfoSchema>;
export type SourceCall = z.infer<typeof sourceCallSchema>;
export type RuntimeErrorData = z.infer<typeof runtimeErrorSchema>;
export type RuntimeErrorCode = RuntimeErrorData['code'];
export type RpcEnvelope = z.infer<typeof rpcEnvelopeSchema>;
export type RuntimeSession = z.infer<typeof runtimeSessionSchema>;
export type WorkerCommand = z.infer<typeof workerCommandSchema>;
export type WorkerResponse = z.infer<typeof workerResponseSchema>;

export type RuntimeHello = z.infer<typeof runtimeHelloSchema>;
export type Bootstrap = z.infer<typeof bootstrapSchema>;
