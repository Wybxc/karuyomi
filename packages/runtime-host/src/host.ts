import { SourceRuntimeManager, type OpenOptions } from './manager.js';
import { VerifiedLoader } from './verified-loader.js';
import type { SourceCall } from '@karuyomi/contracts';

declare global {
  interface Window {
    karuyomiRuntime?: ReturnType<typeof exposeRuntime>;
  }
}

const manager = new SourceRuntimeManager(
  new URL('./worker.js', import.meta.url),
  (url) => new Worker(url),
  new VerifiedLoader(location.origin),
);
function exposeRuntime() {
  return Object.freeze({
    ready: manager.ready,
    open: (options: OpenOptions) => manager.open(options),
    invoke: (call: SourceCall) => manager.invoke(call),
    cancel: (requestId: string) => manager.cancel(requestId),
    acquireImage: () => manager.acquireImage(),
    rebuild: () => manager.rebuild(),
    fetchApi: (options: Parameters<SourceRuntimeManager['fetchApi']>[0]) =>
      manager.fetchApi(options),
    dispose: () => manager.dispose(),
  });
}
window.karuyomiRuntime = exposeRuntime();
window.addEventListener(
  'pagehide',
  () => {
    void manager.dispose();
  },
  { once: true },
);
