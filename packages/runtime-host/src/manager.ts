import {
  protocolVersion,
  runtimeHelloSchema,
  runtimeSessionSchema,
  sourceCallSchema,
  acquireImageSchema,
  cancelImageSchema,
  releaseImageSchema,
  closePageSessionSchema,
  imageResourceSchema,
  type AcquireImage,
  type CancelImage,
  type ReleaseImage,
  type ClosePageSession,
  type ImageResource,
  staticManifestPathSchema,
  workerResponseSchema,
  type RpcEnvelope,
  type RuntimeHello,
  type RuntimeSession,
  type SourceCall,
  type WorkerCommand,
} from '@karuyomi/contracts';
import { createHello } from './hello.js';
import { RuntimeFailure } from './errors.js';
import { sha256, VerifiedLoader } from './verified-loader.js';
import { ImageResourceStore, type ImageCollector } from './image-resources.js';

export interface WorkerEndpoint {
  onmessage: ((event: MessageEvent<unknown>) => void) | null;
  onerror: ((event: ErrorEvent) => unknown) | null;
  postMessage(command: WorkerCommand, transfer?: Transferable[]): void;
  terminate(): void;
}
export interface OpenOptions {
  manifestPath: string;
  identity: string;
  userAgent?: string;
  expectedBuildId?: string;
  expectedBundleSha256?: string;
}
interface TaskBase {
  requestId: string;
  resolve(value: unknown): void;
  reject(error: unknown): void;
  timer: ReturnType<typeof setTimeout>;
}
interface SourceTask extends TaskBase {
  kind: 'source';
  call: SourceCall;
}
interface ImageTask extends TaskBase {
  kind: 'image';
  input: AcquireImage;
  collector: ImageCollector;
  port: MessagePort;
  settled: Promise<void>;
  settle(): void;
  failure?: RuntimeFailure;
  cancelTimer?: ReturnType<typeof setTimeout>;
}
interface PageSessionTask extends TaskBase {
  kind: 'page-session';
  pageSessionId: string;
}
type Task = SourceTask | ImageTask | PageSessionTask;
interface Pending {
  resolve(value: unknown): void;
  reject(error: unknown): void;
}

/** One extension slot. Source calls are serial; callbacks remain in the Worker. */
export class SourceRuntimeManager {
  readonly ready: Promise<RuntimeHello> = Promise.resolve(
    createHello(crypto.randomUUID()),
  );
  private worker: WorkerEndpoint | undefined;
  private session: RuntimeSession | undefined;
  private opening: Promise<RuntimeSession> | undefined;
  private openKey: string | undefined;
  private generation: string | undefined;
  private controller: AbortController | undefined;
  private disposed = false;
  private queue: Task[] = [];
  private active: Task | undefined;
  private pending = new Map<string, Pending>();
  private requestIds = new Set<string>();
  private readonly images: ImageResourceStore;
  private readonly imageTasks = new Map<string, ImageTask>();
  private readonly closedPageSessions = new Map<
    string,
    Promise<{ closed: true }>
  >();

  constructor(
    private readonly workerUrl: URL,
    private readonly createWorker: (url: URL) => WorkerEndpoint,
    private readonly loader: VerifiedLoader,
    private readonly startupTimeoutMs = 60_000,
    private readonly imageOptions: {
      enabled?: boolean;
      store?: ImageResourceStore;
      cancelGraceMs?: number;
    } = {},
  ) {
    this.images = imageOptions.store ?? new ImageResourceStore();
  }

