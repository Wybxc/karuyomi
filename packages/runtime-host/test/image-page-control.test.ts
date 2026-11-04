import { afterEach, expect, test, vi } from 'vitest';
import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import {
  encodeControlRequest,
  encodedImageSchema,
  parseControlResponse,
  type AcquireImage,
  type ControlRequest,
  type SourcePayload,
} from '@karuyomi/contracts';
import type {
  ImageTileOptions,
  ImageTileEvent,
} from '../../../runtime/image-codec/client.ts';
import type { ImageTileTerminal } from '../../../runtime/image-codec/worker-protocol.ts';
import { SourceRuntimeManager, type WorkerEndpoint } from '../src/manager.js';
import type { ImageTileDecodeSession } from '../src/image-tile-store.js';
import { ImageResourceStore } from '../src/image-resources.js';
import { ImageSink } from '../src/image-channel.js';
import { WorkerRuntime } from '../src/worker-runtime.js';
import type { RuntimeDriver } from '../src/teavm-driver.js';
import { VerifiedLoader } from '../src/verified-loader.js';
import { createHello } from '../src/hello.js';
import { installRuntime } from '../src/host-api.js';
import { manifest } from './fixtures.js';
import { deferred, pngHeader } from './image-fixtures.js';

class WorkerHarness implements WorkerEndpoint {
  onmessage: WorkerEndpoint['onmessage'] = null;
  onerror: WorkerEndpoint['onerror'] = null;
  readonly runtime: WorkerRuntime;
  constructor(driver: RuntimeDriver) {
    this.runtime = new WorkerRuntime(driver, (data) =>
      this.onmessage?.(new MessageEvent('message', { data })),
    );
    queueMicrotask(() =>
      this.onmessage?.(
        new MessageEvent('message', {
          data: createHello(this.runtime.workerInstanceId),
        }),
      ),
    );
  }
  postMessage(command: unknown, transfer: Transferable[] = []) {
    void this.runtime.receive(
      command,
      transfer.filter(
        (value): value is MessagePort => value instanceof MessagePort,
      ),
    );
  }
  terminate() {}
}
interface Scenario {
  tail?: ReturnType<typeof deferred<void>>;
  stopped?: ReturnType<typeof deferred<void>>;
  failed?: boolean;
  keepEncodedOwner?: boolean;
}
const cleanup: Array<() => Promise<void>> = [];
afterEach(async () => {
  for (const close of cleanup.splice(0)) await close();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});
