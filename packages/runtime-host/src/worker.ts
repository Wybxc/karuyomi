import { createHello } from './hello.js';
import { TeaVMDriver, type TeaVMGlobals } from './teavm-driver.js';
import { VerifiedLoader } from './verified-loader.js';
import { WorkerRuntime } from './worker-runtime.js';
import { nativeMaterials } from './materials.js';

// Classic Worker is required for TeaVM's JS backend and its global JS exports.
declare function importScripts(...urls: string[]): void;
const context = (
  globalThis as typeof globalThis & {
    karuyomiWorkerContext?: { origin: string };
  }
).karuyomiWorkerContext;
if (context && context.origin !== location.origin) {
  throw new Error('Native Worker origin does not match its document');
}
const origin = context?.origin ?? location.origin;
const driver = new TeaVMDriver(
  globalThis as TeaVMGlobals,
  new VerifiedLoader(origin, undefined, nativeMaterials),
  (url) => importScripts(url),
  origin,
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
