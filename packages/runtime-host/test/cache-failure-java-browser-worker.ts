import { BinaryHttpTransport } from '../src/http-transport.js';
import {
  object,
  workerScope,
} from '../../../runtime/teavm/bridge/bridge-common.js';

declare global {
  var cacheFailureHttpOwner: [string, string, string];
  var cacheFailureDone: ((json: string) => void) | undefined;
}

const scope = workerScope();
scope.addEventListener('error', (event) => {
  scope.postMessage({
    type: 'cache-failure-result',
    passed: false,
    error: event.message,
    filename: event.filename,
    line: event.lineno,
    column: event.colno,
    stack:
      event.error instanceof Error ? event.error.stack : String(event.error),
  });
});
for (const installed of [
  scope.teaCache,
  scope.teaCacheRead,
  scope.teaCacheWrite,
]) {
  if (typeof installed !== 'function')
    throw Error('Required Cache bridge function is not installed');
}
const transport = new BinaryHttpTransport(location.origin, 'v2-fixture');
const token = transport.begin({
  requestId: 'cache-failure-java',
  generation: 'cache-failure-java',
});
scope.cacheFailureHttpOwner = [
  'cache-failure-java',
  'cache-failure-java',
  token,
];
const active = new Set<string>();
let maximumActive = 0,
  cancellations = 0;
Object.assign(scope, {
  teaHttpOpen: (request: string) => {
    const handle = transport.open(request);
    active.add(handle);
    maximumActive = Math.max(maximumActive, active.size);
    return handle;
  },
  teaHttpWrite: (handle: string, bytes: Uint8Array) =>
    transport.write(handle, bytes),
  teaHttpFinish: (handle: string) => transport.finish(handle),
  teaHttpRead: (handle: string, maximum: number) =>
    transport.read(handle, maximum),
  teaHttpClose: (handle: string) => {
    active.delete(handle);
    transport.close(handle);
  },
  teaHttpCancel: (handle: string) => {
    cancellations++;
    active.delete(handle);
    transport.close(handle);
  },
});
scope.cacheFailureDone = (json: string) => {
  if (new TextEncoder().encode(json).length > 65536)
    throw Error('Java failure report too large');
  const result = object(JSON.parse(json) as unknown);
  const report = {
    ...result,
    http: { open: active.size, maximumActive, cancellations },
  };
  transport.dispose();
  scope.postMessage({ type: 'cache-failure-result', ...report });
};
