/* Storage policy only; HTTP caching policy remains in OkHttp's CacheInterceptor. */
import {
  openDB,
  type DBSchema,
  type IDBPDatabase,
  type IDBPTransaction,
} from 'idb';
import {
  integer,
  object,
  optionalText,
  text,
  workerScope,
  type StorageKey,
} from './bridge-common.js';

const CHUNK = 65536,
  CONTROL = 65536,
  METADATA = 48 * 1024;
const MAX_CACHE = 64 * 1024 * 1024,
  MAX_HANDLES = 64,
  MAX_CHUNKS = 8192,
  TIMEOUT = 5000;
const operations = [
  'get',
  'begin',
  'commit',
  'update',
  'remove',
  'abort',
  'reader-close',
  'close',
  'delete',
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
  reader: string | undefined;
  expected: string | null;
  generation: number;
  metadata: unknown;
  length: number;
}
interface Directory {
  key: StorageKey;
  sequence: number;
  generation: number;
  visibleBytes: number;
  allocatedBytes: number;
  limit: number;
}
type EntryKey = [string, string, string];
type ChunkKey = [string, string, string, number];
interface Entry {
  key: EntryKey;
  directory: StorageKey;
  url: string;
  metadata: unknown;
  metadataBytes: number;
  body: string;
  bytes: number;
  version: string;
  access: number;
}
interface Body {
  key: EntryKey;
  bytes: number;
  chunks: number;
  current: boolean;
  staging: boolean;
  pins: number;
}
interface Editor {
  id: string;
  directory: StorageKey;
  url: string;
  worker: string;
  handle: string;
  expected: string | null;
  generation: number;
  metadata: unknown;
  metadataBytes: number;
  body: string;
  length: number;
}
interface Reader {
  id: string;
  directory: StorageKey;
  worker: string;
  handle: string;
  body: string;
  index: number;
  offset: number;
  received: number;
}
export interface CacheSchema extends DBSchema {
  directories: { key: StorageKey; value: Directory };
  entries: {
    key: EntryKey;
    value: Entry;
    indexes: { byAccess: [StorageKey, number] };
  };
  bodies: { key: EntryKey; value: Body };
  chunks: { key: ChunkKey; value: Uint8Array };
  editors: {
    key: string;
    value: Editor;
    indexes: {
      byEntry: [StorageKey, string];
      byDirectory: StorageKey;
      byWorker: [StorageKey, string];
    };
  };
  readers: {
    key: string;
    value: Reader;
    indexes: { byDirectory: StorageKey; byWorker: [StorageKey, string] };
  };
}
type Stores = [
  'directories',
  'entries',
  'bodies',
  'chunks',
  'editors',
  'readers',
];
const stores: Stores = [
  'directories',
  'entries',
  'bodies',
  'chunks',
  'editors',
  'readers',
];
type CacheTx = IDBPTransaction<CacheSchema, Stores, 'readwrite'>;
type Database = IDBPDatabase<CacheSchema>;
class CacheCapacityError extends Error {}

interface Attempt {
  valid: boolean;
}
const pendingBegins = new Map<string, Set<Attempt>>(),
  pendingReads = new Map<string, Set<Attempt>>();
function register(map: Map<string, Set<Attempt>>, key: string): Attempt {
  const attempt = { valid: true },
    attempts = map.get(key) ?? new Set<Attempt>();
  attempts.add(attempt);
  map.set(key, attempts);
  return attempt;
}
function invalidate(map: Map<string, Set<Attempt>>, key: string) {
  for (const attempt of map.get(key) ?? []) attempt.valid = false;
}
function unregister(
  map: Map<string, Set<Attempt>>,
  key: string,
  attempt: Attempt,
) {
  const attempts = map.get(key);
  attempts?.delete(attempt);
  if (attempts?.size === 0) map.delete(key);
}
const sameDirectory = (a: StorageKey, b: StorageKey) =>
  a[0] === b[0] && a[1] === b[1];