  open(options: OpenOptions): Promise<RuntimeSession> {
    if (this.disposed)
      return Promise.reject(
        new RuntimeFailure('runtime_lost', 'Runtime container is disposed'),
      );
    if (!options.identity || options.identity.length > 1000)
      return Promise.reject(
        new RuntimeFailure(
          'access_required',
          'A confirmed Access identity is required',
        ),
      );
    const key = JSON.stringify([
      options.identity,
      options.manifestPath,
      options.expectedBuildId,
      options.expectedBundleSha256,
      options.userAgent,
    ]);
    if (key === this.openKey && this.opening) return this.opening;
    if (key === this.openKey && this.session)
      return Promise.resolve(this.session);
    this.invalidate(
      new RuntimeFailure('runtime_lost', 'Extension slot was replaced'),
    );
    this.openKey = key;
    const generation = crypto.randomUUID();
    this.generation = generation;
    const controller = new AbortController();
    this.controller = controller;
    const timer = setTimeout(() => {
      if (this.generation === generation)
        this.invalidate(
          new RuntimeFailure('timeout', 'Runtime initialization timed out'),
        );
    }, this.startupTimeoutMs);
    const opening = this.start(options, generation, controller.signal);
    this.opening = opening;
    void opening.then(
      () => {
        clearTimeout(timer);
        if (this.generation === generation) this.opening = undefined;
      },
      () => {
        clearTimeout(timer);
        if (this.generation === generation)
          this.invalidate(
            new RuntimeFailure('runtime_lost', 'Runtime initialization failed'),
          );
      },
    );
    return opening;
  }

  private assertGeneration(generation: string): void {
    if (this.generation !== generation)
      throw new RuntimeFailure(
        'runtime_lost',
        'Runtime generation has expired',
      );
  }

  private async start(
    options: OpenOptions,
    generation: string,
    signal: AbortSignal,
  ): Promise<RuntimeSession> {
    const manifest = await this.loader.manifest(options.manifestPath, signal);
    if (
      (options.expectedBuildId &&
        options.expectedBuildId !== manifest.buildId) ||
      (options.expectedBundleSha256 &&
        options.expectedBundleSha256 !== manifest.bundle.sha256)
    ) {
      throw new RuntimeFailure(
        'integrity_error',
        'Manifest does not match the selected build descriptor',
      );
    }
    this.assertGeneration(generation);
    const namespace = await sha256(
      new TextEncoder().encode(
        JSON.stringify([
          options.identity,
          manifest.repoId,
          manifest.packageName,
          manifest.storageSchema,
        ]),
      ),
    );
    this.assertGeneration(generation);
    const url = new URL(this.workerUrl);
    url.searchParams.set('plugin', namespace);
    url.searchParams.set('fsNamespace', namespace);
    const worker = this.createWorker(url);
    this.worker = worker;
    const hello = await new Promise<RuntimeHello>((resolve, reject) => {
      const onAbort = () =>
        reject(
          new RuntimeFailure('runtime_lost', 'Runtime startup was cancelled'),
        );
      signal.addEventListener('abort', onAbort, { once: true });
      worker.onmessage = ({ data }) => {
        const parsed = runtimeHelloSchema.safeParse(data);
        if (!parsed.success || parsed.data.sourceReady) {
          reject(
            new RuntimeFailure(
              'protocol_error',
              'Incompatible runtime Worker handshake',
            ),
          );
        } else resolve(parsed.data);
        signal.removeEventListener('abort', onAbort);
      };
      worker.onerror = () => {
        signal.removeEventListener('abort', onAbort);
        reject(
          new RuntimeFailure('runtime_lost', 'Runtime Worker failed to start'),
        );
      };
    });
    this.assertGeneration(generation);
    const envelope = {
      protocolVersion,
      workerInstanceId: hello.generation,
      generation,
      buildId: manifest.buildId,
    };
    worker.onmessage = ({ data }) => {
      if (this.generation !== generation) return;
      if (
        typeof data === 'object' &&
        data !== null &&
        'type' in data &&
        data.type === 'fatal'
      ) {
        this.invalidate(
          new RuntimeFailure(
            'runtime_lost',
            'Runtime Worker reported an unhandled async failure',
          ),
        );
        return;
      }
      const parsed = workerResponseSchema.safeParse(data);
      if (!parsed.success) return;
      const response = parsed.data;
      if (
        response.generation !== generation ||
        response.workerInstanceId !== envelope.workerInstanceId ||
        response.buildId !== envelope.buildId
      )
        return;
      const waiter = this.pending.get(response.requestId);
      if (!waiter) return;
      this.pending.delete(response.requestId);
      if (response.error) {
        const error = new RuntimeFailure(
          response.error.code,
          response.error.message,
          response.error.retryable,
          response.error.javaClass,
        );
        waiter.reject(error);
        if (error.code === 'access_required' || error.code === 'access_denied')
          this.invalidate(error);
      } else waiter.resolve(response.result);
    };
    worker.onerror = () => {
      if (this.generation === generation)
        this.invalidate(
          new RuntimeFailure('runtime_lost', 'Runtime Worker failed'),
        );
    };
    const result = runtimeSessionSchema.parse(
      await this.send({
        ...envelope,
        requestId: crypto.randomUUID(),
        type: 'open',
        manifest,
        userAgent: options.userAgent ?? 'Karuyomi/0.1',
      }),
    );
    this.assertGeneration(generation);
    if (
      result.generation !== generation ||
      result.buildId !== manifest.buildId ||
      result.workerInstanceId !== envelope.workerInstanceId
    ) {
      throw new RuntimeFailure(
        'protocol_error',
        'Runtime session does not match its Worker envelope',
      );
    }
    this.session =
      this.imageOptions.enabled === false
        ? {
            ...result,
            capabilities: result.capabilities.filter(
              (capability) => capability !== 'processed-image-resources',
            ),
          }
        : result;
    return this.session;
  }

