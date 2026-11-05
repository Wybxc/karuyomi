/** Real manager/Worker/driver and AOT Java; controlled Source and HTTP endpoint. */
import { create } from '@bufbuild/protobuf';
import * as pb from '@karuyomi/protocol';
import {
  workerCommandSchema,
  workerResponseSchema,
  runtimeErrorData,
  type WorkerCommand,
  type WorkerResponse,
} from '@karuyomi/contracts';
import { SourceRuntimeManager, type WorkerEndpoint } from '../src/manager.js';
import { VerifiedLoader } from '../src/verified-loader.js';
import { RuntimeFailure } from '../src/errors.js';
import { object, text } from '../../../runtime/teavm/bridge/bridge-common.js';

interface FixtureEvent {
  event: string;
  receivedAt: number;
}

/** Every operation is forwarded to an actual Worker; no driver or reply is mocked. */
class ObservedWorker implements WorkerEndpoint {
  onmessage: WorkerEndpoint['onmessage'] = null;
  onerror: WorkerEndpoint['onerror'] = null;
  readonly events: FixtureEvent[] = [];
  readonly commands: WorkerCommand[] = [];
  readonly responses: { response: WorkerResponse; receivedAt: number }[] = [];
  readonly namespace: string;
  terminateCalls = 0;
  private readonly actual: Worker;

  constructor(url: URL) {
    const namespace = url.searchParams.get('plugin');
    if (
      !namespace ||
      !/^[a-f0-9]{64}$/.test(namespace) ||
      namespace !== url.searchParams.get('fsNamespace')
    )
      throw Error('Manager did not provide a shared 64hex namespace');
    this.namespace = namespace;
    this.actual = new Worker(url);
    this.actual.onmessage = (event: MessageEvent<unknown>) => {
      const value = event.data;
      if (
        value &&
        typeof value === 'object' &&
        'type' in value &&
        value.type === 'enqueue-fixture-event'
      ) {
        this.events.push({
          event: text(object(value).event),
          receivedAt: performance.now(),
        });
        return;
      }
      const parsed = workerResponseSchema.safeParse(value);
      if (parsed.success)
        this.responses.push({
          response: parsed.data,
          receivedAt: performance.now(),
        });
      this.onmessage?.(event);
    };
    this.actual.onerror = (event) => this.onerror?.(event);
  }

  postMessage(command: unknown, transfer: Transferable[] = []): void {
    this.commands.push(workerCommandSchema.parse(command));
    this.actual.postMessage(command, transfer);
  }

  terminate(): void {
    this.terminateCalls++;
    this.actual.terminate();
  }
}

async function failureOf(promise: Promise<unknown>): Promise<RuntimeFailure> {
  try {
    await promise;
  } catch (error) {
    if (!(error instanceof RuntimeFailure)) throw error;
    return error;
  }
  throw Error('Expected the real manager to reject the request');
}

async function waitUntil(
  condition: () => boolean | Promise<boolean>,
  timeoutMs: number,
  label: string,
): Promise<void> {
  const deadline = performance.now() + timeoutMs;
  while (!(await condition())) {
    if (performance.now() >= deadline) throw Error(label);
    await new Promise<void>((resolve) => setTimeout(resolve, 20));
  }
}

