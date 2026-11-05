import { expose } from 'comlink';
import { object } from '../../../../../runtime/teavm/bridge/bridge-common.js';

declare const self: DedicatedWorkerGlobalScope;

// Each test supplies its own namespace through the native Worker name.
globalThis.karuyomiWorkerContext = {
  plugin: self.name,
  fsNamespace: self.name,
};
const ready = Promise.all([
  import('../../../../../runtime/teavm/bridge/cache-bridge.js'),
  import('../../../../../runtime/teavm/bridge/file-bridge.js'),
]);
const api = {
  async cache(operation: string, arguments_: Record<string, unknown> = {}) {
    await ready;
    const call = globalThis.teaCache;
    if (!call) throw new Error('Cache bridge was not installed');
    return object(
      JSON.parse(
        await call(
          JSON.stringify({
            operation,
            directory: '/browser-test',
            maxSize: 1024 * 1024,
            handle: 'one',
            url: 'https://example.org/cached',
            metadata: { status: 200 },
            ...arguments_,
          }),
        ),
      ),
    );
  },
  async writeCache(editor: string, sequence: number, bytes: Uint8Array) {
    await ready;
    const write = globalThis.teaCacheWrite;
    if (!write) throw new Error('Binary cache bridge was not installed');
    return write(editor, 'one', sequence, bytes);
  },
  async readCache(reader: string, maximum = 65536) {
    await ready;
    const read = globalThis.teaCacheRead;
    if (!read) throw new Error('Binary cache bridge was not installed');
    return read(reader, 'one', maximum);
  },
  async abortNextCommit() {
    await ready;
    const put = IDBObjectStore.prototype.put;
    const add = IDBObjectStore.prototype.add;
    IDBObjectStore.prototype.put = function (
      value: unknown,
      key?: IDBValidKey,
    ) {
      if (this.name !== 'entries') return put.call(this, value, key);
      IDBObjectStore.prototype.put = put;
      // Real duplicate-key requests abort the product transaction, not a mock.
      add.call(this, value, key);
      return add.call(this, value, key);
    };
  },
  async file(operation: string, arguments_: Record<string, unknown> = {}) {
    await ready;
    const call = globalThis.teaFile;
    if (!call) throw new Error('File bridge was not installed');
    return object(
      JSON.parse(
        await call(
          JSON.stringify({
            operation,
            path: '/tmp/browser-test',
            ...arguments_,
          }),
        ),
      ),
    );
  },
  async writeFile(handle: string, bytes: Uint8Array) {
    await ready;
    const write = globalThis.teaFileWrite;
    if (!write) throw new Error('Binary file bridge was not installed');
    return write(handle, bytes);
  },
  async readFile(handle: string) {
    await ready;
    const read = globalThis.teaFileRead;
    if (!read) throw new Error('Binary file bridge was not installed');
    return read(handle, 65536);
  },
  async closeFiles() {
    await ready;
    await globalThis.teaFileSystemClose?.();
  },
};
export type StorageWorkerApi = typeof api;
expose(api);
