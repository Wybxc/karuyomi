/* Durable Java files. Every mutation commits before its Java continuation resumes. */
import {
  array,
  bool,
  decodeBase64,
  encodeBase64,
  idbRequest,
  integer,
  number,
  object,
  optionalText,
  storageKey,
  text,
  workerScope,
  type StorageKey,
} from './bridge-common.js';

interface FileNode {
  key: StorageKey;
  id: string;
  directory: boolean;
  readOnly: boolean;
  modified: number;
  linked: boolean;
  body: Uint8Array;
}
interface PathRow {
  key: StorageKey;
  path: string;
  id: string;
}
interface HandleRow {
  key: [string, string, string];
  owner: StorageKey;
  inode: StorageKey;
}
interface OpenFile {
  inode: string;
  position: number;
  readable: boolean;
  writable: boolean;
  append: boolean;
}
interface Stores {
  paths: IDBObjectStore;
  nodes: IDBObjectStore;
  handles: IDBObjectStore;
  owners: IDBObjectStore;
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
  'read',
  'write',
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
  length: number;
  body: string;
  size: number;
}
export function parseFileRequest(value: unknown): FileRequest {
  const data = object(value);
  const operation = operations.find(
    (operation) => operation === data.operation,
  );
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
    position: operation === 'seek' ? integer(data.position, 0, 2147483647) : 0,
    count:
      operation === 'skip' ? integer(data.count, -2147483647, 2147483647) : 0,
    length: operation === 'read' ? integer(data.length, 0, 2147483647) : 0,
    body: operation === 'write' ? text(data.body) : '',
    size: operation === 'resize' ? integer(data.size, 0, 2147483647) : 0,
  };
}
function nodeValue(value: unknown): FileNode | undefined {
  if (value === undefined) return undefined;
  const data = object(value);
  if (!(data.body instanceof Uint8Array))
    throw Error('Invalid stored file bytes');
  return {
    key: storageKey(data.key),
    id: text(data.id),
    directory: bool(data.directory),
    readOnly: bool(data.readOnly),
    modified: number(data.modified),
    linked: bool(data.linked),
    body: data.body,
  };
}
function pathRow(value: unknown): PathRow {
  const data = object(value);
  return {
    key: storageKey(data.key),
    path: text(data.path),
    id: text(data.id),
  };
}
function handleRow(value: unknown): HandleRow {
  const data = object(value),
    key = array(data.key);
  if (key.length !== 3) throw Error('Invalid stored file handle');
  return {
    key: [text(key[0]), text(key[1]), text(key[2])],
    owner: storageKey(data.owner),
    inode: storageKey(data.inode),
  };
}
declare global {
  var teaFile: ReturnType<typeof createFileBridge>['teaFile'] | undefined;
  var teaFileSystemClose:
    ReturnType<typeof createFileBridge>['teaFileSystemClose'] | undefined;
}

