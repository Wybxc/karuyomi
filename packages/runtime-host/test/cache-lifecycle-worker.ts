/** Test-only Worker driver; all cache operations use the product bridge. */
import { openDB } from 'idb';
import {
  array,
  decodeBase64,
  encodeBase64,
  integer,
  object,
  optionalText,
  text,
  workerScope,
} from '../../../runtime/teavm/bridge/bridge-common.js';
import type { CacheSchema } from '../../../runtime/teavm/bridge/cache-bridge.js';

let chunkReads = 0,
  recordScans = 0;
const originalGet = IDBObjectStore.prototype.get;
IDBObjectStore.prototype.get = function (query: IDBValidKey | IDBKeyRange) {
  if (this.name === 'chunks') chunkReads++;
  return originalGet.call(this, query);
};
const originalGetAll = IDBObjectStore.prototype.getAll;
IDBObjectStore.prototype.getAll = function (
  ...args: Parameters<IDBObjectStore['getAll']>
) {
  recordScans++;
  return originalGetAll.apply(this, args);
};
const originalCursor = IDBObjectStore.prototype.openCursor;
IDBObjectStore.prototype.openCursor = function (
  ...args: Parameters<IDBObjectStore['openCursor']>
) {
  recordScans++;
  return originalCursor.apply(this, args);
};
const originalLockRequest = navigator.locks.request.bind(navigator.locks);
interface ReclaimPause {
  reached: Promise<void>;
  signalReached(): void;
  released: Promise<void>;
  release(): void;
  all: boolean;
}
let reclaimPause: ReclaimPause | undefined;
function pauseReclaim(all = false) {
  if (reclaimPause) throw Error('Reclaim pause is already armed');
  let signalReached = () => {},
    release = () => {};
  const reached = new Promise<void>((resolve) => {
    signalReached = resolve;
  });
  const released = new Promise<void>((resolve) => {
    release = resolve;
  });
  reclaimPause = { reached, signalReached, released, release, all };
}
function delayedLockRequest<T>(
  name: string,
  callback: LockGrantedCallback<T>,
): Promise<Awaited<T>>;
function delayedLockRequest<T>(
  name: string,
  options: LockOptions,
  callback: LockGrantedCallback<T>,
): Promise<Awaited<T>>;
function delayedLockRequest<T>(
  name: string,
  options: LockOptions | LockGrantedCallback<T>,
  callback?: LockGrantedCallback<T>,
): Promise<Awaited<T>> {
  if (typeof options === 'function') return originalLockRequest(name, options);
  if (!callback) throw Error('Missing Web Lock callback');
  const pause = reclaimPause;
  if (options.ifAvailable && pause) {
    if (!pause.all) navigator.locks.request = originalLockRequest;
    pause.signalReached();
    return pause.released.then(() =>
      originalLockRequest(name, options, callback),
    );
  }
  return originalLockRequest(name, options, callback);
}

let pendingMutation: Promise<void> | undefined;
function failNextPut(replacement: string) {
  const originalPut = IDBObjectStore.prototype.put;
  const originalAdd = IDBObjectStore.prototype.add;
  IDBObjectStore.prototype.put = function (value: unknown, key?: IDBValidKey) {
    if (this.name !== 'entries') return originalPut.call(this, value, key);
    IDBObjectStore.prototype.put = originalPut;
    // Both are real IDB requests. The duplicate key aborts the actual product
    // transaction and rolls back its entry removal and editor deletion.
    originalAdd.call(this, value, key);
    const duplicate = originalAdd.call(this, value, key);
    duplicate.onerror = () => {
      if (replacement === 'none') return;
      // Queue a real competing transaction before the abort promise resumes
      // product cleanup. It runs after rollback and before that cleanup CAS.
      const data = object(value),
        owner = array(data.directory),
        directory = [text(owner[0]), text(owner[1])];
      const url = text(data.url);
      const tx = this.transaction.db.transaction(
        ['directories', 'editors'],
        'readwrite',
      );
      pendingMutation = new Promise<void>((resolve, reject) => {
        const store = tx.objectStore('editors');
        const get: IDBRequest<unknown> = store
          .index('byEntry')
          .get([directory, url]);
        get.onsuccess = () => {
          const editor = object(get.result);
          if (replacement === 'editor') {
            store.delete(text(editor.id));
            editor.id = crypto.randomUUID();
            store.put(editor);
          } else if (replacement === 'owner') {
            const sentinel: IDBRequest<unknown> = store
              .index('byEntry')
              .get([directory, 'fault-sentinel']);
            sentinel.onsuccess = () => {
              editor.worker = text(object(sentinel.result).worker);
              store.put(editor);
            };
          } else if (replacement === 'generation') {
            const directories = tx.objectStore('directories'),
              getState: IDBRequest<unknown> = directories.get(directory);
            getState.onsuccess = () => {
              const state = object(getState.result);
              if (typeof state.generation !== 'number')
                throw Error('Missing generation');
              state.generation++;
              editor.generation = state.generation;
              directories.put(state);
              store.put(editor);
            };
          } else throw Error('Unknown replacement fault');
        };
        tx.oncomplete = () => resolve();
        tx.onabort = () =>
          reject(tx.error || Error('Test replacement transaction aborted'));
        tx.onerror = () => {};
      });
    };
    return duplicate;
  };
}