async function fixture(scenario: Scenario = {}) {
  const build = await manifest();
  const sourceStore = new ImageResourceStore({ orientation: async () => 1 });
  const inputs: ImageTileOptions[] = [];
  const trace: string[] = [];
  const prepare = vi.fn(async () => ({
    workerUrl: new URL('blob:https://reader.example/worker'),
    decoder: {
      moduleUrl: 'blob:https://reader.example/decoder',
      wasmBinary: new Uint8Array([1]),
    },
    encoder: {
      moduleUrl: 'blob:https://reader.example/encoder',
      wasmBinary: new Uint8Array([2]),
    },
    release() {
      trace.push('materials-released');
    },
  }));
  const decode = (options: ImageTileOptions): ImageTileDecodeSession => {
    inputs.push(options);
    let cancelled = false;
    const abort = deferred<void>();
    const done = deferred<ImageTileTerminal>();
    const cancel = () => {
      cancelled = true;
      abort.resolve();
    };
    options.signal?.addEventListener('abort', cancel, { once: true });
    const terminal = (): ImageTileTerminal => ({
      status: cancelled ? 'cancelled' : scenario.failed ? 'failed' : 'complete',
      invalidatesTiles: cancelled || !!scenario.failed,
      forced: false,
      decoder: null,
      encoder: null,
      error: scenario.failed ? { name: 'Error', message: 'bad tail' } : null,
    });
    const iterator = (async function* (): AsyncGenerator<ImageTileEvent> {
      trace.push('start');
      try {
        yield {
          kind: 'header',
          format: 'png',
          sourceWidth: 16,
          sourceHeight: 1024,
          width: 16,
          height: 1024,
          rowBytes: 64,
          denominator: 1,
        };
        for (let index = 0; index < 4 && !cancelled; index++) {
          yield {
            kind: 'tile',
            id: `${options.requestId}:${index}`,
            index,
            x: 0,
            y: index * 256,
            width: 16,
            height: 256,
            sourceRect: { x: 0, y: index * 256, width: 16, height: 256 },
            byteLength: 12,
            mimeType: 'image/png',
            provisional: true,
            png: new Blob([new Uint8Array(12)], { type: 'image/png' }),
          };
        }
        if (scenario.tail)
          await Promise.race([scenario.tail.promise, abort.promise]);
        yield { kind: 'terminal', ...terminal() };
      } finally {
        if (scenario.stopped) await scenario.stopped.promise;
        trace.push('stopped');
        options.signal?.removeEventListener('abort', cancel);
        done.resolve(terminal());
      }
    })();
    return {
      completion: done.promise,
      [Symbol.asyncIterator]: () => iterator,
      cancel: async () => {
        cancel();
        await done.promise;
      },
    };
  };
  const invoke = vi.fn(async (): Promise<SourcePayload> => ({
    case: 'mangaPage',
    value: create(pb.MangaPageSchema),
  }));
  const sinks: ImageSink[] = [];
  const acquire = vi.fn(
    async (
      _source: string,
      _session: string,
      _page: string,
      port: MessagePort,
      id: string,
    ) => {
      const sink = new ImageSink(port, id, () => {}, true);
      sinks.push(sink);
      const handle = sink.open('image/png');
      await sink.write(handle, pngHeader(16, 1024));
      return encodedImageSchema.parse(JSON.parse(await sink.close(handle)));
    },
  );
  const manager = new SourceRuntimeManager(
    new URL('https://reader.example/runtime/worker.js'),
    () =>
      new WorkerHarness({
        open: async () => [
          { id: build.sourceIds[0]!, name: 'fixture', lang: 'en' },
        ],
        invoke,
        acquireEncodedImage: acquire,
        closePageSession: async () => ({ closed: true as const }),
        close: async () => {},
      }),
    new VerifiedLoader('https://reader.example', async () =>
      Response.json(build),
    ),
    1000,
    { store: sourceStore, tiles: { prepare, decode } },
  );
  cleanup.push(async () => {
    scenario.tail?.resolve();
    scenario.stopped?.resolve();
    await manager.dispose();
    sinks.forEach((sink) => sink.dispose());
  });
  const session = await manager.open({
    manifestPath: '/extensions/builds/test-build/manifest.json',
    identity: 'owner',
  });
  vi.stubGlobal('window', { addEventListener: vi.fn() });
  const api = installRuntime(manager);
  let sequence = 0;
  const control = async (command: ControlRequest['command']) =>
    parseControlResponse(
      await api.control(
        encodeControlRequest(
          create(pb.ControlRequestSchema, {
            requestId: `control-${++sequence}`,
            command,
          }),
        ),
      ),
    );
  const request: AcquireImage = {
    requestId: 'source-image',
    sourceId: build.sourceIds[0]!,
    pageSessionId: 'chapter',
    pageKey: 'p-0',
    generation: session.generation,
  };
  const acquired = await control({
    case: 'acquireEncodedImage',
    value: create(pb.AcquireImageSchema, request),
  });
  if (acquired.result.case !== 'encodedImage')
    throw new Error(JSON.stringify(acquired));
  const image = acquired.result.value;
  const opened = await control({
    case: 'openImagePage',
    value: create(pb.OpenImagePageSchema, {
      resourceId: image.resourceId,
      generation: session.generation,
    }),
  });
  if (opened.result.case !== 'imagePage') throw new Error('image page missing');
  const page = opened.result.value;
  if (!scenario.keepEncodedOwner)
    await control({
      case: 'releaseImage',
      value: create(pb.ReleaseImageSchema, {
        resourceId: image.resourceId,
        generation: session.generation,
      }),
    });
  const demand = (windowId = 'window-1', sourceY = 0, sourceEndY = 256) =>
    control({
      case: 'requestImageWindow',
      value: create(pb.RequestImageWindowSchema, {
        pageId: page.pageId,
        generation: page.generation,
        windowId,
        sourceY,
        sourceEndY,
        denominator: 1,
      }),
    });
  const wait = (snapshot: pb.ImageWindowSnapshot, timeoutMs = 2000) =>
    control({
      case: 'waitImageWindow',
      value: create(pb.WaitImageWindowSchema, {
        pageId: page.pageId,
        generation: page.generation,
        windowId: snapshot.windowId,
        afterRevision: snapshot.revision,
        timeoutMs,
      }),
    });
  const observe = async (
    until: (snapshot: pb.ImageWindowSnapshot) => boolean,
    start?: pb.ControlResponse,
  ) => {
    let response = start ?? (await demand());
    for (let index = 0; index < 30; index++) {
      if (response.result.case !== 'imageWindow')
        throw new Error(JSON.stringify(response));
      const snapshot = response.result.value;
      if (until(snapshot)) return snapshot;
      response = await wait(snapshot);
    }
    throw new Error('image window did not reach its observation');
  };
  const close = () =>
    control({
      case: 'closeImagePage',
      value: create(pb.CloseImagePageSchema, {
        pageId: page.pageId,
        generation: page.generation,
      }),
    });
  const release = (leaseId: string, generation = page.generation) =>
    control({
      case: 'releaseImageTile',
      value: create(pb.ReleaseImageTileSchema, { leaseId, generation }),
    });
  return {
    manager,
    sourceStore,
    page,
    image,
    control,
    demand,
    observe,
    wait,
    close,
    release,
    inputs,
    trace,
    acquire,
    invoke,
    prepare,
    request,
  };
}

