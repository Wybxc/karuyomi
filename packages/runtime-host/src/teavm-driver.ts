import type {
  BuildManifest,
  SourceInfo,
  SourceCall,
  SourcePayload,
  ProcessedImage,
  Closed,
} from '@karuyomi/contracts';
import {
  sourceInfoSchema,
  javaSourceInvocation,
  parseJavaSourcePayload,
  processedImageSchema,
  closedSchema,
} from '@karuyomi/contracts';
import { RuntimeFailure, runtimeFailure } from './errors.js';
import { VerifiedLoader } from './verified-loader.js';
import {
  BinaryHttpTransport,
  HttpOwnerFailure,
  type HttpCallContext,
} from './http-transport.js';
import { ImageSink } from './image-channel.js';

export interface RuntimeDriver {
  open(
    manifest: BuildManifest,
    userAgent: string,
    signal: AbortSignal,
    context?: HttpCallContext,
  ): Promise<SourceInfo[]>;
  invoke(call: SourceCall, context?: HttpCallContext): Promise<SourcePayload>;
  close(): Promise<void>;
  acquireImage?(
    sourceId: string,
    pageSessionId: string,
    pageKey: string,
    port: MessagePort,
    resourceId: string,
    context: HttpCallContext,
  ): Promise<ProcessedImage>;
  closePageSession?(
    pageSessionId: string,
    context: HttpCallContext,
  ): Promise<Closed>;
}

export interface TeaVMGlobals {
  hostInit?: (
    userAgent: string,
    requestId: string,
    generation: string,
    operationToken: string,
  ) => void;
  hostLoad?: (
    requestId: string,
    generation: string,
    operationToken: string,
  ) => void;
  hostInvoke?: (
    sourceId: string,
    operation: string,
    argsJson: string,
    requestId: string,
    generation: string,
    operationToken: string,
  ) => void;
  hostAcquireImage?: (
    sourceId: string,
    pageSessionId: string,
    pageKey: string,
    requestId: string,
    generation: string,
    operationToken: string,
  ) => void;
  hostClosePageSession?: (
    pageSessionId: string,
    requestId: string,
    generation: string,
    operationToken: string,
  ) => void;
  teaDone?: (value: string) => void;
  teaFail?: (error: string, discardRuntime?: boolean) => void;
  teaHttpOpen?: (request: string) => string;
  teaHttpWrite?: (handle: string, bytes: Uint8Array) => void;
  teaHttpFinish?: (handle: string) => Promise<string>;
  teaHttpRead?: (
    handle: string,
    maxBytes: number,
  ) => Promise<Uint8Array | null>;
  teaHttpClose?: (handle: string) => void;
  teaHttpCancel?: (handle: string) => void;
  teaImageOpen?: () => string;
  teaImageWrite?: (handle: string, bytes: Uint8Array) => Promise<void>;
  teaImageClose?: (handle: string) => Promise<string>;
  teaImageCancel?: (handle: string) => void;
  teaGraphicsBegin?: (context: HttpCallContext) => void;
  teaGraphicsCancel?: (requestId: string, generation: string) => void;
  teaGraphicsEnd?: (requestId: string, generation: string) => void;
  teaGraphicsSync?: (request: unknown) => Record<string, unknown>;
  teaGraphicsAsync?: (request: unknown) => Promise<Record<string, unknown>>;
  teaGraphicsBytesOpen?: (maximum: number) => string;
  teaGraphicsBytesWrite?: (handle: string, bytes: Uint8Array) => void;
  teaGraphicsBytesRead?: (handle: string, maximum: number) => Uint8Array | null;
  teaGraphicsBytesDetach?: (handle: string) => void;
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
  private closed = false;
  private binaryTransport: BinaryHttpTransport | undefined;
  private imageSink: ImageSink | undefined;
  private imageFailure: RuntimeFailure | undefined;
  private graphicsContext: HttpCallContext | undefined;
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
      if (this.imageFailure) {
        waiter?.reject(this.imageFailure);
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
    scope.teaFail = (message, discardRuntime) => {
      const waiter = this.waiter;
      this.waiter = undefined;
      const error =
        (this.bridgeFailure?.code === 'access_required' ||
        this.bridgeFailure?.code === 'access_denied'
          ? this.bridgeFailure
          : discardRuntime
            ? new RuntimeFailure('runtime_lost', message)
            : (this.imageFailure ?? this.bridgeFailure)) ??
        new RuntimeFailure(
          'source_error',
          message,
          false,
          /^([\w.$]+(?:Exception|Error))(?::|\s|$)/.exec(message)?.[1],
        );
      this.bridgeFailure = undefined;
      waiter?.reject(error);
    };
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
    scope.teaImageOpen = () => this.capture(() => this.images().open());
    scope.teaImageWrite = (handle, bytes) =>
      this.captureAsync(() => this.images().write(handle, bytes));
    scope.teaImageClose = (handle) =>
      this.captureAsync(() => this.images().close(handle));
    scope.teaImageCancel = (handle) => this.imageSink?.cancel(handle);
    // The prototype callback relay/eval Worker is deliberately not installed.
    // Sources requiring remote scripts get an explicit capability error.
    scope.teaBrowser = () => {
      throw new RuntimeFailure(
        'unsupported_capability',
        'Remote script execution is not available in this host',
      );
    };
  }