function failNextClose() {
  const originalPut = IDBObjectStore.prototype.put;
  const originalAdd = IDBObjectStore.prototype.add;
  IDBObjectStore.prototype.put = function (value: unknown, key?: IDBValidKey) {
    if (this.name !== 'directories') return originalPut.call(this, value, key);
    IDBObjectStore.prototype.put = originalPut;
    // The directory already exists. A real duplicate-key request aborts the
    // transaction, restoring the editors and entries it just removed.
    return originalAdd.call(this, value, key);
  };
}

function failNextRead() {
  const originalPut = IDBObjectStore.prototype.put,
    originalAdd = IDBObjectStore.prototype.add;
  IDBObjectStore.prototype.put = function (value: unknown, key?: IDBValidKey) {
    if (this.name !== 'readers') return originalPut.call(this, value, key);
    IDBObjectStore.prototype.put = originalPut;
    // A reader already exists. Abort the actual read/cursor transaction.
    return originalAdd.call(this, value, key);
  };
}

async function mutateChunk(message: Record<string, unknown>) {
  const database = await openDB<CacheSchema>('teavm-http-cache-v3'),
    tx = database.transaction(['readers', 'chunks'], 'readwrite'),
    done = tx.done;
  try {
    const reader = await tx.objectStore('readers').get(text(message.reader));
    if (!reader) throw Error('Missing reader for controlled chunk corruption');
    const key: [string, string, string, number] = [
      ...reader.directory,
      reader.body,
      integer(message.index, 0, 8191),
    ];
    if (message.bytes === null) await tx.objectStore('chunks').delete(key);
    else {
      if (
        !(message.bytes instanceof Uint8Array) ||
        message.bytes.length > 65537
      )
        throw Error('Invalid controlled corrupt chunk');
      await tx.objectStore('chunks').put(message.bytes, key);
    }
    await done;
  } catch (error) {
    try {
      tx.abort();
    } catch {
      /* Already terminal. */
    }
    await done.catch(() => {});
    throw error;
  } finally {
    database.close();
  }
}

async function inspectNamespace(reset = false) {
  const namespace = new URL(location.href).searchParams.get('plugin');
  if (!namespace) throw Error('Missing test namespace');
  const database = await openDB<CacheSchema>('teavm-http-cache-v3');
  try {
    const usage = await database.get('usage', namespace);
    const stores = [
      'usage',
      'owners',
      'directories',
      'entries',
      'bodies',
      'chunks',
      'editors',
      'readers',
    ] as const;
    const tx = database.transaction(stores, reset ? 'readwrite' : 'readonly');
    const rows: Record<string, number> = {};
    let allocatedBytes = 0;
    for (const name of stores) {
      rows[name] = 0;
      if (name === 'chunks') {
        let cursor = await tx.objectStore('chunks').openKeyCursor();
        while (cursor) {
          if (cursor.primaryKey[0] === namespace) {
            rows[name]++;
            const chunks = tx.objectStore('chunks');
            if (reset && chunks.delete) await chunks.delete(cursor.primaryKey);
          }
          cursor = await cursor.continue();
        }
      } else if (name === 'editors' || name === 'readers') {
        for await (const cursor of tx.objectStore(name).iterate()) {
          if (cursor.value.namespace !== namespace) continue;
          rows[name]++;
          if (name === 'editors')
            allocatedBytes += integer(object(cursor.value).metadataBytes);
          if (reset && cursor.delete) await cursor.delete();
        }
      } else {
        const store = tx.objectStore(name);
        for await (const cursor of store.iterate()) {
          const key = cursor.primaryKey;
          if (
            name === 'usage'
              ? key !== namespace
              : !Array.isArray(key) || key[0] !== namespace
          )
            continue;
          rows[name]++;
          if (name === 'entries')
            allocatedBytes += integer(object(cursor.value).metadataBytes);
          if (name === 'bodies')
            allocatedBytes += integer(object(cursor.value).bytes);
          if (reset && cursor.delete) await cursor.delete();
        }
      }
    }
    await tx.done;
    return { usage, rows, allocatedBytes };
  } finally {
    database.close();
  }
}