test('formal controls compose one Source body, stable tile URLs and an independent Source slot', async () => {
  const tail = deferred<void>();
  const f = await fixture({ tail });
  const pending = await f.observe((snapshot) => snapshot.tiles.length === 1);
  const first = pending.tiles[0]!;
  expect(first.provisional).toBe(true);
  const repeated = await f.demand();
  expect(repeated.result).toMatchObject({
    case: 'imageWindow',
    value: {
      tiles: [
        { leaseId: first.leaseId, resource: { url: first.resource!.url } },
      ],
    },
  });
  const secondOpen = await f.control({
    case: 'openImagePage',
    value: create(pb.OpenImagePageSchema, {
      resourceId: f.image.resourceId,
      generation: f.page.generation,
    }),
  });
  expect(secondOpen.result).toMatchObject({
    case: 'imagePage',
    value: { pageId: f.page.pageId },
  });
  await f.manager.invoke(
    create(pb.SourceCallSchema, {
      sourceId: f.request.sourceId,
      generation: f.request.generation,
      requestId: 'parallel-metadata',
      request: { case: 'popular', value: { page: 1 } },
    }),
  );
  expect(f.invoke).toHaveBeenCalledOnce();
  expect(f.acquire).toHaveBeenCalledOnce();
  tail.resolve();
  const complete = await f.observe(
    (snapshot) => snapshot.state === pb.ImageWindowState.COMPLETE,
  );
  expect(complete.tiles[0]).toMatchObject({
    leaseId: first.leaseId,
    provisional: false,
    resource: { url: first.resource!.url },
  });
  expect(f.inputs).toHaveLength(1);
  expect(f.trace).toEqual(['start', 'stopped', 'materials-released']);
  await f.close();
  expect(f.sourceStore.snapshot.resources).toBe(0);
  expect(f.manager.imagePageUsage).toMatchObject({
    pages: 0,
    leasedTiles: 1,
    displayUrls: 1,
  });
  await f.release(first.leaseId);
  expect(f.manager.imagePageUsage).toMatchObject({
    cachedBytes: 0,
    leasedTiles: 0,
    displayUrls: 0,
  });
});

