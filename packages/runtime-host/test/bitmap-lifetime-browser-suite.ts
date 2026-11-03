/** Real Canvas Worker gate for Java-owned surface leases and bounded GC observation. */
import {
  integer,
  workerScope,
} from '../../../runtime/teavm/bridge/bridge-common.js';
import type {} from '../../../runtime/teavm/bridge/graphics-bridge.js';
function assert(value: unknown, message: string): asserts value {
  if (!value) throw Error(message);
}
const scope = workerScope();
self.onmessage = async () => {
  const checks: string[] = [];
  const begin = scope.teaGraphicsBegin,
    end = scope.teaGraphicsEnd,
    sync = scope.teaGraphicsSync,
    asynchronous = scope.teaGraphicsAsync,
    snapshot = scope.teaGraphicsSnapshot,
    claim = scope.teaGraphicsBitmapClaim,
    bitmapId = scope.teaGraphicsBitmapId,
    recycle = scope.teaGraphicsBitmapRecycle;
  assert(
    begin &&
      end &&
      sync &&
      asynchronous &&
      snapshot &&
      claim &&
      bitmapId &&
      recycle,
    'Product bitmap lifetime bridge installed',
  );
  let serial = 0;
  const start = () => {
    const identity = {
      requestId: 'bitmap-lifetime-' + ++serial,
      generation: String(serial),
    };
    begin(identity);
    return () => end(identity.requestId, identity.generation);
  };
  const create = () =>
    integer(sync({ op: 'create', width: 16, height: 16 }).id, 1);
  const clean = () =>
    assert(
      Object.values(snapshot()).every((value) => value === 0),
      'Every graphics reservation released',
    );
  const rejected = (operation: () => unknown) => {
    let failed = false;
    try {
      operation();
    } catch (error) {
      failed = error instanceof Error;
    }
    assert(failed, 'Invalid owner rejected');
  };
  let finish = start();
  const id = create(),
    owner = claim(id);
  sync({ op: 'color', id: bitmapId(owner), color: -65536 });
  rejected(() => claim(id));
  rejected(() => bitmapId({ id }));
  finish();
  assert(snapshot().surfaces === 1, 'Live owner retained across End');
  await new Promise((resolve) => setTimeout(resolve, 0));
  finish = start();
  assert(bitmapId(owner) === id, 'Retained owner usable in a later operation');
  sync({ op: 'color', id: bitmapId(owner), color: -16711936 });
  recycle(owner);
  recycle(owner);
  rejected(() => bitmapId(owner));
  finish();
  clean();
  checks.push('live-owner-survives-end-and-counterfeit-duplicate-rejected');
  checks.push('explicit-recycle-idempotent-and-stale-owner-rejected');

  finish = start();
  create();
  finish();
  clean();
  checks.push('unadopted-result-reclaimed-at-operation-end');

  finish = start();
  const liveOwners = Array.from({ length: 64 }, () => claim(create()));
  rejected(create);
  finish();
  assert(
    snapshot().surfaces === 64,
    'Count pressure never evicts a live Java owner',
  );
  for (const value of liveOwners) recycle(value);
  clean();
  checks.push('live-owner-count-budget-rejects-without-eviction');

  finish = start();
  const encoding = claim(create());
  const original = OffscreenCanvas.prototype.convertToBlob;
  let resume: (() => void) | undefined;
  const gate = new Promise<void>((resolve) => {
    resume = resolve;
  });
  OffscreenCanvas.prototype.convertToBlob = function (options) {
    return gate.then(() => original.call(this, options));
  };
  let cancelled = false;
  const encoded = asynchronous({
    op: 'encode',
    id: bitmapId(encoding),
    format: 'PNG',
    quality: 100,
  }).catch((error) => {
    cancelled = error instanceof Error;
  });
  try {
    recycle(encoding);
    assert(
      snapshot().surfaces === 0 && snapshot().rasterBytes > 0,
      'Retired encoding surface stays reserved while browser work is pinned',
    );
    finish();
    assert(resume, 'Controlled encode gate');
    resume();
    await encoded;
    assert(cancelled, 'Ended operation discards late encoded output');
  } finally {
    OffscreenCanvas.prototype.convertToBlob = original;
    resume?.();
    await encoded;
  }
  clean();
  checks.push(
    'recycle-during-encode-preserves-pins-until-late-result-is-discarded',
  );

  const droppedIds: number[] = [];
  const allocateUnrecycled = () => {
    for (let i = 0; i < 8; i++) {
      const value = create();
      droppedIds.push(value);
      claim(value);
    }
  };
  finish = start();
  allocateUnrecycled();
  finish();
  const retainedBeforeGC = snapshot().surfaces;
  assert(retainedBeforeGC === 8, 'Adopted owner is not eagerly deleted by End');
  const started = performance.now();
  let pressure: { value: number }[] | undefined;
  for (let attempt = 0; attempt < 80 && snapshot().surfaces > 0; attempt++) {
    // Bounded ordinary heap pressure and task boundaries, never a fake finalizer.
    pressure = Array.from({ length: 32768 }, (_, value) => ({ value }));
    assert(
      pressure[32767]?.value === 32767,
      'Pressure allocation is observable',
    );
    await new Promise((resolve) => setTimeout(resolve, 10));
    pressure = undefined;
  }
  finish = start();
  finish(); // Reap weak owners whose cleanup callback is still queued.
  const gcResources = snapshot(),
    gcObserved = gcResources.surfaces === 0;
  const gc = {
    observed: gcObserved,
    elapsedMs: performance.now() - started,
    retainedBeforeGC,
    resources: gcResources,
    forced: false,
  };
  // If GC was not scheduled, clean the fixture by id after recording that fact.
  for (const value of droppedIds) sync({ op: 'recycle', id: value });
  clean();
  self.postMessage({
    passed: gcObserved,
    mechanismPassed: true,
    checks,
    gc,
    resources: snapshot(),
  });
};