function jsonSize(value: unknown) {
  return new TextEncoder().encode(JSON.stringify(value)).length;
}
export function parseCacheRequest(value: unknown): CacheRequest {
  const data = object(value),
    operation = operations.find((item) => item === data.operation);
  if (!operation) throw Error('Unknown browser cache operation');
  return {
    operation,
    directory: text(data.directory),
    maxSize: integer(data.maxSize, 1),
    url: optionalText(data.url) ?? '',
    handle: optionalText(data.handle) ?? '',
    editor: optionalText(data.editor),
    reader: optionalText(data.reader),
    expected: optionalText(data.expected) ?? null,
    generation: data.generation === undefined ? 0 : integer(data.generation),
    metadata:
      operation === 'begin' || operation === 'update'
        ? object(data.metadata)
        : undefined,
    length: data.length === undefined ? -1 : integer(data.length, -1),
  };
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
        return new Promise<void>(() => {});
      })
      .catch(reject);
  }));
}
let opening: Promise<Database> | undefined;
const open = () =>
  (opening ??= openDB<CacheSchema>('teavm-http-cache-v2', 1, {
    upgrade(database) {
      database.createObjectStore('directories', { keyPath: 'key' });
      database
        .createObjectStore('entries', { keyPath: 'key' })
        .createIndex('byAccess', ['directory', 'access']);
      database.createObjectStore('bodies', { keyPath: 'key' });
      database.createObjectStore('chunks');
      const editors = database.createObjectStore('editors', { keyPath: 'id' });
      editors.createIndex('byEntry', ['directory', 'url'], { unique: true });
      editors.createIndex('byDirectory', 'directory');
      editors.createIndex('byWorker', ['directory', 'worker']);
      const readers = database.createObjectStore('readers', { keyPath: 'id' });
      readers.createIndex('byDirectory', 'directory');
      readers.createIndex('byWorker', ['directory', 'worker']);
    },
    blocking() {
      void opening?.then((database) => database.close());
      opening = undefined;
    },
    terminated() {
      opening = undefined;
    },
  }).catch((error: unknown) => {
    opening = undefined;
    throw error;
  }));

/** Short atomic storage operations; the callback awaits only IDB requests. */
async function transaction<T>(
  database: Database,
  action: (tx: CacheTx) => Promise<T>,
): Promise<T> {
  const tx = database.transaction(stores, 'readwrite');
  const settled = tx.done.then(
    () => ({ passed: true as const }),
    (error: unknown) => ({ passed: false as const, error }),
  );
  let timedOut = false;
  const timer = setTimeout(() => {
    timedOut = true;
    try {
      tx.abort();
    } catch {
      /* Already terminal. */
    }
  }, TIMEOUT);
  try {
    const value = await action(tx),
      outcome = await settled;
    if (timedOut) throw Error('Cache storage transaction timed out');
    if (!outcome.passed) throw outcome.error;
    return value;
  } catch (error) {
    try {
      tx.abort();
    } catch {
      /* Already terminal. */
    }
    await settled;
    throw error;
  } finally {
    clearTimeout(timer);
  }
}
async function stateFor(
  tx: CacheTx,
  owner: StorageKey,
  maxSize?: number,
): Promise<Directory> {
  const state = (await tx.objectStore('directories').get(owner)) ?? {
    key: owner,
    sequence: 0,
    generation: 0,
    visibleBytes: 0,
    allocatedBytes: 0,
    limit: Math.min(maxSize ?? MAX_CACHE, MAX_CACHE),
  };
  if (maxSize !== undefined) state.limit = Math.min(maxSize, MAX_CACHE);
  return state;
}
const bodyKey = (owner: StorageKey, body: string): EntryKey => [...owner, body];
const entryKey = (owner: StorageKey, url: string): EntryKey => [...owner, url];
const chunkRange = (owner: StorageKey, body: string) =>
  IDBKeyRange.bound(
    [...owner, body, 0],
    [...owner, body, Number.MAX_SAFE_INTEGER],
  );
