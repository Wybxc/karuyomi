import { catalog } from './fixtures.js';
import { afterEach, expect, test, vi } from 'vitest';
import {
  type AcquireImage,
  type SourceCall,
  type SourcePayload,
  processedImageSchema,
  encodeControlRequest,
  parseControlResponse,
} from '@karuyomi/contracts';
import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import { SourceRuntimeManager, type WorkerEndpoint } from '../src/manager.js';
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
  terminated = false;
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
  terminate() {
    this.terminated = true;
  }
}
const managers: SourceRuntimeManager[] = [];
const sinks: ImageSink[] = [];
afterEach(async () => {
  for (const manager of managers.splice(0)) await manager.dispose();
  for (const sink of sinks.splice(0)) sink.dispose();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});
async function setup(
  acquire: NonNullable<RuntimeDriver['acquireImage']>,
  enabled = true,
) {
  const build = await manifest();
  const store = new ImageResourceStore();
  const invoke = vi.fn(async (): Promise<SourcePayload> => ({
    case: 'mangaPage',
    value: create(pb.MangaPageSchema),
  }));
  const closePageSession = vi.fn(async () => ({ closed: true as const }));
  const driver: RuntimeDriver = {
    open: async () => [
      { id: build.sourceIds[0]!, name: 'Fixture', lang: 'en' },
    ],
    invoke,
    acquireImage: acquire,
    closePageSession,
    close: async () => {},
  };
  const workers: WorkerHarness[] = [];
  const manager = new SourceRuntimeManager(
    new URL('https://reader.example/runtime/worker.js'),
    () => {
      const worker = new WorkerHarness(driver);
      workers.push(worker);
      return worker;
    },
    new VerifiedLoader('https://reader.example', async () =>
      Response.json(build),
    ),
    1000,
    { enabled, store, cancelGraceMs: 40 },
  );
  managers.push(manager);
  const session = await manager.open({
    manifestPath: '/extensions/builds/test-build/manifest.json',
    catalog,
    identity: 'owner',
  });
  const request: AcquireImage = {
    requestId: 'image-1',
    sourceId: build.sourceIds[0]!,
    generation: session.generation,
    pageSessionId: 'page-session',
    pageKey: 'p-0',
  };
  return {
    manager,
    store,
    session,
    request,
    workers,
    invoke,
    closePageSession,
  };
}
async function prepare(port: MessagePort, id: string) {
  const sink = new ImageSink(port, id, () => {});
  sinks.push(sink);
  const handle = sink.open();
  await sink.write(handle, pngHeader());
  return processedImageSchema.parse(JSON.parse(await sink.close(handle)));
}
function metadata(request: AcquireImage, requestId: string): SourceCall {
  return create(pb.SourceCallSchema, {
    requestId,
    sourceId: request.sourceId,
    generation: request.generation,
    request: { case: 'popular', value: { page: 1 } },
  });
}

test('image and metadata share the Source lock, while END alone cannot publish', async () => {
  const java = deferred<void>();
  const prepared = deferred<void>();
  const create = vi.spyOn(URL, 'createObjectURL');
  const { manager, request, invoke, store } = await setup(
    async (_source, _session, _page, port, id) => {
      const result = await prepare(port, id);
      prepared.resolve();
      await java.promise;
      return result;
    },
  );
  const acquiring = manager.acquireImage(request);
  const queued = manager.invoke(metadata(request, 'metadata'));
  await prepared.promise;
  expect(create).not.toHaveBeenCalled();
  expect(invoke).not.toHaveBeenCalled();
  java.resolve();
  const image = await acquiring;
  await queued;
  expect(create).toHaveBeenCalledOnce();
  expect(store.snapshot.resources).toBe(1);
  await manager.releaseImage({
    resourceId: image.resourceId,
    generation: image.generation,
  });
  expect(store.snapshot.resources).toBe(0);
});