const scope = workerScope();
function createFileBridge() {
  const params = new URL(location.href).searchParams;
  const namespace =
    scope.karuyomiWorkerContext?.fsNamespace ||
    scope.karuyomiWorkerContext?.plugin ||
    params.get('fsNamespace') ||
    params.get('plugin');
  if (!namespace) throw new Error('Runtime filesystem namespace is required');
  const owner = crypto.randomUUID(),
    handles = new Map<string, OpenFile>();
  const stores = ['paths', 'nodes', 'handles', 'owners'];
  let opening: Promise<IDBDatabase> | undefined,
    starting: Promise<void> | undefined,
    tail: Promise<unknown> = Promise.resolve(),
    releaseOwner: (() => void) | undefined,
    closed = false;
  const lockName = (id: string) =>
    'teavm-java-files:' + JSON.stringify([namespace, id]);
  const key = (path: string): StorageKey => [namespace, path];
  const request = idbRequest;
  const parent = (path: string) => path.slice(0, path.lastIndexOf('/')) || '/';
  function normalize(path: string) {
    if (typeof path !== 'string' || path.includes('\0'))
      throw Error('Invalid file path');
    const parts = [];
    for (const part of path.split('/')) {
      if (!part || part === '.') continue;
      if (part === '..') parts.pop();
      else parts.push(part);
    }
    return '/' + parts.join('/');
  }
  const encode = encodeBase64,
    decode = decodeBase64;
  function open() {
    return (opening ||= new Promise<IDBDatabase>((resolve, reject) => {
      const r = indexedDB.open('teavm-java-files-v1', 1);
      r.onupgradeneeded = () => {
        const db = r.result;
        db.createObjectStore('paths', { keyPath: 'key' });
        db.createObjectStore('nodes', { keyPath: 'key' });
        const h = db.createObjectStore('handles', { keyPath: 'key' });
        h.createIndex('inode', 'inode');
        h.createIndex('owner', 'owner');
        db.createObjectStore('owners', { keyPath: 'key' });
      };
      r.onsuccess = () => {
        r.result.onversionchange = () => {
          r.result.close();
          opening = undefined;
        };
        resolve(r.result);
      };
      r.onerror = () => {
        opening = undefined;
        reject(r.error);
      };
      r.onblocked = () => {
        opening = undefined;
        reject(Error('Java filesystem database upgrade blocked'));
      };
    }));
  }
  async function transaction<T>(
    action: (
      stores: Stores,
      afterCommit: (action: () => void) => void,
    ) => T | Promise<T>,
  ): Promise<T> {
    const db = await open();
    return new Promise<T>((resolve, reject) => {
      const tx = db.transaction(stores, 'readwrite', { durability: 'strict' });
      const s: Stores = {
        paths: tx.objectStore('paths'),
        nodes: tx.objectStore('nodes'),
        handles: tx.objectStore('handles'),
        owners: tx.objectStore('owners'),
      };
      let value: { result: T } | undefined,
        failure: unknown,
        commit: (() => void) | undefined;
      tx.oncomplete = () => {
        if (commit) commit();
        if (value) resolve(value.result);
        else
          reject(Error('Filesystem transaction completed before its result'));
      };
      tx.onabort = () =>
        reject(
          failure || tx.error || Error('Java filesystem transaction aborted'),
        );
      tx.onerror = () => {};
      Promise.resolve()
        .then(() =>
          action(s, (fn) => {
            commit = fn;
          }),
        )
        .then(
          (result) => {
            value = { result };
          },
          (error) => {
            failure = error;
            try {
              tx.abort();
            } catch {
              reject(error);
            }
          },
        );
    });
  }
  const nodeFor = async (
    s: Stores,
    path: string,
  ): Promise<FileNode | undefined> => {
    const value = await request(s.paths.get(key(path)));
    if (value === undefined) return undefined;
    return nodeValue(await request(s.nodes.get(key(pathRow(value).id))));
  };
  async function children(s: Stores, path: string): Promise<PathRow[]> {
    const prefix = path === '/' ? '/' : path + '/';
    return array(
      await request(
        s.paths.getAll(IDBKeyRange.bound(key(prefix), key(prefix + '\uffff'))),
      ),
    )
      .map(pathRow)
      .filter((row) => row.path !== path && row.path.startsWith(prefix));
  }
  async function collect(s: Stores, node: FileNode) {
    if (
      !node.linked &&
      !array(await request(s.handles.index('inode').getAllKeys(node.key)))
        .length
    )
      s.nodes.delete(node.key);
  }
  async function dropOwner(s: Stores, id: string) {
    const rows = array(
      await request(s.handles.index('owner').getAll(key(id))),
    ).map(handleRow);
    for (const row of rows) s.handles.delete(row.key);
    for (const inode of new Set(rows.map((row) => row.inode[1]))) {
      const node = nodeValue(await request(s.nodes.get(key(inode))));
      if (node) await collect(s, node);
    }
    s.owners.delete(key(id));
  }
  function touch(s: Stores, node: FileNode) {
    node.modified = Date.now();
    s.nodes.put(node);
  }
  function create(
    s: Stores,
    path: string,
    directory: boolean,
    parentNode?: FileNode,
  ): FileNode {
    const id = crypto.randomUUID(),
      node: FileNode = {
        key: key(id),
        id,
        directory,
        readOnly: false,
        modified: Date.now(),
        linked: true,
        body: new Uint8Array(),
      };
    s.nodes.add(node);
    s.paths.add({ key: key(path), path, id });
    if (parentNode) touch(s, parentNode);
    return node;
  }
  async function start() {
    if (closed) throw Error('Java filesystem is closed');
    return (starting ||= (async () => {
      if (!navigator.locks)
        throw Error(
          'Java filesystem requires the Web Locks API for Worker lifetime tracking',
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
      const owners = await transaction(async (s) =>
        array(
          await request(
            s.owners.getAll(IDBKeyRange.bound(key(''), key('\uffff'))),
          ),
        ).map((value) => storageKey(object(value).key)),
      );
      for (const row of owners)
        await navigator.locks.request(
          lockName(row[1]),
          { ifAvailable: true },
          async (lock) => {
            if (lock) await transaction((s) => dropOwner(s, row[1]));
          },
        );
      await transaction(async (s) => {
        for (const path of ['/', '/tmp'])
          if (!(await nodeFor(s, path))) create(s, path, true);
        s.owners.put({ key: key(owner) });
      });
    })());
  }
  function validInteger(value: number) {
    if (!Number.isInteger(value) || value < 0 || value > 2147483647)
      throw Error('File offset exceeds TeaVM filesystem range');
    return value;
  }
  async function operate(r: FileRequest): Promise<Record<string, unknown>> {
    await start();
    const path = normalize(r.path || '/');
    if (r.operation === 'initialize') return { ready: true };
    const h = r.handle ? handles.get(r.handle) : undefined;
    const handle = () => {
      if (!h) throw Error('Stream is closed');
      return h;
    };
    if (r.handle && !h) throw Error('Stream is closed');
    if (r.operation === 'tell') return { position: handle().position };
    if (r.operation === 'seek') {
      handle().position = validInteger(r.position);
      return {};
    }
    if (r.operation === 'skip') {
      handle().position = validInteger(handle().position + r.count);
      return {};
    }
    return transaction(async (s, afterCommit) => {
      const node = h
        ? nodeValue(await request(s.nodes.get(key(h.inode))))
        : await nodeFor(s, path);
      if (h && !node) throw Error('Open file inode is missing');
      const openedNode = () => {
        if (!node) throw Error('Open file inode is missing');
        return node;
      };
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
                size: node.directory ? 0 : node.body.length,
              }
            : { exists: false };
        case 'list':
          return node?.directory
            ? {
                names: (await children(s, path))
                  .filter((row) => parent(row.path) === path)
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
          create(s, path, r.operation === 'mkdir', dir);
          return { changed: true };
        }
        case 'delete': {
          if (!node || path === '/') return { changed: false };
          const dir = await nodeFor(s, parent(path));
          if (
            !dir ||
            dir.readOnly ||
            (node.directory && (await children(s, path)).length)
          )
            return { changed: false };
          s.paths.delete(key(path));
          node.linked = false;
          s.nodes.put(node);
          await collect(s, node);
          touch(s, dir);
          return { changed: true };
        }
        case 'rename': {
          const source = normalize(r.source),
            from = await nodeFor(s, source),
            dir = await nodeFor(s, parent(path));
          const oldDir = await nodeFor(s, parent(source));
          if (
            !from ||
            source === '/' ||
            path === '/' ||
            !dir?.directory ||
            dir.readOnly ||
            oldDir?.readOnly
          )
            return { changed: false };
          if (source === path) return { changed: true };
          if (from.directory && path.startsWith(source + '/'))
            return { changed: false };
          if (
            node &&
            (node.directory !== from.directory ||
              (node.directory && (await children(s, path)).length))
          )
            return { changed: false };
          const moving = [
            { key: key(source), path: source, id: from.id },
            ...(from.directory ? await children(s, source) : []),
          ];
          if (node) {
            node.linked = false;
            s.nodes.put(node);
            await collect(s, node);
          }
          for (const row of moving) s.paths.delete(row.key);
          for (const row of moving) {
            const next = path + row.path.slice(source.length);
            s.paths.put({ key: key(next), path: next, id: row.id });
          }
          touch(s, dir);
          if (oldDir && oldDir.id !== dir.id) touch(s, oldDir);
          return { changed: true };
        }
        case 'modified':
        case 'readonly': {
          if (!node) return { changed: false };
          if (r.operation === 'modified') node.modified = r.modified;
          else node.readOnly = !!r.readOnly;
          s.nodes.put(node);
          return { changed: true };
        }
        case 'open': {
          if (!node || node.directory || (r.writable && node.readOnly))
            return {};
          // RandomAccessFile opens readable+writable and must preserve existing bytes.
          if (r.writable && !r.readable && !r.append) {
            node.body = new Uint8Array();
            node.modified = Date.now();
            s.nodes.put(node);
          }
          const handle = crypto.randomUUID();
          s.handles.add({
            key: [namespace, owner, handle],
            owner: key(owner),
            inode: node.key,
          });
          afterCommit(() =>
            handles.set(handle, {
              inode: node.id,
              position: r.append ? node.body.length : 0,
              readable: !!r.readable,
              writable: !!r.writable,
              append: !!r.append,
            }),
          );
          return { handle };
        }
        case 'read': {
          const node = openedNode();
          if (!handle().readable) throw Error('File is not open for reading');
          const end = Math.min(
            node.body.length,
            handle().position + validInteger(r.length),
          );
          const body = node.body.subarray(handle().position, end),
            next = handle().position + body.length;
          afterCommit(() => {
            handle().position = next;
          });
          return { body: encode(body), eof: body.length === 0 };
        }
        case 'write':
        case 'resize': {
          const node = openedNode();
          if (!handle().writable) throw Error('File is not open for writing');
          const body = r.operation === 'write' ? decode(r.body) : undefined;
          if (body && body.length === 0) return {};
          const offset =
            handle().append && body ? node.body.length : handle().position;
          const length = validInteger(
            body ? Math.max(node.body.length, offset + body.length) : r.size,
          );
          const next = new Uint8Array(length);
          next.set(node.body.subarray(0, length));
          if (body) next.set(body, offset);
          node.body = next;
          node.modified = Date.now();
          s.nodes.put(node);
          afterCommit(() => {
            handle().position = body
              ? offset + body.length
              : Math.min(handle().position, length);
          });
          return {};
        }
        case 'size':
          return { size: openedNode().body.length };
        case 'flush':
          return {};
        case 'close': {
          const node = openedNode();
          s.handles.delete([...key(owner), text(r.handle)]);
          await collect(s, node);
          afterCommit(() => handles.delete(text(r.handle)));
          return {};
        }
        default:
          throw Error('Unknown Java filesystem operation ' + r.operation);
      }
    });
  }
  // Keep each descriptor's cursor updates ordered, including callers from different Java fibers.
  const teaFile = (input: string): Promise<string> => {
    const job = tail.then(() =>
      operate(parseFileRequest(JSON.parse(input) as unknown)),
    );
    tail = job.catch(() => {});
    return job.then((result) => JSON.stringify(result));
  };
  const teaFileSystemClose = (): Promise<void> => {
    const job = tail.then(async () => {
      if (starting) await starting;
      if (releaseOwner) await transaction((s) => dropOwner(s, owner));
      handles.clear();
      closed = true;
      releaseOwner?.();
      if (opening) (await opening).close();
    });
    tail = job.catch(() => {});
    return job;
  };
  return { teaFile, teaFileSystemClose };
}
Object.assign(scope, createFileBridge());
