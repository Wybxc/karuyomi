import { createHello } from './hello.js';
import { TeaVMDriver, type TeaVMGlobals } from './teavm-driver.js';
import { VerifiedLoader } from './verified-loader.js';
import { WorkerRuntime } from './worker-runtime.js';

// Classic Worker is required for TeaVM's JS backend and its global JS exports.
declare function importScripts(...urls: string[]): void;
const driver = new TeaVMDriver(
  globalThis as TeaVMGlobals,
  new VerifiedLoader(location.origin),
  (url) => importScripts(url),
  location.origin,
);
const runtime = new WorkerRuntime(driver, (message) =>
  globalThis.postMessage(message),
);
globalThis.postMessage(createHello(runtime.workerInstanceId));
globalThis.onmessage = (event: MessageEvent<unknown>) => {
  void runtime.receive(event.data);
};
globalThis.addEventListener('unhandledrejection', () => {
  // Fatal unbound async work invalidates the generation; it is never replayed.
  globalThis.postMessage({
    type: 'fatal',
    workerInstanceId: runtime.workerInstanceId,
  });
});