test('cancel control reaches a busy Worker and waits for Java unwind before unlocking', async () => {
  const entered = deferred<void>();
  const cancelled = deferred<void>();
  const unwind = deferred<void>();
  const { manager, request, invoke, workers, store } = await setup(
    async (_source, _session, _page, port, id) => {
      const sink = new ImageSink(port, id, () => cancelled.resolve());
      sinks.push(sink);
      sink.open();
      entered.resolve();
      await unwind.promise;
      throw new Error('Java unwound after cancellation');
    },
  );
  const result = expect(manager.acquireImage(request)).rejects.toMatchObject({
    code: 'cancelled',
  });
  await entered.promise;
  const queued = manager.invoke(metadata(request, 'queued'));
  let acknowledged = false;
  const stopping = manager
    .cancelImage({
      requestId: request.requestId,
      generation: request.generation,
    })
    .then(() => {
      acknowledged = true;
    });
  await cancelled.promise;
  expect(acknowledged).toBe(false);
  expect(invoke).not.toHaveBeenCalled();
  unwind.resolve();
  await stopping;
  await result;
  await queued;
  expect(workers[0]?.terminated).toBe(false);
  expect(store.snapshot.resources).toBe(0);
});

test('a noncooperative image producer is recycled after bounded cancel grace', async () => {
  const entered = deferred<void>();
  const { manager, request, workers, store } = await setup(
    async (_source, _session, _page, port, id) => {
      const sink = new ImageSink(port, id, () => {});
      sinks.push(sink);
      sink.open();
      entered.resolve();
      return new Promise(() => {});
    },
  );
  const acquiring = expect(manager.acquireImage(request)).rejects.toMatchObject(
    { code: 'runtime_lost' },
  );
  await entered.promise;
  await manager.cancelImage({
    requestId: request.requestId,
    generation: request.generation,
  });
  await acquiring;
  expect(workers[0]?.terminated).toBe(true);
  expect(store.snapshot.resources).toBe(0);
  await expect(
    manager.acquireImage({ ...request, requestId: 'late' }),
  ).rejects.toMatchObject({ code: 'runtime_lost' });
});

test('a cooperative image timeout preserves the generation for later metadata', async () => {
  const { manager, request, workers } = await setup(
    async (_source, _session, _page, port, id) => {
      const stopped = deferred<void>();
      const sink = new ImageSink(port, id, () => stopped.resolve());
      sinks.push(sink);
      sink.open();
      await stopped.promise;
      throw new Error('Java unwound');
    },
  );
  await expect(
    manager.acquireImage({ ...request, timeoutMs: 15 }),
  ).rejects.toMatchObject({ code: 'timeout' });
  expect(workers[0]?.terminated).toBe(false);
  await expect(
    manager.invoke(metadata(request, 'after-timeout')),
  ).resolves.toMatchObject({ generation: request.generation });
});

test('Java failure after END drops the prepared image without creating a URL', async () => {
  const create = vi.spyOn(URL, 'createObjectURL');
  const { manager, request, store } = await setup(
    async (_source, _session, _page, port, id) => {
      await prepare(port, id);
      throw new Error('Java image finalization failed');
    },
  );
  await expect(manager.acquireImage(request)).rejects.toMatchObject({
    code: 'source_error',
  });
  expect(create).not.toHaveBeenCalled();
  expect(store.snapshot).toEqual({ resources: 0, bytes: 0 });
});

test('cancellation during publication never returns an already revoked URL', async () => {
  const { manager, request, store } = await setup(
    async (_source, _session, _page, port, id) => prepare(port, id),
  );
  const create = URL.createObjectURL.bind(URL);
  const revoke = vi.spyOn(URL, 'revokeObjectURL');
  let stopping: Promise<unknown> | undefined;
  vi.spyOn(URL, 'createObjectURL').mockImplementation((blob) => {
    const url = create(blob);
    stopping = manager.cancelImage({
      requestId: request.requestId,
      generation: request.generation,
    });
    return url;
  });
  await expect(manager.acquireImage(request)).rejects.toMatchObject({
    code: 'cancelled',
  });
  await stopping;
  expect(revoke).toHaveBeenCalledOnce();
  expect(store.snapshot.resources).toBe(0);
});

