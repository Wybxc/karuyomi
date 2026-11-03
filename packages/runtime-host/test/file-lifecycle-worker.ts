/** Test-only fault driver; IO, locks, transactions and chunks are the product bridge. */
import { openDB } from 'idb';
import {
  integer,
  object,
  text,
  workerScope,
} from '../../../runtime/teavm/bridge/bridge-common.js';
import '../../../runtime/teavm/bridge/file-bridge.js';
import type { FileSchema } from '../../../runtime/teavm/bridge/file-bridge.js';

const namespace = new URL(location.href).searchParams.get('fsNamespace');
if (!namespace) throw Error('Missing fixture namespace');
const scope = workerScope();
let failAfter = 0,
  pauseNext = false,
  paused = false,
  failClose = false,
  dropNextReply = false,
  committed = false,
  chunkReads = 0,
  largestChunk = 0;
const originalPut = IDBObjectStore.prototype.put,
  originalAdd = IDBObjectStore.prototype.add,
  originalDelete = IDBObjectStore.prototype.delete,
  originalGet = IDBObjectStore.prototype.get;
IDBObjectStore.prototype.get = function (query: IDBValidKey | IDBKeyRange) {
  if (this.name === 'chunks') chunkReads++;
  return originalGet.call(this, query);
};
IDBObjectStore.prototype.put = function (value: unknown, key?: IDBValidKey) {
  if (this.name !== 'chunks') return originalPut.call(this, value, key);
  if (!(value instanceof Uint8Array)) throw Error('Nonbinary product chunk');
  largestChunk = Math.max(largestChunk, value.length);
  if (pauseNext) {
    pauseNext = false;
    paused = true;
    const usage = this.transaction.objectStore('usage');
    const keepAlive = () => {
      if (!paused) return;
      originalGet.call(usage, text(namespace)).onsuccess = keepAlive;
    };
    keepAlive();
  }
  if (failAfter && --failAfter === 0) {
    originalAdd.call(this, value, key);
    return originalAdd.call(this, value, key); // Real duplicate request aborts product tx.
  }
  return originalPut.call(this, value, key);
};
IDBObjectStore.prototype.delete = function (query: IDBValidKey | IDBKeyRange) {
  if (failClose && this.name === 'owners') {
    failClose = false;
    // The real existing owner key causes ConstraintError after handle/chunk
    // deletions were requested. The complete product cleanup must roll back.
    originalAdd.call(this, { key: query, token: 'deliberate-duplicate-owner' });
  }
  return originalDelete.call(this, query);
};
const required = <T>(value: T | undefined): T => {
  if (!value) throw Error('File bridge not installed');
  return value;
};
globalThis.onmessage = (event: MessageEvent<unknown>) => {
  void (async () => {
    const message = object(event.data),
      id = text(message.id);
    try {
      let result: unknown;
      switch (message.control) {
        case 'read':
          result = {
            bytes: await required(scope.teaFileRead)(
              text(message.handle),
              integer(message.maximum),
            ),
          };
          break;
        case 'write': {
          if (!(message.bytes instanceof Uint8Array))
            throw Error('Missing binary fixture bytes');
          const drop = dropNextReply;
          dropNextReply = false;
          result = {
            accepted: await required(scope.teaFileWrite)(
              text(message.handle),
              message.bytes,
            ),
          };
          if (drop) {
            committed = true;
            return;
          }
          break;
        }
        case 'fail-write':
          failAfter = integer(message.after, 1, 2);
          result = {};
          break;
        case 'fail-close':
          failClose = true;
          result = {};
          break;
        case 'pause-write':
          pauseNext = true;
          result = {};
          break;
        case 'paused':
          result = { paused };
          break;
        case 'resume-write':
          paused = false;
          result = {};
          break;
        case 'drop-write-reply':
          dropNextReply = true;
          committed = false;
          result = {};
          break;
        case 'committed':
          result = { committed };
          break;
        case 'snapshot': {
          const db = await openDB<FileSchema>('teavm-java-files-v2', 1);
          try {
            const tx = db.transaction(
              ['usage', 'inodes', 'chunks'],
              'readonly',
            );
            result = {
              usage: await tx.objectStore('usage').get(text(namespace)),
              inodes: await tx
                .objectStore('inodes')
                .getAll(IDBKeyRange.bound([namespace], [namespace, []])),
              chunkKeys: await tx
                .objectStore('chunks')
                .getAllKeys(IDBKeyRange.bound([namespace], [namespace, []])),
              chunkReads,
              largestChunk,
            };
            await tx.done;
          } finally {
            db.close();
          }
          break;
        }
        case 'reset-metrics':
          chunkReads = largestChunk = 0;
          result = {};
          break;
        case 'close-system':
          await required(scope.teaFileSystemClose)();
          result = {};
          break;
        default:
          result = object(
            JSON.parse(
              await required(scope.teaFile)(JSON.stringify(message.request)),
            ) as unknown,
          );
      }
      postMessage({ id, result });
    } catch (error) {
      postMessage({
        id,
        error:
          error instanceof Error
            ? error.name + ': ' + error.message
            : String(error),
      });
    }
  })();
};
