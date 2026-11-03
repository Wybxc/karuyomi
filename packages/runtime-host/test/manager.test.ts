import { afterEach, expect, test, vi } from 'vitest';
import {
  type SourceCall,
  type WorkerCommand,
  type WorkerResponse,
} from '@karuyomi/contracts';
import { SourceRuntimeManager, type WorkerEndpoint } from '../src/manager.js';
import { WorkerRuntime } from '../src/worker-runtime.js';
import { createHello } from '../src/hello.js';
import type { RuntimeDriver } from '../src/teavm-driver.js';
import { VerifiedLoader } from '../src/verified-loader.js';
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
    this.onmessage?.({ data } as MessageEvent<unknown>);
  }
  postMessage(command: WorkerCommand) {
    this.commands.push(command);
    void this.runtime.receive(command);
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
  manifestPath: '/api/extensions/builds/test/manifest',
  identity: 'verified-owner',
};
const call = (id: string, timeoutMs?: number): SourceCall => ({
  requestId: id,
  sourceId: '9223372036854775806',
  operation: 'popular',
  args: { page: 1 },
  ...(timeoutMs ? { timeoutMs } : {}),
});
const managers: SourceRuntimeManager[] = [];
afterEach(async () => {
  for (const manager of managers.splice(0)) await manager.dispose();
  vi.useRealTimers();
});

async function setup(
  invoke: RuntimeDriver['invoke'] = async () => ({
    mangas: [],
    hasNextPage: false,
  }),
) {
  const workers: FakeWorker[] = [];
  const driver = {
    open: vi.fn(async () => [
      { id: '9223372036854775806', name: 'Test', lang: 'en' },
    ]),
    invoke: vi.fn(invoke),
    close: vi.fn(async () => {}),
  };
  const build = await manifest();
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
      const worker = new FakeWorker(driver);
      workers.push(worker);
      return worker;
    },
    loader,
  );
  managers.push(manager);
  return { manager, workers, driver };
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
  const first = deferred<unknown>();
  const second = deferred<unknown>();
  const { manager, driver } = await setup(
    vi
      .fn()
      .mockReturnValueOnce(first.promise)
      .mockReturnValueOnce(second.promise),
  );
  const session = await manager.open(options);
  const a = manager.invoke(call('a'));
  const b = manager.invoke(call('b'));
  expect(driver.invoke).toHaveBeenCalledTimes(1);
  first.resolve({ mangas: [{ url: '/manga-a' }], hasNextPage: false });
  expect(await a).toMatchObject({
    requestId: 'a',
    generation: session.generation,
  });
  await vi.waitFor(() => expect(driver.invoke).toHaveBeenCalledTimes(2));
  second.resolve({ mangas: [{ url: '/manga-b' }], hasNextPage: true });
  expect(await b).toMatchObject({
    requestId: 'b',
    data: { hasNextPage: true },
  });
});

test('queued cancellation never calls the Source or destroys a running sibling', async () => {
  const active = deferred<unknown>();
  const { manager, workers, driver } = await setup(() => active.promise);
  await manager.open(options);
  const a = manager.invoke(call('active'));
  const b = manager.invoke(call('queued'));
  const cancelled = expect(b).rejects.toMatchObject({ code: 'cancelled' });
  await manager.cancel('queued');
  await cancelled;
  expect(workers[0]?.terminated).toBe(false);
  expect(driver.invoke).toHaveBeenCalledTimes(1);
  active.resolve({});
  await a;
});

test('active cancellation recycles the generation and rejects queued work without replay', async () => {
  const active = deferred<unknown>();
  const { manager, workers } = await setup(() => active.promise);
  const session = await manager.open(options);
  const a = manager.invoke(call('active'));
  const b = manager.invoke(call('queued'));
  const cancelled = expect(a).rejects.toMatchObject({ code: 'cancelled' });
  const lost = expect(b).rejects.toMatchObject({ code: 'runtime_lost' });
  await manager.cancel('active');
  await cancelled;
  await lost;
  expect(workers[0]?.terminated).toBe(true);
  await expect(manager.invoke(call('after'))).rejects.toMatchObject({
    code: 'runtime_lost',
  });
  const next = await manager.open(options);
  expect(next.generation).not.toBe(session.generation);
  active.resolve({ stale: true });
  // A delayed old worker message cannot resolve a new generation's task.
  workers[0]?.emit({
    type: 'response',
    protocolVersion: 1,
    ...session,
    requestId: 'later',
    result: { leaked: true },
  } satisfies WorkerResponse);
});

test('active deadline stops a stuck Source Worker', async () => {
  const { manager, workers } = await setup(() => new Promise(() => {}));
  await manager.open(options);
  vi.useFakeTimers();
  const pending = manager.invoke(call('timeout', 50));
  const expired = expect(pending).rejects.toMatchObject({ code: 'timeout' });
  await vi.advanceTimersByTimeAsync(50);
  await expired;
  expect(workers[0]?.terminated).toBe(true);
});

test('wrong-generation messages and unregistered Source IDs cannot cross the slot', async () => {
  const result = deferred<unknown>();
  const { manager, workers, driver } = await setup(() => result.promise);
  const session = await manager.open(options);
  const pending = manager.invoke(call('current'));
  workers[0]?.emit({
    ...session,
    protocolVersion: 1,
    generation: 'old-generation',
    type: 'response',
    requestId: 'current',
    result: { wrong: true },
  });
  result.resolve({ valid: true });
  expect(await pending).toMatchObject({ data: { valid: true } });
  await expect(
    manager.invoke({ ...call('wrong-source'), sourceId: '1' }),
  ).rejects.toMatchObject({ code: 'protocol_error' });
  expect(driver.invoke).toHaveBeenCalledTimes(1);
});

test('duplicate request ID and image channel are explicit failures', async () => {
  const { manager } = await setup();
  await manager.open(options);
  await manager.invoke(call('same'));
  await expect(manager.invoke(call('same'))).rejects.toMatchObject({
    code: 'protocol_error',
  });
  await expect(manager.acquireImage()).rejects.toMatchObject({
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