test.each(['cancel', 'close'] as const)(
  'completed image requests ignore late %s and retain their resource until release',
  async (action) => {
    const revoke = vi.spyOn(URL, 'revokeObjectURL');
    const { manager, request, store, closePageSession } = await setup(
      async (_source, _session, _page, port, id) => prepare(port, id),
    );
    const image = await manager.acquireImage(request);
    // This continuation can run before the task's promise cleanup. Cancellation
    // must only stop pending production, never revoke an already returned image.
    if (action === 'cancel')
      await manager.cancelImage({
        requestId: request.requestId,
        generation: request.generation,
      });
    else
      await manager.closePageSession({
        pageSessionId: request.pageSessionId,
        generation: request.generation,
      });
    expect(store.snapshot.resources).toBe(1);
    expect(revoke).not.toHaveBeenCalled();
    expect(
      new Uint8Array(await (await fetch(image.url)).arrayBuffer()),
    ).toEqual(pngHeader());
    await manager.closePageSession({
      pageSessionId: request.pageSessionId,
      generation: request.generation,
    });
    expect(closePageSession).toHaveBeenCalledOnce();
    expect(store.snapshot.resources).toBe(1);
    expect(revoke).not.toHaveBeenCalled();
    await manager.releaseImage({
      resourceId: image.resourceId,
      generation: image.generation,
    });
    expect(revoke).toHaveBeenCalledOnce();
    expect(store.snapshot.resources).toBe(0);
  },
);

test('stale image requests and duplicate IDs are rejected, release is idempotent, close is serial', async () => {
  const { manager, request, closePageSession, store } = await setup(
    async (_source, _session, _page, port, id) => prepare(port, id),
  );
  await expect(
    manager.acquireImage({ ...request, generation: 'old' }),
  ).rejects.toMatchObject({ code: 'runtime_lost' });
  const image = await manager.acquireImage(request);
  await expect(manager.acquireImage(request)).rejects.toMatchObject({
    code: 'protocol_error',
  });
  await manager.closePageSession({
    pageSessionId: request.pageSessionId,
    generation: request.generation,
  });
  await manager.closePageSession({
    pageSessionId: request.pageSessionId,
    generation: request.generation,
  });
  expect(closePageSession).toHaveBeenCalledOnce();
  await expect(
    manager.acquireImage({ ...request, requestId: 'closed' }),
  ).rejects.toMatchObject({ code: 'runtime_lost' });
  await manager.releaseImage({
    resourceId: image.resourceId,
    generation: image.generation,
  });
  await manager.releaseImage({
    resourceId: image.resourceId,
    generation: image.generation,
  });
  expect(store.snapshot.resources).toBe(0);
});

test('public page-session close waits for the Worker acknowledgement and returns closed', async () => {
  const { manager, request, closePageSession } = await setup(
    async (_source, _session, _page, port, id) => prepare(port, id),
  );
  const acknowledgement = deferred<{ closed: true }>();
  closePageSession.mockImplementationOnce(() => acknowledgement.promise);
  vi.stubGlobal('window', { addEventListener: vi.fn() });
  const api = installRuntime(manager, () => {
    throw new Error('Search is not used by this foreground fixture');
  });
  const input = {
    pageSessionId: request.pageSessionId,
    generation: request.generation,
  };
  let acknowledged = false;
  const close = async () =>
    parseControlResponse(
      await api.control(
        encodeControlRequest(
          create(pb.ControlRequestSchema, {
            slotId: pb.RuntimeSlot.FOREGROUND,
            requestId: 'control-close',
            command: { case: 'closePageSession', value: input },
          }),
        ),
      ),
    );
  const closing = close().then((result) => {
    acknowledged = true;
    return result;
  });
  await vi.waitFor(() => expect(closePageSession).toHaveBeenCalledOnce());
  expect(acknowledged).toBe(false);
  acknowledgement.resolve({ closed: true });
  await expect(closing).resolves.toMatchObject({
    result: { case: 'closed', value: { closed: true } },
  });
  await expect(close()).resolves.toMatchObject({
    result: { case: 'closed', value: { closed: true } },
  });
  expect(closePageSession).toHaveBeenCalledOnce();
  await manager.rebuild();
  await expect(close()).resolves.toMatchObject({
    result: { case: 'closed', value: { closed: true } },
  });
});

