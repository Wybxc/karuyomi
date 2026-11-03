/* Atomic IndexedDB storage; HTTP policy remains in OkHttp's interceptor. */
import {
  array,
  decodeBase64,
  encodeBase64,
  integer,
  object,
  optionalText,
  text,
  workerScope,
  type StorageKey,
  storageKey,
} from './bridge-common.js';

const operations = [
  'get',
  'begin',
  'put',
  'update',
  'remove',
  'abort',
  'close',
  'clear',
  'delete',
  'urls',
  'initialize',
  'flush',
  'size',
] as const;
type Operation = (typeof operations)[number];
interface CacheRequest {
  operation: Operation;
  directory: string;
  maxSize: number;
  url: string;
  handle: string;
  editor: string | undefined;
  expected: string | null;
  generation: number;
  metadata: unknown;
  body: string;
}
interface CacheLock {
  editor: string;
  owner: string;
}
interface Directory {
  key: StorageKey;
  sequence: number;
  generation: number;
  locks: Record<string, CacheLock>;
}
interface Entry {
  key: [string, string, string];
  url: string;
  metadata: unknown;
  body: Uint8Array;
  bytes: number;
  version: string;
  access: number;
}

export function parseCacheRequest(value: unknown): CacheRequest {
  const data = object(value);
  const operation = operations.find(
    (operation) => operation === data.operation,
  );
  if (!operation) throw Error('Unknown browser cache operation');
  return {
    operation,
    directory: text(data.directory),
    maxSize: integer(data.maxSize, 1),
    url: optionalText(data.url) ?? '',
    handle: optionalText(data.handle) ?? '',
    editor: optionalText(data.editor),
    expected: optionalText(data.expected) ?? null,
    generation: data.generation === undefined ? 0 : integer(data.generation),
    metadata: data.metadata,
    body: operation === 'put' ? text(data.body) : '',
  };
}

function directory(value: unknown, key: StorageKey): Directory {
  if (value === undefined)
    return { key, sequence: 0, generation: 0, locks: {} };
  const data = object(value);
  const locks: Record<string, CacheLock> = {};
  for (const [url, value] of Object.entries(object(data.locks ?? {}))) {
    const lock = object(value);
    locks[url] = {
      editor: text(lock.editor),
      owner: text(lock.owner),
    };
  }
  return {
    key: storageKey(data.key),
    sequence: integer(data.sequence),
    generation: integer(data.generation),
    locks,
  };
}

function entry(value: unknown): Entry {
  const data = object(value),
    key = array(data.key);
  if (key.length !== 3 || !(data.body instanceof Uint8Array))
    throw Error('Invalid stored cache entry');
  return {
    key: [text(key[0]), text(key[1]), text(key[2])],
    url: text(data.url),
    metadata: data.metadata,
    body: data.body,
    bytes: integer(data.bytes),
    version: text(data.version),
    access: integer(data.access),
  };
}

declare global {
  var teaCache: typeof cacheBridge | undefined;
}

const scope = workerScope();
const namespace =
  scope.karuyomiWorkerContext?.plugin ||
  new URL(location.href).searchParams.get('plugin');
if (!namespace) throw Error('Runtime cache namespace is required');
const workerId = crypto.randomUUID();
const lifetimeName = (worker: string) =>
  'teavm-http-cache:' + JSON.stringify([namespace, worker]);
let lifetime: Promise<void> | undefined;
function holdLifetime(): Promise<void> {
  return (lifetime ??= new Promise<void>((resolve, reject) => {
    if (!navigator.locks) {
      reject(
        Error('Browser cache requires Web Locks for Worker lifetime tracking'),
      );
      return;
    }
    navigator.locks
      .request(lifetimeName(workerId), () => {
        resolve();
        // Worker termination releases this lock, including active Source cancellation.
        // Cache.close() only releases that Java handle's editors; sibling handles
        // still belong to this live Worker.
        return new Promise<void>(() => {});
      })
      .catch(reject);
  }));
}
let opening: Promise<IDBDatabase> | undefined;
const open = () =>
  (opening ??= new Promise<IDBDatabase>((resolve, reject) => {
    const request = indexedDB.open('teavm-http-cache-v1', 1);
    request.onupgradeneeded = () => {
      request.result.createObjectStore('entries', { keyPath: 'key' });
      request.result.createObjectStore('directories', { keyPath: 'key' });
    };
    request.onsuccess = () => {
      request.result.onversionchange = () => {
        request.result.close();
        opening = undefined;
      };
      resolve(request.result);
    };
    request.onerror = () => {
      opening = undefined;
      reject(request.error);
    };
    request.onblocked = () => {
      opening = undefined;
      reject(Error('Browser cache database upgrade blocked'));
    };
  }));

