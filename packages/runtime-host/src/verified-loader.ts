import {
  buildManifestSchema,
  bundleArtifactSchema,
  extensionIndexSchema,
  staticManifestPathSchema,
  catalogReferenceSchema,
  type CatalogReference,
  type Artifact,
  type BundleArtifact,
  type BuildManifest,
  type ExtensionIndex,
  type ExtensionBuildDescriptor,
} from '@karuyomi/contracts';
import { create, equals } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { RuntimeFailure } from './errors.js';
import { ExtensionArtifactCache } from './extension-artifact-cache.js';

export const sha256 = async (bytes: Uint8Array): Promise<string> => {
  const digest = await crypto.subtle.digest('SHA-256', new Uint8Array(bytes));
  return Array.from(new Uint8Array(digest), (value) =>
    value.toString(16).padStart(2, '0'),
  ).join('');
};

export type RuntimeMaterialResolver = (
  sha256: string,
) => { bytes: Uint8Array; contentType: string } | undefined;

export class VerifiedLoader {
  constructor(
    private readonly origin: string,
    private readonly fetcher: typeof fetch = (...args) => fetch(...args),
    private readonly materialResolver?: RuntimeMaterialResolver,
    readonly cache?: ExtensionArtifactCache,
    private readonly installedMaterials?: readonly Artifact[],
  ) {}

  private async response(
    catalog: CatalogReference,
    path: string,
    signal: AbortSignal,
    immutable = false,
  ): Promise<Response> {
    catalogReferenceSchema.parse(catalog);
    const url = new URL(path, catalog.catalogUrl);
    if (
      url.origin !== new URL(catalog.catalogUrl).origin ||
      url.pathname !== path ||
      !(
        path === '/extensions/index.json' ||
        staticManifestPathSchema.safeParse(path).success ||
        /^\/extensions\/artifacts\/[a-f0-9]{64}\.gz$/.test(path)
      ) ||
      url.search ||
      url.hash
    ) {
      throw new RuntimeFailure(
        'protocol_error',
        'Extension assets must belong to the selected static catalog',
      );
    }
    const response = await this.fetcher(url.href, {
      signal,
      credentials: 'omit',
      redirect: 'manual',
      cache: immutable ? 'force-cache' : 'no-cache',
    });
    if (
      response.type === 'opaqueredirect' ||
      (response.status >= 300 && response.status < 400)
    ) {
      void response.body?.cancel().catch(() => {});
      throw new RuntimeFailure(
        'protocol_error',
        'Static extension delivery cannot redirect',
      );
    }
    if (!response.ok) {
      void response.body?.cancel().catch(() => {});
      throw new RuntimeFailure(
        'runtime_lost',
        `Static extension asset returned HTTP ${response.status}`,
        response.status >= 500,
      );
    }
    if (
      response.headers.get('content-type')?.toLowerCase().includes('text/html')
    ) {
      void response.body?.cancel().catch(() => {});
      throw new RuntimeFailure(
        'protocol_error',
        'Received HTML instead of a static extension asset',
      );
    }
    return response;
  }

  private async readBounded(
    response: Response,
    limit: number,
    signal: AbortSignal,
    exact = false,
  ): Promise<Uint8Array<ArrayBuffer>> {
    const declared = response.headers.get('content-length');
    if (
      declared !== null &&
      (!/^\d+$/.test(declared) || Number(declared) > limit)
    ) {
      void response.body?.cancel().catch(() => {});
      throw new RuntimeFailure(
        'limit_exceeded',
        'Runtime asset exceeds its declared byte budget',
      );
    }
    if (!response.body)
      throw new RuntimeFailure('integrity_error', 'Runtime asset has no body');
    return this.readStream(response.body, limit, signal, exact);
  }

  private async readStream(
    stream: ReadableStream<Uint8Array>,
    limit: number,
    signal: AbortSignal,
    exact: boolean,
  ): Promise<Uint8Array<ArrayBuffer>> {
    const reader = stream.getReader();
    const abort = () => {
      void reader.cancel(signal.reason).catch(() => {});
    };
    signal.addEventListener('abort', abort, { once: true });
    const buffer = new Uint8Array(limit);
    let size = 0;
    try {
      signal.throwIfAborted();
      for (;;) {
        const { value, done } = await reader.read();
        signal.throwIfAborted();
        if (done) break;
        if (size + value.byteLength > limit) {
          throw new RuntimeFailure(
            'limit_exceeded',
            'Runtime asset exceeded its byte budget while streaming',
          );
        }
        buffer.set(value, size);
        size += value.byteLength;
      }
      if (exact && size !== limit)
        throw new RuntimeFailure(
          'integrity_error',
          'Runtime asset size does not match the manifest',
        );
      return exact ? buffer : buffer.slice(0, size);
    } finally {
      signal.removeEventListener('abort', abort);
      void reader.cancel().catch(() => {});
      reader.releaseLock();
    }
  }

