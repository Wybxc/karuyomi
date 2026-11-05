/** The product Worker entry is unchanged; only fixture diagnostics are added. */
import '../src/worker.js';
import { workerScope } from '../../../runtime/teavm/bridge/bridge-common.js';

workerScope().enqueueFixtureMark = (event) => {
  globalThis.postMessage({ type: 'enqueue-fixture-event', event });
};