  private send(
    command: WorkerCommand,
    transfer: Transferable[] = [],
  ): Promise<unknown> {
    return new Promise((resolve, reject) => {
      this.pending.set(command.requestId, { resolve, reject });
      try {
        this.worker!.postMessage(command, transfer);
      } catch {
        this.pending.delete(command.requestId);
        reject(
          new RuntimeFailure('runtime_lost', 'Runtime message delivery failed'),
        );
      }
    });
  }

  invoke(input: SourceCall): Promise<unknown> {
    const parsed = sourceCallSchema.safeParse(input);
    if (!parsed.success)
      return Promise.reject(
        new RuntimeFailure('protocol_error', 'Invalid Source request'),
      );
    const call = parsed.data;
    if (!this.session)
      return Promise.reject(
        new RuntimeFailure(
          'runtime_lost',
          'Open a verified extension build before invoking a Source',
        ),
      );
    if (this.queue.length >= 128 || this.requestIds.size >= 10_000)
      return Promise.reject(
        new RuntimeFailure(
          'limit_exceeded',
          'Source request queue or generation budget is exhausted',
        ),
      );
    if (this.requestIds.has(call.requestId))
      return Promise.reject(
        new RuntimeFailure(
          'protocol_error',
          'requestId must be unique within a runtime generation',
        ),
      );
    if (JSON.stringify(call.args).length > 128 * 1024)
      return Promise.reject(
        new RuntimeFailure(
          'limit_exceeded',
          'Source control arguments are too large',
        ),
      );
    this.requestIds.add(call.requestId);
    return new Promise((resolve, reject) => {
      const task: Task = {
        kind: 'source',
        requestId: call.requestId,
        call,
        resolve,
        reject,
        timer: setTimeout(() => this.expire(task), call.timeoutMs ?? 30_000),
      };
      this.queue.push(task);
      this.pump();
    });
  }

  private pump(): void {
    if (this.active || !this.session || !this.worker) return;
    const task = this.queue.shift();
    if (!task) return;
    this.active = task;
    const { protocolVersion, workerInstanceId, generation, buildId } =
      this.session;
    const envelope = {
      protocolVersion,
      workerInstanceId,
      generation,
      buildId,
      requestId: task.requestId,
    };
    const command: WorkerCommand =
      task.kind === 'source'
        ? {
            ...envelope,
            type: 'invoke',
            sourceId: task.call.sourceId,
            operation: task.call.operation,
            args: task.call.args,
          }
        : task.kind === 'image'
          ? {
              ...envelope,
              type: 'acquire-image',
              sourceId: task.input.sourceId,
              pageSessionId: task.input.pageSessionId,
              pageKey: task.input.pageKey,
              resourceId: task.collector.resourceId,
            }
          : {
              ...envelope,
              type: 'close-page-session',
              pageSessionId: task.pageSessionId,
            };
    let published = false;
    void this.send(command, task.kind === 'image' ? [task.port] : [])
      .then(async (result) => {
        if (task.kind === 'image') {
          if (task.failure) throw task.failure;
          const resource = await task.collector.publish(result);
          if (task.failure) throw task.failure;
          this.assertGeneration(task.input.generation);
          published = true;
          // Commit ownership before resolving: caller continuations can run
          // before finally, and cancellation only applies to pending production.
          this.imageTasks.delete(task.requestId);
          clearTimeout(task.timer);
          task.resolve(resource);
        } else task.resolve(result);
      })
      .catch((error: unknown) =>
        task.reject(task.kind === 'image' ? (task.failure ?? error) : error),
      )
      .finally(() => {
        clearTimeout(task.timer);
        if (task.kind === 'image') {
          clearTimeout(task.cancelTimer);
          if (!published) task.collector.release(task.failure);
          this.imageTasks.delete(task.requestId);
          task.settle();
        }
        if (this.active === task) {
          this.active = undefined;
          this.pump();
        }
      });
  }

