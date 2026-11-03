import { createHello } from './hello.js';

// This is the public bootstrap only. Private TeaVM artifacts are added in P0-A.
globalThis.postMessage(createHello(crypto.randomUUID()));