self.onmessage = async (event: MessageEvent<unknown>) => {
  const message = object(event.data),
    id = text(message.id);
  try {
    const control = optionalText(message.control);
    if (control) {
      if (control === 'reset-metrics') {
        chunkReads = 0;
        recordScans = 0;
      } else if (control === 'metrics') {
        self.postMessage({ id, result: { chunkReads, recordScans } });
        return;
      } else if (
        control === 'namespace-usage' ||
        control === 'reset-namespace'
      ) {
        self.postMessage({
          id,
          result: await inspectNamespace(control === 'reset-namespace'),
        });
        return;
      } else if (control === 'pause-reclaim') {
        pauseReclaim(message.all === true);
        navigator.locks.request = delayedLockRequest;
      } else if (control === 'wait-reclaim') {
        if (!reclaimPause) throw Error('Reclaim pause is not armed');
        await reclaimPause.reached;
      } else if (control === 'resume-reclaim') {
        if (!reclaimPause) throw Error('Reclaim pause is not armed');
        navigator.locks.request = originalLockRequest;
        reclaimPause.release();
        reclaimPause = undefined;
      } else if (control === 'fail-next-close') {
        failNextClose();
      } else if (control === 'fail-next-read') {
        failNextRead();
      } else if (control === 'mutate-chunk') {
        await mutateChunk(message);
      } else if (control === 'fail-next-put') {
        failNextPut(text(message.replacement));
      } else if (control === 'read') {
        const read = workerScope().teaCacheRead;
        if (!read) throw Error('Binary cache read bridge missing');
        const bytes = await read(
          text(message.reader),
          optionalText(message.handle) ?? 'one',
          Number(message.maximum),
        );
        self.postMessage({ id, result: { bytes } });
        return;
      } else if (control === 'write') {
        const write = workerScope().teaCacheWrite;
        if (!write || !(message.bytes instanceof Uint8Array))
          throw Error('Binary cache write bridge missing');
        const accepted = await write(
          text(message.editor),
          optionalText(message.handle) ?? 'one',
          Number(message.sequence),
          message.bytes,
        );
        self.postMessage({ id, result: { accepted } });
        return;
      } else if (control === 'fill-editor') {
        const write = workerScope().teaCacheWrite;
        if (!write) throw Error('Binary cache write bridge missing');
        const length = integer(message.length, 0, 64 * 1024 * 1024),
          chunkSize = integer(message.chunkSize, 1, 65536),
          block = new Uint8Array(chunkSize).fill(143);
        let written = 0,
          sequence = 0;
        while (written < length) {
          const bytes = block.subarray(
            0,
            Math.min(chunkSize, length - written),
          );
          if (
            !(await write(
              text(message.editor),
              optionalText(message.handle) ?? 'one',
              sequence,
              bytes,
            ))
          )
            break;
          written += bytes.length;
          sequence++;
        }
        self.postMessage({ id, result: { written, chunks: sequence } });
        return;
      } else throw Error('Unknown cache lifecycle control');
      self.postMessage({ id, result: {} });
      return;
    }
    const cache = workerScope().teaCache;
    if (typeof cache !== 'function')
      throw Error('Product cache bridge is missing');
    const request = object(message.request);
    if (request.operation === 'put') {
      const bytes = decodeBase64(text(request.body)),
        write = workerScope().teaCacheWrite;
      if (!write) throw Error('Binary cache write bridge missing');
      for (
        let offset = 0, sequence = 0;
        offset < bytes.length;
        offset += 65536, sequence++
      ) {
        if (
          !(await write(
            text(request.editor),
            text(request.handle),
            sequence,
            bytes.subarray(offset, offset + 65536),
          ))
        )
          break;
      }
      request.operation = 'commit';
      delete request.body;
      delete request.metadata;
    }
    const result = object(
      JSON.parse(await cache(JSON.stringify(request))) as unknown,
    );
    if (request.operation === 'get' && result.entry && request.raw !== true) {
      const entry = object(result.entry),
        read = workerScope().teaCacheRead;
      if (!read) throw Error('Binary cache read bridge missing');
      const parts: Uint8Array[] = [];
      let length = 0,
        bytes;
      while (
        (bytes = await read(
          text(entry.reader),
          text(request.handle),
          65536,
        )) !== null
      ) {
        parts.push(bytes);
        length += bytes.length;
      }
      const all = new Uint8Array(length);
      let offset = 0;
      for (const part of parts) {
        all.set(part, offset);
        offset += part.length;
      }
      // Test-fixture convenience only. The product boundary carries binary chunks.
      entry.body = encodeBase64(all);
    }
    self.postMessage({ id, result });
  } catch (error) {
    await pendingMutation;
    pendingMutation = undefined;
    self.postMessage({
      id,
      error:
        error instanceof Error
          ? error.name + ': ' + error.message
          : String(error),
    });
  }
};