test('observation deadlines preserve work, and window replacement cancels only the old observation', async () => {
  const tail = deferred<void>();
  const f = await fixture({ tail });
  const pending = await f.observe((snapshot) => snapshot.tiles.length === 1);
  const idle = await f.wait(pending, 5);
  expect(idle.result).toMatchObject({
    case: 'imageWindow',
    value: { revision: pending.revision, state: pb.ImageWindowState.PENDING },
  });
  const waiting = f.wait(pending);
  await f.demand('window-2', 768, 1024);
  expect((await waiting).result).toMatchObject({
    case: 'error',
    value: { code: pb.RuntimeErrorCode.CANCELLED },
  });
  expect((await f.demand('window-1')).result).toMatchObject({
    case: 'error',
    value: { code: pb.RuntimeErrorCode.PROTOCOL_ERROR },
  });
  expect((await f.demand('window-2', 0, 256)).result).toMatchObject({
    case: 'error',
    value: { code: pb.RuntimeErrorCode.PROTOCOL_ERROR },
  });
  expect(f.manager.imagePageUsage?.waits).toBe(0);
  expect(f.inputs).toHaveLength(1);
});

test('close waits for codec termination and retains published display quota until release ACK', async () => {
  const tail = deferred<void>();
  const stopped = deferred<void>();
  const f = await fixture({ tail, stopped });
  const pending = await f.observe((snapshot) => snapshot.tiles.length === 1);
  const lease = pending.tiles[0]!;
  let closed = false;
  const closing = f.close().then((value) => {
    closed = true;
    return value;
  });
  await vi.waitFor(() =>
    expect(f.manager.imagePageUsage?.activeDecodes).toBe(1),
  );
  expect(closed).toBe(false);
  expect(f.sourceStore.snapshot.resources).toBe(1);
  expect(f.trace).not.toContain('materials-released');
  stopped.resolve();
  expect((await closing).result.case).toBe('closed');
  expect(f.sourceStore.snapshot.resources).toBe(0);
  expect(f.manager.imagePageUsage).toMatchObject({
    activeDecodes: 0,
    leasedTiles: 1,
    cachedBytes: 12,
    displayUrls: 1,
  });
  await f.release(lease.leaseId, 'foreign-generation');
  expect(f.manager.imagePageUsage?.leasedTiles).toBe(1);
  const revoke = vi.spyOn(URL, 'revokeObjectURL');
  await f.release(lease.leaseId);
  await f.release(lease.leaseId);
  expect(revoke).toHaveBeenCalledExactlyOnceWith(lease.resource!.url);
  expect(f.manager.imagePageUsage).toMatchObject({
    leasedTiles: 0,
    cachedBytes: 0,
  });
});

test('late bad tails invalidate published descriptors while unobserved leases are reclaimed without an ACK', async () => {
  const tail = deferred<void>();
  const f = await fixture({ tail, failed: true });
  const pending = await f.observe((snapshot) => snapshot.tiles.length === 1);
  tail.resolve();
  const failed = await f.observe(
    (snapshot) => snapshot.state === pb.ImageWindowState.FAILED,
  );
  expect(failed.invalidatedLeaseIds).toEqual([pending.tiles[0]!.leaseId]);
  expect(failed.tiles).toEqual([]);
  expect(f.manager.imagePageUsage?.leasedTiles).toBe(1);
  await f.release(pending.tiles[0]!.leaseId);
  await f.close();
  expect(f.manager.imagePageUsage?.cachedBytes).toBe(0);

  const unobserved = await fixture();
  await unobserved.demand();
  await vi.waitFor(() =>
    expect(unobserved.trace).toContain('materials-released'),
  );
  expect(unobserved.manager.imagePageUsage).toMatchObject({
    leasedTiles: 1,
    displayUrls: 0,
  });
  await unobserved.close();
  expect(unobserved.manager.imagePageUsage).toMatchObject({
    leasedTiles: 0,
    cachedBytes: 0,
  });
});

