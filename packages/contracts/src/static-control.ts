import * as pb from '@karuyomi/protocol';
import { create } from '@bufbuild/protobuf';
import { z } from 'zod';
import { hostAbi, protocolVersion, runtimeBaseline } from './generated.ts';
import {
  codec,
  type PlainMessage,
  plainMessage,
  plain,
  messageJson,
  requireCondition,
  requireFields,
} from './codec.ts';

type Present<T, K extends keyof T> = T & { [P in K]-?: NonNullable<T[P]> };
export type Artifact = Present<
  PlainMessage<pb.Artifact>,
  'path' | 'sha256' | 'size'
>;
export type ResourceArtifact = Present<Artifact, 'logicalName'>;
export type BundleArtifact = Required<PlainMessage<pb.BundleArtifact>>;
export type CatalogSource = Required<PlainMessage<pb.CatalogSource>>;
export type BuildManifest = Omit<
  Required<PlainMessage<pb.BuildManifest>>,
  'bundle' | 'hostScripts' | 'resources' | 'sources'
> & {
  sources: CatalogSource[];
  bundle: BundleArtifact;
  hostScripts: Artifact[];
  resources: ResourceArtifact[];
};
export type ExtensionBuildDescriptor = Omit<
  Required<PlainMessage<pb.ExtensionBuildDescriptor>>,
  'sources'
> & { sources: CatalogSource[] };
export type ExtensionIndex = Omit<
  Required<PlainMessage<pb.ExtensionIndex>>,
  'builds'
> & {
  builds: ExtensionBuildDescriptor[];
};
export type Bootstrap = Omit<
  Required<PlainMessage<pb.Bootstrap>>,
  'identity'
> & {
  identity: Required<PlainMessage<pb.Identity>>;
};

export const buildIdSchema = z.string().regex(/^[a-zA-Z0-9._-]{1,200}$/);
export const staticManifestPathSchema = z
  .string()
  .regex(/^\/extensions\/builds\/[a-zA-Z0-9._-]{1,200}\/manifest\.json$/);

export function validId(value: string): void {
  requireCondition(value.length > 0 && value.length <= 200, 'Invalid identity');
}
export function validSourceId(value: string): void {
  requireCondition(/^-?\d{1,19}$/.test(value), 'Invalid Source identity');
  const id = BigInt(value);
  requireCondition(
    id >= -9223372036854775808n && id <= 9223372036854775807n,
    'Source identity exceeds signed int64',
  );
}
function boundedText(value: string, max: number): void {
  requireCondition(value.length > 0 && value.length <= max, 'Invalid text');
}
export function validHash(value: string): void {
  requireCondition(/^[a-f0-9]{64}$/.test(value), 'Invalid SHA-256 digest');
}
function validSources(values: string[]): void {
  requireCondition(
    values.length > 0 &&
      values.length <= 500 &&
      new Set(values).size === values.length,
    'Source identities must be nonempty and unique',
  );
  values.forEach(validSourceId);
}
function catalogSources(
  values: pb.CatalogSource[],
  sourceIds: string[],
): CatalogSource[] {
  const sources = values.map((source) => {
    const value = plain(source);
    requireFields(value, ['id', 'name', 'lang']);
    validSourceId(value.id);
    boundedText(value.name, 500);
    requireCondition(value.name.trim().length > 0, 'Invalid Source name');
    requireCondition(value.lang.length <= 64, 'Invalid Source language');
    return value;
  });
  const ids = new Set(sources.map((source) => source.id));
  requireCondition(
    sources.length === sourceIds.length &&
      ids.size === sources.length &&
      sourceIds.every((id) => ids.has(id)),
    'Catalog metadata must describe exactly the declared Source identities',
  );
  return sources;
}
function validSize(size: number, max: number): void {
  requireCondition(size > 0 && size <= max, 'Artifact exceeds its byte budget');
}

export const artifactSchema = codec<Artifact>((input) => {
  const value = plainMessage(pb.ArtifactSchema, input);
  requireFields(value, ['path', 'sha256', 'size']);
  validHash(value.sha256);
  validSize(value.size, 64 * 1024 * 1024);
  requireCondition(
    value.path === `/runtime/materials/${value.sha256}`,
    'Shared runtime materials must use static delivery',
  );
  if (value.contentType !== undefined)
    requireCondition(value.contentType.length <= 128, 'Invalid content type');
  if (value.logicalName !== undefined) boundedText(value.logicalName, 100);
  return value;
});

export const bundleArtifactSchema = codec<BundleArtifact>((input) => {
  const value = plainMessage(pb.BundleArtifactSchema, input);
  requireFields(value, [
    'path',
    'sha256',
    'size',
    'contentType',
    'encoding',
    'encodedSha256',
    'encodedSize',
  ]);
  validHash(value.sha256);
  validHash(value.encodedSha256);
  validSize(value.size, 64 * 1024 * 1024);
  validSize(value.encodedSize, 25 * 1024 * 1024);
  requireCondition(
    value.path === `/extensions/artifacts/${value.sha256}.gz` &&
      value.encoding === 'gzip',
    'Extension programs must use static gzip delivery at their canonical digest',
  );
  requireCondition(
    value.contentType === 'application/javascript' ||
      value.contentType === 'text/javascript',
    'Extension programs must be JavaScript',
  );
  return value;
});

