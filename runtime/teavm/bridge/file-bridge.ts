/* TeaVM file semantics; IndexedDB transactions and typed requests come from idb. */
import {
  openDB,
  type DBSchema,
  type IDBPDatabase,
  type IDBPTransaction,
} from 'idb';
import {
  bool,
  integer,
  number,
  object,
  optionalText,
  text,
  workerScope,
  type StorageKey,
} from './bridge-common.js';

const CHUNK = 65536,
  CONTROL = 65536,
  FILE_LIMIT = 64 * 1024 * 1024,
  NAMESPACE_LIMIT = 128 * 1024 * 1024,
  METADATA_LIMIT = 2 * 1024 * 1024,
  NODE_LIMIT = 4096,
  HANDLE_LIMIT = 64,
  OWNER_LIMIT = 32,
  PENDING_LIMIT = 4,
  PATH_LIMIT = 4096,
  TIMEOUT = 5000;
type HandleKey = [string, string, string];
type ChunkKey = [string, string, number];
interface FileNode {
  key: StorageKey;
  id: string;
  directory: boolean;
  readOnly: boolean;
  modified: number;
  linked: boolean;
  length: number;
}
interface PathRow {
  key: StorageKey;
  path: string;
  parent: StorageKey;
  id: string;
}
interface HandleRow {
  key: HandleKey;
  owner: StorageKey;
  inode: StorageKey;
}
interface OwnerRow {
  key: StorageKey;
  token: string;
}
interface Usage {
  namespace: string;
  logicalBytes: number;
  allocatedBytes: number;
  metadataBytes: number;
  nodes: number;
  handles: number;
  owners: number;
}
export interface FileSchema extends DBSchema {
  paths: {
    key: StorageKey;
    value: PathRow;
    indexes: { byParent: StorageKey };
  };
  inodes: { key: StorageKey; value: FileNode };
  chunks: { key: ChunkKey; value: Uint8Array };
  handles: {
    key: HandleKey;
    value: HandleRow;
    indexes: { byInode: StorageKey; byOwner: StorageKey };
  };
  owners: { key: StorageKey; value: OwnerRow };
  usage: { key: string; value: Usage };
}
type Stores = ['paths', 'inodes', 'chunks', 'handles', 'owners', 'usage'];
const stores: Stores = [
  'paths',
  'inodes',
  'chunks',
  'handles',
  'owners',
  'usage',
];
type FileTx = IDBPTransaction<FileSchema, Stores, 'readwrite'>;
interface FileTransaction {
  tx: FileTx;
  usage: Usage;
}
interface OpenFile {
  inode: string;
  position: number;
  readable: boolean;
  writable: boolean;
  append: boolean;
}
const operations = [
  'initialize',
  'tell',
  'seek',
  'skip',
  'stat',
  'list',
  'create',
  'mkdir',
  'delete',
  'rename',
  'modified',
  'readonly',
  'open',
  'resize',
  'size',
  'flush',
  'close',
] as const;
interface FileRequest {
  operation: (typeof operations)[number];
  path: string;
  handle: string | undefined;
  source: string;
  modified: number;
  readOnly: boolean;
  writable: boolean;
  readable: boolean;
  append: boolean;
  position: number;
  count: number;
  size: number;
}
export function parseFileRequest(value: unknown): FileRequest {
  const data = object(value),
    operation = operations.find((item) => item === data.operation);
  if (!operation) throw Error('Unknown Java filesystem operation');
  return {
    operation,
    path: optionalText(data.path) ?? '/',
    handle: optionalText(data.handle),
    source: operation === 'rename' ? text(data.source) : '',
    modified: operation === 'modified' ? number(data.modified) : 0,
    readOnly: data.readOnly === undefined ? false : bool(data.readOnly),
    writable: data.writable === undefined ? false : bool(data.writable),
    readable: data.readable === undefined ? false : bool(data.readable),
    append: data.append === undefined ? false : bool(data.append),
    position: operation === 'seek' ? integer(data.position, 0, FILE_LIMIT) : 0,
    count:
      operation === 'skip' ? integer(data.count, -FILE_LIMIT, FILE_LIMIT) : 0,
    size: operation === 'resize' ? integer(data.size, 0, FILE_LIMIT) : 0,
  };
}
const encoder = new TextEncoder();
function jsonSize(value: unknown): number {
  return value === undefined ? 0 : encoder.encode(JSON.stringify(value)).length;
}
function assertUsage(usage: Usage) {
  for (const value of Object.values(usage)) {
    if (
      typeof value === 'number' &&
      (!Number.isSafeInteger(value) || value < 0)
    )
      throw Error('Invalid Java filesystem usage accounting');
  }
  if (
    usage.logicalBytes > NAMESPACE_LIMIT ||
    usage.allocatedBytes > NAMESPACE_LIMIT ||
    usage.metadataBytes > METADATA_LIMIT ||
    usage.nodes > NODE_LIMIT ||
    usage.handles > HANDLE_LIMIT ||
    usage.owners > OWNER_LIMIT
  )
    throw Error('Java filesystem namespace capacity exceeded');
}
function checkedChunk(value: Uint8Array | undefined): Uint8Array | undefined {
  if (
    value !== undefined &&
    (!(value instanceof Uint8Array) || value.byteLength !== CHUNK)
  )
    throw Error('Invalid stored Java file chunk');
  return value;
}
declare global {
  var teaFile: ReturnType<typeof createFileBridge>['teaFile'] | undefined;
  var teaFileRead:
    ReturnType<typeof createFileBridge>['teaFileRead'] | undefined;
  var teaFileWrite:
    ReturnType<typeof createFileBridge>['teaFileWrite'] | undefined;
  var teaFileSystemClose:
    ReturnType<typeof createFileBridge>['teaFileSystemClose'] | undefined;
}
const scope = workerScope();
function createFileBridge() {
  const params = new URL(location.href).searchParams,
    requestedNamespace =
      scope.karuyomiWorkerContext?.fsNamespace ||
      scope.karuyomiWorkerContext?.plugin ||
      params.get('fsNamespace') ||
      params.get('plugin');
  if (!requestedNamespace)
    throw Error('Runtime filesystem namespace is required');
  const namespace: string = requestedNamespace;
  if (encoder.encode(namespace).length > PATH_LIMIT)
    throw Error('Runtime filesystem namespace is too long');
  const owner = crypto.randomUUID(),
    ownerToken = crypto.randomUUID(),
    handles = new Map<string, OpenFile>(),
    key = (value: string): StorageKey => [namespace, value],
    ownerKey = key(owner),
    namespaceRange = () => IDBKeyRange.bound([namespace], [namespace, []]),
    lockName = (id: string) =>
      'teavm-java-files:' + JSON.stringify([namespace, id]);
  let opening: Promise<IDBPDatabase<FileSchema>> | undefined,
    starting: Promise<void> | undefined,
    tail: Promise<unknown> = Promise.resolve(),
    releaseOwner: (() => void) | undefined,
    closePromise: Promise<void> | undefined,
    pending = 0,
    closing = false,
    closed = false;
  const parent = (path: string) => path.slice(0, path.lastIndexOf('/')) || '/';
  function normalize(path: string): string {
    if (path.includes('\0') || encoder.encode(path).length > PATH_LIMIT)
      throw Error('Invalid or overlong Java file path');
    const parts: string[] = [];
    for (const part of path.split('/')) {
      if (!part || part === '.') continue;
      if (part === '..') parts.pop();
      else parts.push(part);
    }
    const result = '/' + parts.join('/');
    if (encoder.encode(result).length > PATH_LIMIT)
      throw Error('Invalid or overlong Java file path');
    return result;
  }
  function open() {
    return (opening ??= openDB<FileSchema>('teavm-java-files-v2', 1, {
      upgrade(db) {
        db.createObjectStore('paths', { keyPath: 'key' }).createIndex(
          'byParent',
          'parent',
        );
        db.createObjectStore('inodes', { keyPath: 'key' });
        db.createObjectStore('chunks');
        const h = db.createObjectStore('handles', { keyPath: 'key' });
        h.createIndex('byInode', 'inode');
        h.createIndex('byOwner', 'owner');
        db.createObjectStore('owners', { keyPath: 'key' });
        db.createObjectStore('usage', { keyPath: 'namespace' });
      },
      blocking() {
        void opening?.then((db) => db.close());
        opening = undefined;
      },
      terminated() {
        opening = undefined;
      },
    }).catch((error: unknown) => {
      opening = undefined;
      throw error;
    }));
  }
  // Only IDB requests are awaited inside this callback. ACK/cursors follow tx.done.
  async function transaction<T>(
    action: (
      state: FileTransaction,
      afterCommit: (fn: () => void) => void,
    ) => Promise<T>,
  ): Promise<T> {
    const db = await open(),
      tx = db.transaction(stores, 'readwrite', { durability: 'strict' }),
      settled = tx.done.then(
        () => ({ passed: true as const }),
        (error: unknown) => ({ passed: false as const, error }),
      ),
      commits: (() => void)[] = [];
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
      const usage = (await tx.objectStore('usage').get(namespace)) ?? {
        namespace,
        logicalBytes: 0,
        allocatedBytes: 0,
        metadataBytes: 256 + encoder.encode(namespace).length,
        nodes: 0,
        handles: 0,
        owners: 0,
      };
      assertUsage(usage);
      const result = await action({ tx, usage }, (fn) => commits.push(fn));
      assertUsage(usage);
      await tx.objectStore('usage').put(usage);
      const outcome = await settled;
      if (!outcome.passed) throw outcome.error;
      // A completed transaction remains committed even if a later timer runs.
      for (const commit of commits) commit();
      return result;
    } catch (error) {
      try {
        tx.abort();
      } catch {
        /* Already terminal. */
      }
      await settled;
      if (timedOut) throw Error('Java filesystem transaction timed out');
      throw error;
    } finally {
      clearTimeout(timer);
    }
  }
  async function putNode(s: FileTransaction, node: FileNode) {
    integer(node.length, 0, FILE_LIMIT);
    const store = s.tx.objectStore('inodes'),
      previous = await store.get(node.key);
    s.usage.nodes += previous ? 0 : 1;
    s.usage.logicalBytes += node.length - (previous?.length ?? 0);
    s.usage.metadataBytes += jsonSize(node) - jsonSize(previous);
    assertUsage(s.usage);
    await store.put(node);
  }
  async function putPath(s: FileTransaction, path: string, id: string) {
    const store = s.tx.objectStore('paths'),
      row: PathRow = {
        key: key(path),
        path,
        parent: key(path === '/' ? '' : parent(path)),
        id,
      },
      previous = await store.get(row.key);
    s.usage.metadataBytes += jsonSize(row) - jsonSize(previous);
    assertUsage(s.usage);
    await store.put(row);
  }
  async function deletePath(s: FileTransaction, row: PathRow) {
    s.usage.metadataBytes -= jsonSize(row);
    await s.tx.objectStore('paths').delete(row.key);
  }
  const chunkRange = (id: string, minimum = 0) =>
    IDBKeyRange.bound(
      [namespace, id, minimum],
      [namespace, id, Number.MAX_SAFE_INTEGER],
    );
  const chunkMetadata = (chunkKey: ChunkKey) => jsonSize(chunkKey) + 32;
  async function putChunk(
    s: FileTransaction,
    chunkKey: ChunkKey,
    bytes: Uint8Array,
  ) {
    const store = s.tx.objectStore('chunks'),
      previous = checkedChunk(await store.get(chunkKey));
    if (!previous) {
      s.usage.allocatedBytes += CHUNK;
      s.usage.metadataBytes += chunkMetadata(chunkKey);
      assertUsage(s.usage);
    }
    await store.put(bytes, chunkKey);
  }
  async function removeChunks(s: FileTransaction, id: string, minimum = 0) {
    let cursor = await s.tx
      .objectStore('chunks')
      .openCursor(chunkRange(id, minimum));
    while (cursor) {
      checkedChunk(cursor.value);
      s.usage.allocatedBytes -= CHUNK;
      s.usage.metadataBytes -= chunkMetadata(cursor.key);
      await cursor.delete();
      cursor = await cursor.continue();
    }
  }
  async function collect(s: FileTransaction, node: FileNode) {
    if (
      node.linked ||
      (await s.tx.objectStore('handles').index('byInode').count(node.key))
    )
      return;
    await removeChunks(s, node.id);
    s.usage.nodes--;
    s.usage.logicalBytes -= node.length;
    s.usage.metadataBytes -= jsonSize(node);
    await s.tx.objectStore('inodes').delete(node.key);
  }
  async function dropHandle(s: FileTransaction, row: HandleRow) {
    await s.tx.objectStore('handles').delete(row.key);
    s.usage.handles--;
    s.usage.metadataBytes -= jsonSize(row);
    const node = await s.tx.objectStore('inodes').get(row.inode);
    if (node) await collect(s, node);
  }
  async function dropOwner(s: FileTransaction, row: OwnerRow) {
    const existing = await s.tx.objectStore('owners').get(row.key);
    if (existing?.token !== row.token) return;
    for (const handle of await s.tx
      .objectStore('handles')
      .index('byOwner')
      .getAll(row.key))
      await dropHandle(s, handle);
    await s.tx.objectStore('owners').delete(row.key);
    s.usage.owners--;
    s.usage.metadataBytes -= jsonSize(existing);
  }
  async function reclaimOwners() {
    const owners = await transaction(async ({ tx }) =>
      tx.objectStore('owners').getAll(namespaceRange()),
    );
    for (const row of owners) {
      if (row.key[1] === owner) continue;
      await navigator.locks.request(
        lockName(row.key[1]),
        { ifAvailable: true },
        async (lock) => {
          if (lock) await transaction((s) => dropOwner(s, row));
        },
      );
    }
  }
  async function nodeFor(s: FileTransaction, path: string) {
    const row = await s.tx.objectStore('paths').get(key(path));
    return row ? s.tx.objectStore('inodes').get(key(row.id)) : undefined;
  }
  async function create(
    s: FileTransaction,
    path: string,
    directory: boolean,
    parentNode?: FileNode,
  ) {
    const id = crypto.randomUUID(),
      node: FileNode = {
        key: key(id),
        id,
        directory,
        readOnly: false,
        modified: Date.now(),
        linked: true,
        length: 0,
      };
    await putNode(s, node);
    await putPath(s, path, id);
    if (parentNode) await touch(s, parentNode);
    return node;
  }
  async function touch(s: FileTransaction, node: FileNode) {
    node.modified = Date.now();
    await putNode(s, node);
  }
  async function start() {
    if (closed) throw Error('Java filesystem is closed');
    return (starting ??= (async () => {
      if (!navigator.locks)
        throw Error(
          'Java filesystem requires Web Locks for Worker lifetime tracking',
        );
      await new Promise<void>((resolve, reject) => {
        navigator.locks
          .request(lockName(owner), () => {
            resolve();
            return new Promise<void>((done) => {
              releaseOwner = done;
            });
          })
          .catch(reject);
      });
      await reclaimOwners();
      await transaction(async (s) => {
        for (const path of ['/', '/tmp'])
          if (!(await nodeFor(s, path))) await create(s, path, true);
        const row: OwnerRow = { key: ownerKey, token: ownerToken };
        s.usage.owners++;
        s.usage.metadataBytes += jsonSize(row);
        assertUsage(s.usage);
        await s.tx.objectStore('owners').add(row);
      });
    })().catch((error: unknown) => {
      releaseOwner?.();
      releaseOwner = undefined;
      starting = undefined;
      throw error;
    }));
  }
  function handle(id: string): OpenFile {
    const result = handles.get(id);
    if (!result) throw Error('File stream is closed');
    return result;
  }
  async function opened(s: FileTransaction, id: string) {
    const h = handle(id),
      row = await s.tx.objectStore('handles').get([namespace, owner, id]);
    if (!row || row.inode[1] !== h.inode)
      throw Error('File stream owner is no longer active');
    const node = await s.tx.objectStore('inodes').get(row.inode);
    if (!node || node.directory) throw Error('Open file inode is missing');
    return { h, row, node };
  }
  async function resize(s: FileTransaction, node: FileNode, length: number) {
    integer(length, 0, FILE_LIMIT);
    if (length < node.length) {
      await removeChunks(s, node.id, Math.ceil(length / CHUNK));
      if (length % CHUNK) {
        const index = Math.floor(length / CHUNK),
          chunkKey: ChunkKey = [namespace, node.id, index],
          bytes = checkedChunk(await s.tx.objectStore('chunks').get(chunkKey));
        if (bytes) {
          bytes.fill(0, length % CHUNK);
          await putChunk(s, chunkKey, bytes);
        }
      }
    }
    node.length = length;
    await touch(s, node);
  }
  async function operate(r: FileRequest): Promise<Record<string, unknown>> {
    await start();
    const path = normalize(r.path);
    if (r.operation === 'initialize') return { ready: true };
    if (r.operation === 'open') await reclaimOwners();
    if (r.operation === 'tell')
      return { position: handle(text(r.handle)).position };
    if (r.operation === 'seek' || r.operation === 'skip') {
      const h = handle(text(r.handle));
      h.position = integer(
        r.operation === 'seek' ? r.position : h.position + r.count,
        0,
        FILE_LIMIT,
      );
      return {};
    }
    return transaction(async (s, afterCommit) => {
      const state = r.handle ? await opened(s, r.handle) : undefined,
        node = state?.node ?? (await nodeFor(s, path));
      switch (r.operation) {
        case 'stat':
          return node
            ? {
                exists: true,
                directory: node.directory,
                file: !node.directory,
                readable: true,
                writable: !node.readOnly,
                modified: node.modified,
                size: node.length,
              }
            : { exists: false };
        case 'list':
          return node?.directory
            ? {
                names: (
                  await s.tx
                    .objectStore('paths')
                    .index('byParent')
                    .getAll(key(path))
                )
                  .map((row) => row.path.slice(row.path.lastIndexOf('/') + 1))
                  .sort(),
              }
            : {};
        case 'create':
        case 'mkdir': {
          if (node) return { changed: false };
          const dir = await nodeFor(s, parent(path));
          if (!dir?.directory || dir.readOnly) {
            if (r.operation === 'create')
              throw Error('Parent directory does not exist or is not writable');
            return { changed: false };
          }
          await create(s, path, r.operation === 'mkdir', dir);
          return { changed: true };
        }
        case 'delete': {
          if (!node || path === '/') return { changed: false };
          const dir = await nodeFor(s, parent(path));
          if (
            !dir ||
            dir.readOnly ||
            (node.directory &&
              (await s.tx
                .objectStore('paths')
                .index('byParent')
                .count(key(path))))
          )
            return { changed: false };
          const row = await s.tx.objectStore('paths').get(key(path));
          if (!row) throw Error('File path disappeared');
          await deletePath(s, row);
          node.linked = false;
          await putNode(s, node);
          await collect(s, node);
          await touch(s, dir);
          return { changed: true };
        }
        case 'rename': {
          const source = normalize(r.source),
            from = await nodeFor(s, source),
            dir = await nodeFor(s, parent(path)),
            oldDir = await nodeFor(s, parent(source));
          if (
            !from ||
            source === '/' ||
            path === '/' ||
            !dir?.directory ||
            dir.readOnly ||
            !oldDir ||
            oldDir.readOnly
          )
            return { changed: false };
          if (source === path) return { changed: true };
          if (from.directory && path.startsWith(source + '/'))
            return { changed: false };
          if (
            node &&
            (node.directory !== from.directory ||
              (node.directory &&
                (await s.tx
                  .objectStore('paths')
                  .index('byParent')
                  .count(key(path)))))
          )
            return { changed: false };
          const sourceRow = await s.tx.objectStore('paths').get(key(source));
          if (!sourceRow) throw Error('File path disappeared');
          const moving = [sourceRow];
          if (from.directory)
            moving.push(
              ...(await s.tx
                .objectStore('paths')
                .getAll(
                  IDBKeyRange.bound(
                    key(source + '/'),
                    key(source + '0'),
                    false,
                    true,
                  ),
                )),
            );
          if (node) {
            const target = await s.tx.objectStore('paths').get(key(path));
            if (!target) throw Error('File path disappeared');
            await deletePath(s, target);
            node.linked = false;
            await putNode(s, node);
            await collect(s, node);
          }
          for (const row of moving) await deletePath(s, row);
          for (const row of moving) {
            const next = normalize(path + row.path.slice(source.length));
            await putPath(s, next, row.id);
          }
          await touch(s, dir);
          if (oldDir.id !== dir.id) await touch(s, oldDir);
          return { changed: true };
        }
        case 'modified':
        case 'readonly': {
          if (!node) return { changed: false };
          if (r.operation === 'modified') node.modified = r.modified;
          else node.readOnly = r.readOnly;
          await putNode(s, node);
          return { changed: true };
        }
        case 'open': {
          if (!node || node.directory || (r.writable && node.readOnly))
            return {};
          if (r.writable && !r.readable && !r.append) await resize(s, node, 0);
          const id = crypto.randomUUID(),
            row: HandleRow = {
              key: [namespace, owner, id],
              owner: ownerKey,
              inode: node.key,
            };
          s.usage.handles++;
          s.usage.metadataBytes += jsonSize(row);
          assertUsage(s.usage);
          await s.tx.objectStore('handles').add(row);
          afterCommit(() =>
            handles.set(id, {
              inode: node.id,
              position: r.append ? node.length : 0,
              readable: r.readable,
              writable: r.writable,
              append: r.append,
            }),
          );
          return { handle: id };
        }
        case 'resize': {
          if (!state || !state.h.writable)
            throw Error('File is not open for writing');
          await resize(s, state.node, r.size);
          afterCommit(() => {
            state.h.position = Math.min(state.h.position, r.size);
          });
          return {};
        }
        case 'size':
          if (!state) throw Error('File stream is closed');
          return { size: state.node.length };
        case 'flush':
          if (!state) throw Error('File stream is closed');
          return {};
        case 'close':
          if (!state) throw Error('File stream is closed');
          await dropHandle(s, state.row);
          afterCommit(() => handles.delete(text(r.handle)));
          return {};
        default:
          throw Error('Unknown Java filesystem operation');
      }
    });
  }
  // Bound queued buffers as well as each operation. No detached background IO.
  function enqueue<T>(action: () => Promise<T>): Promise<T> {
    if (closing || closed)
      return Promise.reject(Error('Java filesystem is closed'));
    if (pending >= PENDING_LIMIT)
      return Promise.reject(Error('Java filesystem operation queue is full'));
    pending++;
    const job = tail.then(action).finally(() => {
      pending--;
    });
    tail = job.catch(() => {});
    return job;
  }
  const teaFile = async (input: string): Promise<string> => {
    if (
      typeof input !== 'string' ||
      input.length > CONTROL ||
      encoder.encode(input).length > CONTROL
    )
      throw Error('Java filesystem control limit exceeded');
    const request = parseFileRequest(JSON.parse(input) as unknown);
    return enqueue(async () => {
      const result = await operate(request),
        encoded = JSON.stringify(result);
      if (encoder.encode(encoded).length > CONTROL)
        throw Error('Java filesystem response limit exceeded');
      return encoded;
    });
  };
  const teaFileRead = async (
    id: string,
    maximum: number,
  ): Promise<Uint8Array | null> => {
    text(id);
    integer(maximum, 1, CHUNK);
    return enqueue(async () => {
      await start();
      return transaction(async (s, afterCommit) => {
        const { h, node } = await opened(s, id);
        if (!h.readable) throw Error('File is not open for reading');
        const count = Math.min(maximum, Math.max(0, node.length - h.position));
        if (!count) return null;
        const bytes = new Uint8Array(count);
        for (let copied = 0; copied < count;) {
          const position = h.position + copied,
            index = Math.floor(position / CHUNK),
            start = position % CHUNK,
            size = Math.min(count - copied, CHUNK - start),
            chunk = checkedChunk(
              await s.tx.objectStore('chunks').get([namespace, node.id, index]),
            );
          if (chunk) bytes.set(chunk.subarray(start, start + size), copied);
          copied += size;
        }
        afterCommit(() => {
          h.position += count;
        });
        return bytes;
      });
    });
  };
  const teaFileWrite = async (id: string, input: Uint8Array): Promise<true> => {
    text(id);
    if (
      !(input instanceof Uint8Array) ||
      input.byteLength < 1 ||
      input.byteLength > CHUNK
    )
      throw Error('Java filesystem binary chunk limit exceeded');
    // Copy only after the pending bound is checked; callers may reuse their JSO buffer.
    if (closing || closed) throw Error('Java filesystem is closed');
    if (pending >= PENDING_LIMIT)
      throw Error('Java filesystem operation queue is full');
    const bytes = input.slice();
    return enqueue(async () => {
      await start();
      return transaction(async (s, afterCommit) => {
        const { h, node } = await opened(s, id);
        if (!h.writable) throw Error('File is not open for writing');
        const offset = h.append ? node.length : h.position,
          end = integer(offset + bytes.length, 0, FILE_LIMIT);
        for (let copied = 0; copied < bytes.length;) {
          const position = offset + copied,
            index = Math.floor(position / CHUNK),
            start = position % CHUNK,
            count = Math.min(bytes.length - copied, CHUNK - start),
            chunkKey: ChunkKey = [namespace, node.id, index],
            chunk =
              checkedChunk(await s.tx.objectStore('chunks').get(chunkKey)) ??
              new Uint8Array(CHUNK);
          chunk.set(bytes.subarray(copied, copied + count), start);
          await putChunk(s, chunkKey, chunk);
          copied += count;
        }
        node.length = Math.max(node.length, end);
        await touch(s, node);
        afterCommit(() => {
          h.position = end;
        });
        return true as const;
      });
    });
  };
  const teaFileSystemClose = (): Promise<void> => {
    closing = true;
    return (closePromise ??= tail
      .then(async () => {
        if (starting) await starting;
        if (releaseOwner)
          await transaction((s) =>
            dropOwner(s, { key: ownerKey, token: ownerToken }),
          );
        handles.clear();
        closed = true;
        releaseOwner?.();
        releaseOwner = undefined;
        if (opening) (await opening).close();
      })
      .catch((error: unknown) => {
        // Failed cleanup retains ownership and may be explicitly retried.
        closePromise = undefined;
        throw error;
      }));
  };
  return { teaFile, teaFileRead, teaFileWrite, teaFileSystemClose };
}
Object.assign(scope, createFileBridge());
