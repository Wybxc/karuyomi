import type { BuildManifest, SourceInfo } from '@karuyomi/contracts';
import { sourceInfoSchema } from '@karuyomi/contracts';
import { RuntimeFailure, runtimeFailure } from './errors.js';
import { VerifiedLoader } from './verified-loader.js';
import {
  BinaryHttpTransport,
  assertBridgeResponse,
  type HttpCallContext,
} from './http-transport.js';

export interface RuntimeDriver {
  open(
    manifest: BuildManifest,
    userAgent: string,
    signal: AbortSignal,
    context?: HttpCallContext,
  ): Promise<SourceInfo[]>;
  invoke(
    sourceId: string,
    operation: string,
    args: Record<string, unknown>,
    context?: HttpCallContext,
  ): Promise<unknown>;
  close(): Promise<void>;
}

export interface TeaVMGlobals {
  hostInit?: (userAgent: string) => void;
  hostLoad?: () => void;
  hostInvoke?: (sourceId: string, operation: string, argsJson: string) => void;
  teaDone?: (value: string) => void;
  teaFail?: (error: string) => void;
  teaHttp?: (request: string) => Promise<string>;
  teaHttpVersion?: number;
  teaHttpOpen?: (request: string) => string;
  teaHttpWrite?: (handle: string, bytes: Uint8Array) => void;
  teaHttpFinish?: (handle: string) => Promise<string>;
  teaHttpRead?: (
    handle: string,
    maxBytes: number,
  ) => Promise<Uint8Array | null>;
  teaHttpClose?: (handle: string) => void;
  teaHttpCancel?: (handle: string) => void;
  teaBrowser?: () => never;
  teaFileSystemClose?: () => Promise<void>;
  karuyomiResources?: Record<string, string>;
}

/** Executes only authenticated, hash-checked release9-derived classic scripts. */
export class TeaVMDriver implements RuntimeDriver {
  private waiter:
    { resolve(value: unknown): void; reject(error: unknown): void } | undefined;
  private bridgeFailure: RuntimeFailure | undefined;
  private readonly objectUrls = new Set<string>();
  private readonly requests = new Set<AbortController>();
  private closed = false;
  private buildId = '';
  private binaryTransport: BinaryHttpTransport | undefined;
  private readonly fallbackGeneration = crypto.randomUUID();

  constructor(
    private readonly scope: TeaVMGlobals,
    private readonly loader: VerifiedLoader,
    private readonly importScript: (url: string) => void,
    private readonly origin: string,
  ) {
    scope.teaDone = (json) => {
      const waiter = this.waiter;
      this.waiter = undefined;
      const failure = this.bridgeFailure;
      this.bridgeFailure = undefined;
      if (
        failure?.code === 'access_required' ||
        failure?.code === 'access_denied'
      ) {
        waiter?.reject(failure);
        return;
      }
      try {
        waiter?.resolve(JSON.parse(json));
      } catch {
        waiter?.reject(
          new RuntimeFailure('protocol_error', 'TeaVM returned invalid JSON'),
        );
      }
    };
    scope.teaFail = (message) => {
      const waiter = this.waiter;
      this.waiter = undefined;
      const error =
        this.bridgeFailure ??
        new RuntimeFailure(
          'source_error',
          message,
          false,
          /^([\w.$]+(?:Exception|Error))(?::|\s|$)/.exec(message)?.[1],
        );
      this.bridgeFailure = undefined;
      waiter?.reject(error);
    };
    scope.teaHttp = (request) => this.http(request);
    scope.teaHttpOpen = (request) =>
      this.capture(() => this.binary().open(request));
    scope.teaHttpWrite = (handle, bytes) =>
      this.capture(() => this.binary().write(handle, bytes));
    scope.teaHttpFinish = (handle) =>
      this.captureAsync(() => this.binary().finish(handle));
    scope.teaHttpRead = (handle, maxBytes) =>
      this.captureAsync(() => this.binary().read(handle, maxBytes));
    scope.teaHttpClose = (handle) => this.binaryTransport?.close(handle);
    scope.teaHttpCancel = scope.teaHttpClose;
    // The prototype callback relay/eval Worker is deliberately not installed.
    // Sources requiring remote scripts get an explicit capability error.
    scope.teaBrowser = () => {
      throw new RuntimeFailure(
        'unsupported_capability',
        'Remote script execution is not available in this host',
      );
    };
  }

  private binary(): BinaryHttpTransport {
    if (!this.binaryTransport || this.scope.teaHttpVersion !== 2)
      throw new RuntimeFailure(
        'unsupported_capability',
        'Binary HTTP was not declared by this build',
      );
    return this.binaryTransport;
  }

  private capture<T>(operation: () => T): T {
    try {
      return operation();
    } catch (error) {
      this.bridgeFailure = runtimeFailure(error);
      throw error;
    }
  }

