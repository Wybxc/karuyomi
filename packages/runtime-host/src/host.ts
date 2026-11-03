import { runtimeHelloSchema, type RuntimeHello } from '@karuyomi/contracts';

declare global {
  interface Window {
    karuyomiRuntime?: {
      ready: Promise<RuntimeHello>;
      dispose(): void;
    };
  }
}

const worker = new Worker(new URL('./worker.js', import.meta.url), {
  type: 'module',
});
const ready = new Promise<RuntimeHello>((resolve, reject) => {
  const timeout = setTimeout(() => {
    worker.terminate();
    reject(new Error('Runtime handshake timed out'));
  }, 10_000);
  worker.onmessage = (event: MessageEvent<unknown>) => {
    clearTimeout(timeout);
    const hello = runtimeHelloSchema.safeParse(event.data);
    if (hello.success) resolve(hello.data);
    else {
      worker.terminate();
      reject(new Error('Incompatible runtime handshake'));
    }
  };
  worker.onerror = () => {
    clearTimeout(timeout);
    worker.terminate();
    reject(new Error('Runtime worker failed'));
  };
});

window.karuyomiRuntime = { ready, dispose: () => worker.terminate() };
// Avoid unhandled rejection when this control shell is opened without an adapter.
void ready.catch(() => {});
window.addEventListener('pagehide', () => worker.terminate(), { once: true });