/** Reap dead editors without awaiting a Web Lock inside an IDB transaction. */
async function reclaimEditors(
  database: IDBDatabase,
  owner: StorageKey,
): Promise<void> {
  const workers = await new Promise<Set<string>>((resolve, reject) => {
    const tx = database.transaction('directories', 'readonly');
    const request: IDBRequest<unknown> = tx
      .objectStore('directories')
      .get(owner);
    let workers = new Set<string>(),
      failure: unknown;
    request.onsuccess = () => {
      try {
        workers = new Set(
          Object.values(directory(request.result, owner).locks)
            .map((lock) => lock.owner.split('/')[0]!)
            .filter((worker) => worker !== workerId),
        );
      } catch (error) {
        failure = error;
        tx.abort();
      }
    };
    tx.oncomplete = () => resolve(workers);
    tx.onabort = () =>
      reject(failure || tx.error || Error('Cache editor lookup aborted'));
    tx.onerror = () => {};
  });
  await Promise.all(
    [...workers].map((worker) =>
      navigator.locks.request(
        lifetimeName(worker),
        { ifAvailable: true },
        async (lock) => {
          if (!lock) return;
          await new Promise<void>((resolve, reject) => {
            const tx = database.transaction('directories', 'readwrite');
            const store = tx.objectStore('directories');
            const request: IDBRequest<unknown> = store.get(owner);
            let failure: unknown;
            request.onsuccess = () => {
              try {
                const state = directory(request.result, owner);
                for (const [url, editor] of Object.entries(state.locks))
                  if (editor.owner.split('/')[0] === worker)
                    delete state.locks[url];
                store.put(state);
              } catch (error) {
                failure = error;
                tx.abort();
              }
            };
            tx.oncomplete = () => resolve();
            tx.onabort = () =>
              reject(
                failure || tx.error || Error('Cache editor recovery aborted'),
              );
            tx.onerror = () => {};
          });
        },
      ),
    ),
  );
}

interface BeginAttempt {
  valid: boolean;
}
// Only in-flight calls are tracked. Java Cache.closed rejects later calls, so
// finished handles do not need an unbounded history of closed identifiers.
const pendingBegins = new Map<string, Set<BeginAttempt>>();

async function releaseFailedEditor(
  database: IDBDatabase,
  owner: StorageKey,
  request: CacheRequest,
): Promise<void> {
  await new Promise<void>((resolve, reject) => {
    const tx = database.transaction('directories', 'readwrite');
    const store = tx.objectStore('directories');
    const get: IDBRequest<unknown> = store.get(owner);
    let failure: unknown;
    get.onsuccess = () => {
      try {
        const state = directory(get.result, owner);
        const lock = state.locks[request.url];
        if (
          state.generation === request.generation &&
          lock !== undefined &&
          lock.editor === request.editor &&
          lock.owner === workerId + '/' + request.handle
        ) {
          delete state.locks[request.url];
          store.put(state);
        }
      } catch (error) {
        failure = error;
        tx.abort();
      }
    };
    tx.oncomplete = () => resolve();
    tx.onabort = () =>
      reject(
        failure || tx.error || Error('Failed cache editor cleanup aborted'),
      );
    tx.onerror = () => {};
  });
}