  private async captureAsync<T>(operation: () => Promise<T>): Promise<T> {
    try {
      return await operation();
    } catch (error) {
      this.bridgeFailure = runtimeFailure(error);
      throw error;
    }
  }

  private call(start: () => void, context?: HttpCallContext): Promise<unknown> {
    if (this.closed)
      return Promise.reject(
        new RuntimeFailure('runtime_lost', 'TeaVM driver was closed'),
      );
    if (this.waiter)
      return Promise.reject(
        new RuntimeFailure(
          'protocol_error',
          'Concurrent TeaVM entry is not allowed',
        ),
      );
    this.binaryTransport?.begin(
      context ?? {
        requestId: crypto.randomUUID(),
        generation: this.fallbackGeneration,
      },
    );
    return new Promise((resolve, reject) => {
      this.bridgeFailure = undefined;
      this.waiter = { resolve, reject };
      try {
        start();
      } catch (error) {
        this.waiter = undefined;
        reject(runtimeFailure(error));
      }
    }).finally(() => this.binaryTransport?.end());
  }

  async open(
    manifest: BuildManifest,
    userAgent: string,
    signal: AbortSignal,
    context?: HttpCallContext,
  ): Promise<SourceInfo[]> {
    this.buildId = manifest.buildId;
    this.scope.teaHttpVersion = manifest.bridgeVersion;
    if (manifest.bridgeVersion === 2)
      this.binaryTransport = new BinaryHttpTransport(this.origin, this.buildId);
    this.scope.karuyomiResources = {};
    for (const resource of manifest.resources) {
      const bytes = await this.loader.sharedArtifact(resource, signal);
      const url = URL.createObjectURL(
        new Blob([bytes as Uint8Array<ArrayBuffer>], {
          type: resource.contentType ?? 'application/octet-stream',
        }),
      );
      this.objectUrls.add(url);
      this.scope.karuyomiResources[resource.logicalName] = url;
    }
    for (const artifact of [...manifest.hostScripts, manifest.bundle]) {
      const bytes = manifest.hostScripts.includes(artifact)
        ? await this.loader.sharedArtifact(artifact, signal, true)
        : await this.loader.artifact(artifact, signal, true);
      const url = URL.createObjectURL(
        new Blob([bytes as Uint8Array<ArrayBuffer>], {
          type: 'application/javascript',
        }),
      );
      try {
        this.importScript(url);
      } finally {
        URL.revokeObjectURL(url);
      }
    }
    if (
      !this.scope.hostInit ||
      !this.scope.hostLoad ||
      !this.scope.hostInvoke
    ) {
      throw new RuntimeFailure(
        'unsupported_capability',
        'This build does not export the product hostInit/hostLoad/hostInvoke ABI',
      );
    }
    await this.call(() => this.scope.hostInit!(userAgent), context);
    const value = await this.call(() => this.scope.hostLoad!(), context);
    if (!Array.isArray(value))
      throw new RuntimeFailure(
        'protocol_error',
        'TeaVM Source list is not an array',
      );
    const sources = value.map((source) => sourceInfoSchema.parse(source));
    const actual = sources.map((source) => source.id).sort();
    const declared = [...manifest.sourceIds].sort();
    if (
      new Set(actual).size !== actual.length ||
      JSON.stringify(actual) !== JSON.stringify(declared)
    ) {
      throw new RuntimeFailure(
        'integrity_error',
        'Loaded Source identities do not match the build manifest',
      );
    }
    return sources;
  }

  invoke(
    sourceId: string,
    operation: string,
    args: Record<string, unknown>,
    context?: HttpCallContext,
  ): Promise<unknown> {
    return this.call(
      () => this.scope.hostInvoke!(sourceId, operation, JSON.stringify(args)),
      context,
    );
  }

  private async http(request: string): Promise<string> {
    const controller = new AbortController();
    this.requests.add(controller);
    try {
      const response = await fetch(new URL('/api/bridge/http', this.origin), {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-App-Request': '1',
          'X-Runtime-Build': this.buildId,
        },
        body: request,
        credentials: 'same-origin',
        redirect: 'manual',
        cache: 'no-store',
        signal: controller.signal,
      });
      assertBridgeResponse(response);
      return await response.text();
    } catch (error) {
      this.bridgeFailure = runtimeFailure(error);
      throw error;
    } finally {
      this.requests.delete(controller);
    }
  }

  async close(): Promise<void> {
    this.closed = true;
    this.binaryTransport?.dispose();
    for (const request of this.requests) request.abort();
    this.requests.clear();
    this.waiter?.reject(
      new RuntimeFailure('runtime_lost', 'TeaVM driver was closed'),
    );
    this.waiter = undefined;
    try {
      await this.scope.teaFileSystemClose?.();
    } finally {
      for (const url of this.objectUrls) URL.revokeObjectURL(url);
      this.objectUrls.clear();
    }
  }
}
