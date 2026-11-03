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
  expires: number;
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
      expires: integer(lock.expires),
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

const cacheBridge = async (input: string): Promise<string> => {
  const request = parseCacheRequest(JSON.parse(input) as unknown);
  const database = await open();
  const owner: StorageKey = [namespace, request.directory];
  const key: Entry['key'] = [...owner, request.url];
  return JSON.stringify(
    await new Promise<Record<string, unknown>>((resolve, reject) => {
      const tx = database.transaction(['entries', 'directories'], 'readwrite');
      const entries = tx.objectStore('entries'),
        directories = tx.objectStore('directories');
      let result: Record<string, unknown> = {},
        failure: unknown;
      tx.oncomplete = () => resolve(result);
      tx.onerror = () => reject(failure || tx.error);
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
          for (const [url, lock] of Object.entries(state.locks))
            if (lock.expires < Date.now()) delete state.locks[url];
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
                while (size > request.maxSize && rows.length) remove(rows[0]!);
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
                  if (state.locks[request.url]) result = { accepted: false };
                  else {
                    const editor = crypto.randomUUID();
                    state.locks[request.url] = {
                      editor,
                      owner: workerId + '/' + request.handle,
                      expires: Date.now() + 300_000,
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
                      ? lock?.editor === request.editor
                      : !lock;
                  const matches =
                    hasEditor &&
                    (row?.version ?? null) === request.expected &&
                    state.generation === request.generation;
                  if (
                    request.operation === 'put' &&
                    lock?.editor === request.editor
                  )
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
                  if (state.locks[request.url]?.editor === request.editor)
                    delete state.locks[request.url];
                  break;
                case 'close':
                  for (const [url, lock] of Object.entries(state.locks))
                    if (lock.owner === workerId + '/' + request.handle)
                      delete state.locks[url];
                  break;
                case 'clear':
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
    }),
  );
};
scope.teaCache = cacheBridge;