test('generation invalidation closes codec owners and still accepts old-generation display cleanup', async () => {
  const f = await fixture();
  const complete = await f.observe(
    (snapshot) => snapshot.state === pb.ImageWindowState.COMPLETE,
  );
  await f.manager.rebuild();
  expect(f.sourceStore.snapshot.resources).toBe(0);
  expect(f.manager.imagePageUsage).toMatchObject({
    pages: 0,
    leasedTiles: 1,
    displayUrls: 1,
  });
  expect((await f.demand('late')).result).toMatchObject({
    case: 'error',
    value: { code: pb.RuntimeErrorCode.RUNTIME_LOST },
  });
  await f.release(complete.tiles[0]!.leaseId);
  expect(f.manager.imagePageUsage?.leasedTiles).toBe(0);
  await f.manager.open({
    manifestPath: '/extensions/builds/test-build/manifest.json',
    identity: 'new-owner',
  });
  expect(f.manager.imagePageUsage?.pages).toBe(0);
});

test('foreign pages and future revisions are rejected, and wait concurrency remains bounded', async () => {
  const tail = deferred<void>();
  const f = await fixture({ tail });
  const pending = await f.observe((snapshot) => snapshot.tiles.length === 1);
  const future = await f.control({
    case: 'waitImageWindow',
    value: create(pb.WaitImageWindowSchema, {
      pageId: f.page.pageId,
      generation: f.page.generation,
      windowId: pending.windowId,
      afterRevision: pending.revision + 1,
      timeoutMs: 5,
    }),
  });
  expect(future.result).toMatchObject({
    case: 'error',
    value: { code: pb.RuntimeErrorCode.PROTOCOL_ERROR },
  });
  const foreign = await f.control({
    case: 'requestImageWindow',
    value: create(pb.RequestImageWindowSchema, {
      pageId: 'foreign',
      generation: f.page.generation,
      windowId: 'foreign-window',
      sourceEndY: 256,
      denominator: 1,
    }),
  });
  expect(foreign.result).toMatchObject({
    case: 'error',
    value: { code: pb.RuntimeErrorCode.RUNTIME_LOST },
  });
  const waits = Array.from({ length: 32 }, () => f.wait(pending));
  expect(f.manager.imagePageUsage?.waits).toBe(32);
  expect((await f.wait(pending)).result).toMatchObject({
    case: 'error',
    value: { code: pb.RuntimeErrorCode.LIMIT_EXCEEDED },
  });
  await f.close();
  expect(
    (await Promise.all(waits)).every(
      (response) => response.result.case === 'error',
    ),
  ).toBe(true);
  expect(f.manager.imagePageUsage?.waits).toBe(0);
});

test('out-of-page windows do not start codec work or replace the current valid demand', async () => {
  const f = await fixture();
  expect((await f.demand('outside', 1024, 1025)).result).toMatchObject({
    case: 'error',
    value: { code: pb.RuntimeErrorCode.PROTOCOL_ERROR },
  });
  expect(f.prepare).not.toHaveBeenCalled();
  const complete = await f.observe(
    (snapshot) => snapshot.state === pb.ImageWindowState.COMPLETE,
  );
  expect((await f.demand('past-tail', 1000, 1025)).result).toMatchObject({
    case: 'error',
    value: { code: pb.RuntimeErrorCode.PROTOCOL_ERROR },
  });
  const repeated = await f.demand();
  expect(repeated.result).toMatchObject({
    case: 'imageWindow',
    value: {
      revision: complete.revision,
      tiles: [{ leaseId: complete.tiles[0]!.leaseId }],
    },
  });
});

