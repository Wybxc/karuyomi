import assert from 'node:assert/strict';
import test from 'node:test';
import { setImmediate as nextTurn } from 'node:timers/promises';
import { ImageCodec } from './codec-api.ts';
import { PngEncoder } from './encoder.ts';
import {
  decodeImageTiles,
  type CodecWorkerEndpoint,
  type ImageTileOptions,
} from './client.ts';
import { CodecWorkerRuntime, type CodecWorkerDependencies } from './worker.ts';
import {
  CODEC_WORKER_LIMITS,
  codecResponseSchema,
  type CodecResponse,
  type CodecStart,
} from './worker-protocol.ts';

function fixtures(failAtEnd = false) {
  const state = {
    reads: 0,
    rows: 0,
    start: 0,
    live: 0,
    peak: 0,
    error: 0,
    closes: 0,
    encodes: 0,
    encoderLive: 0,
    encoderPeak: 0,
    encoderCloses: 0,
  };
  const raw = {
    HEAPU8: new Uint8Array(1024 * 1024),
    _image_input: (length: number) => {
      state.live = state.peak = length;
      return 16;
    },
    _image_open: () => {
      state.live += 128 * 256 * 4;
      state.peak = state.live;
      return 0;
    },
    _image_next: () => {
      state.reads++;
      if (state.rows === 600) {
        state.error = failAtEnd ? 120 : 0;
        return failAtEnd ? -220 : 0;
      }
      const count = Math.min(256, 600 - state.rows);
      state.start = state.rows;
      raw.HEAPU8.fill(29, 65536, 65536 + count * 128 * 4);
      state.rows += count;
      return count;
    },
    _image_strip: () => 65536,
    _image_width: () => 128,
    _image_height: () => 600,
    _image_source_width: () => 128,
    _image_source_height: () => 600,
    _image_strip_start: () => state.start,
    _image_error_code: () => state.error,
    _image_error_phase: () => (state.rows === 600 ? 3 : 2),
    _image_live_bytes: () => state.live,
    _image_peak_bytes: () => state.peak,
    _image_allocations: () => (state.live ? 1 : 0),
    _image_close: () => {
      state.closes++;
      state.live = 0;
    },
  };
  const encoderRaw = {
    HEAPU8: new Uint8Array(1024 * 1024),
    _encoder_input: (length: number) => {
      state.encoderLive = state.encoderPeak = length;
      return 16;
    },
    _encoder_encode: () => {
      state.encodes++;
      encoderRaw.HEAPU8.fill(137, 512 * 1024, 512 * 1024 + 150000);
      state.encoderLive += 150000;
      state.encoderPeak = state.encoderLive;
      return 0;
    },
    _encoder_output: () => 512 * 1024,
    _encoder_length: () => 150000,
    _encoder_error_code: () => 0,
    _encoder_live_bytes: () => state.encoderLive,
    _encoder_peak_bytes: () => state.encoderPeak,
    _encoder_allocations: () => (state.encoderLive ? 1 : 0),
    _encoder_close: () => {
      state.encoderCloses++;
      state.encoderLive = 0;
    },
  };
  return {
    state,
    raw,
    codec: new ImageCodec(raw),
    encoder: new PngEncoder(encoderRaw),
  };
}
const options = (): ImageTileOptions => ({
  workerUrl: new URL('blob:https://example.invalid/worker'),
  blob: new Blob([new Uint8Array([1, 2, 3])]),
  format: 'png',
  decoder: {
    moduleUrl: 'blob:https://example.invalid/png',
    wasmBinary: new Uint8Array([1]),
  },
  encoder: {
    moduleUrl: 'blob:https://example.invalid/encoder',
    wasmBinary: new Uint8Array([2]),
  },
  requestId: 'request',
  generation: 'generation',
});
async function until(predicate: () => boolean) {
  for (let index = 0; index < 100 && !predicate(); index++) await nextTurn();
  assert(predicate(), 'Expected asynchronous fake Worker boundary');
}
function loopback(
  failAtEnd = false,
  dependencies: CodecWorkerDependencies = {},
) {
  const fixture = fixtures(failAtEnd);
  const calls: string[] = [];
  let terminated = false;
  const endpoint: CodecWorkerEndpoint = {
    onmessage: null,
    onerror: null,
    onmessageerror: null,
    postMessage: (message, transfer) => {
      const copy: unknown = structuredClone(message, { transfer });
      queueMicrotask(() => {
        if (!terminated) runtime.receive(copy);
      });
    },
    terminate: () => {
      calls.push('terminate');
      terminated = true;
      void runtime.dispose();
    },
  };
  const runtime = new CodecWorkerRuntime(
    (message, transfer) => {
      const copy: unknown = structuredClone(message, { transfer });
      queueMicrotask(() => {
        if (!terminated)
          endpoint.onmessage?.(new MessageEvent('message', { data: copy }));
      });
    },
    {
      loadDecoder: async () => fixture.codec,
      loadEncoder: async () => fixture.encoder,
      ...dependencies,
    },
  );
  const stream = decodeImageTiles(options(), {
    createWorker: () => endpoint,
    releaseModules: () => calls.push('release'),
  });
  return { ...fixture, calls, runtime, endpoint, stream };
}
test('fake Worker client consumes bounded PNG strips, keeps pulls separate and closes both codecs', async () => {
  const { stream, state, calls } = loopback();
  const iterator = stream[Symbol.asyncIterator]();
  assert.equal((await iterator.next()).value?.kind, 'header');
  assert.equal(state.reads, 0);
  const first = (await iterator.next()).value;
  assert.equal(first?.kind, 'tile');
  if (first?.kind !== 'tile') throw new Error('Expected PNG tile');
  assert.equal(first.height, 256);
  assert.equal(first.png.size, 150000);
  assert.equal(first.provisional, true);
  await nextTurn();
  assert.equal(state.reads, 1);
  assert.equal(state.encodes, 1);
  const tiles = [first];
  while (true) {
    const event = await iterator.next();
    if (event.done) break;
    if (event.value.kind === 'tile') tiles.push(event.value);
  }
  assert.deepEqual(
    tiles.map((tile) => [tile.y, tile.height]),
    [
      [0, 256],
      [256, 256],
      [512, 88],
    ],
  );
  const terminal = await stream.completion;
  assert.equal(terminal.status, 'complete');
  assert.equal(terminal.invalidatesTiles, false);
  assert.equal(terminal.decoder?.liveBytes, 0);
  assert.equal(terminal.encoder?.liveBytes, 0);
  assert.equal(state.encoderCloses, 3);
  assert.deepEqual(calls, ['terminate', 'release']);
});
test('a real fake-module tail error invalidates every provisional tile', async () => {
  const { stream, state } = loopback(true);
  let tiles = 0;
  for await (const event of stream)
    if (event.kind === 'tile') {
      tiles++;
      assert.equal(event.provisional, true);
    }
  const terminal = await stream.completion;
  assert.equal(tiles, 3);
  assert.equal(terminal.status, 'failed');
  assert.equal(terminal.invalidatesTiles, true);
  assert.equal(terminal.decoder?.decodeErrorCode, 120);
  assert.equal(state.live, 0);
  assert.equal(state.encoderLive, 0);
});
test('consumer break cooperatively closes codecs before terminating only the codec Worker', async () => {
  const { stream, state, calls } = loopback();
  for await (const event of stream) if (event.kind === 'tile') break;
  const terminal = await stream.completion;
  assert.equal(terminal.status, 'cancelled');
  assert.equal(terminal.forced, false);
  assert.equal(terminal.invalidatesTiles, true);
  assert.equal(state.reads, 1);
  assert.equal(state.live, 0);
  assert.deepEqual(calls, ['terminate', 'release']);
});

