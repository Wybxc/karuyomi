import { z } from 'zod';

const sha256Schema = z.string().regex(/^[0-9a-f]{64}$/);
const materialArtifactSchema = z
  .object({
    logicalName: z.string().min(1),
    path: z.string().regex(/^\/runtime\/materials\/[0-9a-f]{64}$/),
    sha256: sha256Schema,
    size: z.number().int().positive(),
    contentType: z.string().min(1),
  })
  .refine(
    (artifact) => artifact.path === '/runtime/materials/' + artifact.sha256,
    {
      message: 'Runtime material path must match its SHA-256',
      path: ['path'],
    },
  );

export const runtimeMaterialCatalogSchema = z.object({
  schemaVersion: z.literal(1),
  protocolVersion: z.number().int().positive(),
  hostAbi: z.string().min(1),
  runtimeBaseline: z.string().min(1),
  materialVersion: sha256Schema,
  hostScripts: z.array(materialArtifactSchema),
  resources: z.array(materialArtifactSchema),
  imageCodecs: z.array(materialArtifactSchema),
  sources: z.object({
    zstd: z.object({
      packageName: z.string().min(1),
      version: z.string().min(1),
      file: z.string().min(1),
      sha256: sha256Schema,
      size: z.number().int().positive(),
    }),
    imageCodecs: z
      .object({
        buildIdentity: z.string().min(1),
        abi: z.string().min(1),
        encoderAbi: z.string().min(1),
      })
      .nullable(),
  }),
});

export type RuntimeMaterialArtifact = z.infer<typeof materialArtifactSchema>;
export type RuntimeMaterialCatalog = z.infer<
  typeof runtimeMaterialCatalogSchema
>;
