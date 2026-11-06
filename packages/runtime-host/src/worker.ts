import { createHello } from './hello.js';
import { TeaVMDriver, type TeaVMGlobals } from './teavm-driver.js';
import { VerifiedLoader } from './verified-loader.js';
import { ExtensionArtifactCache } from './extension-artifact-cache.js';
import { WorkerRuntime } from './worker-runtime.js';
import { nativeMaterials } from './materials.js';
import { setRuntimeDiagnosticSink } from './runtime-diagnostics.js';

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
if (import.meta.env.VITE_KARUYOMI_RUNTIME_DIAGNOSTICS === '1')
  setRuntimeDiagnosticSink((diagnostic) =>
    globalThis.postMessage({ type: 'runtime-diagnostic', diagnostic }),
  );
const driver = new TeaVMDriver(
  globalThis as TeaVMGlobals,
  new VerifiedLoader(
    origin,
    undefined,
    nativeMaterials,
    new ExtensionArtifactCache(),
  ),
  (url) => importScripts(url),
  origin,
);
const runtime = new WorkerRuntime(driver, (message) =>
  globalThis.postMessage(message),
);
globalThis.postMessage(createHello(runtime.workerInstanceId));
globalThis.onmessage = (event: MessageEvent<unknown>) => {
  void runtime.receive(event.data, event.ports);
};
globalThis.addEventListener('unhandledrejection', () => {
  // Use the Worker's native error event for an unbound transport failure.
  // RPC responses always use the generated envelope and remain correlated.
  throw new Error('Runtime Worker has an unhandled async failure');
});