test('cancellation preserves an actual decoder cleanup failure from the Worker', async () => {
  const leaking = fixtures();
  const codec = new ImageCodec({
    ...leaking.raw,
    _image_close: () => {
      leaking.state.closes++;
      leaking.state.live = 1;
    },
  });
  const { stream } = loopback(false, { loadDecoder: async () => codec });
  for await (const event of stream) if (event.kind === 'tile') break;
  const terminal = await stream.completion;
  assert.equal(terminal.status, 'failed');
  assert.equal(terminal.invalidatesTiles, true);
  assert.equal(terminal.decoder?.liveBytes, 1);
  assert.equal(terminal.decoder?.closeSucceeded, false);
  assert.equal(terminal.decoder?.error?.name, 'ImageCodecCleanupError');
  assert.match(terminal.error?.message ?? '', /retained allocations/);
});
test('Worker does not send a second data block or decode another strip before ACK/pull', async () => {
  const fixture = fixtures();
  const messages: CodecResponse[] = [];
  const runtime = new CodecWorkerRuntime((message) => messages.push(message), {
    loadDecoder: async () => fixture.codec,
    loadEncoder: async () => fixture.encoder,
  });
  const input = options();
  const request: CodecStart = {
    version: 1,
    type: 'start',
    requestId: input.requestId,
    generation: input.generation,
    blob: input.blob,
    format: input.format,
    denominator: 1,
    decoder: input.decoder,
    encoder: input.encoder,
  };
  runtime.receive(request);
  await until(() => messages.some((message) => message.type === 'header'));
  runtime.receive({
    version: 1,
    type: 'pull',
    requestId: 'request',
    generation: 'generation',
  });
  await until(() => messages.some((message) => message.type === 'data'));
  await nextTurn();
  assert.equal(messages.filter((message) => message.type === 'data').length, 1);
  assert.equal(fixture.state.reads, 1);
  for (let seq = 1; seq <= 3; seq++) {
    runtime.receive({
      version: 1,
      type: 'ack',
      requestId: 'request',
      generation: 'generation',
      seq,
    });
    await nextTurn();
  }
  assert(messages.some((message) => message.type === 'tile-end'));
  assert.equal(fixture.state.reads, 1);
  for (const message of messages)
    if (message.type === 'data')
      assert(message.buffer.byteLength <= CODEC_WORKER_LIMITS.chunkBytes);
  await runtime.dispose();
  assert.equal(fixture.state.live, 0);
});
test('cancel before first pull creates no Worker and releases owned module URLs', async () => {
  let created = 0,
    released = 0;
  const stream = decodeImageTiles(options(), {
    createWorker: () => {
      created++;
      throw new Error('Must not start');
    },
    releaseModules: () => {
      released++;
    },
  });
  await stream.cancel();
  assert.equal(created, 0);
  assert.equal(released, 1);
  assert.equal((await stream.completion).decoder, null);
});
test('oversize Blob fails before reading it or creating a Worker', async () => {
  class UnreadableBlob extends Blob {
    override arrayBuffer(): Promise<ArrayBuffer> {
      throw new Error('Must not read');
    }
  }
  const blob = new UnreadableBlob([
    new Uint8Array(CODEC_WORKER_LIMITS.inputBytes + 1),
  ]);
  let created = 0;
  const stream = decodeImageTiles(
    { ...options(), blob },
    {
      createWorker: () => {
        created++;
        throw new Error('Must not start');
      },
    },
  );
  for await (const _event of stream) {
    /* terminal only */
  }
  assert.equal(created, 0);
  assert.match((await stream.completion).error?.message ?? '', /8 MiB/);
});
test('module transfer rejects partial WASM views before transferring unaccounted backing bytes', async () => {
  for (const wasmBinary of [
    new Uint8Array(new ArrayBuffer(1024), 1, 1),
    new Uint8Array(new ArrayBuffer(1024), 0, 1),
  ]) {
    let created = 0,
      released = 0;
    const input = options();
    const stream = decodeImageTiles(
      { ...input, decoder: { ...input.decoder, wasmBinary } },
      {
        createWorker: () => {
          created++;
          throw new Error('Must not create');
        },
        releaseModules: () => {
          released++;
        },
      },
    );
    for await (const _event of stream) {
      /* validation terminal */
    }
    assert.equal(created, 0);
    assert.equal(released, 1);
    assert.equal((await stream.completion).status, 'failed');
    assert.equal(wasmBinary.buffer.byteLength, 1024);
  }
});
test(
  'unresponsive Worker times out and force termination never invents C release metrics',
  { timeout: 1000 },
  async () => {
    const calls: string[] = [];
    const worker: CodecWorkerEndpoint = {
      onmessage: null,
      onerror: null,
      onmessageerror: null,
      postMessage: () => {},
      terminate: () => {
        calls.push('terminate');
      },
    };
    const stream = decodeImageTiles(
      { ...options(), timeoutMs: 10, cancelGraceMs: 5 },
      {
        createWorker: () => worker,
        releaseModules: () => {
          calls.push('release');
        },
      },
    );
    for await (const _event of stream) {
      /* timeout terminal */
    }
    const terminal = await stream.completion;
    assert.equal(terminal.status, 'failed');
    assert.equal(terminal.forced, true);
    assert.equal(terminal.decoder, null);
    assert.equal(terminal.encoder, null);
    assert.deepEqual(calls, ['terminate', 'release']);
  },
);
test('old-generation frames are ignored and malformed current frames terminate the client', async () => {
  let worker: CodecWorkerEndpoint | undefined;
  const stream = decodeImageTiles(options(), {
    createWorker: () =>
      (worker = {
        onmessage: null,
        onerror: null,
        onmessageerror: null,
        postMessage: () => {},
        terminate: () => {},
      }),
  });
  const pending = stream[Symbol.asyncIterator]().next();
  const send = (message: unknown) =>
    worker?.onmessage?.(new MessageEvent('message', { data: message }));
  send({
    version: 1,
    requestId: 'request',
    generation: 'old',
    type: 'terminal',
    terminal: {
      status: 'cancelled',
      invalidatesTiles: true,
      decoder: null,
      encoder: null,
      error: null,
      forced: false,
    },
  });
  send({
    version: 1,
    requestId: 'request',
    generation: 'generation',
    type: 'data',
    seq: 1,
    buffer: new ArrayBuffer(65537),
  });
  await pending;
  assert.equal((await stream.completion).status, 'failed');
  assert.equal(codecResponseSchema.safeParse({}).success, false);
});

