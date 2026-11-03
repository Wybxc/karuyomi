/** Real Worker/Web Locks/IndexedDB gate, including explicit test fault injection. */
import { object, text } from '../../../runtime/teavm/bridge/bridge-common.js';

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw Error(message);
}
interface Pending {
  resolve(value: Record<string, unknown>): void;
  reject(error: Error): void;
  timer: ReturnType<typeof setTimeout>;
}
class CacheWorker {
  readonly worker: Worker;
  private sequence = 0;
  private pending = new Map<string, Pending>();
  constructor(url: URL) {
    this.worker = new Worker(url);
    this.worker.onmessage = (event: MessageEvent<unknown>) => {
      const message = object(event.data),
        id = text(message.id);
      const pending = this.pending.get(id);
      if (!pending) return;
      this.pending.delete(id);
      clearTimeout(pending.timer);
      if (typeof message.error === 'string')
        pending.reject(Error(message.error));
      else pending.resolve(object(message.result));
    };
    this.worker.onerror = (event) => this.fail(Error(event.message));
  }
  private send(label: string, message: Record<string, unknown>) {
    const id = String(++this.sequence);
    return new Promise<Record<string, unknown>>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(Error('Cache Worker command timed out: ' + label));
      }, 10000);
      this.pending.set(id, { resolve, reject, timer });
      this.worker.postMessage({ id, ...message });
    });
  }
  call(operation: string, extra: Record<string, unknown> = {}, handle = 'one') {
    return this.send(operation, {
      request: {
        operation,
        directory: '/cache-lifecycle',
        maxSize: 1048576,
        handle,
        url: 'https://fixture.example.org/cache',
        metadata: { status: 200 },
        ...extra,
      },
    });
  }
  control(control: string, extra: Record<string, unknown> = {}) {
    return this.send(control, { control, ...extra });
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
    this.fail(Error('Test Worker terminated'));
  }
}
const body = 'AP+A5oyB5LmF5YyW';
const edit = (
  editor: Record<string, unknown>,
  metadata: unknown = { status: 200 },
) => ({
  editor: editor.editor,
  expected: editor.version,
  generation: editor.generation,
  body,
  metadata,
});

async function expectFailure(action: Promise<unknown>, message: string) {
  let failure: unknown;
  try {
    await action;
  } catch (error) {
    failure = error;
  }
  assert(failure instanceof Error, message);
  return failure;
}

async function readExact(
  client: CacheWorker,
  reader: unknown,
  expected: Uint8Array,
  handle = 'one',
) {
  let offset = 0;
  for (let step = 0; step < 16; step++) {
    const bytes = (
      await client.control('read', { reader, handle, maximum: 65536 })
    ).bytes;
    if (bytes === null) {
      assert(offset === expected.length, 'Snapshot reaches exact complete EOF');
      return;
    }
    assert(
      bytes instanceof Uint8Array && bytes.length > 0 && bytes.length <= 65536,
      'Snapshot uses bounded binary chunks',
    );
    assert(
      offset + bytes.length <= expected.length &&
        bytes.every((value, index) => value === expected[offset + index]),
      'Snapshot retains exact bytes',
    );
    offset += bytes.length;
  }
  throw Error('Snapshot did not reach EOF in its bounded fixture');
}

