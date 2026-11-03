/** Actual TeaVM Java references plus the formal product graphics bridge, in a real Worker. */
import {
  object,
  workerScope,
} from '../../../runtime/teavm/bridge/bridge-common.js';
import type {} from '../../../runtime/teavm/bridge/graphics-bridge.js';
declare global {
  var bitmapLifetimeDone: ((json: string) => void) | undefined;
  var bitmapLifetimeRun: (() => void) | undefined;
  var bitmapLifetimeRetain: (() => void) | undefined;
  var bitmapLifetimeAllocate: (() => void) | undefined;
  var bitmapLifetimeUse: (() => void) | undefined;
  var bitmapLifetimeDrop: (() => void) | undefined;
}
function assert(value: unknown, message: string): asserts value {
  if (!value) throw Error(message);
}
const scope = workerScope();
self.onmessage = async () => {
  const begin = scope.teaGraphicsBegin,
    end = scope.teaGraphicsEnd,
    snapshot = scope.teaGraphicsSnapshot;
  assert(begin && end && snapshot, 'Product graphics lifecycle installed');
  let serial = 0;
  const invoke = async (action: (() => void) | undefined) => {
    assert(action, 'Real Java export installed');
    const identity = {
      requestId: 'java-bitmap-' + ++serial,
      generation: String(serial),
    };
    begin(identity);
    try {
      const json = await new Promise<string>((resolve, reject) => {
        const timer = setTimeout(
          () => reject(Error('Java Bitmap gate timed out')),
          30000,
        );
        scope.bitmapLifetimeDone = (value) => {
          clearTimeout(timer);
          resolve(value);
        };
        try {
          action();
        } catch (error) {
          clearTimeout(timer);
          reject(error);
        }
      });
      const result = object(JSON.parse(json) as unknown);
      assert(
        result.passed === true,
        'Java Bitmap scenario: ' + JSON.stringify(result),
      );
      return result;
    } finally {
      scope.bitmapLifetimeDone = undefined;
      end(identity.requestId, identity.generation);
    }
  };
  const observe = async (expected: number) => {
    const started = performance.now();
    let pressure: { value: number }[] | undefined;
    for (
      let attempt = 0;
      attempt < 80 && snapshot().surfaces !== expected;
      attempt++
    ) {
      pressure = Array.from({ length: 32768 }, (_, value) => ({ value }));
      assert(
        pressure[32767]?.value === 32767,
        'Bounded observable heap pressure',
      );
      await new Promise((resolve) => setTimeout(resolve, 10));
      pressure = undefined;
    }
    const identity = {
      requestId: 'java-bitmap-reap-' + ++serial,
      generation: String(serial),
    };
    begin(identity);
    end(identity.requestId, identity.generation);
    const resources = snapshot();
    return {
      observed: resources.surfaces === expected,
      elapsedMs: performance.now() - started,
      forced: false,
      resources,
    };
  };
  try {
    const contracts = await invoke(scope.bitmapLifetimeRun);
    assert(
      contracts.checks === 13 && object(contracts.text).checks === 101,
      'Original Android shared Bitmap13 and Text101 contracts',
    );
    assert(
      Object.values(snapshot()).every((value) => value === 0),
      'Shared contracts release fixtures',
    );
    await invoke(scope.bitmapLifetimeRetain);
    assert(
      snapshot().surfaces === 2,
      'Static Bitmap and Canvas-only owner survive End',
    );
    await invoke(scope.bitmapLifetimeAllocate);
    const unreachable = await observe(2);
    await invoke(scope.bitmapLifetimeUse);
    assert(
      snapshot().surfaces >= 2,
      'Live Java owners survive real GC and a later operation',
    );
    await invoke(scope.bitmapLifetimeDrop);
    const dropped = await observe(0);
    self.postMessage({
      passed: unreachable.observed && dropped.observed,
      contracts,
      checks: [
        'real-teavm-jso-bitmap-copy-13-and-text-101',
        'unrecycled-locals-collected-while-java-bitmap-and-canvas-remain-live',
        'retained-java-owners-released-only-after-references-dropped',
      ],
      unreachable,
      dropped,
      resources: snapshot(),
    });
  } catch (error) {
    self.postMessage({
      passed: false,
      error: String(error),
      resources: snapshot(),
    });
  }
};