  private expire(task: Task): void {
    if (task.kind === 'image') {
      void this.stopImage(
        task,
        new RuntimeFailure('timeout', 'Image acquisition timed out'),
      );
      return;
    }
    if (this.active === task) {
      task.reject(
        new RuntimeFailure(
          'timeout',
          'Source request deadline exceeded; the Worker was recycled',
        ),
      );
      this.invalidate(
        new RuntimeFailure(
          'runtime_lost',
          'An active Source request timed out',
        ),
      );
    } else {
      this.queue = this.queue.filter((queued) => queued !== task);
      task.reject(
        new RuntimeFailure(
          'timeout',
          'Source request deadline expired in the queue',
        ),
      );
    }
  }

  cancel(requestId: string): Promise<void> {
    if (this.active?.requestId === requestId) {
      if (this.active.kind === 'image')
        return this.cancelImage({
          requestId,
          generation: this.active.input.generation,
        }).then(() => {});
      this.active.reject(
        new RuntimeFailure(
          'cancelled',
          'Source request was cancelled; the Worker was recycled',
        ),
      );
      this.invalidate(
        new RuntimeFailure(
          'runtime_lost',
          'Active Source cancellation invalidated the generation',
        ),
      );
    } else {
      const task = this.queue.find((queued) => queued.requestId === requestId);
      if (task) {
        if (task.kind === 'image')
          return this.cancelImage({
            requestId,
            generation: task.input.generation,
          }).then(() => {});
        clearTimeout(task.timer);
        this.queue = this.queue.filter((queued) => queued !== task);
        task.reject(
          new RuntimeFailure(
            'cancelled',
            'Queued Source request was cancelled',
          ),
        );
      }
    }
    return Promise.resolve();
  }

  private invalidate(error: RuntimeFailure): void {
    this.generation = undefined;
    this.session = undefined;
    this.opening = undefined;
    this.openKey = undefined;
    this.controller?.abort();
    this.controller = undefined;
    this.worker?.terminate();
    this.worker = undefined;
    this.images.clear(error);
    for (const task of this.imageTasks.values()) {
      clearTimeout(task.cancelTimer);
      task.collector.release(error);
      task.settle();
    }
    this.imageTasks.clear();
    this.closedPageSessions.clear();
    for (const pending of this.pending.values()) pending.reject(error);
    this.pending.clear();
    for (const task of [...this.queue, ...(this.active ? [this.active] : [])]) {
      clearTimeout(task.timer);
      task.reject(task.kind === 'image' ? (task.failure ?? error) : error);
    }
    this.queue = [];
    this.active = undefined;
    this.requestIds.clear();
  }