async function readerFailureGates(
  url: URL,
  b: CacheWorker,
  c: CacheWorker,
  large: Uint8Array,
  encodedLarge: string,
  checks: string[],
) {
  const seed = async () => {
    await c.call('clear');
    const editor = await c.call('begin');
    assert(
      (await c.call('put', { ...edit(editor), body: encodedLarge }))
        .committed === true,
      'Seed complete reader-lifecycle fixture',
    );
  };
  await seed();
  const dying = new CacheWorker(url);
  try {
    const dead = object((await dying.call('get', { raw: true })).entry),
      live = object((await b.call('get', { raw: true })).entry);
    assert(
      (await dying.control('read', { reader: dead.reader, maximum: 3 }))
        .bytes instanceof Uint8Array,
      'Reader Worker consumed a prefix before dying',
    );
    await c.call('clear');
    assert(
      (await c.call('size')).allocatedBytes === large.length,
      'Both live pins retain one retired body',
    );
    dying.terminate();
    await c.call('size');
    await readExact(b, live.reader, large);
    assert(
      (await c.call('size')).allocatedBytes === 0,
      'Dead reader reclaimed without deleting the live sibling pin',
    );
    checks.push('reader-worker-death-reclaims-retired-body-with-live-sibling');
  } finally {
    dying.terminate();
  }

  const cases: { name: string; index: number; bytes: Uint8Array | null }[] = [
    { name: 'missing', index: 1, bytes: null },
    { name: 'empty', index: 1, bytes: new Uint8Array(0) },
    { name: 'oversized', index: 1, bytes: new Uint8Array(65537) },
    { name: 'truncated-first', index: 0, bytes: large.slice(0, 65535) },
    { name: 'truncated-last', index: 2, bytes: large.slice(131072, -1) },
    { name: 'overlong-last', index: 2, bytes: new Uint8Array(8) },
  ];
  for (const fixture of cases) {
    await seed();
    const doomed = object((await b.call('get', { raw: true })).entry),
      sibling = object((await c.call('get', { raw: true })).entry);
    await b.control('read', { reader: doomed.reader, maximum: 3 });
    await c.call('clear');
    await b.control('mutate-chunk', {
      reader: doomed.reader,
      index: fixture.index,
      bytes: fixture.bytes,
    });
    let ended = false;
    const failure = await expectFailure(
      (async () => {
        for (let step = 0; step < 16; step++) {
          const bytes = (
            await b.control('read', { reader: doomed.reader, maximum: 65536 })
          ).bytes;
          if (bytes === null) {
            ended = true;
            return;
          }
          assert(
            bytes instanceof Uint8Array,
            'Corrupt snapshot still uses binary until rejection',
          );
        }
      })(),
      'Corrupt chunk must fail: ' + fixture.name,
    );
    assert(
      !ended && /cache (body|reader)/i.test(failure.message),
      'Corruption produces a storage error rather than successful EOF: ' +
        fixture.name,
    );
    assert(
      (await c.call('size')).allocatedBytes === large.length,
      'Error cleanup retains the live sibling pin: ' + fixture.name,
    );
    await c.control('mutate-chunk', {
      reader: sibling.reader,
      index: fixture.index,
      bytes: large.slice(
        fixture.index * 65536,
        Math.min(large.length, (fixture.index + 1) * 65536),
      ),
    });
    await readExact(c, sibling.reader, large);
    assert(
      (await c.call('size')).allocatedBytes === 0,
      'Error cleanup releases only the bad reader and final sibling EOF frees retired bytes',
    );
    checks.push(
      'corrupt-chunk-' + fixture.name + '-fails-without-eof-or-pin-leak',
    );
  }

  for (const operation of ['reader-close', 'read-abort']) {
    await seed();
    const doomed = object((await b.call('get', { raw: true })).entry),
      sibling = object((await c.call('get', { raw: true })).entry);
    await b.control('read', { reader: doomed.reader, maximum: 65536 });
    await c.call('clear');
    if (operation === 'reader-close') {
      await b.call('reader-close', { reader: doomed.reader });
      await expectFailure(
        b.control('read', { reader: doomed.reader, maximum: 1 }),
        'Read after explicit reader close must fail rather than return EOF',
      );
    } else {
      await b.control('fail-next-read');
      const failure = await expectFailure(
        b.control('read', { reader: doomed.reader, maximum: 1024 }),
        'Real IDB failure during a later read must be reported',
      );
      assert(
        failure.message.includes('ConstraintError'),
        'Read preserves original IDB abort error',
      );
    }
    assert(
      (await c.call('size')).allocatedBytes === large.length,
      'Early reader cleanup retains live sibling bytes',
    );
    await readExact(c, sibling.reader, large);
    assert(
      (await c.call('size')).allocatedBytes === 0,
      'Last reader releases retired body after ' + operation,
    );
    checks.push('partial-read-' + operation + '-releases-only-its-pin');
  }

  await seed();
  const doomed = object((await b.call('get', { raw: true }, 'closing')).entry),
    sibling = object((await b.call('get', { raw: true }, 'sibling')).entry),
    foreign = object((await c.call('get', { raw: true }, 'foreign')).entry);
  await b.control('read', {
    reader: doomed.reader,
    handle: 'closing',
    maximum: 3,
  });
  await c.call('clear');
  for (const request of [
    { reader: doomed.reader, handle: 'wrong' },
    { reader: foreign.reader, handle: 'foreign' },
  ]) {
    await b.control('fail-next-close');
    const failure = await expectFailure(
      b.call('reader-close', { reader: request.reader }, request.handle),
      'Controlled reader-close failure must be preserved',
    );
    assert(
      failure.message.includes('ConstraintError'),
      'Wrong-owner failure keeps original IDB error',
    );
  }
  assert(
    (
      await b.control('read', {
        reader: doomed.reader,
        handle: 'closing',
        maximum: 1,
      })
    ).bytes instanceof Uint8Array,
    'Failed wrong-handle cleanup never invalidates the owned reader',
  );
  await b.control('fail-next-close');
  const failure = await expectFailure(
    b.call('reader-close', { reader: doomed.reader }, 'closing'),
    'Failed owned reader close still reports storage failure',
  );
  assert(
    failure.message.includes('ConstraintError'),
    'Independent close cleanup preserves original IDB error',
  );
  await expectFailure(
    b.control('read', { reader: doomed.reader, handle: 'closing', maximum: 1 }),
    'Failed owned reader close has nevertheless released its snapshot',
  );
  await readExact(b, sibling.reader, large, 'sibling');
  assert(
    (await c.call('size')).allocatedBytes === large.length,
    'Sibling close preserves the live foreign reader pin',
  );
  await readExact(c, foreign.reader, large, 'foreign');
  assert(
    (await c.call('size')).allocatedBytes === 0,
    'Independent failed-close cleanup frees only owned pin and leaves no retired bytes',
  );
  checks.push(
    'reader-close-idb-abort-cas-preserves-sibling-handle-and-foreign-owner',
  );
}