  async manifest(
    catalog: CatalogReference,
    path: string,
    signal: AbortSignal,
  ): Promise<BuildManifest> {
    if (!staticManifestPathSchema.safeParse(path).success) {
      throw new RuntimeFailure(
        'protocol_error',
        'Invalid static build manifest path',
      );
    }
    const response = await this.response(catalog, path, signal);
    if (
      response.headers
        .get('content-type')
        ?.split(';')[0]
        ?.trim()
        .toLowerCase() !== 'application/json'
    ) {
      void response.body?.cancel().catch(() => {});
      throw new RuntimeFailure('protocol_error', 'Build manifest must be JSON');
    }
    const bytes = await this.readBounded(response, 64 * 1024, signal);
    try {
      const manifest = buildManifestSchema.parse(
        JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)),
      );
      if (
        path !== `/extensions/builds/${manifest.buildId}/manifest.json` ||
        manifest.repoId !== catalog.repoId
      )
        throw Error('Manifest identity mismatch');
      return manifest;
    } catch {
      throw new RuntimeFailure(
        'protocol_error',
        'Build manifest has an incompatible protocol, ABI or shape',
      );
    }
  }

  async index(
    catalog: CatalogReference,
    signal: AbortSignal,
  ): Promise<ExtensionIndex> {
    const response = await this.response(
      catalog,
      '/extensions/index.json',
      signal,
    );
    if (
      response.headers
        .get('content-type')
        ?.split(';')[0]
        ?.trim()
        .toLowerCase() !== 'application/json'
    ) {
      void response.body?.cancel().catch(() => {});
      throw new RuntimeFailure(
        'protocol_error',
        'Extension index must be JSON',
      );
    }
    const bytes = await this.readBounded(response, 2 * 1024 * 1024, signal);
    try {
      const index = extensionIndexSchema.parse(
        JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)),
      );
      if (index.repoId !== catalog.repoId)
        throw Error('Catalog identity mismatch');
      return index;
    } catch {
      throw new RuntimeFailure(
        'protocol_error',
        'Extension index has an incompatible shape',
      );
    }
  }

  async prepare(
    catalog: CatalogReference,
    build: ExtensionBuildDescriptor,
    signal: AbortSignal,
  ): Promise<{
    catalog: CatalogReference;
    build: ExtensionBuildDescriptor;
    bundleSha256: string;
    byteLength: number;
  }> {
    if (!this.cache)
      throw new RuntimeFailure(
        'unsupported_capability',
        'Managed extension preparation requires an artifact cache',
      );
    const index = await this.index(catalog, signal);
    const current = index.builds.find(
      (value) => value.packageName === build.packageName,
    );
    if (
      !current ||
      !equals(
        pb.ExtensionBuildDescriptorSchema,
        create(pb.ExtensionBuildDescriptorSchema, current),
        create(pb.ExtensionBuildDescriptorSchema, build),
      )
    )
      throw new RuntimeFailure(
        'source_error',
        'The selected extension is no longer current; refresh the catalog',
      );
    const manifest = await this.manifest(catalog, build.manifestPath, signal);
    const descriptor: ExtensionBuildDescriptor = {
      buildId: manifest.buildId,
      packageName: manifest.packageName,
      repoId: manifest.repoId,
      version: manifest.version,
      sourceIds: manifest.sourceIds,
      sources: manifest.sources,
      manifestPath: build.manifestPath,
    };
    if (
      !equals(
        pb.ExtensionBuildDescriptorSchema,
        create(pb.ExtensionBuildDescriptorSchema, descriptor),
        create(pb.ExtensionBuildDescriptorSchema, build),
      )
    )
      throw new RuntimeFailure(
        'integrity_error',
        'The build manifest does not match the selected catalog entry',
      );
    for (const material of [...manifest.hostScripts, ...manifest.resources]) {
      if (this.installedMaterials) {
        const installed = this.installedMaterials.find(
          (value) => value.sha256 === material.sha256,
        );
        if (
          !installed ||
          installed.path !== material.path ||
          installed.size !== material.size ||
          installed.contentType !== material.contentType ||
          installed.logicalName !== material.logicalName
        )
          throw new RuntimeFailure(
            'unsupported_capability',
            'The installed app lacks this runtime material; update the app',
          );
      } else {
        await this.sharedArtifact(
          material,
          signal,
          manifest.hostScripts.includes(material),
        );
      }
      signal.throwIfAborted();
    }
    const bytes = await this.artifact(catalog, manifest.bundle, signal, true);
    signal.throwIfAborted();
    return {
      catalog: { ...catalog },
      build: current,
      bundleSha256: manifest.bundle.sha256,
      byteLength: bytes.byteLength,
    };
  }

  async artifact(
    catalog: CatalogReference,
    artifact: BundleArtifact,
    signal: AbortSignal,
    script = false,
  ): Promise<Uint8Array<ArrayBuffer>> {
    catalogReferenceSchema.parse(catalog);
    if (
      !bundleArtifactSchema.safeParse(artifact).success ||
      artifact.path !== `/extensions/artifacts/${artifact.sha256}.gz`
    ) {
      throw new RuntimeFailure(
        'integrity_error',
        'Artifact URL must match its registered digest',
      );
    }
    if (
      script &&
      !['application/javascript', 'text/javascript'].includes(
        artifact.contentType,
      )
    )
      throw new RuntimeFailure(
        'protocol_error',
        'Extension code requires a JavaScript canonical type',
      );
    const pin = this.cache
      ? await this.cache.retain(artifact.sha256, signal)
      : undefined;
    try {
      const cached = await this.cache?.read(artifact, signal);
      signal.throwIfAborted();
      if (cached) return cached;
      const response = await this.response(
        catalog,
        artifact.path,
        signal,
        true,
      );
      const mime = response.headers
        .get('content-type')
        ?.split(';')[0]
        ?.trim()
        .toLowerCase();
      if (
        mime !== 'application/gzip' ||
        response.headers.has('content-encoding') ||
        (script &&
          !['application/javascript', 'text/javascript'].includes(
            artifact.contentType,
          ))
      ) {
        void response.body?.cancel().catch(() => {});
        throw new RuntimeFailure(
          'protocol_error',
          'Extension transport must be gzip with a JavaScript canonical type',
        );
      }
      const encoded = await this.readBounded(
        response,
        artifact.encodedSize,
        signal,
        true,
      );
      if ((await sha256(encoded)) !== artifact.encodedSha256)
        throw new RuntimeFailure(
          'integrity_error',
          'Compressed extension hash does not match its manifest',
        );
      signal.throwIfAborted();
      if (typeof DecompressionStream === 'undefined')
        throw new RuntimeFailure(
          'unsupported_capability',
          'Gzip extension loading requires DecompressionStream',
        );
      let bytes: Uint8Array<ArrayBuffer>;
      try {
        const source = new ReadableStream<BufferSource>({
          start(controller) {
            controller.enqueue(encoded);
            controller.close();
          },
        });
        bytes = await this.readStream(
          source.pipeThrough(new DecompressionStream('gzip')),
          artifact.size,
          signal,
          true,
        );
      } catch (error) {
        if (error instanceof RuntimeFailure || signal.aborted) throw error;
        throw new RuntimeFailure(
          'integrity_error',
          'Extension gzip data is invalid or truncated',
        );
      }
      if ((await sha256(bytes)) !== artifact.sha256) {
        throw new RuntimeFailure(
          'integrity_error',
          'Canonical extension hash does not match the static manifest',
        );
      }
      signal.throwIfAborted();
      await this.cache?.storeVerified(artifact, bytes, signal);
      signal.throwIfAborted();
      return bytes;
    } finally {
      pin?.release();
      await pin?.released;
    }
  }

  /** Shared host code/data comes from static Web assets or the installed app. */
  async sharedArtifact(
    artifact: Artifact,
    signal: AbortSignal,
    script = false,
  ): Promise<Uint8Array<ArrayBuffer>> {
    signal.throwIfAborted();
    if (artifact.path !== `/runtime/materials/${artifact.sha256}`) {
      throw new RuntimeFailure(
        'integrity_error',
        'Material URL does not match its digest',
      );
    }
    let bytes: Uint8Array<ArrayBuffer>;
    let mime: string | null;
    if (this.materialResolver) {
      const material = this.materialResolver(artifact.sha256);
      if (!material) {
        throw new RuntimeFailure(
          'unsupported_capability',
          'The installed app does not include this runtime material; update the app',
        );
      }
      bytes = new Uint8Array(material.bytes);
      mime = material.contentType;
    } else {
      const url = new URL(`/runtime/materials/${artifact.sha256}`, this.origin);
      const response = await this.fetcher(url.href, {
        signal,
        credentials: 'omit',
        redirect: 'manual',
        cache: 'force-cache',
      });
      if (!response.ok || response.type === 'opaqueredirect') {
        await response.body?.cancel();
        throw new RuntimeFailure(
          'unsupported_capability',
          'This Web deployment does not include the required runtime material',
        );
      }
      mime = response.headers.get('content-type');
      bytes = await this.readBounded(response, artifact.size, signal, true);
    }
    mime = mime?.split(';')[0]?.trim().toLowerCase() ?? null;
    const declared = artifact.contentType?.toLowerCase();
    if (
      !mime ||
      (script &&
        !['application/javascript', 'text/javascript'].includes(mime)) ||
      (declared &&
        mime !== declared &&
        !(
          script &&
          ['application/javascript', 'text/javascript'].includes(declared) &&
          ['application/javascript', 'text/javascript'].includes(mime)
        ))
    ) {
      throw new RuntimeFailure(
        'integrity_error',
        'Runtime material MIME does not match the manifest',
      );
    }
    if (
      bytes.byteLength !== artifact.size ||
      (await sha256(bytes)) !== artifact.sha256
    ) {
      throw new RuntimeFailure(
        'integrity_error',
        'Runtime material size or hash does not match the manifest',
      );
    }
    signal.throwIfAborted();
    return bytes;
  }
}