test('Native does not advertise or acquire Web Blob resources', async () => {
  const acquire = vi.fn(async () =>
    processedImageSchema.parse({
      resourceId: 'unreachable',
      generation: 'unreachable',
      byteLength: 1,
    }),
  );
  const { manager, request, session } = await setup(acquire, false);
  expect(session.capabilities).not.toContain('processed-image-resources');
  await expect(manager.acquireImage(request)).rejects.toMatchObject({
    code: 'unsupported_capability',
  });
  expect(acquire).not.toHaveBeenCalled();
});

test('formal host control delivers opaque Source bytes once with only ownership metadata', async () => {
  const decode = vi.fn(() => {
    throw new Error('UI owns decoding');
  });
  vi.stubGlobal('createImageBitmap', decode);
  const bytes = new Uint8Array([255, 0, 173, 3]);
  const acquire = vi.fn<NonNullable<RuntimeDriver['acquireImage']>>(
    async (_source, _session, _page, port, id) => {
      const sink = new ImageSink(port, id, () => {});
      sinks.push(sink);
      const handle = sink.open();
      await sink.write(handle, bytes);
      return processedImageSchema.parse(JSON.parse(await sink.close(handle)));
    },
  );
  const { manager, request, store } = await setup(acquire);
  vi.stubGlobal('window', { addEventListener: vi.fn() });
  const api = installRuntime(manager, () => {
    throw new Error('Search is not used by this foreground fixture');
  });
  const response = parseControlResponse(
    await api.control(
      encodeControlRequest(
        create(pb.ControlRequestSchema, {
          slotId: pb.RuntimeSlot.FOREGROUND,
          requestId: 'opaque-control',
          command: { case: 'acquireImage', value: request },
        }),
      ),
    ),
  );
  expect(response.result.case).toBe('image');
  if (response.result.case !== 'image')
    throw new Error('Image response missing');
  const value = response.result.value;
  expect(Object.keys(value).sort()).toEqual([
    '$typeName',
    'byteLength',
    'generation',
    'resourceId',
    'url',
  ]);
  expect(value.byteLength).toBe(bytes.length);
  expect(new Uint8Array(await (await fetch(value.url)).arrayBuffer())).toEqual(
    bytes,
  );
  expect(acquire).toHaveBeenCalledOnce();
  expect(decode).not.toHaveBeenCalled();
  const released = parseControlResponse(
    await api.control(
      encodeControlRequest(
        create(pb.ControlRequestSchema, {
          slotId: pb.RuntimeSlot.FOREGROUND,
          requestId: 'opaque-release',
          command: {
            case: 'releaseImage',
            value: {
              resourceId: value.resourceId,
              generation: value.generation,
            },
          },
        }),
      ),
    ),
  );
  expect(released.result.case).toBe('released');
  expect(store.snapshot).toEqual({ resources: 0, bytes: 0 });
});

test('URL publication failure frees the Source slot and resource budget without retrying Source', async () => {
  const acquire = vi.fn<NonNullable<RuntimeDriver['acquireImage']>>(
    async (_source, _session, _page, port, id) => prepare(port, id),
  );
  const { manager, request, store, invoke } = await setup(acquire);
  vi.spyOn(URL, 'createObjectURL').mockImplementationOnce(() => {
    throw new Error('URL unavailable');
  });
  const acquiring = expect(manager.acquireImage(request)).rejects.toThrow(
    'URL unavailable',
  );
  const queued = manager.invoke(metadata(request, 'after-url-failure'));
  await acquiring;
  await queued;
  expect(invoke).toHaveBeenCalledOnce();
  expect(acquire).toHaveBeenCalledOnce();
  expect(store.snapshot).toEqual({ resources: 0, bytes: 0 });
});
