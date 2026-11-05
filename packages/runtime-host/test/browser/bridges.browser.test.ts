import { afterEach, expect, test } from 'vitest';
import { releaseProxy, wrap, type Remote } from 'comlink';
import { deleteDB } from 'idb';
import {
  integer,
  object,
  text,
} from '../../../../runtime/teavm/bridge/bridge-common.js';
import { createGraphicsBridge } from '../../../../runtime/teavm/bridge/graphics-bridge.js';
import StorageWorker from './fixtures/storage.worker.ts?worker';
import type { StorageWorkerApi } from './fixtures/storage.worker.ts';

type RunningWorker = { worker: Worker; api: Remote<StorageWorkerApi> };
const workers = new Set<RunningWorker>();
function start(namespace = crypto.randomUUID()): RunningWorker {
  const worker = new StorageWorker({ name: namespace });
  const running = { worker, api: wrap<StorageWorkerApi>(worker) };
  workers.add(running);
  return running;
}
function stop(running: RunningWorker) {
  running.api[releaseProxy]();
  running.worker.terminate();
  workers.delete(running);
}
afterEach(async () => {
  for (const running of workers) stop(running);
  await Promise.all([
    deleteDB('teavm-http-cache-v3'),
    deleteDB('teavm-java-files-v2'),
  ]);
});

async function stage(api: Remote<StorageWorkerApi>, bytes: Uint8Array) {
  const editor = await api.cache('begin', { length: bytes.length });
  expect(editor.accepted).toBe(true);
  for (let offset = 0, sequence = 0; offset < bytes.length; offset += 65536) {
    expect(
      await api.writeCache(
        text(editor.editor),
        sequence++,
        bytes.slice(offset, offset + 65536),
      ),
    ).toBe(true);
  }
  return {
    editor: text(editor.editor),
    expected: editor.version,
    generation: integer(editor.generation),
  };
}
async function store(api: Remote<StorageWorkerApi>, bytes: Uint8Array) {
  expect(await api.cache('commit', await stage(api, bytes))).toEqual({
    committed: true,
  });
}

test('cache readers retain their exact binary snapshot through replacement and clear', async () => {
  const { api } = start();
  const bytes = Uint8Array.from({ length: 131075 }, (_, index) => index % 251);
  await store(api, bytes);
  const entry = object((await api.cache('get')).entry);
  expect(entry).not.toHaveProperty('body');
  expect(entry.length).toBe(bytes.length);
  await store(api, new Uint8Array([99, 88, 77]));
  await api.cache('clear');
  expect(await api.cache('get')).toEqual({});
  const received = new Uint8Array(bytes.length);
  let offset = 0;
  while (true) {
    const chunk = await api.readCache(text(entry.reader));
    if (chunk === null) break;
    expect(chunk.length).toBeGreaterThan(0);
    expect(chunk.length).toBeLessThanOrEqual(65536);
    received.set(chunk, offset);
    offset += chunk.length;
  }
  expect(offset).toBe(bytes.length);
  expect(received).toEqual(bytes);
});

test('real Worker lifetime locks exclude active editors and reclaim a dead owner', async () => {
  const namespace = crypto.randomUUID();
  const first = start(namespace);
  const second = start(namespace);
  const isolated = start();
  await store(first.api, new Uint8Array([11, 22]));
  expect((await first.api.cache('begin')).accepted).toBe(true);
  expect((await second.api.cache('begin')).accepted).toBe(false);
  expect((await isolated.api.cache('begin')).accepted).toBe(true);
  stop(first);
  await expect
    .poll(() => second.api.cache('begin'), { timeout: 5000 })
    .toMatchObject({ accepted: true });
  const entry = object((await second.api.cache('get')).entry);
  expect(await second.api.readCache(text(entry.reader))).toEqual(
    new Uint8Array([11, 22]),
  );
});

