/** Test-only Worker driver; all cache operations use the product bridge. */
import {
  array,
  object,
  optionalText,
  text,
  workerScope,
} from '../../../runtime/teavm/bridge/bridge-common.js';
import type {} from '../../../runtime/teavm/bridge/cache-bridge.js';

const originalLockRequest = navigator.locks.request.bind(navigator.locks);
interface ReclaimPause {
  reached: Promise<void>;
  signalReached(): void;
  released: Promise<void>;
  release(): void;
}
let reclaimPause: ReclaimPause | undefined;
function pauseReclaim() {
  if (reclaimPause) throw Error('Reclaim pause is already armed');
  let signalReached = () => {},
    release = () => {};
  const reached = new Promise<void>((resolve) => {
    signalReached = resolve;
  });
  const released = new Promise<void>((resolve) => {
    release = resolve;
  });
  reclaimPause = { reached, signalReached, released, release };
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
    navigator.locks.request = originalLockRequest;
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
        entryKey = array(data.key);
      const owner = [text(entryKey[0]), text(entryKey[1])];
      const url = text(data.url);
      const tx = this.transaction.db.transaction('directories', 'readwrite');
      pendingMutation = new Promise<void>((resolve, reject) => {
        const store = tx.objectStore('directories');
        const get: IDBRequest<unknown> = store.get(owner);
        get.onsuccess = () => {
          const state = object(get.result),
            locks = object(state.locks);
          const lock = object(locks[url]);
          if (replacement === 'editor') lock.editor = crypto.randomUUID();
          else if (replacement === 'owner')
            lock.owner = text(object(locks['fault-sentinel']).owner);
          else if (replacement === 'generation') {
            if (typeof state.generation !== 'number')
              throw Error('Missing directory generation');
            state.generation++;
          } else throw Error('Unknown replacement fault');
          store.put(state);
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

self.onmessage = async (event: MessageEvent<unknown>) => {
  const message = object(event.data),
    id = text(message.id);
  try {
    const control = optionalText(message.control);
    if (control) {
      if (control === 'pause-reclaim') {
        pauseReclaim();
        navigator.locks.request = delayedLockRequest;
      } else if (control === 'wait-reclaim') {
        if (!reclaimPause) throw Error('Reclaim pause is not armed');
        await reclaimPause.reached;
      } else if (control === 'resume-reclaim') {
        if (!reclaimPause) throw Error('Reclaim pause is not armed');
        navigator.locks.request = originalLockRequest;
        reclaimPause.release();
        reclaimPause = undefined;
      } else if (control === 'fail-next-put') {
        failNextPut(text(message.replacement));
      } else throw Error('Unknown cache lifecycle control');
      self.postMessage({ id, result: {} });
      return;
    }
    const cache = workerScope().teaCache;
    if (typeof cache !== 'function')
      throw Error('Product cache bridge is missing');
    const result: unknown = JSON.parse(
      await cache(JSON.stringify(message.request)),
    );
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
