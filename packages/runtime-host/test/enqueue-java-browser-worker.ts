import { BinaryHttpTransport } from '../src/http-transport.js';
import type { TeaVMGlobals } from '../src/teavm-driver.js';
import { workerScope } from '../../../runtime/teavm/bridge/bridge-common.js';

declare global {
  var enqueueFixtureMark: (event: string) => void;
  var enqueueFixtureStart: () => void;
}

const scope = workerScope();
const java: { [K in keyof TeaVMGlobals]?: TeaVMGlobals[K] | undefined } = scope;
const transport = new BinaryHttpTransport(location.origin, 'enqueue-fixture');
const events: string[] = [];
const checks: string[] = [];
const active = new Set<string>();
const tokens = new Set<string>();
let maximumActive = 0;
let cancellations = 0;
let currentEntry = '';

function check(value: boolean, message: string): void {
  if (!value) throw Error(message);
  checks.push(message);
}

function required<T>(value: T | undefined): T {
  if (value === undefined) throw Error('Missing real TeaVM host export');
  return value;
}

scope.enqueueFixtureMark = (event) => {
  events.push(event);
  if (event === 'expired-owner-rejected') {
    void fetch('/event', { method: 'POST', body: event });
  }
};

Object.assign(java, {
  teaHttpOpen: (request: string) => {
    const handle = transport.open(request);
    active.add(handle);
    maximumActive = Math.max(maximumActive, active.size);
    return handle;
  },
  teaHttpWrite: (handle: string, bytes: Uint8Array) =>
    transport.write(handle, bytes),
  teaHttpFinish: (handle: string) => transport.finish(handle),
  teaHttpRead: (handle: string, maximum: number) =>
    transport.read(handle, maximum),
  teaHttpClose: (handle: string) => {
    active.delete(handle);
    transport.close(handle);
  },
  teaHttpCancel: (handle: string) => {
    cancellations++;
    active.delete(handle);
    transport.close(handle);
  },
});

type EntryResult =
  | { success: true; value: unknown }
  | { success: false; error: string; discardRuntime: boolean };

async function entry(
  label: string,
  start: (token: string) => void,
): Promise<EntryResult> {
  currentEntry = label;
  const token = transport.begin({
    requestId: 'same-rpc',
    generation: 'same-generation',
  });
  check(!tokens.has(token), label + ': unique entry token');
  tokens.add(token);
  try {
    return await new Promise<EntryResult>((resolve, reject) => {
      const timer = setTimeout(
        () => reject(Error(label + ': real TeaVM entry timed out')),
        6000,
      );
      java.teaDone = (json) => {
        clearTimeout(timer);
        events.push('done-' + label);
        try {
          resolve({ success: true, value: JSON.parse(json) as unknown });
        } catch (error) {
          reject(error);
        }
      };
      java.teaFail = (error, discardRuntime) => {
        clearTimeout(timer);
        events.push('fail-' + label);
        resolve({
          success: false,
          error,
          discardRuntime: discardRuntime === true,
        });
      };
      try {
        start(token);
      } catch (error) {
        clearTimeout(timer);
        reject(error);
      }
    });
  } finally {
    check(
      active.size === 0,
      label + ': no leaked HTTP handles at entry completion',
    );
    transport.end();
  }
}

const popular = (page: number) =>
  entry(String(page), (token) => {
    required(java.hostInvoke)(
      '1',
      'popular',
      JSON.stringify({ page }),
      'same-rpc',
      'same-generation',
      token,
    );
  });

function before(first: string, second: string): boolean {
  const a = events.indexOf(first),
    b = events.indexOf(second);
  return a >= 0 && b > a;
}

async function run(): Promise<void> {
  try {
    const init = await entry('init', (token) =>
      required(java.hostInit)(
        'Enqueue fixture',
        'same-rpc',
        'same-generation',
        token,
      ),
    );
    check(init.success, 'real TeaHost hostInit succeeds');
    const loaded = await entry('load', (token) =>
      required(java.hostLoad)('same-rpc', 'same-generation', token),
    );
    check(
      loaded.success &&
        Array.isArray(loaded.value) &&
        loaded.value.length === 1,
      'real TeaHost hostLoad discovers controlled Source',
    );

    check((await popular(1)).success, 'nested enqueue completes');
    check(
      before('return-1', 'nested-first'),
      'Source returns before its first asynchronous callback',
    );
    check(
      before('nested-first', 'nested-second') &&
        before('nested-second', 'done-1'),
      'TeaHost delivers RPC only after nested callbacks drain',
    );

    const failed = await popular(2);
    check(
      !failed.success &&
        failed.error.includes('fixture callback failed') &&
        !failed.discardRuntime,
      'callback exception becomes nonfatal Source failure',
    );
    check(
      !events.includes('unexpected-second-callback'),
      'onResponse exception never triggers a second onFailure callback',
    );

    check(
      (await popular(3)).success,
      'handled onFailure allows next RPC to succeed',
    );
    check(
      before('handled-network-failure', 'done-3'),
      'handled network failure drains before RPC completion',
    );

    check((await popular(4)).success, 'explicit Call cancellation is handled');
    check(
      before('cancelled-body-rejected', 'done-4'),
      'cancelled response body rejects before RPC completion',
    );
    check(
      (await popular(5)).success,
      'next RPC succeeds while expired child resumes',
    );
    check(
      before('entry-5', 'expired-owner-rejected') &&
        before('expired-owner-rejected', 'next-callback'),
      'expired bound owner is rejected during next entry',
    );
    check(
      !events.some(
        (event) =>
          event.startsWith('unexpected-late') ||
          event.startsWith('late-child-failed'),
      ),
      'late owner neither executes nor starts HTTP in the next entry',
    );

    check(
      (await popular(6)).success,
      'Call construction finishes without binding old owner',
    );
    check(
      (await popular(7)).success,
      'deferred Calls bind at their first execute and enqueue',
    );
    check(
      before('deferred-foreground', 'deferred-background') &&
        before('deferred-background', 'done-7'),
      'deferred foreground and callback complete under new entry',
    );
    check(
      cancellations > 0,
      'Call cancellation reaches actual binary transport',
    );
    await java.teaFileSystemClose?.();
    transport.dispose();
    scope.postMessage({
      type: 'enqueue-result',
      passed: true,
      checks,
      events,
      http: { open: active.size, maximumActive, cancellations },
      entries: tokens.size,
    });
  } catch (error) {
    transport.dispose();
    scope.postMessage({
      type: 'enqueue-result',
      passed: false,
      entry: currentEntry,
      error: String(error),
      stack: error instanceof Error ? error.stack : undefined,
      checks,
      events,
    });
  }
}

scope.enqueueFixtureStart = () => {
  void run();
};
