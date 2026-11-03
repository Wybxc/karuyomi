import { SourceRuntimeManager, type WorkerEndpoint } from './manager.js';
import { installRuntime } from './host-api.js';
import { RuntimeFailure } from './errors.js';
import { VerifiedLoader } from './verified-loader.js';
import { isNativeControlPage } from './native-location.js';

declare const __KARUYOMI_MATERIAL_VERSION__: string;
declare global {
  interface Window {
    __karuyomiNativeRuntime?: {
      workerSource: string;
      materialVersion: string;
    };
  }
}

// Dart installs this IIFE at document start, in the page's world, after checking
// the bundled manifest and both JS file digests. Cookies stay in the HTTPS view.
const configuration = window.__karuyomiNativeRuntime;
delete window.__karuyomiNativeRuntime;
if (
  !isNativeControlPage(location) ||
  !configuration ||
  configuration.materialVersion !== __KARUYOMI_MATERIAL_VERSION__ ||
  typeof configuration.workerSource !== 'string' ||
  !configuration.workerSource
) {
  throw new RuntimeFailure(
    'integrity_error',
    'Native runtime bootstrap is incompatible',
  );
}
if (!window.karuyomiRuntime) {
  const origin = location.origin;
  const workerSource = configuration.workerSource;
  const workerUrl = new URL('/runtime/native-worker.js', origin);
  const createWorker = (requested: URL): WorkerEndpoint => {
    const plugin = requested.searchParams.get('plugin');
    const fsNamespace = requested.searchParams.get('fsNamespace');
    if (
      requested.origin !== origin ||
      requested.pathname !== workerUrl.pathname ||
      !plugin ||
      !/^[a-f0-9]{64}$/.test(plugin) ||
      fsNamespace !== plugin
    ) {
      throw new RuntimeFailure(
        'protocol_error',
        'Native Worker context is invalid',
      );
    }
    const context = JSON.stringify({ origin, plugin, fsNamespace });
    const blob = new Blob(
      ['globalThis.karuyomiWorkerContext=' + context + ';\n', workerSource],
      { type: 'application/javascript' },
    );
    const objectUrl = URL.createObjectURL(blob);
    let worker: Worker;
    try {
      worker = new Worker(objectUrl);
    } catch (error) {
      URL.revokeObjectURL(objectUrl);
      throw error;
    }
    let revoked = false;
    const revoke = () => {
      if (revoked) return;
      revoked = true;
      URL.revokeObjectURL(objectUrl);
    };
    worker.addEventListener('message', revoke, { once: true });
    worker.addEventListener('error', revoke, { once: true });
    return {
      get onmessage() {
        return worker.onmessage;
      },
      set onmessage(value) {
        worker.onmessage = value;
      },
      get onerror() {
        return worker.onerror;
      },
      set onerror(value) {
        worker.onerror = value;
      },
      postMessage: (message, transfer = []) =>
        worker.postMessage(message, transfer),
      terminate: () => {
        worker.terminate();
        revoke();
      },
    };
  };
  installRuntime(
    new SourceRuntimeManager(
      workerUrl,
      createWorker,
      new VerifiedLoader(origin, undefined, () => undefined),
      60_000,
      { enabled: false },
    ),
  );
}