async function collectBody(tx: CacheTx, state: Directory, body: Body) {
  if (body.current || body.staging || body.pins) {
    await tx.objectStore('bodies').put(body);
    return;
  }
  await tx.objectStore('chunks').delete(chunkRange(state.key, body.key[2]));
  await tx.objectStore('bodies').delete(body.key);
  state.allocatedBytes -= body.bytes;
}
async function detachEntry(tx: CacheTx, state: Directory, row: Entry) {
  await tx.objectStore('entries').delete(row.key);
  state.visibleBytes -= row.metadataBytes + row.bytes;
  state.allocatedBytes -= row.metadataBytes;
  const body = await tx.objectStore('bodies').get(bodyKey(state.key, row.body));
  if (!body) throw Error('Missing cache entry body');
  body.current = false;
  await collectBody(tx, state, body);
}
async function abortEditor(tx: CacheTx, state: Directory, editor: Editor) {
  await tx.objectStore('editors').delete(editor.id);
  state.allocatedBytes -= editor.metadataBytes;
  const body = await tx
    .objectStore('bodies')
    .get(bodyKey(state.key, editor.body));
  if (!body) throw Error('Missing cache staging body');
  body.staging = false;
  await collectBody(tx, state, body);
}
async function closeReader(tx: CacheTx, state: Directory, reader: Reader) {
  await tx.objectStore('readers').delete(reader.id);
  const body = await tx
    .objectStore('bodies')
    .get(bodyKey(state.key, reader.body));
  if (!body || body.pins < 1) throw Error('Missing cache reader snapshot');
  body.pins--;
  await collectBody(tx, state, body);
}
const accessRange = (owner: StorageKey) =>
  IDBKeyRange.bound([owner, 0], [owner, Number.MAX_SAFE_INTEGER]);
