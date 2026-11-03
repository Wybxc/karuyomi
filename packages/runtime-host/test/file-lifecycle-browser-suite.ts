/** Run from a normal browser page with product bridge Worker builds. No Source network. */
import {
  integer,
  object,
  text,
} from '../../../runtime/teavm/bridge/bridge-common.js';

function assert(value: unknown, label: string): asserts value {
  if (!value) throw Error(label);
}
async function rejects(action: Promise<unknown>, label: string) {
  let failure: unknown;
  try {
    await action;
  } catch (error) {
    failure = error;
  }
  assert(failure instanceof Error, label);
}
class FileWorker {
  private worker: Worker;
  private sequence = 0;
  private pending = new Map<
    string,
    {
      resolve(result: Record<string, unknown>): void;
      reject(error: Error): void;
      timer: ReturnType<typeof setTimeout>;
    }
  >();
  constructor(url: URL) {
    this.worker = new Worker(url);
    this.worker.onmessage = (event: MessageEvent<unknown>) => {
      const value = object(event.data),
        id = text(value.id),
        task = this.pending.get(id);
      if (!task) return;
      this.pending.delete(id);
      clearTimeout(task.timer);
      if (typeof value.error === 'string') task.reject(Error(value.error));
      else task.resolve(object(value.result));
    };
    this.worker.onerror = (event) => this.fail(Error(event.message));
  }
  control(control: string, extra: Record<string, unknown> = {}) {
    return this.send({ control, ...extra });
  }
  call(operation: string, extra: Record<string, unknown> = {}) {
    return this.send({ request: { operation, ...extra } });
  }
  private send(message: Record<string, unknown>) {
    const id = String(++this.sequence);
    return new Promise<Record<string, unknown>>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(Error('File fixture command timed out'));
      }, 15000);
      this.pending.set(id, { resolve, reject, timer });
      this.worker.postMessage({ id, ...message });
    });
  }
  async open(path: string, extra: Record<string, unknown> = {}) {
    return text(
      (
        await this.call('open', {
          path,
          readable: true,
          writable: true,
          ...extra,
        })
      ).handle,
    );
  }
  async create(path: string, extra: Record<string, unknown> = {}) {
    await this.call('create', { path });
    return this.open(path, extra);
  }
  async write(handle: string, bytes: Uint8Array) {
    assert(
      (await this.control('write', { handle, bytes })).accepted === true,
      'Write committed',
    );
  }
  async read(handle: string, maximum = 65536): Promise<Uint8Array | null> {
    const value = (await this.control('read', { handle, maximum })).bytes;
    if (value === null) return null;
    assert(
      value instanceof Uint8Array && value.length <= maximum,
      'Bounded binary read',
    );
    return value;
  }
  private fail(error: Error) {
    for (const task of this.pending.values()) {
      clearTimeout(task.timer);
      task.reject(error);
    }
    this.pending.clear();
  }
  terminate() {
    this.worker.terminate();
    this.fail(Error('File fixture Worker terminated'));
  }
}
const FILE = 64 * 1024 * 1024;
async function until(worker: FileWorker, control: string, property: string) {
  for (let attempt = 0; attempt < 100; attempt++) {
    if ((await worker.control(control))[property] === true) return;
    await new Promise<void>((resolve) => setTimeout(resolve, 10));
  }
  throw Error('Fixture barrier not reached: ' + control);
}
function equal(actual: Uint8Array | null, expected: Uint8Array, label: string) {
  assert(
    actual?.length === expected.length &&
      actual.every((byte, index) => byte === expected[index]),
    label,
  );
}
export async function runFileLifecycleSuite(workerUrl: string) {
  const url = new URL(workerUrl, location.href);
  url.searchParams.set('fsNamespace', 'files-stage3-' + crypto.randomUUID());
  const workers: FileWorker[] = [],
    checks: string[] = [],
    make = (target = url) => {
      const worker = new FileWorker(target);
      workers.push(worker);
      return worker;
    };
  const a = make(),
    b = make();
  try {
    await a.call('initialize');
    const first = await a.create('/tmp/binary'),
      fixture = new Uint8Array(65536);
    for (let i = 0; i < fixture.length; i++) fixture[i] = i & 255;
    await a.write(first, fixture);
    await a.write(first, fixture);
    await a.write(first, new Uint8Array([0, 255, 7]));
    await a.call('seek', { handle: first, position: 0 });
    equal(await a.read(first), fixture, 'First binary chunk exact');
    equal(await a.read(first), fixture, 'Second binary chunk exact');
    equal(
      await a.read(first),
      new Uint8Array([0, 255, 7]),
      'Short final chunk exact',
    );
    assert((await a.read(first)) === null, 'EOF is null');
    await rejects(
      a.control('write', { handle: first, bytes: new Uint8Array(65537) }),
      'Oversized write rejects',
    );
    await rejects(
      a.control('read', { handle: first, maximum: 65537 }),
      'Oversized demand rejects',
    );
    await rejects(
      a.call('write', { handle: first, body: 'AA==' }),
      'Old JSON body operation removed',
    );
    const boundary = new Uint8Array([5, 6, 7, 8]);
    await a.call('seek', { handle: first, position: 65535 });
    await a.write(first, boundary);
    await a.call('seek', { handle: first, position: 65535 });
    equal(
      await a.read(first, 4),
      boundary,
      'Unaligned write crosses two chunks',
    );
    checks.push('bounded-binary-random-io-and-no-base64');

    const sparse = await a.create('/tmp/sparse');
    await a.call('resize', { handle: sparse, size: FILE });
    let snapshot = await a.control('snapshot');
    assert(
      object(snapshot.usage).logicalBytes === FILE + 131075,
      'Sparse logical bytes charged',
    );
    assert(
      Array.isArray(snapshot.chunkKeys) && snapshot.chunkKeys.length === 3,
      'Sparse resize creates no chunks',
    );
    await a.call('seek', { handle: sparse, position: FILE - 1 });
    await a.write(sparse, new Uint8Array([42]));
    await a.call('seek', { handle: sparse, position: FILE - 2 });
    equal(
      await a.read(sparse, 2),
      new Uint8Array([0, 42]),
      'Sparse missing range zero filled',
    );
    await rejects(
      a.call('resize', { handle: sparse, size: FILE + 1 }),
      'File limit rejects',
    );
    assert(
      (await a.call('tell', { handle: sparse })).position === FILE,
      'Failed resize keeps cursor',
    );
    checks.push('sparse-resize-and-file-capacity');

    const sibling = await b.open('/tmp/binary');
    await b.call('seek', { handle: sibling, position: 100000 });
    await a.call('resize', { handle: first, size: 65537 });
    await a.call('resize', { handle: first, size: 131075 });
    await a.call('seek', { handle: first, position: 65535 });
    equal(
      await a.read(first, 5),
      new Uint8Array([5, 6, 0, 0, 0]),
      'Truncate and reextend never expose old tail',
    );
    assert(
      (await b.call('tell', { handle: sibling })).position === 100000,
      'Sibling cursor remains independent',
    );
    equal(
      await b.read(sibling, 3),
      new Uint8Array(3),
      'Sibling observes committed zeros',
    );
    checks.push('truncate-reextend-zero-and-independent-cursors');

    const replacement = await a.create('/tmp/replacement');
    await a.write(replacement, new Uint8Array([9, 10]));
    assert(
      (
        await a.call('rename', {
          source: '/tmp/binary',
          path: '/tmp/replacement',
        })
      ).changed === true,
      'Rename replaces target',
    );
    await a.call('seek', { handle: replacement, position: 0 });
    equal(
      await a.read(replacement, 2),
      new Uint8Array([9, 10]),
      'Replaced target open inode survives',
    );
    await a.call('delete', { path: '/tmp/replacement' });
    await b.call('seek', { handle: sibling, position: 65535 });
    equal(
      await b.read(sibling, 2),
      new Uint8Array([5, 6]),
      'Cold read through original handle survives rename/unlink',
    );
    await b.write(sibling, new Uint8Array([22]));
    await a.call('seek', { handle: first, position: 65537 });
    equal(
      await a.read(first, 1),
      new Uint8Array([22]),
      'Unlinked open inode still writable',
    );
    for (const handle of [first, replacement])
      await a.call('close', { handle });
    await b.call('close', { handle: sibling });
    checks.push('rename-replacement-and-unlinked-open-inodes');

    await a.call('mkdir', { path: '/tmp/source' });
    const nested = await a.create('/tmp/source/\uffffz');
    await a.write(nested, new Uint8Array([31]));
    await a.call('rename', { source: '/tmp/source', path: '/tmp/moved' });
    assert(
      (await b.call('stat', { path: '/tmp/moved/\uffffz' })).exists === true,
      'Directory rename includes high Unicode suffix',
    );
    await a.call('seek', { handle: nested, position: 0 });
    equal(
      await a.read(nested, 1),
      new Uint8Array([31]),
      'Directory rename preserves handles',
    );
    await a.call('close', { handle: nested });
    await a.call('delete', { path: '/tmp/moved/\uffffz' });
    await a.call('delete', { path: '/tmp/moved' });
    checks.push('directory-rename-and-unicode-paths');

    const appendA = await a.create('/tmp/append', { append: true }),
      appendB = await b.open('/tmp/append', { append: true });
    await Promise.all([
      a.write(appendA, new Uint8Array(65536).fill(11)),
      b.write(appendB, new Uint8Array(65536).fill(12)),
    ]);
    const reader = await a.open('/tmp/append', { writable: false }),
      one = await a.read(reader),
      two = await a.read(reader);
    assert(
      one?.every((byte) => byte === one[0]) &&
        two?.every((byte) => byte === two[0]) &&
        one[0] !== two[0] &&
        [one[0], two[0]].every((byte) => byte === 11 || byte === 12),
      'Concurrent append computes EOF inside transactions',
    );
    for (const handle of [appendA, reader]) await a.call('close', { handle });
    await b.call('close', { handle: appendB });
    await a.call('delete', { path: '/tmp/append' });
    const isolatedUrl = new URL(url);
    isolatedUrl.searchParams.set(
      'fsNamespace',
      'isolated-' + crypto.randomUUID(),
    );
    const isolated = make(isolatedUrl);
    assert(
      (await isolated.call('stat', { path: '/tmp/sparse' })).exists === false,
      'Namespaces isolated',
    );
    await isolated.control('close-system');
    checks.push('multiworker-append-and-namespace-isolation');

    const limitB = await b.create('/tmp/limit-b');
    // Remove all other logical bytes before filling the shared namespace.
    await a.call('resize', { handle: sparse, size: FILE });
    await b.call('resize', { handle: limitB, size: FILE });
    const excess = await b.create('/tmp/excess');
    await rejects(
      b.write(excess, new Uint8Array([1])),
      'Namespace logical capacity rejects',
    );
    assert(
      (await b.call('tell', { handle: excess })).position === 0,
      'Rejected write never advances cursor',
    );
    await a.call('delete', { path: '/tmp/sparse' });
    await rejects(
      b.write(excess, new Uint8Array([1])),
      'Unlinked open inode still charged',
    );
    await a.call('close', { handle: sparse });
    await b.write(excess, new Uint8Array([1]));
    await b.call('close', { handle: limitB });
    await b.call('delete', { path: '/tmp/limit-b' });
    await b.call('close', { handle: excess });
    await b.call('delete', { path: '/tmp/excess' });
    checks.push('namespace-and-unlinked-open-capacity');

    const handleFile = await a.create('/tmp/handles');
    await a.write(handleFile, new Uint8Array([77]));
    const opened: string[] = [handleFile];
    for (let index = 1; index < 64; index++)
      opened.push(await a.open('/tmp/handles'));
    await rejects(
      b.open('/tmp/handles', { readable: false, writable: true }),
      'Shared namespace handle quota rejects',
    );
    await a.call('seek', { handle: handleFile, position: 0 });
    equal(
      await a.read(handleFile, 1),
      new Uint8Array([77]),
      'Failed output open rolls back truncation',
    );
    for (const handle of opened) await a.call('close', { handle });
    await a.call('delete', { path: '/tmp/handles' });
    await rejects(
      a.call('create', { path: '/tmp/' + 'x'.repeat(4096) }),
      'Path bound rejects',
    );
    checks.push('handle-quota-and-output-open-rollback');

    const metadataPaths: string[] = [];
    let capacityRejected = false;
    for (let index = 0; index < 400; index++) {
      const path = '/tmp/' + 'm'.repeat(3500) + index;
      try {
        await a.call('create', { path });
        metadataPaths.push(path);
      } catch (error) {
        assert(
          error instanceof Error && error.message.includes('capacity'),
          'Metadata failure is capacity, not IO',
        );
        capacityRejected = true;
        break;
      }
    }
    assert(
      capacityRejected && metadataPaths.length > 0,
      'Metadata has a separate bounded namespace budget',
    );
    assert(
      integer(object((await a.control('snapshot')).usage).metadataBytes) <=
        2 * 1024 * 1024,
      'Rejected metadata creation rolls accounting back',
    );
    for (const path of metadataPaths) await a.call('delete', { path });
    checks.push('metadata-budget-and-atomic-creation-rejection');

    const failed = await a.create('/tmp/failure');
    await a.write(failed, fixture);
    await a.write(failed, fixture);
    await a.call('seek', { handle: failed, position: 65535 });
    const before = await a.control('snapshot');
    await a.control('fail-write', { after: 2 });
    await rejects(
      a.write(failed, new Uint8Array([90, 91])),
      'Real IDB ConstraintError rejects',
    );
    assert(
      (await a.call('tell', { handle: failed })).position === 65535,
      'Aborted write cursor unchanged',
    );
    equal(
      await a.read(failed, 2),
      new Uint8Array([255, 0]),
      'Aborted cross-chunk write preserves all prior bytes',
    );
    const after = await a.control('snapshot');
    assert(
      JSON.stringify(before.usage) === JSON.stringify(after.usage),
      'Aborted transaction rolls usage back',
    );
    checks.push('idb-abort-preserves-data-length-cursor-and-usage');

    await a.control('pause-write');
    const heldWrite = a.write(failed, new Uint8Array([20]));
    await until(a, 'paused', 'paused');
    const queued = [
      a.call('size', { handle: failed }),
      a.call('flush', { handle: failed }),
      a.call('tell', { handle: failed }),
    ];
    await rejects(
      a.call('size', { handle: failed }),
      'Pending operation queue is bounded',
    );
    await a.control('resume-write');
    await Promise.all([heldWrite, ...queued]);
    checks.push('bounded-pending-operations');

    const closingWorker = make(),
      baseline = object((await b.control('snapshot')).usage),
      closingFile = await closingWorker.create('/tmp/close-shared');
    await closingWorker.write(closingFile, new Uint8Array([17]));
    const peer = await b.open('/tmp/close-shared', { writable: false });
    await closingWorker.call('delete', { path: '/tmp/close-shared' });
    const ownRetired = await closingWorker.create('/tmp/close-retired');
    await closingWorker.call('resize', { handle: ownRetired, size: 1048576 });
    await closingWorker.write(ownRetired, new Uint8Array([18]));
    await closingWorker.call('delete', { path: '/tmp/close-retired' });
    const beforeCloseFailure = object((await b.control('snapshot')).usage);
    await closingWorker.control('fail-close');
    await rejects(
      closingWorker.control('close-system'),
      'Real IDB abort rejects system teardown',
    );
    await b.call('open', { path: '/tmp/does-not-exist', readable: true });
    assert(
      JSON.stringify(object((await b.control('snapshot')).usage)) ===
        JSON.stringify(beforeCloseFailure),
      'Failed teardown retains owner lock, handles, unlinked data and all quota',
    );
    equal(
      await b.read(peer, 1),
      new Uint8Array([17]),
      'Failed teardown preserves foreign open handle',
    );
    await rejects(
      closingWorker.call('initialize'),
      'Failed cleanup remains fail-closed',
    );
    await closingWorker.control('close-system');
    assert(
      object((await b.control('snapshot')).usage).logicalBytes ===
        integer(baseline.logicalBytes) + 1,
      'Explicit teardown retry releases only owned retired inode',
    );
    await b.call('seek', { handle: peer, position: 0 });
    equal(
      await b.read(peer, 1),
      new Uint8Array([17]),
      'Successful owner cleanup preserves foreign pin',
    );
    await b.call('close', { handle: peer });
    assert(
      JSON.stringify(object((await b.control('snapshot')).usage)) ===
        JSON.stringify(baseline),
      'Retry and final foreign close restore complete accounting',
    );
    checks.push('idb-abort-on-system-close-retains-owner-and-explicit-retry');

    const abandoned = await a.create('/tmp/abandoned');
    await a.call('resize', { handle: abandoned, size: FILE });
    await a.call('delete', { path: '/tmp/abandoned' });
    await a.control('reset-metrics');
    await a.call('stat', { path: '/tmp/failure' });
    await a.call('list', { path: '/tmp' });
    await a.call('size', { handle: failed });
    await a.call('flush', { handle: failed });
    assert(
      (await a.control('snapshot')).chunkReads === 0,
      'Metadata operations do not read file bodies',
    );
    await a.call('seek', { handle: failed, position: 0 });
    await a.control('pause-write');
    const inFlight = a.write(failed, new Uint8Array([88])).catch(() => {});
    await until(a, 'paused', 'paused');
    a.terminate();
    await inFlight;
    const reopened = make(),
      alive = await b.open('/tmp/failure', { writable: false });
    const recovered = await reopened.open('/tmp/failure', { writable: false });
    equal(
      await reopened.read(recovered, 1),
      new Uint8Array([0]),
      'Terminated pending transaction rolls back',
    );
    const reclaimed = object((await reopened.control('snapshot')).usage);
    assert(
      integer(reclaimed.handles) === 2,
      'Dead handles reclaimed without reclaiming live owner',
    );
    assert(
      reclaimed.logicalBytes === 131072,
      'Dead owner releases unlinked sparse inode quota',
    );
    checks.push('metadata-only-and-terminate-pending-transaction');

    const late = await reopened.open('/tmp/failure');
    await reopened.control('drop-write-reply');
    const lateWrite = reopened
      .write(late, new Uint8Array([99]))
      .catch(() => {});
    await until(reopened, 'committed', 'committed');
    reopened.terminate();
    await lateWrite;
    const final = make(),
      finalHandle = await final.open('/tmp/failure', { writable: false });
    equal(
      await final.read(finalHandle, 1),
      new Uint8Array([99]),
      'Commit survives death before Java continuation ACK',
    );
    await b.call('seek', { handle: alive, position: 0 });
    equal(
      await b.read(alive, 1),
      new Uint8Array([99]),
      'Live sibling handle remains usable',
    );
    await final.call('delete', { path: '/tmp/failure' });
    await final.control('close-system');
    await rejects(
      final.call('initialize'),
      'Closed filesystem rejects future operations',
    );
    await b.call('close', { handle: alive });
    assert(
      object((await b.control('snapshot')).usage).allocatedBytes === 0,
      'Final handle close collects retired inode chunks',
    );
    checks.push('commit-before-ack-and-owned-system-teardown');
    return {
      passed: true,
      checks,
      userAgent: navigator.userAgent,
      scope:
        'Actual Worker, IndexedDB and Web Locks with product file bridge; controlled faults, no Source/Java/Native/performance claim.',
    };
  } finally {
    for (const worker of workers) worker.terminate();
  }
}