export async function runCacheLifecycleSuite(workerUrl: string) {
  const url = new URL(workerUrl, location.href);
  url.searchParams.set('plugin', 'cache-lifecycle-' + crypto.randomUUID());
  const a = new CacheWorker(url),
    b = new CacheWorker(url),
    c = new CacheWorker(url);
  const checks: string[] = [];
  try {
    await a.call('clear');
    const initial = await a.call('begin');
    assert(initial.accepted === true, 'Initial editor accepted');
    assert(
      (await a.call('put', edit(initial))).committed === true,
      'Initial complete entry committed',
    );
    const original = object((await b.call('get')).entry);
    assert(original.body === body, 'Initial body survives another Worker');

    const abandoned = await a.call('begin');
    assert(abandoned.accepted === true, 'Worker A owns replacement editor');
    assert(
      (await b.call('begin')).accepted === false,
      'A live Worker retains exclusive editor',
    );
    assert(
      (await b.call('put', edit(abandoned))).committed === false,
      'Another live Worker cannot commit the editor',
    );
    await b.call('abort', { editor: abandoned.editor });
    assert(
      (await c.call('begin')).accepted === false,
      'Foreign put and abort preserve live owner',
    );
    checks.push('live-owner-and-handle-isolation');

    a.terminate();
    const restartStart = performance.now();
    const recovered = await b.call('begin', { metadata: { status: 201 } });
    const recoveryMs = performance.now() - restartStart;
    assert(
      recovered.accepted === true,
      'A dead Worker editor is immediately reclaimable',
    );
    assert(
      recovered.version === original.version,
      'Recovery preserves the old complete entry version',
    );
    const afterRestart = object((await c.call('get')).entry);
    assert(
      afterRestart.body === body,
      'Recovery preserves the old complete body',
    );
    assert(
      (await b.call('put', edit(abandoned, { stale: true }))).committed ===
        false,
      'Abandoned editor cannot commit after takeover',
    );
    assert(
      (await c.call('begin')).accepted === false,
      'Stale submission does not remove replacement editor',
    );
    assert(
      (await b.call('put', edit(recovered, { status: 201 }))).committed ===
        true,
      'Recovered editor commits normally',
    );
    checks.push('terminate-reopen-without-editor-timeout');

    const current = object((await b.call('get')).entry);
    assert(
      object(current.metadata).status === 201,
      'Recovered metadata committed',
    );
    assert(
      (
        await c.call('update', {
          expected: 'stale',
          generation: current.generation,
          metadata: { status: 202 },
        })
      ).committed === false,
      'Version CAS rejects stale metadata',
    );
    assert(
      (
        await c.call('update', {
          expected: current.version,
          generation: current.generation,
          metadata: { status: 203 },
        })
      ).committed === true,
      'Version CAS accepts current metadata',
    );
    assert(
      object((await b.call('get')).entry).body === body,
      'Metadata update preserves bytes',
    );
    checks.push('entry-version-cas-preserved');

    const concurrent = await Promise.all([
      b.call('begin', { url: 'concurrent' }),
      c.call('begin', { url: 'concurrent' }),
    ]);
    assert(
      concurrent.filter((value) => value.accepted === true).length === 1,
      'Only one concurrent live editor',
    );
    const winner = concurrent[0]!.accepted ? b : c;
    const winnerEditor = concurrent[0]!.accepted
      ? concurrent[0]!
      : concurrent[1]!;
    await winner.call('abort', {
      url: 'concurrent',
      editor: winnerEditor.editor,
    });
    checks.push('concurrent-editor-exclusion');

    const first = await b.call('begin', { url: 'close-one' }, 'first');
    const second = await b.call('begin', { url: 'close-two' }, 'second');
    assert(
      first.accepted === true && second.accepted === true,
      'Sibling Java handles can own independent editors',
    );
    await b.call('close', {}, 'first');
    const released = await c.call('begin', { url: 'close-one' });
    assert(
      released.accepted === true,
      'Close releases the selected handle editor',
    );
    assert(
      (await c.call('begin', { url: 'close-two' })).accepted === false,
      'Close preserves sibling handle editor',
    );
    await b.call('close', {}, 'second');
    const releasedSibling = await c.call('begin', { url: 'close-two' });
    assert(
      releasedSibling.accepted === true,
      'Closing sibling handle releases its editor',
    );
    checks.push('close-only-owned-java-handle');

    const beforeClear = await b.call('begin');
    assert(beforeClear.accepted === true, 'Editor acquired before clear');
    await c.call('clear');
    assert(
      (await b.call('put', edit(beforeClear))).committed === false,
      'Clear generation rejects pending editor',
    );
    const afterClear = await b.call('begin');
    assert(
      afterClear.accepted === true &&
        afterClear.generation !== beforeClear.generation,
      'Clear advances generation and permits new editor',
    );
    assert(
      (await c.call('begin')).accepted === false,
      'New editor remains exclusive after clear',
    );
    assert(
      (await b.call('put', edit(afterClear))).committed === true,
      'Fresh generation commits',
    );
    assert(
      object((await c.call('get')).entry).body === body,
      'Fresh generation has complete body',
    );
    checks.push('clear-generation-fence-preserved');

    const beforeFailure = object((await c.call('get')).entry);
    const failedEditor = await b.call('begin');
    await b.control('fail-next-put', { replacement: 'none' });
    let failure: unknown;
    try {
      await b.call('put', edit(failedEditor, { status: 500 }));
    } catch (error) {
      failure = error;
    }
    assert(
      failure instanceof Error && failure.message.includes('ConstraintError'),
      'Real IDB request failure remains an error',
    );
    const afterFailure = object((await c.call('get')).entry);
    assert(
      afterFailure.body === beforeFailure.body &&
        afterFailure.version === beforeFailure.version,
      'IDB abort preserves old complete entry',
    );
    const retry = await b.call('begin');
    assert(
      retry.accepted === true,
      'Failed put releases its editor while owner stays alive',
    );
    await b.call('abort', { editor: retry.editor });
    checks.push('failed-put-abort-releases-live-editor');

    for (const replacement of ['editor', 'owner', 'generation']) {
      await c.call('clear');
      const seed = await b.call('begin');
      assert(
        (await b.call('put', edit(seed))).committed === true,
        'Seed complete fault-race entry',
      );
      const sentinel = await c.call('begin', { url: 'fault-sentinel' });
      assert(sentinel.accepted === true, 'Live replacement owner sentinel');
      const doomed = await b.call('begin');
      await b.control('fail-next-put', { replacement });
      let raceFailure: unknown;
      try {
        await b.call('put', edit(doomed));
      } catch (error) {
        raceFailure = error;
      }
      assert(
        raceFailure instanceof Error &&
          raceFailure.message.includes('ConstraintError'),
        'Fault-race put still rejects: ' + replacement,
      );
      assert(
        (await c.call('begin')).accepted === false,
        'Failure cleanup preserves replacement ' + replacement,
      );
      assert(
        object((await c.call('get')).entry).body === body,
        'Fault-race keeps old complete body: ' + replacement,
      );
    }
    checks.push('failed-put-cleanup-owner-editor-generation-cas');

    await c.call('clear');
    const reclaimSentinel = await c.call('begin', { url: 'reclaim-sentinel' });
    assert(
      reclaimSentinel.accepted === true,
      'Live owner triggers a real reclaim probe',
    );
    await b.control('pause-reclaim');
    const lateBegin = b.call('begin', { url: 'late-begin' }, 'closing');
    await b.control('wait-reclaim');
    await b.call('close', {}, 'closing');
    await b.control('resume-reclaim');
    assert(
      (await lateBegin).accepted === false,
      'Close invalidates a begin already awaiting reclaim',
    );
    assert(
      (await c.call('begin', { url: 'late-begin' })).accepted === true,
      'Late begin never recreates an editor after close',
    );
    checks.push('close-fences-inflight-begin-before-await');

    await b.control('pause-reclaim');
    const deletedBegin = b.call('begin', { url: 'deleted-begin' }, 'deleting');
    await b.control('wait-reclaim');
    await b.call('delete', {}, 'deleting');
    await b.control('resume-reclaim');
    assert(
      (await deletedBegin).accepted === false,
      'Delete invalidates a begin already awaiting reclaim',
    );
    assert(
      (await c.call('begin', { url: 'deleted-begin' })).accepted === true,
      'Late begin never recreates an editor after delete',
    );
    const evictedBegin = await b.call('begin', { url: 'after-evict' }, 'live');
    assert(
      evictedBegin.accepted === true,
      'Live handle can begin before evictAll',
    );
    await b.call('clear', {}, 'live');
    assert(
      (await b.call('begin', { url: 'after-evict' }, 'live')).accepted === true,
      'EvictAll leaves its Java handle available for future begin',
    );
    checks.push('delete-fences-inflight-begin-without-closing-evictall');
    await c.call('clear');
    const large = new Uint8Array(131079);
    for (let i = 0; i < large.length; i++) large[i] = i & 255;
    // Build the fixture encoding in bounded pieces; no spread of the complete body.
    let fixture = '';
    for (let offset = 0; offset < large.length; offset += 16384)
      fixture += String.fromCharCode(...large.subarray(offset, offset + 16384));
    const encodedLarge = btoa(fixture);
    const largeEditor = await c.call('begin');
    assert(
      (await c.call('put', { ...edit(largeEditor), body: encodedLarge }))
        .committed === true,
      'Multi-chunk body commits',
    );
    const snapshot = object((await b.call('get', { raw: true })).entry);
    await b.control('reset-metrics');
    await b.call('size');
    await b.call('urls');
    await b.call('flush');
    assert(
      (
        await b.call('update', {
          expected: snapshot.version,
          generation: snapshot.generation,
          metadata: { status: 304 },
        })
      ).committed === true,
      'Metadata update on immutable snapshot body',
    );
    assert(
      (await b.control('metrics')).chunkReads === 0,
      'Size, URLs, LRU and 304 update never read chunks',
    );
    const prefix = (
      await b.control('read', { reader: snapshot.reader, maximum: 3 })
    ).bytes;
    assert(
      prefix instanceof Uint8Array && prefix.length === 3,
      'Snapshot read obeys demand',
    );
    const replacementEditor = await c.call('begin', {
      metadata: { status: 204 },
    });
    assert(
      (await c.call('put', edit(replacementEditor))).committed === true,
      'Replace entry without changing existing snapshot',
    );
    assert(
      object((await c.call('get')).entry).body === body,
      'New get sees complete replacement body',
    );
    await c.call('clear');
    const retained = await c.call('size');
    assert(
      retained.size === 0 && retained.allocatedBytes === large.length,
      'Clear retains pinned body in allocated budget',
    );
    const parts: Uint8Array[] = [prefix];
    let total = prefix.length;
    for (;;) {
      const part = (
        await b.control('read', { reader: snapshot.reader, maximum: 65536 })
      ).bytes;
      if (part === null) break;
      assert(
        part instanceof Uint8Array && part.length <= 65536,
        'Bounded binary snapshot chunk',
      );
      parts.push(part);
      total += part.length;
    }
    const restored = new Uint8Array(total);
    let at = 0;
    for (const part of parts) {
      restored.set(part, at);
      at += part.length;
    }
    assert(
      total === large.length &&
        restored.every((value, index) => value === large[index]),
      'Pinned old body survives clear exactly',
    );
    assert(
      (await c.call('size')).allocatedBytes === 0,
      'EOF releases retired body and allocated budget',
    );
    checks.push('binary-chunks-snapshot-replace-clear-and-eof-budget');
    checks.push('metadata-only-size-urls-lru-and-304');

    const limited = await b.call('begin', { maxSize: 100, url: 'budget' });
    assert(limited.accepted === true, 'Small metadata fits budget');
    assert(
      (
        await b.control('write', {
          editor: limited.editor,
          sequence: 0,
          bytes: new Uint8Array(101),
        })
      ).accepted === false,
      'Over-budget chunk aborts staging',
    );
    assert(
      (await b.call('begin', { maxSize: 100, url: 'budget' })).accepted ===
        true,
      'Budget failure releases live editor',
    );
    let invalidChunk: unknown;
    try {
      await b.control('write', {
        editor: limited.editor,
        sequence: 0,
        bytes: new Uint8Array(65537),
      });
    } catch (error) {
      invalidChunk = error;
    }
    assert(invalidChunk instanceof Error, 'Oversized binary chunk rejects');
    checks.push('binary-chunk-and-staging-budget-boundaries');
    await c.call('clear');
    const ownedEditor = await c.call('begin');
    assert(
      (
        await c.control('write', {
          editor: ownedEditor.editor,
          handle: 'foreign',
          sequence: 0,
          bytes: new Uint8Array([9]),
        })
      ).accepted === false,
      'Sibling Java handle cannot write owner editor',
    );
    assert(
      (await c.call('put', edit(ownedEditor))).committed === true,
      'Foreign binary write preserves rightful editor',
    );
    const ownedReader = object((await c.call('get', { raw: true })).entry);
    let foreignRead: unknown;
    try {
      await c.control('read', {
        reader: ownedReader.reader,
        handle: 'foreign',
        maximum: 1,
      });
    } catch (error) {
      foreignRead = error;
    }
    assert(
      foreignRead instanceof Error,
      'Sibling Java handle cannot read owner snapshot',
    );
    const rightful = (
      await c.control('read', { reader: ownedReader.reader, maximum: 65536 })
    ).bytes;
    assert(
      rightful instanceof Uint8Array && rightful[0] === 0,
      'Foreign read does not close or advance rightful snapshot',
    );
    await c.call('reader-close', { reader: ownedReader.reader });
    checks.push('binary-reader-writer-java-handle-isolation');
    await c.call('clear');
    const seal = (editor: Record<string, unknown>, url: string) => ({
      url,
      maxSize: 100,
      editor: editor.editor,
      expected: editor.version,
      generation: editor.generation,
    });
    const visibleA = await b.call('begin', { url: 'visible-a', maxSize: 100 });
    assert(
      (
        await b.control('write', {
          editor: visibleA.editor,
          sequence: 0,
          bytes: new Uint8Array(70),
        })
      ).accepted === true,
      'Seed A fits visible budget',
    );
    assert(
      (await b.call('commit', seal(visibleA, 'visible-a'))).committed === true,
      'Seed A commits 84 logical bytes',
    );
    const busyA = await b.call('begin', { url: 'visible-a', maxSize: 100 });
    const visibleB = await c.call('begin', { url: 'visible-b', maxSize: 100 });
    assert(
      (
        await c.control('write', {
          editor: visibleB.editor,
          sequence: 0,
          bytes: new Uint8Array(10),
        })
      ).accepted === true,
      'B fits allocated staging budget',
    );
    assert(
      (await c.call('commit', seal(visibleB, 'visible-b'))).committed === false,
      'Commit rejects when active A prevents visible trim',
    );
    assert(
      (await c.call('size', { maxSize: 100 })).size === 84,
      'Rejected commit leaves visible budget intact',
    );
    assert(
      (await c.call('get', { url: 'visible-b', maxSize: 100 })).entry ===
        undefined,
      'Rejected commit publishes no entry',
    );
    assert(
      (await c.call('begin', { url: 'visible-a', maxSize: 100 })).accepted ===
        false,
      'Budget rejection preserves another active editor',
    );
    const retryB = await c.call('begin', { url: 'visible-b', maxSize: 100 });
    assert(
      retryB.accepted === true,
      'Rejected commit releases its own staging editor',
    );
    await c.call('abort', { ...seal(retryB, 'visible-b') });
    await b.call('abort', { ...seal(busyA, 'visible-a') });
    const smallB = await c.call('begin', {
      url: 'visible-b',
      maxSize: 100,
      metadata: {},
    });
    assert(
      (
        await c.control('write', {
          editor: smallB.editor,
          sequence: 0,
          bytes: new Uint8Array(10),
        })
      ).accepted === true,
      'Smaller metadata B fits',
    );
    assert(
      (await c.call('commit', seal(smallB, 'visible-b'))).committed === true,
      'A plus smaller B fits 96 bytes',
    );
    const beforeUpdate = object(
      (await c.call('get', { url: 'visible-b', maxSize: 100 })).entry,
    );
    const busyAgain = await b.call('begin', { url: 'visible-a', maxSize: 100 });
    assert(
      (
        await c.call('update', {
          url: 'visible-b',
          maxSize: 100,
          expected: beforeUpdate.version,
          generation: beforeUpdate.generation,
          metadata: { status: 304 },
        })
      ).committed === false,
      'Metadata update rejects when visible trim cannot finish',
    );
    const afterUpdate = object(
      (await c.call('get', { url: 'visible-b', maxSize: 100 })).entry,
    );
    assert(
      afterUpdate.version === beforeUpdate.version &&
        Object.keys(object(afterUpdate.metadata)).length === 0,
      'Rejected metadata update rolls back version and metadata',
    );
    assert(
      (await c.call('size', { maxSize: 100 })).size === 96,
      'Update rollback preserves visible budget',
    );
    await b.call('abort', seal(busyAgain, 'visible-a'));
    checks.push('visible-budget-commit-and-update-atomic-rejection');
    for (const operation of ['close', 'delete']) {
      await c.call('clear');
      const seed = await b.call('begin');
      assert(
        (await b.call('put', edit(seed))).committed === true,
        'Seed old complete entry before failed ' + operation,
      );
      const beforeClose = object((await c.call('get')).entry);
      const snapshotBeforeClose = object(
        (await b.call('get', { raw: true }, 'doomed')).entry,
      );
      const doomed = await b.call('begin', {}, 'doomed');
      const sibling = await b.call('begin', { url: 'sibling' }, 'sibling');
      const foreign = await c.call('begin', { url: 'foreign' });
      assert(
        doomed.accepted === true &&
          sibling.accepted === true &&
          foreign.accepted === true,
        'Own, sibling and foreign editors active before failed ' + operation,
      );
      await b.control('fail-next-close');
      let closeFailure: unknown;
      try {
        await b.call(operation, {}, 'doomed');
      } catch (error) {
        closeFailure = error;
      }
      assert(
        closeFailure instanceof Error &&
          closeFailure.message.includes('ConstraintError'),
        'Failed ' + operation + ' still reports original real IDB error',
      );
      const afterClose = object((await c.call('get')).entry);
      assert(
        afterClose.body === beforeClose.body &&
          afterClose.version === beforeClose.version &&
          afterClose.generation === beforeClose.generation,
        'Failed ' + operation + ' rolls back old entry and generation',
      );
      assert(
        (await c.call('begin')).accepted === true,
        'Failed ' + operation + ' releases closed live handle editor',
      );
      assert(
        (await c.call('begin', { url: 'sibling' })).accepted === false &&
          (await b.call('begin', { url: 'foreign' })).accepted === false,
        'Failed ' + operation + ' preserves sibling and foreign editors',
      );
      const retainedSnapshot = (
        await b.control('read', {
          reader: snapshotBeforeClose.reader,
          handle: 'doomed',
          maximum: 65536,
        })
      ).bytes;
      assert(
        retainedSnapshot instanceof Uint8Array &&
          btoa(String.fromCharCode(...retainedSnapshot)) === body,
        'Failed ' + operation + ' preserves already opened reader snapshot',
      );
      await b.call(
        'reader-close',
        { reader: snapshotBeforeClose.reader },
        'doomed',
      );
      checks.push('failed-' + operation + '-releases-only-closed-handle');
    }
    await readerFailureGates(url, b, c, large, encodedLarge, checks);
    return {
      passed: true,
      checks,
      recoveryMs,
      userAgent: navigator.userAgent,
      scope:
        'Real Worker lifetime locks and atomic cache entries. No Java CacheInterceptor, Source, memory or device gate.',
    };
  } finally {
    try {
      await b.call('clear');
    } finally {
      a.terminate();
      b.terminate();
      c.terminate();
    }
  }
}
