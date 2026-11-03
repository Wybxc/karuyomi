import {
  buildManifestSchema,
  type Artifact,
  type BuildManifest,
} from '@karuyomi/contracts';
import { RuntimeFailure } from './errors.js';

export const sha256 = async (bytes: Uint8Array): Promise<string> => {
  const digest = await crypto.subtle.digest(
    'SHA-256',
    bytes as Uint8Array<ArrayBuffer>,
  );
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

  private async response(path: string, signal: AbortSignal): Promise<Response> {
    const url = new URL(path, this.origin);
    if (
      url.origin !== this.origin ||
      !url.pathname.startsWith('/api/') ||
      url.search ||
      url.hash
    ) {
      throw new RuntimeFailure(
        'protocol_error',
        'Runtime assets must use the authenticated same-origin API',
      );
    }
    const response = await this.fetcher(url.href, {
      signal,
      credentials: 'same-origin',
      redirect: 'manual',
      cache: 'no-cache',
    });
    if (
      response.type === 'opaqueredirect' ||
      (response.status >= 300 && response.status < 400) ||
      response.status === 401
    ) {
      throw new RuntimeFailure('access_required', 'Access session is required');
    }
    if (response.status === 403)
      throw new RuntimeFailure('access_denied', 'Access session was denied');
    if (!response.ok)
      throw new RuntimeFailure(
        'runtime_lost',
        `Private runtime asset returned HTTP ${response.status}`,
        response.status >= 500,
      );
    if (
      response.headers.get('content-type')?.toLowerCase().includes('text/html')
    ) {
      throw new RuntimeFailure(
        'access_required',
        'Received a login page instead of a private runtime asset',
      );
    }
    return response;
  }

  private async readBounded(
    response: Response,
    limit: number,
    exact = false,
  ): Promise<Uint8Array> {
    const declared = response.headers.get('content-length');
    if (
      declared !== null &&
      (!/^\d+$/.test(declared) || Number(declared) > limit)
    ) {
      await response.body?.cancel();
      throw new RuntimeFailure(
        'limit_exceeded',
        'Runtime asset exceeds its declared byte budget',
      );
    }
    const reader = response.body?.getReader();
    if (!reader)
      throw new RuntimeFailure('integrity_error', 'Runtime asset has no body');
    const buffer = new Uint8Array(limit);
    let size = 0;
    try {
      for (;;) {
        const { value, done } = await reader.read();
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
      return exact ? buffer : buffer.subarray(0, size);
    } finally {
      await reader.cancel().catch(() => {});
      reader.releaseLock();
    }
  }

  async manifest(path: string, signal: AbortSignal): Promise<BuildManifest> {
    if (!/^\/api\/extensions\/builds\/[^/?#]+\/manifest$/.test(path)) {
      throw new RuntimeFailure(
        'protocol_error',
        'Invalid private build manifest path',
      );
    }
    const response = await this.response(path, signal);
    if (
      !response.headers
        .get('content-type')
        ?.toLowerCase()
        .includes('application/json')
    ) {
      throw new RuntimeFailure('protocol_error', 'Build manifest must be JSON');
    }
    const bytes = await this.readBounded(response, 64 * 1024);
    try {
      return buildManifestSchema.parse(
        JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)),
      );
    } catch {
      throw new RuntimeFailure(
        'protocol_error',
        'Build manifest has an incompatible protocol, ABI or shape',
      );
    }
  }

  async artifact(
    artifact: Artifact,
    signal: AbortSignal,
    script = false,
  ): Promise<Uint8Array> {
    if (artifact.path !== `/api/extensions/artifacts/${artifact.sha256}`) {
      throw new RuntimeFailure(
        'integrity_error',
        'Artifact URL must match its registered digest',
      );
    }
    const response = await this.response(artifact.path, signal);
    const mime = response.headers
      .get('content-type')
      ?.split(';')[0]
      ?.trim()
      .toLowerCase();
    if (
      script &&
      mime !== 'application/javascript' &&
      mime !== 'text/javascript'
    ) {
      throw new RuntimeFailure(
        'protocol_error',
        'Runtime script is not JavaScript',
      );
    }
    const bytes = await this.readBounded(response, artifact.size, true);
    if ((await sha256(bytes)) !== artifact.sha256) {
      throw new RuntimeFailure(
        'integrity_error',
        'Runtime asset hash does not match the authenticated manifest',
      );
    }
    return bytes;
  }

  /** Shared host code/data comes from static Web assets or the installed app. */
  async sharedArtifact(
    artifact: Artifact,
    signal: AbortSignal,
    script = false,
  ): Promise<Uint8Array> {
    signal.throwIfAborted();
    if (artifact.path !== `/runtime/materials/${artifact.sha256}`) {
      throw new RuntimeFailure(
        'integrity_error',
        'Material URL does not match its digest',
      );
    }
    let bytes: Uint8Array;
    let mime: string | null;
    if (this.materialResolver) {
      const material = this.materialResolver(artifact.sha256);
      if (!material) {
        throw new RuntimeFailure(
          'unsupported_capability',
          'The installed app does not include this runtime material; update the app',
        );
      }
      bytes = material.bytes.slice();
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
      bytes = await this.readBounded(response, artifact.size, true);
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