test('a bad tail before the first tile observation leaves no hidden lease or invalidation ACK', async () => {
  const f = await fixture({ failed: true });
  await f.demand();
  await vi.waitFor(() => expect(f.trace).toContain('materials-released'));
  expect(f.manager.imagePageUsage).toMatchObject({
    leasedTiles: 1,
    displayUrls: 0,
  });
  const failed = await f.observe(
    (snapshot) => snapshot.state === pb.ImageWindowState.FAILED,
  );
  expect(failed.invalidatedLeaseIds).toEqual([]);
  expect(f.manager.imagePageUsage).toMatchObject({
    leasedTiles: 0,
    cachedBytes: 0,
  });
  await f.close();
  expect(f.sourceStore.snapshot.resources).toBe(0);
});

test('final host disposal shares one completion and reclaims disconnected displays only after codec termination', async () => {
  const tail = deferred<void>();
  const stopped = deferred<void>();
  const f = await fixture({ tail, stopped });
  await f.observe((snapshot) => snapshot.tiles.length === 1);
  let disposed = false;
  const first = f.manager.dispose();
  const again = f.manager.dispose();
  expect(again).toBe(first);
  void first.then(() => {
    disposed = true;
  });
  await Promise.resolve();
  expect(disposed).toBe(false);
  expect(f.manager.imagePageUsage?.leasedTiles).toBe(1);
  expect(f.sourceStore.snapshot.resources).toBe(1);
  stopped.resolve();
  await first;
  expect(f.sourceStore.snapshot.resources).toBe(0);
  expect(f.manager.imagePageUsage).toMatchObject({
    activeDecodes: 0,
    pages: 0,
    leasedTiles: 0,
    cachedBytes: 0,
    displayUrls: 0,
  });
});

test('a closing encoded owner cannot be reopened until its codec terminates; later opens remain idempotent', async () => {
  const tail = deferred<void>();
  const stopped = deferred<void>();
  const f = await fixture({ tail, stopped, keepEncodedOwner: true });
  await f.observe((snapshot) => snapshot.tiles.length === 1);
  const closing = f.close();
  const open = () =>
    f.control({
      case: 'openImagePage',
      value: create(pb.OpenImagePageSchema, {
        resourceId: f.image.resourceId,
        generation: f.page.generation,
      }),
    });
  expect((await open()).result).toMatchObject({
    case: 'error',
    value: { code: pb.RuntimeErrorCode.CANCELLED },
  });
  stopped.resolve();
  await closing;
  const next = await open();
  if (next.result.case !== 'imagePage')
    throw new Error('replacement page missing');
  expect(next.result.value.pageId).not.toBe(f.page.pageId);
  expect((await open()).result).toMatchObject({
    case: 'imagePage',
    value: { pageId: next.result.value.pageId },
  });
  expect(f.manager.imagePageUsage?.pages).toBe(1);
});

test('failed-page release ACK advances revision and wakes its observation without decoding again', async () => {
  const tail = deferred<void>();
  const f = await fixture({ tail, failed: true });
  const pending = await f.observe((snapshot) => snapshot.tiles.length === 1);
  tail.resolve();
  const failed = await f.observe(
    (snapshot) => snapshot.state === pb.ImageWindowState.FAILED,
  );
  let observed = false;
  const waiting = f.wait(failed).then((response) => {
    observed = true;
    return response;
  });
  expect(f.manager.imagePageUsage?.waits).toBe(1);
  await f.release(pending.tiles[0]!.leaseId);
  await vi.waitFor(() => expect(observed).toBe(true), {
    timeout: 100,
    interval: 1,
  });
  const response = await waiting;
  expect(response.result.case).toBe('imageWindow');
  if (response.result.case !== 'imageWindow')
    throw new Error('failed window observation missing');
  expect(response.result.value.revision).toBeGreaterThan(failed.revision);
  expect(response.result.value.invalidatedLeaseIds).toEqual([]);
  expect(response.result.value.state).toBe(pb.ImageWindowState.FAILED);
  expect(f.manager.imagePageUsage?.waits).toBe(0);
  expect(f.inputs).toHaveLength(1);
});

