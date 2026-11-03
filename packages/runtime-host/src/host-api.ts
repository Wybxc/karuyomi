import type { SourceCall } from '@karuyomi/contracts';
import type { OpenOptions, SourceRuntimeManager } from './manager.js';

export function installRuntime(manager: SourceRuntimeManager): RuntimeHostApi {
  if (window.karuyomiRuntime) return window.karuyomiRuntime;
  const api = Object.freeze(createRuntimeApi(manager));
  window.karuyomiRuntime = api;
  window.addEventListener(
    'pagehide',
    () => {
      void manager.dispose();
    },
    { once: true },
  );
  return api;
}

export type RuntimeHostApi = ReturnType<typeof createRuntimeApi>;
function createRuntimeApi(manager: SourceRuntimeManager) {
  return {
    ready: manager.ready,
    open: (options: OpenOptions) => manager.open(options),
    invoke: (call: SourceCall) => manager.invoke(call),
    cancel: (requestId: string) => manager.cancel(requestId),
    acquireImage: () => manager.acquireImage(),
    rebuild: () => manager.rebuild(),
    fetchApi: (options: Parameters<SourceRuntimeManager['fetchApi']>[0]) =>
      manager.fetchApi(options),
    dispose: () => manager.dispose(),
  };
}

declare global {
  interface Window {
    karuyomiRuntime?: RuntimeHostApi;
  }
}