const cacheBridge = async (input: string): Promise<string> => {
  const request = parseCacheRequest(JSON.parse(input) as unknown);
  const handle = JSON.stringify([request.directory, request.handle]);
  const attempt = request.operation === 'begin' ? { valid: true } : undefined;
  if (attempt) {
    const attempts = pendingBegins.get(handle) ?? new Set<BeginAttempt>();
    attempts.add(attempt);
    pendingBegins.set(handle, attempts);
  } else if (request.operation === 'close' || request.operation === 'delete') {
    for (const pending of pendingBegins.get(handle) ?? [])
      pending.valid = false;
  }
  try {
    await holdLifetime();
    const database = await open();
    const owner: StorageKey = [namespace, request.directory];
    await reclaimEditors(database, owner);
    const key: Entry['key'] = [...owner, request.url];
    let response: Record<string, unknown>;
    try {
      response = await new Promise<Record<string, unknown>>(
        (resolve, reject) => {
          const tx = database.transaction(
            ['entries', 'directories'],
            'readwrite',
          );
          const entries = tx.objectStore('entries'),
            directories = tx.objectStore('directories');
          let result: Record<string, unknown> = {},
            failure: unknown;
          tx.oncomplete = () => resolve(result);
          // An error event precedes rollback. Cleanup must wait for onabort.
          tx.onerror = () => {};
          tx.onabort = () =>
            reject(
              failure || tx.error || Error('Browser cache transaction aborted'),
            );
          const fail = (error: unknown) => {
            failure = error;
            tx.abort();
          };
          // Issue dependent requests only from IDB callbacks to keep the transaction live.
          const getDirectory: IDBRequest<unknown> = directories.get(owner);
          getDirectory.onsuccess = () => {
            try {
              const state = directory(getDirectory.result, owner);
              const cursor = entries.openCursor(
                IDBKeyRange.bound([...owner, ''], [...owner, '\uffff']),
              );
              const rows: Entry[] = [];
              cursor.onsuccess = () => {
                try {
                  const current = cursor.result;
                  if (current) {
                    const row = entry(current.value as unknown);
                    if (row.key[0] === owner[0] && row.key[1] === owner[1])
                      rows.push(row);
                    current.continue();
                    return;
                  }
                  let row = rows.find((value) => value.url === request.url);
                  let size = rows.reduce((sum, value) => sum + value.bytes, 0);
                  const remove = (value: Entry) => {
                    entries.delete(value.key);
                    delete state.locks[value.url];
                    size -= value.bytes;
                    rows.splice(rows.indexOf(value), 1);
                  };
                  const touch = (value: Entry) => {
                    value.access = ++state.sequence;
                    entries.put(value);
                  };
                  const trim = () => {
                    rows.sort((a, b) => a.access - b.access);
                    while (size > request.maxSize && rows.length)
                      remove(rows[0]!);
                  };
                  switch (request.operation) {
                    case 'get':
                      if (row) {
                        touch(row);
                        result = {
                          entry: {
                            metadata: row.metadata,
                            body: encodeBase64(row.body),
                            version: row.version,
                            generation: state.generation,
                          },
                        };
                      }
                      break;
                    case 'begin':
                      if (!attempt?.valid || state.locks[request.url])
                        result = { accepted: false };
                      else {
                        const editor = crypto.randomUUID();
                        state.locks[request.url] = {
                          editor,
                          owner: workerId + '/' + request.handle,
                        };
                        result = {
                          accepted: true,
                          editor,
                          version: row?.version ?? null,
                          generation: state.generation,
                        };
                      }
                      break;
                    case 'put':
                    case 'update': {
                      const lock = state.locks[request.url];
                      const hasEditor =
                        request.operation === 'put'
                          ? lock !== undefined &&
                            lock.editor === request.editor &&
                            lock.owner === workerId + '/' + request.handle
                          : !lock;
                      const matches =
                        hasEditor &&
                        (row?.version ?? null) === request.expected &&
                        state.generation === request.generation;
                      if (request.operation === 'put' && hasEditor)
                        delete state.locks[request.url];
                      if (!matches) {
                        result = { committed: false };
                        break;
                      }
                      let body: Uint8Array;
                      if (request.operation === 'update') {
                        if (!row) {
                          result = { committed: false };
                          break;
                        }
                        body = row.body;
                      } else body = decodeBase64(request.body);
                      const metadata = request.metadata;
                      const bytes =
                        body.byteLength +
                        new TextEncoder().encode(JSON.stringify(metadata))
                          .byteLength;
                      if (row) remove(row);
                      if (bytes <= request.maxSize) {
                        row = {
                          key,
                          url: request.url,
                          metadata,
                          body,
                          bytes,
                          version: crypto.randomUUID(),
                          access: ++state.sequence,
                        };
                        rows.push(row);
                        size += bytes;
                        entries.put(row);
                        trim();
                        result = { committed: true };
                      } else result = { committed: false };
                      break;
                    }
                    case 'remove':
                      if (row) remove(row);
                      delete state.locks[request.url];
                      break;
                    case 'abort':
                      if (
                        state.locks[request.url]?.editor === request.editor &&
                        state.locks[request.url]?.owner ===
                          workerId + '/' + request.handle
                      )
                        delete state.locks[request.url];
                      break;
                    case 'close':
                      for (const [url, lock] of Object.entries(state.locks))
                        if (lock.owner === workerId + '/' + request.handle)
                          delete state.locks[url];
                      break;
                    case 'clear':
                    case 'delete':
                      for (const value of [...rows]) remove(value);
                      state.locks = {};
                      state.generation++;
                      break;
                    case 'urls':
                      result = {
                        urls: rows
                          .sort((a, b) => a.access - b.access)
                          .map((value) => value.url),
                      };
                      break;
                    case 'initialize':
                    case 'flush':
                      trim();
                      break;
                    case 'size':
                      result = { size };
                      break;
                  }
                  directories.put(state);
                } catch (error) {
                  fail(error);
                }
              };
            } catch (error) {
              fail(error);
            }
          };
        },
      );
    } catch (error) {
      if (request.operation === 'put') {
        try {
          // The failed transaction has rolled back the earlier lock deletion.
          // A separate CAS must not unlock a replacement owner or generation.
          await releaseFailedEditor(database, owner, request);
        } catch (cleanupError) {
          throw new AggregateError(
            [error, cleanupError],
            'Cache put and editor cleanup failed',
          );
        }
      }
      throw error;
    }
    return JSON.stringify(response);
  } finally {
    if (attempt) {
      const attempts = pendingBegins.get(handle);
      attempts?.delete(attempt);
      if (attempts?.size === 0) pendingBegins.delete(handle);
    }
  }
};
scope.teaCache = cacheBridge;