  private images(): ImageSink {
    if (!this.imageSink)
      throw new RuntimeFailure(
        'protocol_error',
        'No image operation is active',
      );
    return this.imageSink;
  }

  private binary(): BinaryHttpTransport {
    if (!this.binaryTransport)
      throw new RuntimeFailure(
        'runtime_lost',
        'Source HTTP transport is not initialized',
      );
    return this.binaryTransport;
  }

  private capture<T>(operation: () => T): T {
    const token = this.binaryTransport?.operationToken;
    try {
      return operation();
    } catch (error) {
      this.recordCurrentBridgeFailure(error, token);
      throw error;
    }
  }

  private async captureAsync<T>(operation: () => Promise<T>): Promise<T> {
    const token = this.binaryTransport?.operationToken;
    try {
      return await operation();
    } catch (error) {
      this.recordCurrentBridgeFailure(error, token);
      throw error;
    }
  }

  private recordCurrentBridgeFailure(
    error: unknown,
    token: string | undefined,
  ): void {
    if (
      !(error instanceof HttpOwnerFailure) &&
      token === this.binaryTransport?.operationToken
    )
      this.recordBridgeFailure(error);
  }

  private recordBridgeFailure(error: unknown): void {
    if (
      this.bridgeFailure?.code !== 'access_required' &&
      this.bridgeFailure?.code !== 'access_denied'
    )
      this.bridgeFailure = runtimeFailure(error);
  }

  private call(
    start: (owner: HttpCallContext, token: string) => void,
    context?: HttpCallContext,
  ): Promise<unknown> {
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
    const owner = context ?? {
      requestId: crypto.randomUUID(),
      generation: this.fallbackGeneration,
    };
    const token = this.binary().begin(owner);
    try {
      this.scope.teaGraphicsBegin?.(owner);
    } catch (error) {
      this.binaryTransport?.end();
      return Promise.reject(
        this.graphicsFailure(error) ?? runtimeFailure(error),
      );
    }
    this.graphicsContext = owner;
    return new Promise((resolve, reject) => {
      this.bridgeFailure = undefined;
      this.waiter = { resolve, reject };
      try {
        start(owner, token);
      } catch (error) {
        this.waiter = undefined;
        reject(runtimeFailure(error));
      }
    }).finally(() => {
      this.binaryTransport?.end();
      this.scope.teaGraphicsEnd?.(owner.requestId, owner.generation);
      this.graphicsContext = undefined;
    });
  }

