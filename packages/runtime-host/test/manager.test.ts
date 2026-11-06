import { catalog } from './fixtures.js';
import { afterEach, expect, test, vi } from 'vitest';
import {
  type BuildManifest,
  type SourceCall,
  type WorkerCommand,
  type WorkerResponse,
  type SourcePayload,
  type AcquireImage,
  workerCommandSchema,
  workerResponseSchema,
  processedImageSchema,
  messageJson,
  protocolVersion,
  encodeControlRequest,
  parseControlResponse,
} from '@karuyomi/contracts';
import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { SourceRuntimeManager, type WorkerEndpoint } from '../src/manager.js';
import { WorkerRuntime } from '../src/worker-runtime.js';
import { createHello } from '../src/hello.js';
import type { RuntimeDriver } from '../src/teavm-driver.js';
import { VerifiedLoader } from '../src/verified-loader.js';
import { installRuntime } from '../src/host-api.js';
import { ImageResourceStore } from '../src/image-resources.js';
import { ImageSink } from '../src/image-channel.js';
import { RuntimeFailure } from '../src/errors.js';
import 'fake-indexeddb/auto';
import { manifest, bytes, encodedBytes } from './fixtures.js';
import { ExtensionArtifactCache } from '../src/extension-artifact-cache.js';

class FakeWorker implements WorkerEndpoint {
  onmessage: WorkerEndpoint['onmessage'] = null;
  onerror: WorkerEndpoint['onerror'] = null;
  terminated = false;
  commands: WorkerCommand[] = [];
  runtime: WorkerRuntime;
  constructor(driver: RuntimeDriver) {
    this.runtime = new WorkerRuntime(driver, (data) => this.emit(data));
    queueMicrotask(() => this.emit(createHello(this.runtime.workerInstanceId)));
  }
  emit(data: unknown) {
    this.onmessage?.(new MessageEvent('message', { data }));
  }
  postMessage(input: unknown, transfer: Transferable[] = []) {
    const command = workerCommandSchema.parse(input);
    this.commands.push(command);
    void this.runtime.receive(
      input,
      transfer.filter(
        (value): value is MessagePort => value instanceof MessagePort,
      ),
    );
  }
  terminate() {
    this.terminated = true;
  }
}

function deferred<T>() {
  let resolve!: (value: T) => void;
  let reject!: (error: unknown) => void;
  const promise = new Promise<T>((yes, no) => {
    resolve = yes;
    reject = no;
  });
  return { promise, resolve, reject };
}
const options = {
  manifestPath: '/extensions/builds/test-build/manifest.json',
  catalog,
  identity: 'verified-owner',
};
const call = (id: string, generation: string, timeoutMs?: number): SourceCall =>
  create(pb.SourceCallSchema, {
    requestId: id,
    sourceId: '9223372036854775806',
    generation,
    request: { case: 'popular', value: { page: 1 } },
    ...(timeoutMs ? { timeoutMs } : {}),
  });