export async function runEnqueueManagerSuite() {
  const checks: string[] = [];
  const workers: ObservedWorker[] = [];
  const managers: SourceRuntimeManager[] = [];
  const evidence: Record<string, unknown> = {};
  let stage = 'initializing';
  let completed = false;
  let failure: string | undefined;
  let cleanupPassed = false;
  const check = (value: unknown, label: string): void => {
    if (!value) throw Error(label);
    checks.push(label);
  };
  const make = () => {
    const manager = new SourceRuntimeManager(
      new URL('/manager-worker.js', location.href),
      (url) => {
        const worker = new ObservedWorker(url);
        workers.push(worker);
        return worker;
      },
      new VerifiedLoader(location.origin),
      60000,
    );
    managers.push(manager);
    return manager;
  };
  const options = {
    identity: 'controlled-enqueue-' + crypto.randomUUID(),
    manifestPath: '/extensions/builds/enqueue-manager/manifest.json',
    expectedBuildId: 'enqueue-manager',
  };
  const call = (
    manager: SourceRuntimeManager,
    generation: string,
    page: number,
    requestId: string = crypto.randomUUID(),
  ) =>
    manager.invoke(
      create(pb.SourceCallSchema, {
        requestId,
        generation,
        sourceId: '1',
        // Java's real 30-second drain must fire before the manager's queue deadline.
        timeoutMs: 60000,
        request: { case: 'popular', value: { page } },
      }),
    );
  try {
    const first = make();
    const initial = await first.open(options);
    const oldWorker = workers[0];
    if (!oldWorker) throw Error('Manager did not create a real Worker');
    stage = 'pending-limit';
    const limited = await call(first, initial.generation, 8);
    check(
      limited.payload.case === 'mangaPage',
      '64-callback RPC returns typed Source result',
    );
    const events = oldWorker.events.map((value) => value.event);
    check(
      events.includes('limit-registered-64') &&
        events.includes('limit-rejected-65'),
      '64 pending callbacks accepted and 65th synchronously rejected',
    );
    check(
      events.filter((value) => value === 'limit-callback-entered').length ===
        64 &&
        events.filter((value) => value === 'limit-callback-finished').length ===
          64 &&
        events.includes('limit-all-entered') &&
        events.includes('limit-all-finished'),
      'all 64 callbacks enter their barrier and finish exactly once',
    );
    check(
      !events.includes('unexpected-limit-65-callback'),
      'rejected callback never starts',
    );
    check(
      oldWorker.terminateCalls === 0,
      'handled callback limit keeps the real Worker alive',
    );
    check(
      (await call(first, initial.generation, 10)).payload.case === 'mangaPage',
      'next RPC succeeds after the 64 callbacks drain',
    );

    stage = 'fatal-drain';
    const fatalRequest = 'fatal-drain-' + crypto.randomUUID();
    const fatal = failureOf(call(first, initial.generation, 9, fatalRequest));
    await waitUntil(
      () =>
        oldWorker.events.some(
          (value) => value.event === 'drain-callback-entered',
        ),
      5000,
      'Real HTTP callback did not start',
    );
    const queuedRequest = 'never-started-' + crypto.randomUUID();
    const queued = failureOf(
      call(first, initial.generation, 10, queuedRequest),
    );
    const replacement = make();
    const busy = await failureOf(replacement.open(options));
    check(
      busy.code === 'storage_busy' && workers.length === 1,
      'second manager cannot acquire namespace while fatal callback is pending',
    );
    const failed = await fatal;
    const rejectedQueue = await queued;
    check(
      failed.code === 'runtime_lost' &&
        failed.message.includes(
          'Background HTTP callbacks exceeded drain deadline',
        ),
      'unchanged Java drain produces fatal runtime_lost before manager timeout',
    );
    const returned = oldWorker.events.find(
      (value) => value.event === 'return-9',
    );
    const fatalResponse = oldWorker.responses.find(
      (value) =>
        value.response.envelope.requestId === fatalRequest &&
        value.response.result.case === 'error',
    );
    if (
      !returned ||
      !fatalResponse ||
      fatalResponse.response.result.case !== 'error'
    )
      throw Error(
        'Missing actual Java-return or generated fatal response evidence',
      );
    const elapsedMs = fatalResponse.receivedAt - returned.receivedAt;
    evidence.fatalDrainElapsedMs = elapsedMs;
    evidence.fatalError = failed.toJSON();
    evidence.queuedError = rejectedQueue.toJSON();
    const fatalData = runtimeErrorData(fatalResponse.response.result.value);
    check(
      elapsedMs >= 29500 &&
        elapsedMs < 55000 &&
        fatalData.code === 'runtime_lost' &&
        fatalData.message.includes('drain deadline'),
      'real Worker emits generated fatal response after the actual 30-second drain',
    );
    check(
      rejectedQueue.code === 'runtime_lost' &&
        !oldWorker.commands.some(
          (command) => command.envelope.requestId === queuedRequest,
        ),
      'fatal result rejects queued RPC without sending it to the Worker',
    );
    check(
      oldWorker.terminateCalls === 1,
      'manager terminates the fatal real Worker exactly once',
    );
    await waitUntil(
      async () => {
        const response = await fetch('/network-state', { cache: 'no-store' });
        if (!response.ok)
          throw Error('Network evidence endpoint is unavailable');
        const state = object(await response.json());
        if (!Array.isArray(state.network))
          throw Error('Invalid network evidence');
        return state.network.some((value: unknown) => {
          const event = object(value);
          return (
            event.path === '/drain-timeout' &&
            event.closed === true &&
            event.completed === false
          );
        });
      },
      5000,
      'Fatal manager recycle did not close held upstream before service cleanup',
    );
    evidence.upstreamClosedBeforeServiceCleanup = true;
    check(
      true,
      'held HTTP connection closes before report and service cleanup',
    );
    const stale = await failureOf(call(first, initial.generation, 10));
    check(
      stale.code === 'runtime_lost',
      'old generation is rejected after fatal recycle',
    );
    await waitUntil(
      async () => {
        const locks = await navigator.locks.query();
        return !locks.held?.some(
          (lock) =>
            lock.name === 'karuyomi:source-writer:' + oldWorker.namespace,
        );
      },
      5000,
      'Fatal manager recycle did not release namespace',
    );

    stage = 'same-namespace-recovery';
    const recovered = await replacement.open(options);
    const newWorker = workers[1];
    if (!newWorker) throw Error('Replacement did not create a real Worker');
    check(
      newWorker.namespace === oldWorker.namespace &&
        recovered.generation !== initial.generation &&
        recovered.workerInstanceId !== initial.workerInstanceId,
      'new manager acquires the same namespace with a new Worker and generation',
    );
    const commandsBeforeStale = newWorker.commands.length;
    const staleReplacement = await failureOf(
      call(replacement, initial.generation, 10),
    );
    check(
      staleReplacement.code === 'runtime_lost' &&
        newWorker.commands.length === commandsBeforeStale,
      'replacement rejects old generation without sending it to the new Worker',
    );
    check(
      (await call(replacement, recovered.generation, 10)).payload.case ===
        'mangaPage',
      'fresh actual TeaVM RPC succeeds after fatal manager recycle',
    );
    evidence.generations = {
      expired: initial.generation,
      recovered: recovered.generation,
    };
    completed = true;
  } catch (error) {
    failure = String(error);
  } finally {
    const results = await Promise.allSettled(
      managers.map((manager) => manager.dispose()),
    );
    cleanupPassed =
      results.every((result) => result.status === 'fulfilled') &&
      workers.every((worker) => worker.terminateCalls === 1);
    for (const worker of workers)
      if (worker.terminateCalls === 0) worker.terminate();
    if (!cleanupPassed && failure === undefined)
      failure = 'Manager cleanup failed';
  }
  return {
    passed: completed && failure === undefined && cleanupPassed,
    stage,
    ...(failure === undefined ? {} : { error: failure }),
    checks,
    ...evidence,
    cleanupPassed,
    workers: workers.map((worker) => ({
      namespace: worker.namespace,
      terminateCalls: worker.terminateCalls,
      commands: worker.commands.map((command) => ({
        requestId: command.envelope.requestId,
        command: command.command.case,
      })),
      events: worker.events,
    })),
    userAgent: navigator.userAgent,
    scope:
      'Actual TeaVM, TeaHost, product manager/WorkerRuntime/TeaVMDriver/loader and HTTP-v2; controlled Source and endpoint. No official Source, workerd, Access or Native claim.',
  };
}