async function makeSpace(
  tx: CacheTx,
  state: Directory,
  bytes: number,
  protectedUrl: string,
  trimVisible = false,
): Promise<boolean> {
  let cursor = await tx
    .objectStore('entries')
    .index('byAccess')
    .openCursor(accessRange(state.key));
  while (
    cursor &&
    (trimVisible
      ? state.visibleBytes > state.limit
      : state.allocatedBytes + bytes > state.limit * 2)
  ) {
    const row = cursor.value;
    if (
      row.url !== protectedUrl &&
      !(await tx
        .objectStore('editors')
        .index('byEntry')
        .get([state.key, row.url]))
    )
      await detachEntry(tx, state, row);
    cursor = await cursor.continue();
  }
  return trimVisible
    ? state.visibleBytes <= state.limit
    : state.allocatedBytes + bytes <= state.limit * 2;
}
/** Web Lock probes never keep an IDB transaction alive. */
async function reclaimEditors(database: Database, owner: StorageKey) {
  const lookup = database.transaction(['editors', 'readers'], 'readonly');
  const [editors, readers] = await Promise.all([
    lookup.objectStore('editors').index('byDirectory').getAll(owner),
    lookup.objectStore('readers').index('byDirectory').getAll(owner),
  ]);
  await lookup.done;
  const workers = new Set(
    [...editors, ...readers]
      .map((item) => item.worker)
      .filter((worker) => worker !== workerId),
  );
  await Promise.all(
    [...workers].map((worker) =>
      navigator.locks.request(
        lifetimeName(worker),
        { ifAvailable: true },
        async (lock) => {
          if (!lock) return;
          await transaction(database, async (tx) => {
            const state = await stateFor(tx, owner),
              key: [StorageKey, string] = [owner, worker];
            for (const editor of await tx
              .objectStore('editors')
              .index('byWorker')
              .getAll(key))
              await abortEditor(tx, state, editor);
            for (const reader of await tx
              .objectStore('readers')
              .index('byWorker')
              .getAll(key))
              await closeReader(tx, state, reader);
            await tx.objectStore('directories').put(state);
          });
        },
      ),
    ),
  );
}
async function releaseFailedEditor(
  database: Database,
  owner: StorageKey,
  id: string,
  handle: string,
  generation: number,
) {
  await transaction(database, async (tx) => {
    const state = await stateFor(tx, owner),
      editor = await tx.objectStore('editors').get(id);
    if (
      state.generation === generation &&
      editor?.worker === workerId &&
      editor.handle === handle &&
      editor.generation === generation &&
      sameDirectory(editor.directory, owner)
    ) {
      await abortEditor(tx, state, editor);
      await tx.objectStore('directories').put(state);
    }
  });
}
/** Java closes its handle before awaiting storage, so failure must release it too. */
async function releaseClosedHandle(
  database: Database,
  owner: StorageKey,
  handle: string,
) {
  await transaction(database, async (tx) => {
    const state = await stateFor(tx, owner);
    for (const editor of await tx
      .objectStore('editors')
      .index('byWorker')
      .getAll([owner, workerId]))
      if (editor.handle === handle) await abortEditor(tx, state, editor);
    await tx.objectStore('directories').put(state);
  });
}
/** Java releases a snapshot once; a failed close must not strand its body pin. */
async function releaseFailedReader(
  database: Database,
  owner: StorageKey,
  id: string,
  handle: string,
) {
  await transaction(database, async (tx) => {
    const reader = await tx.objectStore('readers').get(id);
    if (
      reader?.worker === workerId &&
      reader.handle === handle &&
      sameDirectory(reader.directory, owner)
    ) {
      invalidate(pendingReads, reader.id);
      const state = await stateFor(tx, owner);
      await closeReader(tx, state, reader);
      await tx.objectStore('directories').put(state);
    }
  });
}
async function control(
  request: CacheRequest,
  attempt: Attempt | undefined,
  database: Database,
  owner: StorageKey,
): Promise<Record<string, unknown>> {
  return transaction(database, async (tx) => {
    const state = await stateFor(tx, owner, request.maxSize),
      entries = tx.objectStore('entries'),
      editors = tx.objectStore('editors'),
      readers = tx.objectStore('readers');
    const key = entryKey(owner, request.url),
      row = await entries.get(key);
    let result: Record<string, unknown> = {};
    switch (request.operation) {
      case 'get':
        if (row) {
          if ((await readers.index('byDirectory').count(owner)) >= MAX_HANDLES)
            break;
          const body = await tx
            .objectStore('bodies')
            .get(bodyKey(owner, row.body));
          if (
            !body ||
            body.staging ||
            !body.current ||
            body.bytes !== row.bytes
          )
            throw Error('Invalid cache snapshot body');
          const reader = crypto.randomUUID();
          body.pins++;
          row.access = ++state.sequence;
          await tx.objectStore('bodies').put(body);
          await entries.put(row);
          await readers.add({
            id: reader,
            directory: owner,
            worker: workerId,
            handle: request.handle,
            body: row.body,
            index: 0,
            offset: 0,
            received: 0,
          });
          result = {
            entry: {
              metadata: row.metadata,
              reader,
              length: row.bytes,
              version: row.version,
              generation: state.generation,
            },
          };
        }
        break;
      case 'begin':
        {
          const metadataBytes = jsonSize(request.metadata);
          if (
            !attempt?.valid ||
            metadataBytes > METADATA ||
            metadataBytes > state.limit ||
            request.length > state.limit - metadataBytes ||
            (await editors.index('byEntry').get([owner, request.url])) ||
            (await editors.index('byDirectory').count(owner)) >= MAX_HANDLES
          ) {
            result = { accepted: false };
            break;
          }
          if (
            !(await makeSpace(tx, state, metadataBytes, request.url)) ||
            !attempt.valid
          ) {
            result = { accepted: false };
            break;
          }
          const id = crypto.randomUUID(),
            body = crypto.randomUUID();
          await tx.objectStore('bodies').add({
            key: bodyKey(owner, body),
            bytes: 0,
            chunks: 0,
            current: false,
            staging: true,
            pins: 0,
          });
          await editors.add({
            id,
            directory: owner,
            url: request.url,
            worker: workerId,
            handle: request.handle,
            expected: row?.version ?? null,
            generation: state.generation,
            metadata: request.metadata,
            metadataBytes,
            body,
            length: request.length,
          });
          state.allocatedBytes += metadataBytes;
          result = {
            accepted: true,
            editor: id,
            version: row?.version ?? null,
            generation: state.generation,
          };
        }
        break;
      case 'commit':
        {
          const editor = request.editor
            ? await editors.get(request.editor)
            : undefined;
          if (
            !editor ||
            editor.worker !== workerId ||
            editor.handle !== request.handle ||
            editor.url !== request.url ||
            editor.generation !== request.generation ||
            !sameDirectory(editor.directory, owner)
          ) {
            result = { committed: false };
            break;
          }
          const body = await tx
            .objectStore('bodies')
            .get(bodyKey(owner, editor.body));
          if (!body) throw Error('Missing staged cache body');
          if (
            editor.generation !== state.generation ||
            editor.expected !== (row?.version ?? null) ||
            request.expected !== editor.expected ||
            body.bytes + editor.metadataBytes > state.limit ||
            (editor.length >= 0 && editor.length !== body.bytes)
          ) {
            await abortEditor(tx, state, editor);
            result = { committed: false };
            break;
          }
          if (row) await detachEntry(tx, state, row);
          body.staging = false;
          body.current = true;
          await tx.objectStore('bodies').put(body);
          const entry: Entry = {
            key,
            directory: owner,
            url: request.url,
            metadata: editor.metadata,
            metadataBytes: editor.metadataBytes,
            body: editor.body,
            bytes: body.bytes,
            version: crypto.randomUUID(),
            access: ++state.sequence,
          };
          await entries.put(entry);
          await editors.delete(editor.id);
          state.visibleBytes += body.bytes + editor.metadataBytes;
          if (!(await makeSpace(tx, state, 0, request.url, true)))
            throw new CacheCapacityError(
              'Cache visible budget is pinned by active editors',
            );
          result = { committed: true };
        }
        break;
      case 'update':
        {
          const metadataBytes = jsonSize(request.metadata);
          if (
            !row ||
            metadataBytes > METADATA ||
            (await editors.index('byEntry').get([owner, request.url])) ||
            row.version !== request.expected ||
            state.generation !== request.generation ||
            row.bytes + metadataBytes > state.limit ||
            !(await makeSpace(
              tx,
              state,
              Math.max(0, metadataBytes - row.metadataBytes),
              request.url,
            ))
          ) {
            result = { committed: false };
            break;
          }
          state.visibleBytes += metadataBytes - row.metadataBytes;
          state.allocatedBytes += metadataBytes - row.metadataBytes;
          row.metadata = request.metadata;
          row.metadataBytes = metadataBytes;
          row.version = crypto.randomUUID();
          row.access = ++state.sequence;
          await entries.put(row);
          if (!(await makeSpace(tx, state, 0, request.url, true)))
            throw new CacheCapacityError(
              'Cache visible budget is pinned by active editors',
            );
          result = { committed: true };
        }
        break;
      case 'remove':
        {
          const editor = await editors
            .index('byEntry')
            .get([owner, request.url]);
          if (editor) await abortEditor(tx, state, editor);
          if (row) await detachEntry(tx, state, row);
        }
        break;
      case 'abort':
        {
          const editor = request.editor
            ? await editors.get(request.editor)
            : undefined;
          if (
            editor?.worker === workerId &&
            editor.handle === request.handle &&
            editor.url === request.url &&
            sameDirectory(editor.directory, owner)
          )
            await abortEditor(tx, state, editor);
        }
        break;
      case 'reader-close':
        {
          const reader = request.reader
            ? await readers.get(request.reader)
            : undefined;
          if (
            reader?.worker === workerId &&
            reader.handle === request.handle &&
            sameDirectory(reader.directory, owner)
          ) {
            invalidate(pendingReads, reader.id);
            await closeReader(tx, state, reader);
          }
        }
        break;
      case 'close':
        for (const editor of await editors
          .index('byWorker')
          .getAll([owner, workerId]))
          if (editor.handle === request.handle)
            await abortEditor(tx, state, editor);
        break;
      case 'clear':
      case 'delete':
        for (const editor of await editors.index('byDirectory').getAll(owner))
          await abortEditor(tx, state, editor);
        for (const entry of await entries
          .index('byAccess')
          .getAll(accessRange(owner)))
          await detachEntry(tx, state, entry);
        state.generation++;
        break;
      case 'urls':
        result = {
          urls: (
            await entries.index('byAccess').getAll(accessRange(owner))
          ).map((entry) => entry.url),
        };
        break;
      case 'initialize':
      case 'flush':
        await makeSpace(tx, state, 0, '', true);
        break;
      case 'size':
        result = {
          size: state.visibleBytes,
          allocatedBytes: state.allocatedBytes,
        };
        break;
    }
    await tx.objectStore('directories').put(state);
    return result;
  });
}
const cacheBridge = async (input: string): Promise<string> => {
  if (
    input.length > CONTROL ||
    new TextEncoder().encode(input).length > CONTROL
  )
    throw Error('Cache control exceeds 64 KiB');
  const request = parseCacheRequest(JSON.parse(input) as unknown),
    handle = JSON.stringify([request.directory, request.handle]);
  const attempt =
    request.operation === 'begin' ? register(pendingBegins, handle) : undefined;
  if (request.operation === 'close' || request.operation === 'delete')
    invalidate(pendingBegins, handle);
  try {
    await holdLifetime();
    const database = await open(),
      owner: StorageKey = [namespace, request.directory];
    let result: Record<string, unknown>;
    try {
      await reclaimEditors(database, owner);
      result = await control(request, attempt, database, owner);
    } catch (error) {
      if (request.operation === 'commit' && request.editor) {
        try {
          await releaseFailedEditor(
            database,
            owner,
            request.editor,
            request.handle,
            request.generation,
          );
        } catch (cleanup) {
          throw new AggregateError(
            [error, cleanup],
            'Cache commit and editor cleanup failed',
          );
        }
      }
      if (request.operation === 'close' || request.operation === 'delete') {
        try {
          await releaseClosedHandle(database, owner, request.handle);
        } catch (cleanup) {
          throw new AggregateError(
            [error, cleanup],
            'Cache close and handle cleanup failed',
          );
        }
      }
      if (request.operation === 'reader-close' && request.reader) {
        try {
          await releaseFailedReader(
            database,
            owner,
            request.reader,
            request.handle,
          );
        } catch (cleanup) {
          throw new AggregateError(
            [error, cleanup],
            'Cache snapshot close and cleanup failed',
          );
        }
      }
      if (error instanceof CacheCapacityError) result = { committed: false };
      else throw error;
    }
    const response = JSON.stringify(result);
    if (new TextEncoder().encode(response).length > CONTROL)
      throw Error('Cache response exceeds 64 KiB');
    return response;
  } finally {
    if (attempt) unregister(pendingBegins, handle, attempt);
  }
};
const cacheWrite = async (
  id: string,
  handle: string,
  sequence: number,
  bytes: Uint8Array,
): Promise<boolean> => {
  text(id);
  text(handle);
  integer(sequence);
  if (
    !(bytes instanceof Uint8Array) ||
    bytes.length < 1 ||
    bytes.length > CHUNK
  )
    throw Error('Invalid binary cache chunk size');
  await holdLifetime();
  const database = await open();
  let acquired: Editor | undefined;
  try {
    return await transaction(database, async (tx) => {
      const editor = await tx.objectStore('editors').get(id);
      if (!editor || editor.worker !== workerId || editor.handle !== handle)
        return false;
      acquired = editor;
      const state = await stateFor(tx, editor.directory),
        body = await tx
          .objectStore('bodies')
          .get(bodyKey(editor.directory, editor.body));
      if (!body) throw Error('Missing staged cache body');
      if (
        editor.generation !== state.generation ||
        body.chunks !== sequence ||
        body.chunks >= MAX_CHUNKS ||
        body.bytes + bytes.length + editor.metadataBytes > state.limit ||
        (editor.length >= 0 && body.bytes + bytes.length > editor.length) ||
        !(await makeSpace(tx, state, bytes.length, editor.url))
      ) {
        await abortEditor(tx, state, editor);
        await tx.objectStore('directories').put(state);
        return false;
      }
      await tx
        .objectStore('chunks')
        .add(bytes, [...editor.directory, editor.body, sequence]);
      body.chunks++;
      body.bytes += bytes.length;
      state.allocatedBytes += bytes.length;
      await tx.objectStore('bodies').put(body);
      await tx.objectStore('directories').put(state);
      return true;
    });
  } catch (error) {
    if (acquired) {
      try {
        await releaseFailedEditor(
          database,
          acquired.directory,
          id,
          acquired.handle,
          acquired.generation,
        );
      } catch (cleanup) {
        throw new AggregateError(
          [error, cleanup],
          'Cache write and editor cleanup failed',
        );
      }
    }
    throw error;
  }
};
const cacheRead = async (
  id: string,
  handle: string,
  maximum: number,
): Promise<Uint8Array | null> => {
  text(id);
  text(handle);
  integer(maximum, 1, CHUNK);
  const attempt = register(pendingReads, id);
  try {
    await holdLifetime();
    const database = await open();
    const result = await transaction(database, async (tx) => {
      const reader = await tx.objectStore('readers').get(id);
      if (
        !attempt.valid ||
        !reader ||
        reader.worker !== workerId ||
        reader.handle !== handle
      )
        throw Error('Cache reader is closed');
      const state = await stateFor(tx, reader.directory),
        body = await tx
          .objectStore('bodies')
          .get(bodyKey(reader.directory, reader.body));
      if (!body || body.staging || body.pins < 1)
        throw Error('Missing cache reader body');
      if (reader.received === body.bytes) {
        if (reader.index !== body.chunks || reader.offset !== 0)
          throw Error('Cache body length mismatch');
        await closeReader(tx, state, reader);
        await tx.objectStore('directories').put(state);
        return null;
      }
      const chunk = await tx
        .objectStore('chunks')
        .get([...reader.directory, reader.body, reader.index]);
      if (
        !(chunk instanceof Uint8Array) ||
        chunk.length < 1 ||
        chunk.length > CHUNK ||
        reader.offset >= chunk.length ||
        reader.index >= body.chunks
      )
        throw Error('Missing or invalid cache body chunk');
      const end = Math.min(chunk.length, reader.offset + maximum),
        value = chunk.slice(reader.offset, end);
      reader.offset = end;
      reader.received += value.length;
      if (reader.received > body.bytes)
        throw Error('Cache body exceeds stored length');
      if (end === chunk.length) {
        reader.index++;
        reader.offset = 0;
      }
      await tx.objectStore('readers').put(reader);
      return value;
    });
    if (!attempt.valid) throw Error('Cache reader closed during read');
    return result;
  } catch (error) {
    try {
      const database = await open();
      await transaction(database, async (tx) => {
        const reader = await tx.objectStore('readers').get(id);
        if (reader?.worker === workerId && reader.handle === handle) {
          const state = await stateFor(tx, reader.directory);
          await closeReader(tx, state, reader);
          await tx.objectStore('directories').put(state);
        }
      });
    } catch (cleanup) {
      throw new AggregateError(
        [error, cleanup],
        'Cache read and snapshot cleanup failed',
      );
    }
    throw error;
  } finally {
    unregister(pendingReads, id, attempt);
  }
};
declare global {
  var teaCache: typeof cacheBridge | undefined;
  var teaCacheRead: typeof cacheRead | undefined;
  var teaCacheWrite: typeof cacheWrite | undefined;
}
scope.teaCache = cacheBridge;
scope.teaCacheRead = cacheRead;
scope.teaCacheWrite = cacheWrite;