export const hostScriptListSchema = codec<Artifact[]>((input) => {
  requireCondition(
    Array.isArray(input) && input.length <= 16,
    'Invalid host materials',
  );
  return input.map((value: unknown) => artifactSchema.parse(value));
});
export const resourceListSchema = codec<ResourceArtifact[]>((input) => {
  requireCondition(
    Array.isArray(input) && input.length <= 16,
    'Invalid runtime resources',
  );
  return input.map((item: unknown) => {
    const value = artifactSchema.parse(item);
    requireFields(value, ['logicalName']);
    return value;
  });
});

export const buildManifestSchema = codec<BuildManifest>((input) => {
  const value = plainMessage(pb.BuildManifestSchema, input);
  requireFields(value, [
    'protocolVersion',
    'hostAbi',
    'runtimeBaseline',
    'bridgeVersion',
    'buildId',
    'packageName',
    'repoId',
    'version',
    'storageSchema',
    'sourceIds',
    'bundle',
    'hostScripts',
    'resources',
    'sources',
  ]);
  requireCondition(
    value.protocolVersion === protocolVersion &&
      value.hostAbi === hostAbi &&
      value.runtimeBaseline === runtimeBaseline &&
      value.bridgeVersion === 2,
    'Incompatible runtime build ABI',
  );
  buildIdSchema.parse(value.buildId);
  boundedText(value.packageName, 200);
  boundedText(value.repoId, 200);
  boundedText(value.version, 100);
  boundedText(value.storageSchema, 100);
  validSources(value.sourceIds);
  const sources = catalogSources(value.sources, value.sourceIds);
  const bundle = bundleArtifactSchema.parse(
    messageJson(pb.BundleArtifactSchema, value.bundle),
  );
  const hostScripts = hostScriptListSchema.parse(
    value.hostScripts.map((item) => messageJson(pb.ArtifactSchema, item)),
  );
  const resources = resourceListSchema.parse(
    value.resources.map((item) => messageJson(pb.ArtifactSchema, item)),
  );
  requireCondition(
    [bundle, ...hostScripts, ...resources].reduce(
      (sum, item) => sum + item.size,
      0,
    ) <=
      96 * 1024 * 1024,
    'Build exceeds the runtime loading budget',
  );
  return { ...value, bundle, hostScripts, resources, sources };
});

export const extensionBuildDescriptorSchema = codec<ExtensionBuildDescriptor>(
  (input) => {
    const value = plainMessage(pb.ExtensionBuildDescriptorSchema, input);
    requireFields(value, [
      'buildId',
      'packageName',
      'repoId',
      'version',
      'sourceIds',
      'manifestPath',
      'sources',
    ]);
    buildIdSchema.parse(value.buildId);
    boundedText(value.packageName, 200);
    boundedText(value.repoId, 200);
    boundedText(value.version, 100);
    validSources(value.sourceIds);
    requireCondition(
      value.manifestPath ===
        `/extensions/builds/${value.buildId}/manifest.json`,
      'Manifest path must match its build',
    );
    return {
      ...value,
      sources: catalogSources(value.sources, value.sourceIds),
    };
  },
);

export const extensionIndexSchema = codec<ExtensionIndex>((input) => {
  const value = plainMessage(pb.ExtensionIndexSchema, input);
  requireFields(value, ['schemaVersion', 'builds']);
  requireCondition(
    value.schemaVersion === 1 && value.builds.length <= 5000,
    'Invalid extension index',
  );
  const builds = value.builds.map((build) =>
    extensionBuildDescriptorSchema.parse(
      messageJson(pb.ExtensionBuildDescriptorSchema, build),
    ),
  );
  requireCondition(
    new Set(builds.map((build) => build.packageName)).size === builds.length &&
      new Set(builds.map((build) => build.buildId)).size === builds.length,
    'The static index must contain one current build per package',
  );
  return { ...value, builds };
});

export const bootstrapSchema = codec<Bootstrap>((input) => {
  const value = plainMessage(pb.BootstrapSchema, input);
  requireFields(value, ['protocolVersion', 'identity', 'expiresAt', 'stage']);
  const identity = plain(value.identity);
  requireFields(identity, ['subject', 'email']);
  validId(identity.subject);
  z.email().parse(identity.email);
  requireCondition(
    value.protocolVersion === protocolVersion &&
      Number.isSafeInteger(value.expiresAt) &&
      value.expiresAt > 0 &&
      (value.stage === pb.BootstrapStage.P0 ||
        value.stage === pb.BootstrapStage.SCAFFOLD),
    'Invalid bootstrap metadata',
  );
  return { ...value, identity };
});

export { BootstrapStage } from '@karuyomi/protocol';
export function encodeBootstrap(value: Bootstrap): pb.BootstrapJson {
  const result = messageJson(
    pb.BootstrapSchema,
    create(pb.BootstrapSchema, value),
  );
  bootstrapSchema.parse(result);
  return result;
}
