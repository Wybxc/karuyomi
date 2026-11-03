import {
  buildManifestSchema,
  bundleArtifactSchema,
  extensionIndexSchema,
  staticManifestPathSchema,
  type Artifact,
  type BundleArtifact,
  type BuildManifest,
  type ExtensionIndex,
} from '@karuyomi/contracts';
import { RuntimeFailure } from './errors.js';

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
  ) {}

  private async response(
    path: string,
    signal: AbortSignal,
    immutable = false,
  ): Promise<Response> {
    const url = new URL(path, this.origin);
    if (
      url.origin !== this.origin ||
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
        'Extensions must use the same-origin static catalog',
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

  async manifest(path: string, signal: AbortSignal): Promise<BuildManifest> {
    if (!staticManifestPathSchema.safeParse(path).success) {
      throw new RuntimeFailure(
        'protocol_error',
        'Invalid static build manifest path',
      );
    }
    const response = await this.response(path, signal);
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
      if (path !== `/extensions/builds/${manifest.buildId}/manifest.json`)
        throw Error('Manifest identity mismatch');
      return manifest;
    } catch {
      throw new RuntimeFailure(
        'protocol_error',
        'Build manifest has an incompatible protocol, ABI or shape',
      );
    }
  }

  async index(signal: AbortSignal): Promise<ExtensionIndex> {
    const response = await this.response('/extensions/index.json', signal);
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
      return extensionIndexSchema.parse(
        JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)),
      );
    } catch {
      throw new RuntimeFailure(
        'protocol_error',
        'Extension index has an incompatible shape',
      );
    }
  }

  async artifact(
    artifact: BundleArtifact,
    signal: AbortSignal,
    script = false,
  ): Promise<Uint8Array<ArrayBuffer>> {
    if (
      !bundleArtifactSchema.safeParse(artifact).success ||
      artifact.path !== `/extensions/artifacts/${artifact.sha256}.gz`
    ) {
      throw new RuntimeFailure(
        'integrity_error',
        'Artifact URL must match its registered digest',
      );
    }
    const response = await this.response(artifact.path, signal, true);
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
    return bytes;
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