  async acquireImage(input: AcquireImage): Promise<ImageResource> {
    const parsed = acquireImageSchema.safeParse(input);
    if (!parsed.success)
      throw new RuntimeFailure('protocol_error', 'Invalid image request');
    const request = parsed.data;
    if (this.imageOptions.enabled === false)
      throw new RuntimeFailure(
        'unsupported_capability',
        'Native processed-image delivery is not implemented',
      );
    const session = this.session;
    if (
      !session ||
      session.generation !== request.generation ||
      !session.sources.some((source) => source.id === request.sourceId)
    )
      throw new RuntimeFailure(
        'runtime_lost',
        'Image request belongs to an expired Source runtime',
      );
    if (!session.capabilities.includes('processed-image-resources'))
      throw new RuntimeFailure(
        'unsupported_capability',
        'The loaded build does not provide image resources',
      );
    if (this.closedPageSessions.has(request.pageSessionId))
      throw new RuntimeFailure('runtime_lost', 'Page session was closed');
    this.reserveRequest(request.requestId);
    const collector = this.images.create(request.generation);
    const channel = new MessageChannel();
    collector.attach(channel.port1);
    let settle!: () => void;
    const settled = new Promise<void>((resolve) => {
      settle = resolve;
    });
    return new Promise<ImageResource>((resolve, reject) => {
      const task: ImageTask = {
        kind: 'image',
        requestId: request.requestId,
        input: request,
        collector,
        port: channel.port2,
        settled,
        settle,
        resolve: (value) => {
          // The publication path above is the only producer for this promise.
          const resource = imageResourceSchema.parse(value);
          resolve(resource);
        },
        reject,
        timer: setTimeout(() => {
          void this.stopImage(
            task,
            new RuntimeFailure('timeout', 'Image acquisition timed out'),
          );
        }, request.timeoutMs ?? 30_000),
      };
      this.imageTasks.set(request.requestId, task);
      this.queue.push(task);
      this.pump();
    });
  }

  async cancelImage(input: CancelImage): Promise<{ released: true }> {
    const parsed = cancelImageSchema.safeParse(input);
    if (!parsed.success)
      throw new RuntimeFailure('protocol_error', 'Invalid image cancellation');
    if (parsed.data.generation === this.generation) {
      const task = this.imageTasks.get(parsed.data.requestId);
      if (task)
        await this.stopImage(
          task,
          new RuntimeFailure('cancelled', 'Image acquisition was cancelled'),
        );
    }
    return { released: true };
  }

  private async stopImage(
    task: ImageTask,
    error: RuntimeFailure,
  ): Promise<void> {
    if (task.failure) return task.settled;
    task.failure = error;
    clearTimeout(task.timer);
    if (this.active !== task) {
      this.queue = this.queue.filter((candidate) => candidate !== task);
      task.collector.release(error);
      task.port.close();
      this.imageTasks.delete(task.requestId);
      task.reject(error);
      task.settle();
    } else {
      task.collector.abort(error);
      task.cancelTimer = setTimeout(() => {
        if (this.active === task) {
          const lost = new RuntimeFailure(
            'runtime_lost',
            'Image cancellation did not stop Java; the Worker was recycled',
          );
          task.failure = lost;
          this.invalidate(lost);
        }
      }, this.imageOptions.cancelGraceMs ?? 1000);
    }
    await task.settled;
  }

  releaseImage(input: ReleaseImage): Promise<{ released: true }> {
    const parsed = releaseImageSchema.safeParse(input);
    if (!parsed.success)
      return Promise.reject(
        new RuntimeFailure('protocol_error', 'Invalid image release'),
      );
    this.images.release(parsed.data.resourceId, parsed.data.generation);
    return Promise.resolve({ released: true });
  }

  closePageSession(input: ClosePageSession): Promise<{ closed: true }> {
    const parsed = closePageSessionSchema.safeParse(input);
    if (!parsed.success)
      return Promise.reject(
        new RuntimeFailure('protocol_error', 'Invalid page session close'),
      );
    if (parsed.data.generation !== this.generation || !this.session)
      return Promise.resolve({ closed: true });
    const existing = this.closedPageSessions.get(parsed.data.pageSessionId);
    if (existing) return existing;
    const closing = (async (): Promise<{ closed: true }> => {
      await Promise.all(
        [...this.imageTasks.values()]
          .filter(
            (task) => task.input.pageSessionId === parsed.data.pageSessionId,
          )
          .map((task) =>
            this.stopImage(
              task,
              new RuntimeFailure('cancelled', 'Page session was closed'),
            ),
          ),
      );
      if (parsed.data.generation !== this.generation) return { closed: true };
      const requestId = crypto.randomUUID();
      this.reserveRequest(requestId);
      await new Promise((resolve, reject) => {
        const task: PageSessionTask = {
          kind: 'page-session',
          requestId,
          pageSessionId: parsed.data.pageSessionId,
          resolve,
          reject,
          timer: setTimeout(() => this.expire(task), 30_000),
        };
        this.queue.push(task);
        this.pump();
      });
      return { closed: true };
    })();
    this.closedPageSessions.set(parsed.data.pageSessionId, closing);
    return closing;
  }