  async open(
    manifest: BuildManifest,
    userAgent: string,
    signal: AbortSignal,
    context?: HttpCallContext,
  ): Promise<SourceInfo[]> {
    this.binaryTransport?.dispose();
    this.binaryTransport = new BinaryHttpTransport(
      this.origin,
      manifest.buildId,
    );
    this.scope.karuyomiResources = {};
    for (const resource of manifest.resources) {
      const bytes = await this.loader.sharedArtifact(resource, signal);
      const url = URL.createObjectURL(
        new Blob([bytes], {
          type: resource.contentType ?? 'application/octet-stream',
        }),
      );
      this.objectUrls.add(url);
      this.scope.karuyomiResources[resource.logicalName] = url;
    }
    const execute = (bytes: Uint8Array<ArrayBuffer>) => {
      const url = URL.createObjectURL(
        new Blob([bytes], {
          type: 'application/javascript',
        }),
      );
      try {
        this.importScript(url);
      } finally {
        URL.revokeObjectURL(url);
      }
    };
    for (const artifact of manifest.hostScripts)
      execute(await this.loader.sharedArtifact(artifact, signal, true));
    execute(await this.loader.artifact(manifest.bundle, signal, true));
    this.installGraphicsFailures();
    if (
      !this.scope.hostInit ||
      !this.scope.hostLoad ||
      !this.scope.hostInvoke ||
      !this.scope.hostAcquireImage ||
      !this.scope.hostClosePageSession
    ) {
      throw new RuntimeFailure(
        'unsupported_capability',
        'This build does not export the complete Source and image host ABI',
      );
    }
    await this.call(
      (owner, token) =>
        this.scope.hostInit!(
          userAgent,
          owner.requestId,
          owner.generation,
          token,
        ),
      context,
    );
    const value = await this.call(
      (owner, token) =>
        this.scope.hostLoad!(owner.requestId, owner.generation, token),
      context,
    );
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

  async invoke(
    call: SourceCall,
    context?: HttpCallContext,
  ): Promise<SourcePayload> {
    const invocation = javaSourceInvocation(call);
    const raw = await this.call(
      (owner, token) =>
        this.scope.hostInvoke!(
          call.sourceId,
          invocation.operation,
          invocation.argsJson,
          owner.requestId,
          owner.generation,
          token,
        ),
      context,
    );
    return parseJavaSourcePayload(call, raw);
  }

  async acquireImage(
    sourceId: string,
    pageSessionId: string,
    pageKey: string,
    port: MessagePort,
    resourceId: string,
    context: HttpCallContext,
  ): Promise<ProcessedImage> {
    return processedImageSchema.parse(
      await this.acquireImageResult(
        sourceId,
        pageSessionId,
        pageKey,
        port,
        resourceId,
        context,
      ),
    );
  }

  private async acquireImageResult(
    sourceId: string,
    pageSessionId: string,
    pageKey: string,
    port: MessagePort,
    resourceId: string,
    context: HttpCallContext,
  ): Promise<unknown> {
    if (this.waiter)
      throw new RuntimeFailure(
        'protocol_error',
        'Concurrent TeaVM entry is not allowed',
      );
    const sink = new ImageSink(port, resourceId, (error) => {
      this.imageFailure ??= error;
      this.binaryTransport?.end();
      this.cancelGraphics();
    });
    this.imageSink = sink;
    this.imageFailure = undefined;
    try {
      const raw = await this.call(
        (owner, token) =>
          this.scope.hostAcquireImage!(
            sourceId,
            pageSessionId,
            pageKey,
            owner.requestId,
            owner.generation,
            token,
          ),
        context,
      );
      return raw;
    } finally {
      sink.dispose();
      this.imageSink = undefined;
      this.imageFailure = undefined;
    }
  }

  async closePageSession(
    pageSessionId: string,
    context: HttpCallContext,
  ): Promise<Closed> {
    const raw = await this.call(
      (owner, token) =>
        this.scope.hostClosePageSession!(
          pageSessionId,
          owner.requestId,
          owner.generation,
          token,
        ),
      context,
    );
    return closedSchema.parse(raw);
  }

  async close(): Promise<void> {
    this.closed = true;
    this.binaryTransport?.dispose();
    this.cancelGraphics();
    this.imageSink?.abort(
      new RuntimeFailure('runtime_lost', 'Image runtime was closed'),
    );
    this.imageSink?.dispose();
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

  private cancelGraphics(): void {
    const owner = this.graphicsContext;
    if (owner)
      this.scope.teaGraphicsCancel?.(owner.requestId, owner.generation);
  }

  private installGraphicsFailures(): void {
    const record = (error: unknown) => {
      const failure = this.graphicsFailure(error);
      if (failure) this.recordBridgeFailure(failure);
    };
    const capture =
      <Args extends unknown[], Result>(operation: (...args: Args) => Result) =>
      (...args: Args): Result => {
        try {
          return operation(...args);
        } catch (error) {
          record(error);
          throw error;
        }
      };
    if (this.scope.teaGraphicsBytesOpen)
      this.scope.teaGraphicsBytesOpen = capture(
        this.scope.teaGraphicsBytesOpen,
      );
    if (this.scope.teaGraphicsBytesWrite)
      this.scope.teaGraphicsBytesWrite = capture(
        this.scope.teaGraphicsBytesWrite,
      );
    if (this.scope.teaGraphicsBytesRead)
      this.scope.teaGraphicsBytesRead = capture(
        this.scope.teaGraphicsBytesRead,
      );
    if (this.scope.teaGraphicsBytesDetach)
      this.scope.teaGraphicsBytesDetach = capture(
        this.scope.teaGraphicsBytesDetach,
      );
    const sync = this.scope.teaGraphicsSync,
      async = this.scope.teaGraphicsAsync;
    if (sync)
      this.scope.teaGraphicsSync = (request) => {
        try {
          return sync(request);
        } catch (error) {
          record(error);
          throw error;
        }
      };
    if (async)
      this.scope.teaGraphicsAsync = async (request) => {
        try {
          return await async(request);
        } catch (error) {
          record(error);
          throw error;
        }
      };
  }

  private graphicsFailure(error: unknown): RuntimeFailure | undefined {
    if (
      error instanceof Error &&
      'code' in error &&
      (error.code === 'limit_exceeded' ||
        error.code === 'cancelled' ||
        error.code === 'unsupported_capability')
    )
      return new RuntimeFailure(error.code, error.message);
    return undefined;
  }
}