test('cache clear invalidates a staged generation and binary chunks remain bounded', async () => {
  const { api } = start();
  const editor = await stage(api, new Uint8Array([1, 2, 3]));
  await expect(
    api.writeCache(editor.editor, 1, new Uint8Array(65537)),
  ).rejects.toThrow(/chunk size/);
  await api.cache('clear');
  expect(await api.cache('commit', editor)).toEqual({ committed: false });
  expect(await api.cache('get')).toEqual({});
});

test('an actual IndexedDB abort rolls back a cache commit and releases its editor', async () => {
  const { api } = start();
  await store(api, new Uint8Array([1, 2]));
  const before = object((await api.cache('get')).entry);
  const editor = await stage(api, new Uint8Array([3, 4]));
  await api.abortNextCommit();
  await expect(api.cache('commit', editor)).rejects.toThrow();
  const after = object((await api.cache('get')).entry);
  expect(after.version).toBe(before.version);
  expect(await api.readCache(text(after.reader))).toEqual(
    new Uint8Array([1, 2]),
  );
  expect((await api.cache('begin')).accepted).toBe(true);
});

test('an unlinked file remains readable through its handle until close', async () => {
  const { api } = start();
  await api.file('create');
  const handle = text(
    (await api.file('open', { readable: true, writable: true })).handle,
  );
  expect(await api.writeFile(handle, new Uint8Array([4, 5, 6]))).toBe(true);
  await api.file('seek', { handle, position: 0 });
  expect(await api.file('delete')).toEqual({ changed: true });
  expect(await api.file('stat')).toEqual({ exists: false });
  expect(await api.readFile(handle)).toEqual(new Uint8Array([4, 5, 6]));
  expect(await api.readFile(handle)).toBeNull();
  await api.file('close', { handle });
  await expect(api.readFile(handle)).rejects.toThrow(/closed/);
  await api.closeFiles();
});

test('the actual OffscreenCanvas bridge paints exact pixels and releases task resources', () => {
  const bridge = createGraphicsBridge();
  bridge.teaGraphicsBegin({ requestId: 'pixels', generation: '1' });
  const id = integer(
    bridge.teaGraphicsSync({ op: 'create', width: 2, height: 2 }).id,
  );
  bridge.teaGraphicsSync({ op: 'color', id, color: -16711936 });
  const pixels = bridge.teaGraphicsSync({ op: 'pixels', id });
  expect(bridge.teaGraphicsBytesRead(text(pixels.bytes), 65536)).toEqual(
    new Uint8Array([
      0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255, 0, 255,
    ]),
  );
  bridge.teaGraphicsEnd('pixels', '1');
  expect(Object.values(bridge.teaGraphicsSnapshot())).toEqual([
    0, 0, 0, 0, 0, 0,
  ]);
  expect(() => bridge.teaGraphicsSync({ op: 'color', id, color: 0 })).toThrow();
});

test('a claimed bitmap survives task end, rejects counterfeit owners and recycles explicitly', () => {
  const bridge = createGraphicsBridge();
  bridge.teaGraphicsBegin({ requestId: 'owner', generation: '1' });
  const id = integer(
    bridge.teaGraphicsSync({ op: 'create', width: 2, height: 2 }).id,
  );
  const owner = bridge.teaGraphicsBitmapClaim(id);
  expect(() => bridge.teaGraphicsBitmapClaim(id)).toThrow();
  expect(() => bridge.teaGraphicsBitmapId({})).toThrow();
  bridge.teaGraphicsEnd('owner', '1');
  expect(bridge.teaGraphicsSnapshot().surfaces).toBe(1);
  bridge.teaGraphicsBegin({ requestId: 'owner', generation: '2' });
  expect(bridge.teaGraphicsBitmapId(owner)).toBe(id);
  bridge.teaGraphicsBitmapRecycle(owner);
  bridge.teaGraphicsBitmapRecycle(owner);
  expect(() => bridge.teaGraphicsBitmapId(owner)).toThrow();
  bridge.teaGraphicsEnd('owner', '2');
  expect(Object.values(bridge.teaGraphicsSnapshot())).toEqual([
    0, 0, 0, 0, 0, 0,
  ]);
});