  private reserveRequest(requestId: string): void {
    if (this.queue.length >= 128 || this.requestIds.size >= 10_000)
      throw new RuntimeFailure(
        'limit_exceeded',
        'Runtime request budget is exhausted',
      );
    if (this.requestIds.has(requestId))
      throw new RuntimeFailure(
        'protocol_error',
        'requestId must be unique within a runtime generation',
      );
    this.requestIds.add(requestId);
  }

  rebuild(): Promise<void> {
    this.invalidate(
      new RuntimeFailure('runtime_lost', 'Runtime container was rebuilt'),
    );
    return Promise.resolve();
  }

  /** Private APIs share Access cookies; the public catalog permits only GET. */
  async fetchApi(options: {
    path: string;
    method?: string;
    headers?: Record<string, string>;
    body?: string;
  }): Promise<{
    status: number;
    headers: Record<string, string>;
    body: string;
    redirected: boolean;
  }> {
    const url = new URL(options.path, this.workerUrl.origin);
    const staticJson =
      options.path === '/extensions/index.json' ||
      staticManifestPathSchema.safeParse(options.path).success;
    const privateApi =
      url.pathname === '/api' || url.pathname.startsWith('/api/');
    if (
      url.origin !== this.workerUrl.origin ||
      (!privateApi && !staticJson) ||
      url.hash ||
      (staticJson &&
        (url.pathname !== options.path ||
          url.search ||
          (options.method !== undefined && options.method !== 'GET') ||
          options.body !== undefined))
    ) {
      throw new RuntimeFailure(
        'protocol_error',
        'Control requests require the private API or a catalog JSON GET',
      );
    }
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 30_000);
    try {
      if (
        options.body &&
        new TextEncoder().encode(options.body).byteLength > 128 * 1024
      ) {
        throw new RuntimeFailure(
          'limit_exceeded',
          'API control request is too large',
        );
      }
      const response = await fetch(url.href, {
        method: options.method ?? 'GET',
        headers: staticJson
          ? { Accept: 'application/json' }
          : (options.headers ?? {}),
        ...(options.body === undefined ? {} : { body: options.body }),
        credentials: staticJson ? 'omit' : 'same-origin',
        redirect: 'manual',
        cache: staticJson ? 'no-cache' : 'no-store',
        signal: controller.signal,
      });
      if (
        response.type === 'opaqueredirect' ||
        (response.status >= 300 && response.status < 400)
      ) {
        await response.body?.cancel();
        return {
          status: response.status,
          headers: {},
          body: '',
          redirected: true,
        };
      }
      const headers: Record<string, string> = {};
      response.headers.forEach((value, key) => {
        headers[key] = value;
      });
      const reader = response.body?.getReader();
      const decoder = new TextDecoder();
      let body = '',
        bytes = 0;
      if (reader) {
        try {
          for (;;) {
            const result = await reader.read();
            if (result.done) break;
            bytes += result.value.byteLength;
            if (bytes > 2 * 1024 * 1024)
              throw new RuntimeFailure(
                'limit_exceeded',
                'API control response is too large',
              );
            body += decoder.decode(result.value, { stream: true });
          }
          body += decoder.decode();
        } finally {
          await reader.cancel().catch(() => {});
          reader.releaseLock();
        }
      }
      return { status: response.status, headers, body, redirected: false };
    } finally {
      clearTimeout(timer);
    }
  }

  async dispose(): Promise<void> {
    if (this.disposed) return;
    this.disposed = true;
    // A quiet Worker can commit/release filesystem ownership before termination.
    if (this.session && !this.active) {
      const envelope: RpcEnvelope = {
        ...this.session,
        requestId: crypto.randomUUID(),
      };
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        await Promise.race([
          this.send({ ...envelope, type: 'shutdown' }),
          new Promise((resolve) => {
            timer = setTimeout(resolve, 1000);
          }),
        ]);
      } catch {
        /* The generation is invalidated below even if shutdown fails. */
      } finally {
        clearTimeout(timer);
      }
    }
    this.invalidate(
      new RuntimeFailure('runtime_lost', 'Runtime container was disposed'),
    );
  }
}