const mangaPage = (url = '/manga', hasNextPage = false): SourcePayload => ({
  case: 'mangaPage',
  value: create(pb.MangaPageSchema, { mangas: [{ url }], hasNextPage }),
});
const managers: SourceRuntimeManager[] = [];
const sinks: ImageSink[] = [];
afterEach(async () => {
  for (const manager of managers.splice(0)) await manager.dispose();
  for (const sink of sinks.splice(0)) sink.dispose();
  vi.useRealTimers();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

test('the public generated control entry correlates typed Source success and structured failures', async () => {
  const { manager, driver } = await setup();
  vi.stubGlobal('window', { addEventListener: vi.fn() });
  const api = installRuntime(manager);
  const opening = parseControlResponse(
    await api.control(
      encodeControlRequest(
        create(pb.ControlRequestSchema, {
          requestId: 'control-open',
          command: { case: 'open', value: options },
        }),
      ),
    ),
  );
  expect(opening.requestId).toBe('control-open');
  if (opening.result.case !== 'session')
    throw new Error('Expected session control response');
  const response = parseControlResponse(
    await api.control(
      encodeControlRequest(
        create(pb.ControlRequestSchema, {
          requestId: 'control-source',
          command: {
            case: 'invoke',
            value: call('source-call', opening.result.value.generation),
          },
        }),
      ),
    ),
  );
  expect(response.requestId).toBe('control-source');
  expect(response.result).toMatchObject({
    case: 'source',
    value: { requestId: 'source-call', payload: { case: 'mangaPage' } },
  });
  const invalid = parseControlResponse(
    await api.control({ requestId: 'conflicting', ready: {}, dispose: {} }),
  );
  expect(invalid).toMatchObject({
    requestId: 'conflicting',
    result: {
      case: 'error',
      value: { code: pb.RuntimeErrorCode.PROTOCOL_ERROR },
    },
  });
  expect(driver.invoke).toHaveBeenCalledOnce();
});

async function setup(
  invoke: RuntimeDriver['invoke'] = async () => mangaPage(),
  initialBuild?: BuildManifest,
  images?: {
    store: ImageResourceStore;
    acquire: NonNullable<RuntimeDriver['acquireImage']>;
  },
  loaderOverride?: VerifiedLoader,
  appOrigin = 'https://read.example.com',
) {
  const workers: FakeWorker[] = [];
  const workerUrls: URL[] = [];
  const driver = {
    open: vi.fn(async () => [
      { id: '9223372036854775806', name: 'Test', lang: 'en' },
    ]),
    invoke: vi.fn(invoke),
    close: vi.fn(async () => {}),
    ...(images
      ? {
          acquireImage: vi.fn(images.acquire),
          closePageSession: vi.fn(async () => ({ closed: true as const })),
        }
      : {}),
  };
  const build = initialBuild ?? (await manifest());
  const loader =
    loaderOverride ??
    new VerifiedLoader(appOrigin, (async () =>
      Response.json(build)) as typeof fetch);
  const manager = new SourceRuntimeManager(
    new URL('/runtime/worker.js', appOrigin),
    (url) => {
      expect(url.searchParams.get('plugin')).toMatch(/^[a-f0-9]{64}$/);
      expect(url.searchParams.get('plugin')).toBe(
        url.searchParams.get('fsNamespace'),
      );
      expect(url.href).not.toContain(options.identity);
      workerUrls.push(new URL(url));
      const worker = new FakeWorker(driver);
      workers.push(worker);
      return worker;
    },
    loader,
    60_000,
    images ? { store: images.store } : {},
  );
  managers.push(manager);
  return { manager, workers, workerUrls, driver };
}

async function setupImages(invoke?: RuntimeDriver['invoke']) {
  const store = new ImageResourceStore({ maxBytes: 5 });
  const bytes = new Uint8Array([255, 0, 173]);
  const value = await setup(invoke, undefined, {
    store,
    acquire: async (_source, _session, _page, port, id) => {
      const sink = new ImageSink(port, id, () => {});
      sinks.push(sink);
      const handle = sink.open();
      await sink.write(handle, bytes);
      return processedImageSchema.parse(JSON.parse(await sink.close(handle)));
    },
  });
  const session = await value.manager.open(options);
  const request: AcquireImage = {
    requestId: 'delivered-image',
    sourceId: session.sources[0]!.id,
    generation: session.generation,
    pageSessionId: 'chapter-session',
    pageKey: 'p-0',
  };
  const image = await value.manager.acquireImage(request);
  return { ...value, store, bytes, session, request, image };
}

test('same build open is shared; only actual initialized Sources produce a session', async () => {
  const { manager, workers, driver } = await setup();
  expect((await manager.ready).sourceReady).toBe(false);
  const first = manager.open(options);
  expect(manager.open(options)).toBe(first);
  const session = await first;
  expect(session.sources[0]?.id).toBe('9223372036854775806');
  expect((await manager.open(options)).generation).toBe(session.generation);
  expect(workers).toHaveLength(1);
  expect(driver.open).toHaveBeenCalledTimes(1);
});

test('extension updates and Worker replacement retain the same storage namespace', async () => {
  const build = await manifest();
  const { manager, workers, workerUrls } = await setup(undefined, build);
  const first = await manager.open(options);
  build.buildId = 'updated-build';
  build.version = '2';
  const updatedOptions = {
    ...options,
    manifestPath: '/extensions/builds/updated-build/manifest.json',
    expectedBuildId: 'updated-build',
    userAgent: 'Updated client',
  };
  const updated = await manager.open(updatedOptions);
  expect(updated.buildId).toBe('updated-build');
  expect(updated.generation).not.toBe(first.generation);
  expect(workers[0]?.terminated).toBe(true);
  expect(workerUrls).toHaveLength(2);
  expect(workerUrls[1]?.searchParams.get('fsNamespace')).toBe(
    workerUrls[0]?.searchParams.get('fsNamespace'),
  );

  await manager.dispose();
  const recreated = await setup(undefined, build);
  await recreated.manager.open(updatedOptions);
  expect(recreated.workerUrls[0]?.searchParams.get('plugin')).toBe(
    workerUrls[0]?.searchParams.get('plugin'),
  );
});

test.each([
  { boundary: 'identity', changes: {}, identity: 'another-owner' },
  { boundary: 'repository', changes: { repoId: 'another-repo' } },
  { boundary: 'package', changes: { packageName: 'another.extension' } },
  { boundary: 'storage schema', changes: { storageSchema: '2' } },
])(
  'changing $boundary isolates both Cache and ordinary files',
  async ({ changes, identity }) => {
    const baseline = await setup();
    await baseline.manager.open(options);
    const isolated = await setup(undefined, {
      ...(await manifest()),
      ...changes,
    });
    await isolated.manager.open({
      ...options,
      identity: identity ?? options.identity,
      catalog: { ...catalog, repoId: changes.repoId ?? catalog.repoId },
    });
    const baselineNamespace =
      baseline.workerUrls[0]?.searchParams.get('plugin');
    const isolatedNamespace =
      isolated.workerUrls[0]?.searchParams.get('plugin');
    expect(isolatedNamespace).not.toBe(baselineNamespace);
    expect(isolated.workerUrls[0]?.searchParams.get('fsNamespace')).toBe(
      isolatedNamespace,
    );
  },
);

test('selected build identity and digest are checked before creating a Worker, including reused manifests', async () => {
  const { manager, workers } = await setup();
  await expect(
    manager.open({ ...options, expectedBuildId: 'unregistered-build' }),
  ).rejects.toMatchObject({ code: 'integrity_error' });
  expect(workers).toHaveLength(0);
  const session = await manager.open(options);
  await expect(
    manager.open({ ...options, expectedBundleSha256: '0'.repeat(64) }),
  ).rejects.toMatchObject({ code: 'integrity_error' });
  expect(workers).toHaveLength(1);
  expect(workers[0]?.terminated).toBe(true);
  const replacement = await manager.open(options);
  expect(replacement.generation).not.toBe(session.generation);
});

test('frontend concurrent invocations are serial and preserve request identities', async () => {
  const first = deferred<SourcePayload>();
  const second = deferred<SourcePayload>();
  const { manager, driver } = await setup(
    vi
      .fn()
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise),
  );
  const session = await manager.open(options);
  const a = manager.invoke(call('a', session.generation));
  const b = manager.invoke(call('b', session.generation));
  expect(driver.invoke).toHaveBeenCalledTimes(1);
  first.resolve(mangaPage('/manga-a'));
  expect(await a).toMatchObject({
    requestId: 'a',
    generation: session.generation,
  });
  await vi.waitFor(() => expect(driver.invoke).toHaveBeenCalledTimes(2));
  second.resolve(mangaPage('/manga-b', true));
  expect(await b).toMatchObject({
    requestId: 'b',
    payload: { case: 'mangaPage', value: { hasNextPage: true } },
  });
});

test('queued cancellation never calls the Source or destroys a running sibling', async () => {
  const active = deferred<SourcePayload>();
  const { manager, workers, driver } = await setup(() => active.promise);
  const session = await manager.open(options);
  const a = manager.invoke(call('active', session.generation));
  const b = manager.invoke(call('queued', session.generation));
  const cancelled = expect(b).rejects.toMatchObject({ code: 'cancelled' });
  await manager.cancel('active', 'obsolete-generation');
  expect(workers[0]?.terminated).toBe(false);
  await manager.cancel('queued');
  await cancelled;
  expect(workers[0]?.terminated).toBe(false);
  expect(driver.invoke).toHaveBeenCalledTimes(1);
  active.resolve(mangaPage());
  await a;
  await manager.cancel('active', session.generation);
  expect(workers[0]?.terminated).toBe(false);
});

test('active cancellation recycles the generation and rejects queued work without replay', async () => {
  const active = deferred<SourcePayload>();
  const { manager, workers } = await setup(() => active.promise);
  const session = await manager.open(options);
  const a = manager.invoke(call('active', session.generation));
  const b = manager.invoke(call('queued', session.generation));
  const cancelled = expect(a).rejects.toMatchObject({ code: 'cancelled' });
  const lost = expect(b).rejects.toMatchObject({ code: 'runtime_lost' });
  vi.stubGlobal('window', { addEventListener: vi.fn() });
  const api = installRuntime(manager);
  const response = parseControlResponse(
    await api.control(
      encodeControlRequest(
        create(pb.ControlRequestSchema, {
          requestId: 'cancel-control',
          command: {
            case: 'cancel',
            value: { requestId: 'active', generation: session.generation },
          },
        }),
      ),
    ),
  );
  expect(response.result).toMatchObject({
    case: 'error',
    value: { code: pb.RuntimeErrorCode.RUNTIME_LOST },
  });
  await cancelled;
  await lost;
  expect(workers[0]?.terminated).toBe(true);
  await expect(
    manager.invoke(call('after', session.generation)),
  ).rejects.toMatchObject({
    code: 'runtime_lost',
  });
  const next = await manager.open(options);
  expect(next.generation).not.toBe(session.generation);
  active.resolve(mangaPage('/stale'));
  // A delayed old worker message cannot resolve a new generation's task.
  workers[0]?.emit(
    messageJson(
      pb.WorkerResponseSchema,
      create(pb.WorkerResponseSchema, {
        envelope: { ...session, requestId: 'later' },
        result: {
          case: 'source',
          value: {
            requestId: 'later',
            generation: session.generation,
            buildId: session.buildId,
            payload: mangaPage('/leaked'),
          },
        },
      }),
    ),
  );
});

test('active deadline stops a stuck Source Worker', async () => {
  const { manager, workers } = await setup(() => new Promise(() => {}));
  const session = await manager.open(options);
  vi.useFakeTimers();
  const pending = manager.invoke(call('timeout', session.generation, 50));
  const expired = expect(pending).rejects.toMatchObject({ code: 'timeout' });
  await vi.advanceTimersByTimeAsync(50);
  await expired;
  expect(workers[0]?.terminated).toBe(true);
});

test('native Worker failure invalidates pending work without an untyped fatal message', async () => {
  const { manager, workers } = await setup(() => new Promise(() => {}));
  const session = await manager.open(options);
  const pending = manager.invoke(call('transport-failure', session.generation));
  const rejected = expect(pending).rejects.toMatchObject({
    code: 'runtime_lost',
  });
  workers[0]?.onerror?.(
    Object.assign(new Event('error'), {
      message: 'transport failed',
      filename: '',
      lineno: 0,
      colno: 0,
      error: new Error('transport failed'),
    }),
  );
  await rejected;
  expect(workers[0]?.terminated).toBe(true);
});

test('wrong-generation messages and unregistered Source IDs cannot cross the slot', async () => {
  const result = deferred<SourcePayload>();
  const { manager, workers, driver } = await setup(() => result.promise);
  const session = await manager.open(options);
  const pending = manager.invoke(call('current', session.generation));
  workers[0]?.emit(
    messageJson(
      pb.WorkerResponseSchema,
      create(pb.WorkerResponseSchema, {
        envelope: {
          ...session,
          protocolVersion,
          generation: 'old-generation',
          requestId: 'current',
        },
        result: {
          case: 'source',
          value: {
            requestId: 'current',
            generation: 'old-generation',
            buildId: session.buildId,
            payload: mangaPage('/wrong'),
          },
        },
      }),
    ),
  );
  result.resolve(mangaPage('/valid'));
  expect(await pending).toMatchObject({
    payload: { case: 'mangaPage', value: { mangas: [{ url: '/valid' }] } },
  });
  await expect(
    manager.invoke({
      ...call('wrong-source', session.generation),
      sourceId: '1',
    }),
  ).rejects.toMatchObject({ code: 'protocol_error' });
  expect(driver.invoke).toHaveBeenCalledTimes(1);
});

test('duplicate request ID and image channel are explicit failures', async () => {
  const { manager } = await setup();
  const session = await manager.open(options);
  await manager.invoke(call('same', session.generation));
  await expect(
    manager.invoke(call('same', session.generation)),
  ).rejects.toMatchObject({
    code: 'protocol_error',
  });
  await expect(
    manager.acquireImage({
      requestId: 'image',
      generation: (await manager.open(options)).generation,
      sourceId: '9223372036854775806',
      pageSessionId: 'session',
      pageKey: 'p-0',
    }),
  ).rejects.toMatchObject({
    code: 'unsupported_capability',
  });
});

test('dispose releases file ownership, stops Worker and forbids reuse', async () => {
  const { manager, driver, workers } = await setup();
  await manager.open(options);
  await manager.dispose();
  expect(driver.close).toHaveBeenCalledTimes(1);
  expect(workers[0]?.terminated).toBe(true);
  await expect(manager.open(options)).rejects.toMatchObject({
    code: 'runtime_lost',
  });
});

test.each(['access_required', 'access_denied'] as const)(
  '%s stops execution but retains delivered images, their budget and cleanup ownership',
  async (code) => {
    const failure = deferred<SourcePayload>();
    const { manager, workers, driver, store, image, bytes, session, request } =
      await setupImages(() => failure.promise);
    const revoke = vi.spyOn(URL, 'revokeObjectURL');
    const expected = {
      code,
      message: 'Original Access failure',
      retryable: true,
    };
    const active = expect(
      manager.invoke(call('expired', session.generation)),
    ).rejects.toMatchObject(expected);
    const queued = expect(
      manager.invoke(call('prefetch', session.generation)),
    ).rejects.toMatchObject(expected);
    failure.reject(new RuntimeFailure(code, expected.message, true));
    await active;
    await queued;
    expect(workers[0]?.terminated).toBe(true);
    expect(driver.invoke).toHaveBeenCalledOnce();
    expect(store.snapshot).toEqual({ resources: 1, bytes: bytes.byteLength });
    expect(
      new Uint8Array(await (await fetch(image.url)).arrayBuffer()),
    ).toEqual(bytes);
    await expect(
      manager.invoke(call('paused', session.generation)),
    ).rejects.toMatchObject(expected);
    await expect(
      manager.acquireImage({ ...request, requestId: 'paused-image' }),
    ).rejects.toMatchObject(expected);
    await expect(
      manager.closePageSession({
        pageSessionId: request.pageSessionId,
        generation: request.generation,
      }),
    ).resolves.toEqual({ closed: true });
    expect(driver.closePageSession).not.toHaveBeenCalled();
    expect(revoke).not.toHaveBeenCalled();
    const nextOwner = await setup();
    await nextOwner.manager.open(options);
    const release = {
      resourceId: image.resourceId,
      generation: image.generation,
    };
    await manager.releaseImage(release);
    await manager.releaseImage(release);
    expect(revoke).toHaveBeenCalledExactlyOnceWith(image.url);
    expect(store.snapshot).toEqual({ resources: 0, bytes: 0 });
  },
);

test('same-identity reconnect retains old UI resources and charges them until release', async () => {
  const { manager, driver, store, session, image, request, bytes } =
    await setupImages(async () => {
      throw new RuntimeFailure('access_required', 'Session expired');
    });
  const revoke = vi.spyOn(URL, 'revokeObjectURL');
  await expect(
    manager.invoke(call('expire', session.generation)),
  ).rejects.toMatchObject({ code: 'access_required' });
  await manager.rebuild();
  const reopened = await manager.open(options);
  expect(reopened.generation).not.toBe(session.generation);
  expect(revoke).not.toHaveBeenCalled();
  expect(new Uint8Array(await (await fetch(image.url)).arrayBuffer())).toEqual(
    bytes,
  );
  const nextRequest = { ...request, generation: reopened.generation };
  await expect(
    manager.acquireImage({ ...nextRequest, requestId: 'over-budget' }),
  ).rejects.toMatchObject({ code: 'limit_exceeded' });
  await vi.waitFor(() =>
    expect(store.snapshot).toEqual({ resources: 1, bytes: bytes.byteLength }),
  );
  await manager.closePageSession({
    pageSessionId: request.pageSessionId,
    generation: session.generation,
  });
  expect(driver.closePageSession).not.toHaveBeenCalled();
  await manager.releaseImage({
    resourceId: image.resourceId,
    generation: image.generation,
  });
  const fresh = await manager.acquireImage({
    ...nextRequest,
    requestId: 'after-release',
  });
  expect(fresh.generation).toBe(reopened.generation);
  expect(store.snapshot).toEqual({ resources: 1, bytes: bytes.byteLength });
  expect(revoke).toHaveBeenCalledExactlyOnceWith(image.url);
});

test('an image Access failure discards only the pending collector and retains the delivered sibling', async () => {
  const { manager, driver, workers, store, image, request, bytes } =
    await setupImages();
  const acquire = driver.acquireImage;
  if (!acquire) throw new Error('Image fixture requires an image driver');
  acquire.mockRejectedValueOnce(
    new RuntimeFailure('access_required', 'Image bridge session expired'),
  );
  const revoke = vi.spyOn(URL, 'revokeObjectURL');
  await expect(
    manager.acquireImage({ ...request, requestId: 'failed-image' }),
  ).rejects.toMatchObject({
    code: 'access_required',
    message: 'Image bridge session expired',
  });
  expect(workers[0]?.terminated).toBe(true);
  expect(store.snapshot).toEqual({ resources: 1, bytes: bytes.byteLength });
  expect(revoke).not.toHaveBeenCalled();
  expect(new Uint8Array(await (await fetch(image.url)).arrayBuffer())).toEqual(
    bytes,
  );
  await manager.releaseImage({
    resourceId: image.resourceId,
    generation: image.generation,
  });
  expect(store.snapshot).toEqual({ resources: 0, bytes: 0 });
});

test('disposing an Access-paused manager revokes all retained images', async () => {
  const { manager, store, session, image } = await setupImages(async () => {
    throw new RuntimeFailure('access_required', 'Session expired');
  });
  const revoke = vi.spyOn(URL, 'revokeObjectURL');
  await expect(
    manager.invoke(call('expire', session.generation)),
  ).rejects.toMatchObject({ code: 'access_required' });
  expect(store.snapshot.resources).toBe(1);
  await manager.dispose();
  expect(revoke).toHaveBeenCalledExactlyOnceWith(image.url);
  expect(store.snapshot).toEqual({ resources: 0, bytes: 0 });
});

test('a different identity clears retained images and late old cleanup cannot release new ownership', async () => {
  const { manager, store, session, image, request, bytes } = await setupImages(
    async () => {
      throw new RuntimeFailure('access_required', 'Session expired');
    },
  );
  const revoke = vi.spyOn(URL, 'revokeObjectURL');
  await expect(
    manager.invoke(call('expire', session.generation)),
  ).rejects.toMatchObject({ code: 'access_required' });
  const other = await manager.open({ ...options, identity: 'another-owner' });
  expect(revoke).toHaveBeenCalledExactlyOnceWith(image.url);
  expect(store.snapshot).toEqual({ resources: 0, bytes: 0 });
  const current = await manager.acquireImage({
    ...request,
    generation: other.generation,
    requestId: 'other-owner-image',
  });
  await manager.releaseImage({
    resourceId: image.resourceId,
    generation: image.generation,
  });
  await manager.closePageSession({
    pageSessionId: request.pageSessionId,
    generation: session.generation,
  });
  expect(store.snapshot).toEqual({ resources: 1, bytes: bytes.byteLength });
  expect(
    new Uint8Array(await (await fetch(current.url)).arrayBuffer()),
  ).toEqual(bytes);
});

test('private API authentication failure also suspends the active Worker without revoking the UI image', async () => {
  const { manager, workers, session, image, store } = await setupImages();
  const revoke = vi.spyOn(URL, 'revokeObjectURL');
  vi.stubGlobal(
    'fetch',
    vi.fn(async () => new Response('', { status: 401 })),
  );
  expect((await manager.fetchApi({ path: '/api/bootstrap' })).status).toBe(401);
  expect(workers[0]?.terminated).toBe(true);
  expect(store.snapshot.resources).toBe(1);
  expect(revoke).not.toHaveBeenCalled();
  await expect(
    manager.invoke(call('after-api-failure', session.generation)),
  ).rejects.toMatchObject({ code: 'access_required' });
  await manager.releaseImage({
    resourceId: image.resourceId,
    generation: image.generation,
  });
  expect(revoke).toHaveBeenCalledExactlyOnceWith(image.url);
});

test('a delayed API authentication failure cannot suspend a replacement generation', async () => {
  const { manager, workers } = await setup();
  const first = await manager.open(options);
  const response = deferred<Response>();
  vi.stubGlobal(
    'fetch',
    vi.fn(() => response.promise),
  );
  const pending = manager.fetchApi({ path: '/api/bootstrap' });
  const current = await manager.open({ ...options, userAgent: 'Replacement' });
  expect(current.generation).not.toBe(first.generation);
  response.resolve(new Response('', { status: 401 }));
  expect((await pending).status).toBe(401);
  expect(workers[1]?.terminated).toBe(false);
  await expect(
    manager.invoke(call('current-after-stale-401', current.generation)),
  ).resolves.toMatchObject({ generation: current.generation });
});

test('real namespace Web Locks reject a second build and are released before disposal completes', async () => {
  const first = await setup();
  await first.manager.open(options);
  const namespace = first.workerUrls[0]!.searchParams.get('plugin');
  const lockName = `karuyomi:source-writer:${namespace}`;
  expect((await navigator.locks.query()).held).toContainEqual(
    expect.objectContaining({ name: lockName, mode: 'exclusive' }),
  );
  const second = await setup(undefined, {
    ...(await manifest()),
    buildId: 'other-build',
    version: '2',
  });
  const nextOptions = {
    ...options,
    manifestPath: '/extensions/builds/other-build/manifest.json',
  };
  await expect(second.manager.open(nextOptions)).rejects.toMatchObject({
    code: 'storage_busy',
  });
  expect(second.workers).toHaveLength(0);
  expect(second.driver.open).not.toHaveBeenCalled();
  await first.manager.dispose();
  expect((await navigator.locks.query()).held).not.toContainEqual(
    expect.objectContaining({ name: lockName }),
  );
  await second.manager.open(nextOptions);
  expect(second.workers).toHaveLength(1);
});

test('failed or cancelled startup releases its namespace without a dangling writer', async () => {
  const failed = await setup();
  failed.driver.open.mockRejectedValueOnce(new Error('Initialization failed'));
  await expect(failed.manager.open(options)).rejects.toMatchObject({
    code: 'source_error',
  });
  expect(failed.workers[0]?.terminated).toBe(true);

  const delayed = await setup();
  const sources = deferred<Awaited<ReturnType<RuntimeDriver['open']>>>();
  delayed.driver.open.mockImplementationOnce(() => sources.promise);
  const cancelled = expect(delayed.manager.open(options)).rejects.toMatchObject(
    {
      code: 'runtime_lost',
    },
  );
  await vi.waitFor(() => expect(delayed.workers).toHaveLength(1));
  await delayed.manager.rebuild();
  await cancelled;
  expect(delayed.workers[0]?.terminated).toBe(true);
  const next = await setup();
  await next.manager.open(options);
  sources.resolve([{ id: '9223372036854775806', name: 'Late', lang: 'en' }]);
  expect(next.workers[0]?.terminated).toBe(false);
});

test('fatal runtime_lost terminates the Worker and rejects queued operations before reuse', async () => {
  const failure = deferred<SourcePayload>();
  const { manager, driver, workers } = await setup(() => failure.promise);
  const session = await manager.open(options);
  const active = expect(
    manager.invoke(call('fatal-drain', session.generation)),
  ).rejects.toMatchObject({ code: 'runtime_lost' });
  const queued = expect(
    manager.invoke(call('never-started', session.generation)),
  ).rejects.toMatchObject({ code: 'runtime_lost' });
  failure.reject(new RuntimeFailure('runtime_lost', 'Callbacks did not stop'));
  await active;
  await queued;
  expect(workers[0]?.terminated).toBe(true);
  expect(driver.invoke).toHaveBeenCalledOnce();
  await expect(
    manager.invoke(call('old-generation', session.generation)),
  ).rejects.toMatchObject({ code: 'runtime_lost' });
  const current = await manager.open(options);
  driver.invoke.mockResolvedValueOnce(mangaPage());
  await expect(
    manager.invoke(call('new-generation', current.generation)),
  ).resolves.toMatchObject({ generation: current.generation });
});

test('the JSON control bridge permits only the catalog static GET paths without credentials', async () => {
  const { manager } = await setup();
  const fetcher = vi.fn(async () => Response.json({ builds: [] }));
  vi.stubGlobal('fetch', fetcher);
  for (const path of [
    '/extensions/index.json',
    '/extensions/builds/test-build/manifest.json',
  ]) {
    expect((await manager.fetchApi({ path })).status).toBe(200);
    expect(fetcher).toHaveBeenLastCalledWith(
      'https://read.example.com' + path,
      expect.objectContaining({
        method: 'GET',
        credentials: 'omit',
        cache: 'no-cache',
        headers: { Accept: 'application/json' },
      }),
    );
  }
  fetcher.mockClear();
  for (const input of [
    { path: '/extensions/index.json', method: 'POST' },
    { path: '/extensions/index.json', body: '' },
    { path: '/extensions/index.json?cursor=old' },
    { path: '/extensions/builds/../index.json' },
    { path: '/extensions/artifacts/' + 'a'.repeat(64) + '.gz' },
    { path: '/runtime/materials.json' },
    { path: 'https://other.example/extensions/index.json' },
  ])
    await expect(manager.fetchApi(input)).rejects.toMatchObject({
      code: 'protocol_error',
    });
  expect(fetcher).not.toHaveBeenCalled();
  await manager.fetchApi({
    path: '/api/settings?scope=reader',
    method: 'PUT',
    headers: { 'X-App-Request': '1' },
    body: '{}',
  });
  expect(fetcher).toHaveBeenCalledWith(
    'https://read.example.com/api/settings?scope=reader',
    expect.objectContaining({
      method: 'PUT',
      credentials: 'same-origin',
      cache: 'no-store',
      headers: { 'X-App-Request': '1' },
      body: '{}',
    }),
  );
});

test.each([
  ['/extensions/builds/test-build/manifest.json', 64 * 1024],
  ['/extensions/index.json', 2 * 1024 * 1024],
  ['/api/bootstrap', 2 * 1024 * 1024],
])('the JSON control bridge bounds %s while streaming', async (path, limit) => {
  const { manager } = await setup();
  const atLimit = new Uint8Array(limit).fill(120);
  const fetcher = vi.fn(async () => new Response(atLimit));
  vi.stubGlobal('fetch', fetcher);
  expect((await manager.fetchApi({ path })).body).toHaveLength(limit);

  const cancel = vi.fn();
  let chunks = 0;
  const stream = new ReadableStream<Uint8Array>(
    {
      pull(controller) {
        if (chunks === 0) controller.enqueue(atLimit);
        else if (chunks === 1) controller.enqueue(new Uint8Array([120]));
        else controller.close();
        chunks += 1;
      },
      cancel,
    },
    { highWaterMark: 0 },
  );
  fetcher.mockImplementationOnce(async () => new Response(stream));
  await expect(manager.fetchApi({ path })).rejects.toMatchObject({
    code: 'limit_exceeded',
  });
  expect(cancel).toHaveBeenCalledOnce();
});

test('typed bootstrap keeps long width in open identity, reaches the Worker, and changed values force a new generation', async () => {
  const { manager, driver, workers } = await setup();
  const preferenceBootstrap = create(pb.PreferenceBootstrapSchema, {
    packageName: 'eu.kanade.tachiyomi.extension.test',
    sources: [
      {
        sourceId: '9223372036854775806',
        entries: [
          {
            key: 'session-long',
            value: {
              value: { case: 'longInteger', value: 9223372036854775807n },
            },
          },
        ],
      },
    ],
  });
  const opening = { ...options, preferenceBootstrap };
  const first = await manager.open(opening);
  expect(await manager.open(opening)).toEqual(first);
  expect(driver.open).toHaveBeenCalledTimes(1);
  const sent = workers[0]?.commands.find(
    (command) => command.command.case === 'open',
  );
  if (sent?.command.case !== 'open') throw new Error('Expected Worker open');
  expect(sent.command.value.preferenceBootstrap).toEqual(preferenceBootstrap);
  const second = await manager.open({
    ...options,
    preferenceBootstrap: create(pb.PreferenceBootstrapSchema, {
      packageName: preferenceBootstrap.packageName,
      sources: [
        {
          sourceId: '9223372036854775806',
          entries: [
            {
              key: 'session-long',
              value: { value: { case: 'longInteger', value: 0n } },
            },
          ],
        },
      ],
    }),
  });
  expect(second.generation).not.toBe(first.generation);
  expect(workers[0]?.terminated).toBe(true);
  expect(driver.open).toHaveBeenCalledTimes(2);
});

test.each(['accepted', 'vetoed', 'failed'] as const)(
  'a %s preference edit runs once, blocks queued and future work, and requires a fresh confirmed generation',
  async (outcome) => {
    const waiting = deferred<SourcePayload>();
    const { manager, driver, workers } = await setup(async (request) => {
      if (request.request.case === 'editPreference') return waiting.promise;
      return mangaPage();
    });
    const session = await manager.open(options);
    const editing = manager.invoke(
      create(pb.SourceCallSchema, {
        requestId: 'edit-once',
        sourceId: '9223372036854775806',
        generation: session.generation,
        request: {
          case: 'editPreference',
          value: {
            snapshotId: 'prefs-1',
            path: [0],
            command: {
              case: 'change',
              value: { value: { case: 'boolean', value: false } },
            },
          },
        },
      }),
    );
    const editResult =
      outcome === 'failed'
        ? expect(editing).rejects.toMatchObject({ code: 'source_error' })
        : expect(editing).resolves.toMatchObject({
            payload: { case: 'preferenceEdit' },
          });
    await expect(
      manager.invoke(call('later-read', session.generation)),
    ).rejects.toMatchObject({ code: 'protocol_error' });
    await expect(
      manager.invoke(
        create(pb.SourceCallSchema, {
          requestId: 'repeated-edit',
          sourceId: '9223372036854775806',
          generation: session.generation,
          request: { case: 'getPreferences', value: {} },
        }),
      ),
    ).rejects.toMatchObject({ code: 'protocol_error' });
    if (outcome === 'failed')
      waiting.reject(
        new RuntimeFailure('source_error', 'listener failed after mutation'),
      );
    else
      waiting.resolve({
        case: 'preferenceEdit',
        value: create(pb.PreferenceEditResultSchema, {
          accepted: outcome === 'accepted',
          snapshot: { snapshotId: 'prefs-2' },
        }),
      });
    await editResult;
    await expect(
      manager.invoke(call('after-edit', session.generation)),
    ).rejects.toMatchObject({ code: 'protocol_error' });
    expect(driver.invoke).toHaveBeenCalledTimes(1);
    const reopened = await manager.open(options);
    expect(reopened.generation).not.toBe(session.generation);
    expect(workers[0]?.terminated).toBe(true);
    expect(driver.open).toHaveBeenCalledTimes(2);
    await manager.invoke(call('confirmed-read', reopened.generation));
    expect(driver.invoke).toHaveBeenCalledTimes(2);
  },
);

test('requests already queued behind a preference edit are rejected before their Source listener or page work starts', async () => {
  const reading = deferred<SourcePayload>();
  const editing = deferred<SourcePayload>();
  const { manager, driver } = await setup(async (request) =>
    request.request.case === 'editPreference'
      ? editing.promise
      : reading.promise,
  );
  const session = await manager.open(options);
  const activeRead = manager.invoke(call('before-edit', session.generation));
  const edit = manager.invoke(
    create(pb.SourceCallSchema, {
      requestId: 'queued-edit',
      sourceId: '9223372036854775806',
      generation: session.generation,
      request: {
        case: 'editPreference',
        value: {
          snapshotId: 'prefs-1',
          path: [0],
          command: { case: 'click', value: {} },
        },
      },
    }),
  );
  const blocked = expect(
    manager.invoke(call('queued-after-edit', session.generation)),
  ).rejects.toMatchObject({ code: 'protocol_error' });
  reading.resolve(mangaPage());
  await activeRead;
  await vi.waitFor(() => expect(driver.invoke).toHaveBeenCalledTimes(2));
  await blocked;
  editing.resolve({
    case: 'preferenceEdit',
    value: create(pb.PreferenceEditResultSchema, {
      snapshot: { snapshotId: 'prefs-2' },
    }),
  });
  await edit;
  expect(driver.invoke).toHaveBeenCalledTimes(2);
});

test('close waits for shutdown ACK, rejects opening while closing, and old close cannot stop the next generation', async () => {
  const { manager, driver, workers } = await setup();
  const session = await manager.open(options);
  const gate = deferred<void>();
  driver.close.mockImplementationOnce(async () => gate.promise);
  const input = create(pb.CloseBuildRequestSchema, {
    buildId: session.buildId,
    generation: session.generation,
  });
  const closing = manager.closeBuild(input);
  expect(manager.closeBuild(input)).toBe(closing);
  await expect(manager.open(options)).rejects.toMatchObject({
    code: 'source_error',
  });
  expect(workers[0]?.terminated).toBe(false);
  gate.resolve();
  await expect(closing).resolves.toEqual({ closed: true });
  expect(workers[0]?.terminated).toBe(true);
  await expect(manager.closeBuild(input)).resolves.toEqual({ closed: true });
  const next = await manager.open(options);
  expect(next.generation).not.toBe(session.generation);
  await expect(manager.closeBuild(input)).rejects.toMatchObject({
    code: 'runtime_lost',
  });
  expect(workers[1]?.terminated).toBe(false);
  await expect(
    manager.invoke(call('after-old-close', next.generation)),
  ).resolves.toMatchObject({ generation: next.generation });
});

test('close refuses active requests without losing the current Source and shutdown failure does not claim ACK', async () => {
  const gate = deferred<SourcePayload>();
  const { manager, driver, workers } = await setup(() => gate.promise);
  const session = await manager.open(options);
  const invoked = manager.invoke(call('still-running', session.generation));
  const input = create(pb.CloseBuildRequestSchema, {
    buildId: session.buildId,
    generation: session.generation,
  });
  await expect(manager.closeBuild(input)).rejects.toMatchObject({
    code: 'source_error',
  });
  expect(workers[0]?.terminated).toBe(false);
  gate.resolve(mangaPage());
  await invoked;
  driver.close.mockRejectedValueOnce(
    new RuntimeFailure('source_error', 'close failed'),
  );
  await expect(manager.closeBuild(input)).rejects.toMatchObject({
    code: 'source_error',
  });
  expect(workers[0]?.terminated).toBe(true);
  await expect(manager.closeBuild(input)).rejects.toMatchObject({
    code: 'runtime_lost',
  });
});

test('preparation uses only static delivery, shares verified bytes, and leaves an active Source intact', async () => {
  const build = await manifest();
  const descriptor = {
    buildId: build.buildId,
    packageName: build.packageName,
    repoId: build.repoId,
    version: build.version,
    sourceIds: build.sourceIds,
    manifestPath: options.manifestPath,
    sources: build.sources,
  };
  const fetcher = vi.fn(async (input: RequestInfo | URL) => {
    const path = new URL(String(input)).pathname;
    if (path === '/extensions/index.json')
      return Response.json({
        schemaVersion: 1,
        repoId: catalog.repoId,
        builds: [descriptor],
      });
    if (path === options.manifestPath) return Response.json(build);
    if (path === build.bundle.path)
      return new Response(encodedBytes, {
        headers: { 'Content-Type': 'application/gzip' },
      });
    throw new Error('Unexpected path ' + path);
  });
  const cache = new ExtensionArtifactCache(crypto.randomUUID());
  const loader = new VerifiedLoader(
    'https://read.example.com',
    fetcher,
    undefined,
    cache,
  );
  const { manager, driver, workers } = await setup(
    undefined,
    undefined,
    undefined,
    loader,
  );
  const apiWindow = { addEventListener: vi.fn() };
  vi.stubGlobal('window', apiWindow);
  const api = installRuntime(manager);
  const response = parseControlResponse(
    await api.control(
      encodeControlRequest(
        create(pb.ControlRequestSchema, {
          requestId: 'prepare-control',
          command: {
            case: 'prepareBuild',
            value: {
              preparationId: 'prepare-first',
              build: descriptor,
              catalog,
            },
          },
        }),
      ),
    ),
  );
  expect(response.result.case).toBe('preparedBuild');
  expect(workers).toHaveLength(0);
  expect(driver.open).not.toHaveBeenCalled();
  expect(driver.invoke).not.toHaveBeenCalled();
  expect((await manager.extensionCache()).artifacts[0]?.sha256).toBe(
    build.bundle.sha256,
  );
  const digest = vi.spyOn(crypto.subtle, 'digest');
  await expect(
    loader.artifact(catalog, build.bundle, new AbortController().signal, true),
  ).resolves.toHaveLength(build.bundle.size);
  expect(digest).not.toHaveBeenCalled();
  const session = await manager.open(options);
  await expect(
    manager.forgetExtensionArtifact(build.bundle.sha256),
  ).rejects.toMatchObject({ code: 'storage_busy' });
  fetcher.mockResolvedValueOnce(new Response('unavailable', { status: 503 }));
  await expect(
    manager.prepareBuild(
      create(pb.PrepareBuildRequestSchema, {
        catalog,
        preparationId: 'prepare-failure',
        build: descriptor,
      }),
    ),
  ).rejects.toMatchObject({ code: 'runtime_lost' });
  expect(workers[0]?.terminated).toBe(false);
  await expect(
    manager.invoke(call('after-preparation-failure', session.generation)),
  ).resolves.toMatchObject({ generation: session.generation });
  await manager.closeBuild(
    create(pb.CloseBuildRequestSchema, {
      buildId: session.buildId,
      generation: session.generation,
    }),
  );
  await manager.forgetExtensionArtifact(build.bundle.sha256);
  expect((await manager.extensionCache()).totalBytes).toBe(0);
  await manager.dispose();
  const open = vi.spyOn(indexedDB, 'open');
  await expect(manager.extensionCache()).rejects.toMatchObject({
    code: 'runtime_lost',
  });
  await expect(
    manager.forgetExtensionArtifact(build.bundle.sha256),
  ).rejects.toMatchObject({ code: 'runtime_lost' });
  expect(open).not.toHaveBeenCalled();
});

test('forget cancels and drains preparation before removal so a late download cannot restore deleted bytes', async () => {
  const build = await manifest();
  const descriptor = {
    buildId: build.buildId,
    packageName: build.packageName,
    repoId: build.repoId,
    version: build.version,
    sourceIds: build.sourceIds,
    manifestPath: options.manifestPath,
    sources: build.sources,
  };
  const started = deferred<void>();
  const cancelled = vi.fn();
  let block = true;
  const fetcher = vi.fn(async (input: RequestInfo | URL) => {
    const path = new URL(String(input)).pathname;
    if (path === '/extensions/index.json')
      return Response.json({
        schemaVersion: 1,
        repoId: catalog.repoId,
        builds: [descriptor],
      });
    if (path === options.manifestPath) return Response.json(build);
    if (block)
      return new Response(
        new ReadableStream<Uint8Array>(
          {
            pull() {
              started.resolve();
              return new Promise<void>(() => {});
            },
            cancel: cancelled,
          },
          { highWaterMark: 0 },
        ),
        { headers: { 'Content-Type': 'application/gzip' } },
      );
    return new Response(encodedBytes, {
      headers: { 'Content-Type': 'application/gzip' },
    });
  });
  const cache = new ExtensionArtifactCache(crypto.randomUUID());
  const loader = new VerifiedLoader(
    'https://read.example.com',
    fetcher,
    undefined,
    cache,
  );
  const { manager, workers } = await setup(
    undefined,
    undefined,
    undefined,
    loader,
  );
  const preparation = manager.prepareBuild(
    create(pb.PrepareBuildRequestSchema, {
      catalog,
      preparationId: 'to-cancel',
      build: descriptor,
    }),
  );
  const rejected = expect(preparation).rejects.toMatchObject({
    code: 'cancelled',
  });
  await started.promise;
  await manager.forgetExtensionArtifact(build.bundle.sha256);
  await rejected;
  expect(cancelled).toHaveBeenCalledOnce();
  expect((await manager.extensionCache()).artifacts).toEqual([]);
  expect(workers).toHaveLength(0);
  block = false;
  await manager.prepareBuild(
    create(pb.PrepareBuildRequestSchema, {
      catalog,
      preparationId: 'new-preparation',
      build: descriptor,
    }),
  );
  await manager.cancelPreparation('to-cancel');
  expect((await manager.extensionCache()).artifacts).toHaveLength(1);
});

test('disposing rejects new work while cancellation drains and rejects a late preparation result', async () => {
  const build = await manifest();
  const descriptor = {
    buildId: build.buildId,
    packageName: build.packageName,
    repoId: build.repoId,
    version: build.version,
    sourceIds: build.sourceIds,
    manifestPath: options.manifestPath,
    sources: build.sources,
  };
  const loader = new VerifiedLoader('https://read.example.com', async () =>
    Response.json(build),
  );
  const drain = deferred<{
    catalog: typeof catalog;
    build: typeof descriptor;
    bundleSha256: string;
    byteLength: number;
  }>();
  const aborted = deferred<void>();
  vi.spyOn(loader, 'prepare').mockImplementation(
    async (_catalog, _build, signal) => {
      signal.addEventListener('abort', () => aborted.resolve(), { once: true });
      return drain.promise;
    },
  );
  const { manager } = await setup(undefined, undefined, undefined, loader);
  const session = await manager.open(options);
  const preparation = manager.prepareBuild(
    create(pb.PrepareBuildRequestSchema, {
      catalog,
      preparationId: 'dispose-preparation',
      build: descriptor,
    }),
  );
  const failure = expect(preparation).rejects.toMatchObject({
    code: 'cancelled',
  });
  const disposing = manager.dispose();
  await aborted.promise;
  await expect(
    manager.invoke(call('during-disposal', session.generation)),
  ).rejects.toMatchObject({ code: 'runtime_lost' });
  await expect(
    manager.acquireImage(
      create(pb.AcquireImageSchema, {
        requestId: 'image-during-disposal',
        generation: session.generation,
        sourceId: session.sources[0]!.id,
        pageSessionId: 'page-session',
        pageKey: 'page-key',
      }),
    ),
  ).rejects.toMatchObject({ code: 'runtime_lost' });
  drain.resolve({
    catalog,
    build: descriptor,
    bundleSha256: build.bundle.sha256,
    byteLength: build.bundle.size,
  });
  await failure;
  await disposing;
});

test('preparation deadline cancels a stalled body without terminating an active Source', async () => {
  const build = await manifest();
  const descriptor = {
    buildId: build.buildId,
    packageName: build.packageName,
    repoId: build.repoId,
    version: build.version,
    sourceIds: build.sourceIds,
    manifestPath: options.manifestPath,
    sources: build.sources,
  };
  const started = deferred<void>();
  const cancelled = vi.fn();
  const fetcher = vi.fn(async (input: RequestInfo | URL) => {
    const path = new URL(String(input)).pathname;
    if (path === '/extensions/index.json')
      return Response.json({
        schemaVersion: 1,
        repoId: catalog.repoId,
        builds: [descriptor],
      });
    if (path === options.manifestPath) return Response.json(build);
    return new Response(
      new ReadableStream<Uint8Array>(
        {
          pull() {
            started.resolve();
            return new Promise<void>(() => {});
          },
          cancel: cancelled,
        },
        { highWaterMark: 0 },
      ),
      { headers: { 'Content-Type': 'application/gzip' } },
    );
  });
  const cache = new ExtensionArtifactCache(crypto.randomUUID());
  const loader = new VerifiedLoader(
    'https://read.example.com',
    fetcher,
    undefined,
    cache,
  );
  const { manager, workers } = await setup(
    undefined,
    undefined,
    undefined,
    loader,
  );
  const session = await manager.open(options);
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  const preparation = manager.prepareBuild(
    create(pb.PrepareBuildRequestSchema, {
      catalog,
      preparationId: 'deadline-preparation',
      build: descriptor,
    }),
  );
  const failure = expect(preparation).rejects.toMatchObject({
    code: 'timeout',
  });
  await started.promise;
  await vi.advanceTimersByTimeAsync(60_000);
  await failure;
  expect(cancelled).toHaveBeenCalledOnce();
  expect(workers[0]?.terminated).toBe(false);
  expect((await manager.extensionCache()).artifacts).toEqual([]);
  await expect(
    manager.invoke(call('after-deadline', session.generation)),
  ).resolves.toMatchObject({ generation: session.generation });
});

test('a transient page-session close failure can retry the original identity and only a successful ACK is retained', async () => {
  const { manager, driver, workers, session, image, request } =
    await setupImages();
  await manager.releaseImage({
    resourceId: image.resourceId,
    generation: session.generation,
  });
  driver.closePageSession!.mockRejectedValueOnce(
    new RuntimeFailure('source_error', 'Temporary cleanup failure', true),
  );
  const input = {
    pageSessionId: request.pageSessionId,
    generation: session.generation,
  };
  await expect(manager.closePageSession(input)).rejects.toMatchObject({
    code: 'source_error',
  });
  expect(workers[0]?.terminated).toBe(false);
  const retry = manager.closePageSession(input);
  expect(manager.closePageSession(input)).toBe(retry);
  await expect(retry).resolves.toEqual({ closed: true });
  await expect(manager.closePageSession(input)).resolves.toEqual({
    closed: true,
  });
  expect(driver.closePageSession).toHaveBeenCalledTimes(2);
  expect(driver.closePageSession!.mock.calls.map(([id]) => id)).toEqual([
    request.pageSessionId,
    request.pageSessionId,
  ]);
  await expect(
    manager.invoke(call('after-cleanup-retry', session.generation)),
  ).resolves.toMatchObject({ generation: session.generation });
});

test('failed shutdown remains unacknowledged and an explicit rebuild confirms reset before removing the cached artifact', async () => {
  const build = await manifest();
  const cache = new ExtensionArtifactCache(crypto.randomUUID());
  await cache.storeVerified(build.bundle, bytes);
  const loader = new VerifiedLoader(
    'https://read.example.com',
    async () => Response.json(build),
    undefined,
    cache,
  );
  const { manager, driver, workers } = await setup(
    undefined,
    undefined,
    undefined,
    loader,
  );
  const session = await manager.open(options);
  const input = create(pb.CloseBuildRequestSchema, {
    buildId: session.buildId,
    generation: session.generation,
  });
  driver.close.mockRejectedValueOnce(
    new RuntimeFailure('source_error', 'Shutdown did not finish'),
  );
  await expect(manager.closeBuild(input)).rejects.toMatchObject({
    code: 'source_error',
  });
  expect(workers[0]?.terminated).toBe(true);
  await expect(manager.closeBuild(input)).rejects.toMatchObject({
    code: 'runtime_lost',
  });
  vi.stubGlobal('window', { addEventListener: vi.fn() });
  const api = installRuntime(manager);
  const reset = parseControlResponse(
    await api.control(
      encodeControlRequest(
        create(pb.ControlRequestSchema, {
          requestId: 'recover-after-failed-shutdown',
          command: { case: 'rebuild', value: {} },
        }),
      ),
    ),
  );
  expect(reset.result.case).toBe('completed');
  await manager.forgetExtensionArtifact(build.bundle.sha256);
  expect((await manager.extensionCache()).artifacts).toEqual([]);
  await expect(manager.closeBuild(input)).rejects.toMatchObject({
    code: 'runtime_lost',
  });
  const next = await manager.open(options);
  expect(next.generation).not.toBe(session.generation);
  await expect(
    manager.invoke(call('after-explicit-reset', next.generation)),
  ).resolves.toMatchObject({ generation: next.generation });
});

test('the same repository ID at a new catalog origin cannot inherit files or Cookies', async () => {
  const { manager, workerUrls } = await setup();
  const first = await manager.open(options);
  const replacement = await manager.open({
    ...options,
    catalog: {
      ...catalog,
      catalogUrl: 'https://mirror.example/extensions/index.json',
    },
  });
  expect(replacement.generation).not.toBe(first.generation);
  expect(replacement.catalog.catalogUrl).toBe(
    'https://mirror.example/extensions/index.json',
  );
  expect(workerUrls[1]?.searchParams.get('fsNamespace')).not.toBe(
    workerUrls[0]?.searchParams.get('fsNamespace'),
  );
});

test('a session ACK from another catalog is rejected before Source readiness', async () => {
  const { manager, workers, driver } = await setup();
  driver.open.mockImplementationOnce(async () => {
    const worker = workers[0]!;
    const emit = worker.emit.bind(worker);
    worker.emit = (data) => {
      const response = workerResponseSchema.parse(data);
      if (response.result.case === 'session')
        response.result.value.catalog = create(pb.CatalogReferenceSchema, {
          ...catalog,
          catalogUrl: 'https://foreign.example/extensions/index.json',
        });
      emit(messageJson(pb.WorkerResponseSchema, response));
    };
    return [{ id: '9223372036854775806', name: 'Test', lang: 'en' }];
  });
  await expect(manager.open(options)).rejects.toMatchObject({
    code: 'protocol_error',
  });
  expect(workers[0]?.terminated).toBe(true);
});

test('Native namespaces isolate the same subject and external repository across API deployments', async () => {
  const external = {
    ...options,
    catalog: {
      ...catalog,
      catalogUrl: 'https://external.example/extensions/index.json',
    },
  };
  const first = await setup();
  const second = await setup(
    undefined,
    undefined,
    undefined,
    undefined,
    'https://another-app.example',
  );
  await first.manager.open(external);
  await second.manager.open(external);
  expect(first.workerUrls[0]?.searchParams.get('fsNamespace')).not.toBe(
    second.workerUrls[0]?.searchParams.get('fsNamespace'),
  );
});