test('a failed batch of tile URLs releases every unpublished pin and permits the same-window retry', async () => {
  const f = await fixture();
  const firstDemand = await f.demand('wide', 0, 768);
  await vi.waitFor(() => expect(f.trace).toContain('materials-released'));
  expect(f.manager.imagePageUsage).toMatchObject({
    leasedTiles: 3,
    displayUrls: 0,
  });
  const create = URL.createObjectURL.bind(URL);
  const urls: string[] = [];
  const createSpy = vi
    .spyOn(URL, 'createObjectURL')
    .mockImplementation((blob) => {
      if (urls.length === 1) throw new Error('object URL creation failed');
      const url = create(blob);
      urls.push(url);
      return url;
    });
  const revoke = vi.spyOn(URL, 'revokeObjectURL');
  const failed = await f.demand('wide', 0, 768);
  expect(failed.result).toMatchObject({
    case: 'error',
    value: { code: pb.RuntimeErrorCode.SOURCE_ERROR },
  });
  expect(revoke).toHaveBeenCalledExactlyOnceWith(urls[0]);
  expect(f.manager.imagePageUsage).toMatchObject({
    leasedTiles: 0,
    leasedPixels: 0,
    displayUrls: 0,
    cachedBytes: 36,
  });
  if (firstDemand.result.case !== 'imageWindow')
    throw new Error('initial window missing');
  expect((await f.wait(firstDemand.result.value)).result).toMatchObject({
    case: 'error',
    value: { code: pb.RuntimeErrorCode.SOURCE_ERROR, retryable: true },
  });
  createSpy.mockImplementation(create);
  const recovered = await f.demand('wide', 0, 768);
  expect(recovered.result).toMatchObject({
    case: 'imageWindow',
    value: { windowId: 'wide', state: pb.ImageWindowState.COMPLETE },
  });
  if (recovered.result.case !== 'imageWindow')
    throw new Error('recovered window missing');
  expect(recovered.result.value.tiles).toHaveLength(3);
  expect(f.manager.imagePageUsage).toMatchObject({
    leasedTiles: 3,
    displayUrls: 3,
    cachedBytes: 36,
  });
  expect(f.inputs).toHaveLength(1);
});

test('rolling back new URL publication preserves resources published by an earlier snapshot', async () => {
  const f = await fixture();
  const initial = await f.observe(
    (snapshot) => snapshot.state === pb.ImageWindowState.COMPLETE,
  );
  const original = initial.tiles[0]!;
  await f.demand('wider', 0, 768);
  await vi.waitFor(() =>
    expect(
      f.trace.filter((item) => item === 'materials-released'),
    ).toHaveLength(2),
  );
  const create = URL.createObjectURL.bind(URL);
  const added: string[] = [];
  const createSpy = vi
    .spyOn(URL, 'createObjectURL')
    .mockImplementation((blob) => {
      if (added.length === 1) throw new Error('second new URL failed');
      const url = create(blob);
      added.push(url);
      return url;
    });
  const revoke = vi.spyOn(URL, 'revokeObjectURL');
  expect((await f.demand('wider', 0, 768)).result.case).toBe('error');
  expect(revoke).toHaveBeenCalledExactlyOnceWith(added[0]);
  expect(revoke).not.toHaveBeenCalledWith(original.resource!.url);
  expect(f.manager.imagePageUsage).toMatchObject({
    leasedTiles: 1,
    displayUrls: 1,
    cachedBytes: 36,
  });
  expect((await fetch(original.resource!.url)).ok).toBe(true);
  createSpy.mockImplementation(create);
  const recovered = await f.demand('wider', 0, 768);
  if (recovered.result.case !== 'imageWindow')
    throw new Error('recovered window missing');
  expect(recovered.result.value.tiles).toHaveLength(3);
  expect(recovered.result.value.tiles[0]).toMatchObject({
    leaseId: original.leaseId,
    resource: { url: original.resource!.url },
  });
  expect(f.inputs).toHaveLength(2);
});