for (const stage of ['encoder', 'decoder'] as const)
  test(
    `cancel during pending ${stage} initialization settles without invented cleanup`,
    { timeout: 1000 },
    async () => {
      let loading = false;
      const never = () => {
        loading = true;
        return new Promise<never>(() => {});
      };
      const { stream, state, calls } = loopback(
        false,
        stage === 'encoder' ? { loadEncoder: never } : { loadDecoder: never },
      );
      const pending = stream[Symbol.asyncIterator]().next();
      await until(() => loading);
      await stream.cancel();
      const terminal = await stream.completion;
      assert.equal(terminal.status, 'cancelled');
      assert.equal(terminal.forced, false);
      assert.equal(terminal.decoder?.liveBytes ?? null, null);
      if (terminal.decoder)
        assert.equal(terminal.decoder.closeSucceeded, false);
      assert.equal(state.closes, 0);
      assert.equal(state.encoderCloses, 0);
      assert.deepEqual(calls, ['terminate', 'release']);
      assert.equal((await pending).value?.kind, 'terminal');
    },
  );

test(
  'missing DATA ACK times out, invalidates tiles and closes both owned contexts',
  { timeout: 1000 },
  async () => {
    const fixture = fixtures();
    let resolveTerminal: ((message: CodecResponse) => void) | undefined;
    const ended = new Promise<CodecResponse>((resolve) => {
      resolveTerminal = resolve;
    });
    const runtime = new CodecWorkerRuntime(
      (message) => {
        if (message.type === 'header')
          runtime.receive({
            version: 1,
            requestId: 'request',
            generation: 'generation',
            type: 'pull',
          });
        if (message.type === 'terminal') resolveTerminal?.(message);
      },
      {
        loadDecoder: async () => fixture.codec,
        loadEncoder: async () => fixture.encoder,
        ackTimeoutMs: 5,
      },
    );
    const input = options();
    runtime.receive({
      version: 1,
      type: 'start',
      requestId: input.requestId,
      generation: input.generation,
      blob: input.blob,
      format: input.format,
      denominator: 1,
      decoder: input.decoder,
      encoder: input.encoder,
    });
    const response = await ended;
    if (response.type !== 'terminal')
      throw new Error('Expected timeout terminal');
    assert.equal(response.terminal.status, 'failed');
    assert.equal(response.terminal.invalidatesTiles, true);
    assert.match(
      response.terminal.error?.message ?? '',
      /acknowledgement timed out/,
    );
    assert.equal(fixture.state.live, 0);
    assert.equal(fixture.state.encoderLive, 0);
  },
);

test('a signal cancels a paused tile session without another consumer pull', async () => {
  const fixture = loopback();
  const controller = new AbortController();
  const stream = decodeImageTiles(
    { ...options(), signal: controller.signal },
    { createWorker: () => fixture.endpoint },
  );
  const iterator = stream[Symbol.asyncIterator]();
  assert.equal((await iterator.next()).value?.kind, 'header');
  assert.equal((await iterator.next()).value?.kind, 'tile');
  controller.abort();
  const terminal = await stream.completion;
  assert.equal(terminal.status, 'cancelled');
  assert.equal(terminal.forced, false);
  assert.equal(terminal.decoder?.liveBytes, 0);
});

test('a tile session rejects a second consumer and concurrent next calls', async () => {
  const { stream } = loopback();
  const iterator = stream[Symbol.asyncIterator]();
  assert.throws(() => stream[Symbol.asyncIterator](), /already has a consumer/);
  const pending = iterator.next();
  await assert.rejects(iterator.next(), /Concurrent/);
  await pending;
  await stream.cancel();
});
