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
const limits = {
  allocatedBytes: 128 * 1024 * 1024,
  metadataBytes: 4 * 1024 * 1024,
  directories: 32,
  entries: 4096,
  bodies: 4224,
  chunks: 16384,
  readers: 64,
  editors: 64,
  owners: 32,
} as const;
type Reservation = { -readonly [K in keyof typeof limits]: number };
interface Usage extends Reservation {
  namespace: string;
  sequence: number;
}
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
  namespace: string;
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
  chunkMetadataBytes: number;
  current: boolean;
  staging: boolean;
  pins: number;
}
interface Editor {
  id: string;
  directory: StorageKey;
  url: string;
  worker: string;
  namespace: string;
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
  namespace: string;
  handle: string;
  body: string;
  index: number;
  offset: number;
  received: number;
}
export interface CacheSchema extends DBSchema {
  usage: { key: string; value: Usage };
  owners: {
    key: StorageKey;
    value: { key: StorageKey; namespace: string };
    indexes: { byNamespace: string };
  };
  directories: { key: StorageKey; value: Directory };
  entries: {
    key: EntryKey;
    value: Entry;
    indexes: {
      byAccess: [StorageKey, number];
      byNamespaceAccess: [string, number];
    };
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
      byNamespaceWorker: [string, string];
    };
  };
  readers: {
    key: string;
    value: Reader;
    indexes: {
      byDirectory: StorageKey;
      byWorker: [StorageKey, string];
      byNamespaceWorker: [string, string];
    };
  };
}
type Stores = [
  'usage',
  'owners',
  'directories',
  'entries',
  'bodies',
  'chunks',
  'editors',
  'readers',
];
const stores: Stores = [
  'usage',
  'owners',
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
interface Context {
  tx: CacheTx;
  usage: Usage;
  states: Map<string, Directory>;
  persisted: Set<string>;
}

interface Attempt {
  valid: boolean;
}
const pendingBegins = new Map<string, Set<Attempt>>(),
  pendingReads = new Map<string, Set<Attempt>>();
// Only ordinary data/ref creation is admitted here. Terminal cleanup bypasses
// this window: Java closes once, so refusing its ACK could strand a live pin.
let ordinaryPending = 0;
function admit() {
  if (ordinaryPending >= 4) return false;
  ordinaryPending++;
  return true;
}
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
function boundedText(value: string, maximum: number) {
  if (new TextEncoder().encode(value).length > maximum)
    throw Error('Cache identifier exceeds its UTF-8 budget');
  return value;
}
export function parseCacheRequest(value: unknown): CacheRequest {
  const data = object(value),
    operation = operations.find((item) => item === data.operation);
  if (!operation) throw Error('Unknown browser cache operation');
  return {
    operation,
    directory: boundedText(text(data.directory), 4096),
    maxSize: integer(data.maxSize, 1),
    url: boundedText(optionalText(data.url) ?? '', 16384),
    handle: boundedText(optionalText(data.handle) ?? '', 256),
    editor:
      data.editor === undefined
        ? undefined
        : boundedText(text(data.editor), 256),
    reader:
      data.reader === undefined
        ? undefined
        : boundedText(text(data.reader), 256),
    expected:
      data.expected === undefined || data.expected === null
        ? null
        : boundedText(text(data.expected), 256),
    generation: data.generation === undefined ? 0 : integer(data.generation),
    metadata:
      operation === 'begin' || operation === 'update'
        ? object(data.metadata)
        : undefined,
    length: data.length === undefined ? -1 : integer(data.length, -1),
  };
}
const scope = workerScope();
const requestedNamespace =
  scope.karuyomiWorkerContext?.plugin ||
  new URL(location.href).searchParams.get('plugin');
if (!requestedNamespace) throw Error('Runtime cache namespace is required');
const namespace = boundedText(requestedNamespace, 256);
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
  (opening ??= openDB<CacheSchema>('teavm-http-cache-v3', 1, {
    upgrade(database) {
      database.createObjectStore('usage', { keyPath: 'namespace' });
      database
        .createObjectStore('owners', { keyPath: 'key' })
        .createIndex('byNamespace', 'namespace');
      database.createObjectStore('directories', { keyPath: 'key' });
      const entries = database.createObjectStore('entries', { keyPath: 'key' });
      entries.createIndex('byAccess', ['directory', 'access']);
      entries.createIndex('byNamespaceAccess', ['namespace', 'access']);
      database.createObjectStore('bodies', { keyPath: 'key' });
      database.createObjectStore('chunks');
      const editors = database.createObjectStore('editors', { keyPath: 'id' });
      editors.createIndex('byEntry', ['directory', 'url'], { unique: true });
      editors.createIndex('byDirectory', 'directory');
      editors.createIndex('byWorker', ['directory', 'worker']);
      editors.createIndex('byNamespaceWorker', ['namespace', 'worker']);
      const readers = database.createObjectStore('readers', { keyPath: 'id' });
      readers.createIndex('byDirectory', 'directory');
      readers.createIndex('byWorker', ['directory', 'worker']);
      readers.createIndex('byNamespaceWorker', ['namespace', 'worker']);
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

/** Conservative logical structure reservation, including primary/index keys.
 * Numbers/booleans have a fixed allowance: advancing a reader cannot allocate
 * metadata merely because a cursor acquired another decimal digit. Payload
 * metadata and binary values are accounted separately in allocatedBytes. */
function structure(...values: unknown[]) {
  return 192 + values.reduce<number>((sum, value) => sum + jsonSize(value), 0);
}
const directoryCharge = (row: Directory) => structure(row.key, row.key);
const entryCharge = (row: Entry) =>
  structure(
    {
      key: row.key,
      namespace: row.namespace,
      directory: row.directory,
      url: row.url,
      body: row.body,
      version: row.version,
    },
    row.key,
    [row.directory, 0],
    [row.namespace, 0],
  );
const bodyCharge = (row: Body) => structure(row.key, row.key);
const editorCharge = (row: Editor) =>
  structure(
    {
      id: row.id,
      namespace: row.namespace,
      directory: row.directory,
      url: row.url,
      worker: row.worker,
      handle: row.handle,
      expected: row.expected,
      body: row.body,
    },
    row.id,
    [row.directory, row.url],
    row.directory,
    [row.directory, row.worker],
    [row.namespace, row.worker],
  );
const readerCharge = (row: Reader) =>
  structure(
    {
      id: row.id,
      namespace: row.namespace,
      directory: row.directory,
      worker: row.worker,
      handle: row.handle,
      body: row.body,
    },
    row.id,
    row.directory,
    [row.directory, row.worker],
    [row.namespace, row.worker],
  );
const ownerCharge = (key: StorageKey) => structure(key, key, key[0]);
// Chunks have a binary value and one out-of-line primary key, no value-side key
// or secondary index. This also permits 128 MiB in ordinary 8 KiB writes within
// the independent 4 MiB structure reservation for typical short directories.
const chunkCharge = (key: ChunkKey) => 64 + jsonSize(key);
function emptyUsage(): Usage {
  return {
    namespace,
    sequence: 0,
    allocatedBytes: 0,
    metadataBytes: structure(namespace, namespace),
    directories: 0,
    entries: 0,
    bodies: 0,
    chunks: 0,
    readers: 0,
    editors: 0,
    owners: 0,
  };
}
function fits(usage: Usage, extra: Partial<Reservation> = {}) {
  return (Object.keys(limits) as (keyof Reservation)[]).every(
    (key) => usage[key] + (extra[key] ?? 0) <= limits[key],
  );
}
function assertUsage(usage: Usage) {
  for (const key of Object.keys(limits) as (keyof Reservation)[]) {
    if (!Number.isSafeInteger(usage[key]) || usage[key] < 0)
      throw Error('Invalid cache namespace ledger: ' + key);
  }
  if (!Number.isSafeInteger(usage.sequence) || usage.sequence < 0)
    throw Error('Invalid cache LRU sequence');
  if (!fits(usage))
    throw new CacheCapacityError('Cache namespace reservation exhausted');
}
function allocated(context: Context, state: Directory, delta: number) {
  state.allocatedBytes += delta;
  context.usage.allocatedBytes += delta;
}
function sequence(context: Context) {
  if (context.usage.sequence === Number.MAX_SAFE_INTEGER)
    throw new CacheCapacityError('Cache LRU sequence exhausted');
  return ++context.usage.sequence;
}
/** Short atomic storage operations; the callback awaits only IDB requests.
 * The ledger and all affected directories commit before the caller receives ACK. */
async function transaction<T>(
  database: Database,
  action: (context: Context) => Promise<T>,
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
    const usage =
      (await tx.objectStore('usage').get(namespace)) ?? emptyUsage();
    assertUsage(usage);
    const context: Context = {
      tx,
      usage,
      states: new Map(),
      persisted: new Set(),
    };
    const value = await action(context);
    assertUsage(usage);
    for (const [directory, state] of context.states) {
      if (!context.persisted.has(directory)) continue;
      if (
        !Number.isSafeInteger(state.allocatedBytes) ||
        state.allocatedBytes < 0 ||
        !Number.isSafeInteger(state.visibleBytes) ||
        state.visibleBytes < 0 ||
        state.visibleBytes > state.allocatedBytes
      )
        throw Error('Invalid cache directory ledger');
      await tx.objectStore('directories').put(state);
    }
    await tx.objectStore('usage').put(usage);
    const outcome = await settled;
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
  context: Context,
  owner: StorageKey,
  maxSize?: number,
): Promise<Directory> {
  let state = context.states.get(owner[1]);
  if (!state) {
    state = await context.tx.objectStore('directories').get(owner);
    if (state) context.persisted.add(owner[1]);
    else
      state = {
        key: owner,
        sequence: 0,
        generation: 0,
        visibleBytes: 0,
        allocatedBytes: 0,
        limit: Math.min(maxSize ?? MAX_CACHE, MAX_CACHE),
      };
    context.states.set(owner[1], state);
  }
  if (maxSize !== undefined) state.limit = Math.min(maxSize, MAX_CACHE);
  return state;
}
function ensureDirectory(context: Context, state: Directory) {
  if (context.persisted.has(state.key[1])) return;
  context.persisted.add(state.key[1]);
  context.usage.directories++;
  context.usage.metadataBytes += directoryCharge(state);
}
const bodyKey = (owner: StorageKey, body: string): EntryKey => [...owner, body];
const entryKey = (owner: StorageKey, url: string): EntryKey => [...owner, url];
const chunkRange = (owner: StorageKey, body: string) =>
  IDBKeyRange.bound(
    [...owner, body, 0],
    [...owner, body, Number.MAX_SAFE_INTEGER],
  );
async function addOwner(context: Context, worker: string) {
  const key: StorageKey = [namespace, worker],
    owners = context.tx.objectStore('owners');
  if (await owners.get(key)) return;
  await owners.add({ key, namespace });
  context.usage.owners++;
  context.usage.metadataBytes += ownerCharge(key);
}
async function releaseOwner(context: Context, worker: string) {
  const { tx, usage } = context,
    key: StorageKey = [namespace, worker];
  if (
    (await tx.objectStore('editors').index('byNamespaceWorker').count(key)) ||
    (await tx.objectStore('readers').index('byNamespaceWorker').count(key))
  )
    return;
  if (!(await tx.objectStore('owners').get(key))) return;
  await tx.objectStore('owners').delete(key);
  usage.owners--;
  usage.metadataBytes -= ownerCharge(key);
}
async function removeEditor(context: Context, editor: Editor) {
  await context.tx.objectStore('editors').delete(editor.id);
  context.usage.editors--;
  context.usage.metadataBytes -= editorCharge(editor);
  await releaseOwner(context, editor.worker);
}
async function collectBody(context: Context, state: Directory, body: Body) {
  const { tx, usage } = context;
  if (body.current || body.staging || body.pins) {
    await tx.objectStore('bodies').put(body);
    return;
  }
  await tx.objectStore('chunks').delete(chunkRange(state.key, body.key[2]));
  await tx.objectStore('bodies').delete(body.key);
  allocated(context, state, -body.bytes);
  usage.bodies--;
  usage.chunks -= body.chunks;
  // The reservation belongs to the committed body, not possibly corrupt values.
  usage.metadataBytes -= bodyCharge(body) + body.chunkMetadataBytes;
}
async function detachEntry(context: Context, state: Directory, row: Entry) {
  const { tx, usage } = context;
  await tx.objectStore('entries').delete(row.key);
  usage.entries--;
  usage.metadataBytes -= entryCharge(row);
  state.visibleBytes -= row.metadataBytes + row.bytes;
  allocated(context, state, -row.metadataBytes);
  const body = await tx.objectStore('bodies').get(bodyKey(state.key, row.body));
  if (!body) throw Error('Missing cache entry body');
  body.current = false;
  await collectBody(context, state, body);
}
async function abortEditor(context: Context, state: Directory, editor: Editor) {
  await removeEditor(context, editor);
  allocated(context, state, -editor.metadataBytes);
  const body = await context.tx
    .objectStore('bodies')
    .get(bodyKey(state.key, editor.body));
  if (!body) throw Error('Missing cache staging body');
  body.staging = false;
  await collectBody(context, state, body);
}
async function closeReader(context: Context, state: Directory, reader: Reader) {
  const { tx, usage } = context;
  await tx.objectStore('readers').delete(reader.id);
  usage.readers--;
  usage.metadataBytes -= readerCharge(reader);
  await releaseOwner(context, reader.worker);
  const body = await tx
    .objectStore('bodies')
    .get(bodyKey(state.key, reader.body));
  if (!body || body.pins < 1) throw Error('Missing cache reader snapshot');
  body.pins--;
  await collectBody(context, state, body);
}
const accessRange = (owner: StorageKey) =>
  IDBKeyRange.bound([owner, 0], [owner, Number.MAX_SAFE_INTEGER]);
async function evictable(
  context: Context,
  row: Entry,
  owner: StorageKey,
  protectedUrl: string,
) {
  return (
    !(sameDirectory(row.directory, owner) && row.url === protectedUrl) &&
    !(await context.tx
      .objectStore('editors')
      .index('byEntry')
      .get([row.directory, row.url]))
  );
}
async function makeSpace(
  context: Context,
  state: Directory,
  bytes: number,
  protectedUrl: string,
  trimVisible = false,
  extra: Partial<Reservation> = {},
): Promise<boolean> {
  const { tx, usage } = context;
  const localPressure = trimVisible
    ? state.visibleBytes > state.limit
    : state.allocatedBytes + bytes > state.limit * 2;
  let cursor = localPressure
    ? await tx
        .objectStore('entries')
        .index('byAccess')
        .openCursor(accessRange(state.key))
    : null;
  while (
    cursor &&
    (trimVisible
      ? state.visibleBytes > state.limit
      : state.allocatedBytes + bytes > state.limit * 2)
  ) {
    const row = cursor.value;
    if (await evictable(context, row, state.key, protectedUrl))
      await detachEntry(context, state, row);
    cursor = await cursor.continue();
  }
  if (trimVisible) return state.visibleBytes <= state.limit;
  const reservation = { ...extra, allocatedBytes: bytes };
  if (fits(usage, reservation))
    return state.allocatedBytes + bytes <= state.limit * 2;
  // Namespace LRU: a cold directory must not permanently consume another one's
  // budget. Pinned snapshots remain charged after detaching their current entry.
  let global = await tx
    .objectStore('entries')
    .index('byNamespaceAccess')
    .openCursor(
      IDBKeyRange.bound([namespace, 0], [namespace, Number.MAX_SAFE_INTEGER]),
    );
  while (global && !fits(usage, reservation)) {
    const row = global.value;
    if (await evictable(context, row, state.key, protectedUrl))
      await detachEntry(context, await stateFor(context, row.directory), row);
    global = await global.continue();
  }
  return (
    fits(usage, reservation) && state.allocatedBytes + bytes <= state.limit * 2
  );
}
/** Namespace-wide Web Lock probes never keep an IDB transaction alive.
 * Ordinary binary read/write uses direct lookups, not this bounded owner scan. */
async function reclaimEditors(database: Database) {
  const workers = await database.getAllFromIndex(
    'owners',
    'byNamespace',
    namespace,
  );
  await Promise.all(
    workers
      .filter((row) => row.key[1] !== workerId)
      .map((row) =>
        navigator.locks.request(
          lifetimeName(row.key[1]),
          { ifAvailable: true },
          async (lock) => {
            if (!lock) return;
            await transaction(database, async (context) => {
              const { tx } = context,
                worker = row.key[1],
                key: StorageKey = [namespace, worker];
              for (const editor of await tx
                .objectStore('editors')
                .index('byNamespaceWorker')
                .getAll(key))
                await abortEditor(
                  context,
                  await stateFor(context, editor.directory),
                  editor,
                );
              for (const reader of await tx
                .objectStore('readers')
                .index('byNamespaceWorker')
                .getAll(key))
                await closeReader(
                  context,
                  await stateFor(context, reader.directory),
                  reader,
                );
              await releaseOwner(context, worker);
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
  await transaction(database, async (context) => {
    const state = await stateFor(context, owner),
      editor = await context.tx.objectStore('editors').get(id);
    if (
      state.generation === generation &&
      editor?.worker === workerId &&
      editor.handle === handle &&
      editor.generation === generation &&
      sameDirectory(editor.directory, owner)
    )
      await abortEditor(context, state, editor);
  });
}
/** Java closes its handle before awaiting storage, so failure must release it too. */
async function releaseClosedHandle(
  database: Database,
  owner: StorageKey,
  handle: string,
) {
  await transaction(database, async (context) => {
    const state = await stateFor(context, owner);
    for (const editor of await context.tx
      .objectStore('editors')
      .index('byWorker')
      .getAll([owner, workerId]))
      if (editor.handle === handle) await abortEditor(context, state, editor);
  });
}
/** Java releases a snapshot once; a failed close must not strand its body pin. */
async function releaseFailedReader(
  database: Database,
  owner: StorageKey,
  id: string,
  handle: string,
) {
  await transaction(database, async (context) => {
    const reader = await context.tx.objectStore('readers').get(id);
    if (
      reader?.worker === workerId &&
      reader.handle === handle &&
      sameDirectory(reader.directory, owner)
    ) {
      invalidate(pendingReads, reader.id);
      await closeReader(context, await stateFor(context, owner), reader);
    }
  });
}
async function control(
  request: CacheRequest,
  attempt: Attempt | undefined,
  database: Database,
  owner: StorageKey,
): Promise<Record<string, unknown>> {
  return transaction(database, async (context) => {
    const { tx, usage } = context;
    const state = await stateFor(context, owner, request.maxSize),
      entries = tx.objectStore('entries'),
      editors = tx.objectStore('editors'),
      readers = tx.objectStore('readers');
    const key = entryKey(owner, request.url),
      row = await entries.get(key);
    let result: Record<string, unknown> = {};
    switch (request.operation) {
      case 'get':
        if (row) {
          if (usage.readers >= MAX_HANDLES) break;
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
          const record: Reader = {
            id: reader,
            namespace,
            directory: owner,
            worker: workerId,
            handle: request.handle,
            body: row.body,
            index: 0,
            offset: 0,
            received: 0,
          };
          await addOwner(context, workerId);
          usage.readers++;
          usage.metadataBytes += readerCharge(record);
          assertUsage(usage);
          body.pins++;
          row.access = sequence(context);
          await tx.objectStore('bodies').put(body);
          await entries.put(row);
          await readers.add(record);
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
            usage.editors >= MAX_HANDLES
          ) {
            result = { accepted: false };
            break;
          }
          const id = crypto.randomUUID(),
            body = crypto.randomUUID();
          const bodyRecord: Body = {
            key: bodyKey(owner, body),
            bytes: 0,
            chunks: 0,
            chunkMetadataBytes: 0,
            current: false,
            staging: true,
            pins: 0,
          };
          const editor: Editor = {
            id,
            namespace,
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
          };
          ensureDirectory(context, state);
          await addOwner(context, workerId);
          if (
            !(await makeSpace(
              context,
              state,
              metadataBytes,
              request.url,
              false,
              {
                bodies: 1,
                editors: 1,
                metadataBytes: bodyCharge(bodyRecord) + editorCharge(editor),
              },
            )) ||
            !attempt.valid
          )
            throw new CacheCapacityError('Cache cannot reserve an editor');
          await tx.objectStore('bodies').add(bodyRecord);
          await editors.add(editor);
          usage.bodies++;
          usage.editors++;
          usage.metadataBytes += bodyCharge(bodyRecord) + editorCharge(editor);
          allocated(context, state, metadataBytes);
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
            await abortEditor(context, state, editor);
            result = { committed: false };
            break;
          }
          if (row) await detachEntry(context, state, row);
          body.staging = false;
          body.current = true;
          await tx.objectStore('bodies').put(body);
          const entry: Entry = {
            key,
            namespace,
            directory: owner,
            url: request.url,
            metadata: editor.metadata,
            metadataBytes: editor.metadataBytes,
            body: editor.body,
            bytes: body.bytes,
            version: crypto.randomUUID(),
            access: sequence(context),
          };
          await removeEditor(context, editor);
          if (
            !(await makeSpace(context, state, 0, request.url, false, {
              entries: 1,
              metadataBytes: entryCharge(entry),
            }))
          )
            throw new CacheCapacityError('Cache cannot reserve an entry');
          await entries.put(entry);
          usage.entries++;
          usage.metadataBytes += entryCharge(entry);
          state.visibleBytes += body.bytes + editor.metadataBytes;
          if (!(await makeSpace(context, state, 0, request.url, true)))
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
              context,
              state,
              Math.max(0, metadataBytes - row.metadataBytes),
              request.url,
            ))
          ) {
            result = { committed: false };
            break;
          }
          state.visibleBytes += metadataBytes - row.metadataBytes;
          allocated(context, state, metadataBytes - row.metadataBytes);
          row.metadata = request.metadata;
          row.metadataBytes = metadataBytes;
          row.version = crypto.randomUUID();
          row.access = sequence(context);
          await entries.put(row);
          if (!(await makeSpace(context, state, 0, request.url, true)))
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
          if (editor) await abortEditor(context, state, editor);
          if (row) await detachEntry(context, state, row);
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
            await abortEditor(context, state, editor);
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
            await closeReader(context, state, reader);
          }
        }
        break;
      case 'close':
        for (const editor of await editors
          .index('byWorker')
          .getAll([owner, workerId]))
          if (editor.handle === request.handle)
            await abortEditor(context, state, editor);
        break;
      case 'clear':
      case 'delete':
        for (const editor of await editors.index('byDirectory').getAll(owner))
          await abortEditor(context, state, editor);
        for (const entry of await entries
          .index('byAccess')
          .getAll(accessRange(owner)))
          await detachEntry(context, state, entry);
        state.generation++;
        break;
      case 'urls': {
        const urls: string[] = [];
        let length = 16;
        for await (const cursor of entries
          .index('byAccess')
          .iterate(accessRange(owner))) {
          length += jsonSize(cursor.value.url) + 1;
          if (length > CONTROL) throw Error('Cache URL list exceeds 64 KiB');
          urls.push(cursor.value.url);
        }
        result = { urls };
        break;
      }
      case 'initialize':
        ensureDirectory(context, state);
        await makeSpace(context, state, 0, '', true);
        break;
      case 'flush':
        await makeSpace(context, state, 0, '', true);
        break;
      case 'size':
        result = {
          size: state.visibleBytes,
          allocatedBytes: state.allocatedBytes,
        };
        break;
    }
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
  const ordinary = request.operation === 'get' || request.operation === 'begin';
  if (ordinary && !admit())
    return JSON.stringify(
      request.operation === 'get' ? {} : { accepted: false },
    );
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
      if (
        request.operation !== 'close' &&
        request.operation !== 'reader-close' &&
        request.operation !== 'abort'
      )
        await reclaimEditors(database);
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
      if (error instanceof CacheCapacityError && request.operation === 'get')
        result = {};
      else if (
        error instanceof CacheCapacityError &&
        request.operation === 'begin'
      )
        result = { accepted: false };
      else if (
        error instanceof CacheCapacityError &&
        (request.operation === 'commit' || request.operation === 'update')
      )
        result = { committed: false };
      else throw error;
    }
    const response = JSON.stringify(result);
    if (new TextEncoder().encode(response).length > CONTROL)
      throw Error('Cache response exceeds 64 KiB');
    return response;
  } finally {
    if (attempt) unregister(pendingBegins, handle, attempt);
    if (ordinary) ordinaryPending--;
  }
};
const cacheWrite = async (
  id: string,
  handle: string,
  sequence: number,
  bytes: Uint8Array,
): Promise<boolean> => {
  boundedText(text(id), 256);
  boundedText(text(handle), 256);
  integer(sequence);
  if (
    !(bytes instanceof Uint8Array) ||
    bytes.length < 1 ||
    bytes.length > CHUNK
  )
    throw Error('Invalid binary cache chunk size');
  const admitted = admit();
  let database: Database | undefined;
  let acquired: Editor | undefined;
  try {
    await holdLifetime();
    database = await open();
    if (!admitted) {
      const editor = await database.get('editors', id);
      if (editor?.worker === workerId && editor.handle === handle)
        await releaseFailedEditor(
          database,
          editor.directory,
          id,
          handle,
          editor.generation,
        );
      return false;
    }
    return await transaction(database, async (context) => {
      const { tx, usage } = context;
      const editor = await tx.objectStore('editors').get(id);
      if (!editor || editor.worker !== workerId || editor.handle !== handle)
        return false;
      acquired = editor;
      const state = await stateFor(context, editor.directory),
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
        !(await makeSpace(context, state, bytes.length, editor.url, false, {
          chunks: 1,
          metadataBytes: chunkCharge([
            ...editor.directory,
            editor.body,
            sequence,
          ]),
        }))
      ) {
        await abortEditor(context, state, editor);
        return false;
      }
      await tx
        .objectStore('chunks')
        .add(bytes, [...editor.directory, editor.body, sequence]);
      body.chunks++;
      const metadataBytes = chunkCharge([
        ...editor.directory,
        editor.body,
        sequence,
      ]);
      body.chunkMetadataBytes += metadataBytes;
      body.bytes += bytes.length;
      allocated(context, state, bytes.length);
      usage.chunks++;
      usage.metadataBytes += metadataBytes;
      await tx.objectStore('bodies').put(body);
      return true;
    });
  } catch (error) {
    if (acquired && database) {
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
    if (error instanceof CacheCapacityError) return false;
    throw error;
  } finally {
    if (admitted) ordinaryPending--;
  }
};
const cacheRead = async (
  id: string,
  handle: string,
  maximum: number,
): Promise<Uint8Array | null> => {
  boundedText(text(id), 256);
  boundedText(text(handle), 256);
  integer(maximum, 1, CHUNK);
  const attempt = register(pendingReads, id);
  const admitted = admit();
  try {
    if (!admitted) throw Error('Cache ordinary operation window is full');
    await holdLifetime();
    const database = await open();
    const result = await transaction(database, async (context) => {
      const { tx } = context;
      const reader = await tx.objectStore('readers').get(id);
      if (
        !attempt.valid ||
        !reader ||
        reader.worker !== workerId ||
        reader.handle !== handle
      )
        throw Error('Cache reader is closed');
      const state = await stateFor(context, reader.directory),
        body = await tx
          .objectStore('bodies')
          .get(bodyKey(reader.directory, reader.body));
      if (!body || body.staging || body.pins < 1)
        throw Error('Missing cache reader body');
      if (reader.received === body.bytes) {
        if (reader.index !== body.chunks || reader.offset !== 0)
          throw Error('Cache body length mismatch');
        await closeReader(context, state, reader);
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
      await transaction(database, async (context) => {
        const { tx } = context;
        const reader = await tx.objectStore('readers').get(id);
        if (reader?.worker === workerId && reader.handle === handle) {
          const state = await stateFor(context, reader.directory);
          await closeReader(context, state, reader);
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
    if (admitted) ordinaryPending--;
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
