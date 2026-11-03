import { afterEach, expect, test, vi } from 'vitest';
import {
  type BuildManifest,
  type SourceCall,
  type WorkerCommand,
  type WorkerResponse,
  type SourcePayload,
  workerCommandSchema,
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
import { manifest } from './fixtures.js';

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
  postMessage(input: unknown) {
    const command = workerCommandSchema.parse(input);
    this.commands.push(command);
    void this.runtime.receive(input);
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
afterEach(async () => {
  for (const manager of managers.splice(0)) await manager.dispose();
  vi.useRealTimers();
  vi.unstubAllGlobals();
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
) {
  const workers: FakeWorker[] = [];
  const workerUrls: URL[] = [];
  const driver = {
    open: vi.fn(async () => [
      { id: '9223372036854775806', name: 'Test', lang: 'en' },
    ]),
    invoke: vi.fn(invoke),
    close: vi.fn(async () => {}),
  };
  const build = initialBuild ?? (await manifest());
  const loader = new VerifiedLoader('https://read.example.com', (async () =>
    Response.json(build)) as typeof fetch);
  const manager = new SourceRuntimeManager(
    new URL('https://read.example.com/runtime/worker.js'),
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
  );
  managers.push(manager);
  return { manager, workers, workerUrls, driver };
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
  await manager.cancel('queued');
  await cancelled;
  expect(workers[0]?.terminated).toBe(false);
  expect(driver.invoke).toHaveBeenCalledTimes(1);
  active.resolve(mangaPage());
  await a;
});

test('active cancellation recycles the generation and rejects queued work without replay', async () => {
  const active = deferred<SourcePayload>();
  const { manager, workers } = await setup(() => active.promise);
  const session = await manager.open(options);
  const a = manager.invoke(call('active', session.generation));
  const b = manager.invoke(call('queued', session.generation));
  const cancelled = expect(a).rejects.toMatchObject({ code: 'cancelled' });
  const lost = expect(b).rejects.toMatchObject({ code: 'runtime_lost' });
  await manager.cancel('active');
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
