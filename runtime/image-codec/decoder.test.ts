import assert from 'node:assert/strict';
import { test } from 'node:test';
import { setImmediate as nextTurn } from 'node:timers/promises';
import { ImageCodec, IMAGE_CODEC_LIMITS } from './codec-api.ts';
import {
  decodeImage,
  type ImageDecodeDependencies,
  type ImageDecodeEvent,
  type ImageDecodeOptions,
  type ImageDecodeSession,
} from './decoder.ts';

function fixture(
  options: {
    width?: number;
    height?: number;
    growOnOpen?: boolean;
    failAtEnd?: boolean;
    leak?: boolean;
  } = {},
) {
  const sourceWidth = options.width ?? 128;
  const sourceHeight = options.height ?? 600;
  const state = {
    reads: 0,
    opens: 0,
    closes: 0,
    rows: 0,
    start: 0,
    inputBytes: 0,
    live: 0,
    peak: 0,
    error: 0,
    phase: 0,
    width: sourceWidth,
    height: sourceHeight,
  };
  const stripPointer = 65536;
  const raw = {
    HEAPU8: new Uint8Array(2 * 1024 * 1024),
    _image_input(length: number) {
      state.inputBytes = length;
      state.live = length;
      state.peak = length;
      return 64;
    },
    _image_open(length: number, rows: number, denominator: number) {
      state.opens++;
      assert.equal(length, state.inputBytes);
      assert.equal(rows, IMAGE_CODEC_LIMITS.stripRows);
      state.width = Math.ceil(sourceWidth / denominator);
      state.height = Math.ceil(sourceHeight / denominator);
      state.rows = state.start = state.error = state.phase = 0;
      state.live += state.width * 4 * rows;
      state.peak = state.live;
      if (options.growOnOpen) raw.HEAPU8 = new Uint8Array(3 * 1024 * 1024);
      return 0;
    },
    _image_next() {
      state.reads++;
      if (state.rows === state.height) {
        state.phase = 3;
        if (options.failAtEnd) {
          state.error = 120;
          return -220;
        }
        return 0;
      }
      const count = Math.min(256, state.height - state.rows);
      state.start = state.rows;
      for (let index = 0; index < count * state.width * 4; index++)
        raw.HEAPU8[stripPointer + index] =
          (state.start * state.width * 4 + index + 17) % 256;
      state.rows += count;
      state.phase = 2;
      return count;
    },
    _image_strip: () => stripPointer,
    _image_width: () => state.width,
    _image_height: () => state.height,
    _image_source_width: () => sourceWidth,
    _image_source_height: () => sourceHeight,
    _image_strip_start: () => state.start,
    _image_error_code: () => state.error,
    _image_error_phase: () => state.phase,
    _image_live_bytes: () => state.live,
    _image_peak_bytes: () => state.peak,
    _image_allocations: () => (state.live ? 1 : 0),
    _image_close() {
      state.closes++;
      state.live = options.leak ? 1 : 0;
    },
  };
  return { raw, state, codec: new ImageCodec(raw) };
}

const input = () => new Uint8Array([1, 2, 3, 4, 5]);
const codecUrl = new URL('https://example.invalid/codec.mjs');
function session(
  codec: ImageCodec,
  options: Partial<ImageDecodeOptions> = {},
  dependencies: ImageDecodeDependencies = {},
) {
  return decodeImage(
    { bytes: input(), codecUrl, format: 'png', ...options },
    {
      loadCodec: async () => codec,
      ...dependencies,
    },
  );
}
async function drain(stream: ImageDecodeSession) {
  const kinds: ImageDecodeEvent['kind'][] = [];
  for await (const event of stream) kinds.push(event.kind);
  return { terminal: await stream.completion, kinds };
}

function deferred<Value>() {
  const callbacks: {
    resolve?: (value: Value) => void;
    reject?: (reason: unknown) => void;
  } = {};
  const promise = new Promise<Value>((resolve, reject) => {
    callbacks.resolve = resolve;
    callbacks.reject = reject;
  });
  if (!callbacks.resolve || !callbacks.reject)
    throw new Error('Cannot initialize deferred test loader');
  return { promise, resolve: callbacks.resolve, reject: callbacks.reject };
}

test('rejects missing WASM exports instead of asserting an arbitrary module type', () => {
  assert.throws(() => new ImageCodec({ HEAPU8: new Uint8Array(8) }));
});

test('publishes metadata before decode and advances only when chunks are pulled', async () => {
  const { codec, state } = fixture();
  const stream = session(codec);
  const iterator = stream[Symbol.asyncIterator]();
  const header = await iterator.next();
  assert.equal(header.value?.kind, 'header');
  assert.equal(state.reads, 0);
  const first = await iterator.next();
  assert.equal(first.value?.kind, 'chunk');
  assert.equal(state.reads, 1);
  if (first.value?.kind !== 'chunk') throw new Error('Expected a byte chunk');
  assert.equal(first.value.bytes.length, 65536);
  assert.equal(first.value.bytes[0], 17);
  const firstCopy = first.value.bytes;
  const second = await iterator.next();
  assert.equal(second.value?.kind, 'chunk');
  assert.equal(state.reads, 1);
  assert.equal(firstCopy[0], 17);
  let delivered =
    first.value.bytes.length +
    (second.value?.kind === 'chunk' ? second.value.bytes.length : 0);
  while (true) {
    const next = await iterator.next();
    if (next.done) break;
    if (next.value.kind === 'chunk') {
      assert(next.value.bytes.length <= 65536);
      assert.equal(next.value.offset, delivered);
      delivered += next.value.bytes.length;
    }
  }
  const terminal = await stream.completion;
  assert.equal(terminal.status, 'complete');
  assert.equal(terminal.deliveredBytes, 128 * 600 * 4);
  assert.equal(delivered, terminal.deliveredBytes);
  assert.equal(terminal.decodedRows, 600);
  assert.equal(terminal.liveBytes, 0);
  assert.equal(terminal.allocations, 0);
  assert.equal(terminal.closeSucceeded, true);
  assert.equal(state.closes, 1);
});

test('reads the current HEAPU8 after memory growth and copies output bytes', async () => {
  const { codec } = fixture({ growOnOpen: true });
  const stream = session(codec);
  for await (const event of stream) {
    if (event.kind !== 'chunk') continue;
    assert.equal(event.bytes[0], (event.offset + 17) % 256);
    assert(event.bytes.buffer instanceof ArrayBuffer);
  }
  assert.equal((await stream.completion).heapBytes, 3 * 1024 * 1024);
});

test('cancel before first next resolves completion without loading a module', async () => {
  const { codec, state } = fixture();
  let loads = 0;
  const stream = session(
    codec,
    {},
    {
      loadCodec: async () => {
        loads++;
        return codec;
      },
    },
  );
  await stream.cancel();
  const terminal = await stream.completion;
  assert.equal(terminal.status, 'cancelled');
  assert.equal(terminal.liveBytes, null);
  assert.equal(terminal.closeSucceeded, false);
  assert.equal(loads, 0);
  assert.equal(state.closes, 0);
  const { kinds } = await drain(stream);
  assert.deepEqual(kinds, ['terminal']);
});

test('already aborted signals resolve before iteration without acquiring ownership', async () => {
  const { codec, state } = fixture();
  const stream = session(codec, { signal: AbortSignal.abort() });
  assert.equal((await stream.completion).status, 'cancelled');
  assert.equal(state.opens, 0);
  assert.equal(state.closes, 0);
});

for (const mode of ['cancel', 'signal'] as const)
  test(
    `${mode} while a loader never resolves still settles the session`,
    { timeout: 1000 },
    async () => {
      const { codec, state } = fixture();
      const loading = deferred<ImageCodec>();
      const started = deferred<void>();
      const controller = new AbortController();
      const stream = session(
        codec,
        { signal: controller.signal },
        {
          loadCodec: () => {
            started.resolve();
            return loading.promise;
          },
        },
      );
      const iterator = stream[Symbol.asyncIterator]();
      const pending = iterator.next();
      await started.promise;
      if (mode === 'signal') controller.abort();
      else await stream.cancel();
      const terminal = await stream.completion;
      assert.equal(terminal.status, 'cancelled');
      assert.equal(terminal.header, null);
      assert.equal(terminal.liveBytes, null);
      assert.equal(terminal.allocations, null);
      assert.equal(terminal.peakBytes, null);
      assert.equal(terminal.heapBytes, null);
      assert.equal(terminal.closeSucceeded, false);
      assert.equal(state.opens, 0);
      assert.equal(state.closes, 0);
      assert.equal((await pending).value?.kind, 'terminal');
    },
  );

test(
  'a module arriving after loader cancellation never acquires ownership',
  { timeout: 1000 },
  async () => {
    const { raw, state } = fixture();
    let acquisitions = 0;
    const codec = new (class extends ImageCodec {
      override acquire() {
        acquisitions++;
        return super.acquire();
      }
    })(raw);
    const loading = deferred<ImageCodec>();
    const started = deferred<void>();
    const stream = session(
      codec,
      {},
      {
        loadCodec: () => {
          started.resolve();
          return loading.promise;
        },
      },
    );
    const pending = stream[Symbol.asyncIterator]().next();
    await started.promise;
    await stream.cancel();
    const terminal = await stream.completion;
    loading.resolve(codec);
    await nextTurn();
    assert.equal(terminal.status, 'cancelled');
    assert.equal(acquisitions, 0);
    assert.equal(state.inputBytes, 0);
    assert.equal(state.opens, 0);
    assert.equal(state.closes, 0);
    await pending;
  },
);

test(
  'a loader rejecting after cancellation has no unhandled rejection',
  { timeout: 1000 },
  async (context) => {
    const { codec, state } = fixture();
    const unhandled: unknown[] = [];
    const onUnhandled = (reason: unknown) => {
      unhandled.push(reason);
    };
    process.on('unhandledRejection', onUnhandled);
    context.after(() => process.off('unhandledRejection', onUnhandled));
    const loading = deferred<ImageCodec>();
    const started = deferred<void>();
    const stream = session(
      codec,
      {},
      {
        loadCodec: () => {
          started.resolve();
          return loading.promise;
        },
      },
    );
    const pending = stream[Symbol.asyncIterator]().next();
    await started.promise;
    await stream.cancel();
    loading.reject(new Error('Late loader failure'));
    await nextTurn();
    assert.deepEqual(unhandled, []);
    assert.equal((await stream.completion).status, 'cancelled');
    assert.equal(state.opens, 0);
    assert.equal(state.closes, 0);
    await pending;
  },
);

for (const boundary of ['header', 'chunk'] as const)
  test(`signal abort at ${boundary} closes without another consumer next`, async () => {
    const { codec, state } = fixture();
    const controller = new AbortController();
    const stream = session(codec, { signal: controller.signal });
    const iterator = stream[Symbol.asyncIterator]();
    assert.equal((await iterator.next()).value?.kind, 'header');
    if (boundary === 'chunk')
      assert.equal((await iterator.next()).value?.kind, 'chunk');
    controller.abort();
    const terminal = await stream.completion;
    assert.equal(terminal.status, 'cancelled');
    assert.equal(terminal.liveBytes, 0);
    assert.equal(terminal.allocations, 0);
    assert.equal(terminal.closeSucceeded, true);
    assert.equal(state.closes, 1);
    assert.equal(state.reads, boundary === 'header' ? 0 : 1);
  });

test('consumer break closes the codec and resolves a cancelled terminal', async () => {
  const { codec, state } = fixture();
  const stream = session(codec);
  for await (const event of stream) if (event.kind === 'chunk') break;
  const terminal = await stream.completion;
  assert.equal(terminal.status, 'cancelled');
  assert.equal(terminal.decodedRows, 256);
  assert.equal(terminal.deliveredBytes, 65536);
  assert.equal(terminal.liveBytes, 0);
  assert.equal(state.closes, 1);
});

test('rejects input size and unsupported PNG scaling before invoking the loader', async () => {
  const { codec } = fixture();
  let loads = 0;
  const dependencies = {
    loadCodec: async () => {
      loads++;
      return codec;
    },
  };
  for (const options of [
    { bytes: new Uint8Array() },
    { bytes: new Uint8Array(IMAGE_CODEC_LIMITS.inputBytes + 1) },
    { bytes: new Uint8Array(new SharedArrayBuffer(8)) },
    { denominator: 2 as const },
  ]) {
    const { terminal } = await drain(session(codec, options, dependencies));
    assert.equal(terminal.status, 'failed');
    assert.equal(terminal.liveBytes, null);
  }
  assert.equal(loads, 0);
});

test('JPEG native scale dimensions are distinct from source dimensions', async () => {
  for (const denominator of [1, 2, 4] as const) {
    const { codec } = fixture({ width: 129, height: 601 });
    const { terminal } = await drain(
      session(codec, { format: 'jpeg', denominator }),
    );
    assert.equal(terminal.status, 'complete');
    assert.equal(terminal.header?.sourceWidth, 129);
    assert.equal(terminal.header?.sourceHeight, 601);
    assert.equal(terminal.header?.width, Math.ceil(129 / denominator));
    assert.equal(terminal.header?.height, Math.ceil(601 / denominator));
  }
});

test('late decode failure never emits a complete terminal and still closes', async () => {
  const { codec } = fixture({ failAtEnd: true });
  const { terminal } = await drain(session(codec));
  assert.equal(terminal.status, 'failed');
  assert.equal(terminal.decodeErrorCode, 120);
  assert.equal(terminal.deliveredBytes, 128 * 600 * 4);
  assert.equal(terminal.closeSucceeded, true);
  assert.equal(terminal.liveBytes, 0);
});

test('a runtime function return is validated instead of treated as a line count', async () => {
  const { raw, state } = fixture();
  const codec = new ImageCodec({ ...raw, _image_next: () => 'not a count' });
  const { terminal } = await drain(session(codec));
  assert.equal(terminal.status, 'failed');
  assert.equal(terminal.deliveredBytes, 0);
  assert.equal(terminal.liveBytes, 0);
  assert.equal(state.closes, 1);
});

test('invalid dimensions, row counts and strip coordinates fail before publishing bytes', async () => {
  for (const corrupt of [
    'dimensions',
    'row-count',
    'strip-start',
    'strip-pointer',
  ] as const) {
    const { raw, state } = fixture();
    const codec = new ImageCodec({
      ...raw,
      ...(corrupt === 'dimensions' ? { _image_source_width: () => 4097 } : {}),
      ...(corrupt === 'row-count' ? { _image_next: () => 257 } : {}),
      ...(corrupt === 'strip-start' ? { _image_strip_start: () => 1 } : {}),
      ...(corrupt === 'strip-pointer'
        ? { _image_strip: () => raw.HEAPU8.length - 1 }
        : {}),
    });
    const { terminal } = await drain(session(codec));
    assert.equal(terminal.status, 'failed');
    assert.equal(terminal.deliveredBytes, 0);
    assert.equal(terminal.liveBytes, 0);
    assert.equal(state.closes, 1);
  }
});

test('a complete row sequence with a retained C error flag is still a failed image', async () => {
  const { raw } = fixture();
  const { terminal } = await drain(
    session(new ImageCodec({ ...raw, _image_error_code: () => 120 })),
  );
  assert.equal(terminal.status, 'failed');
  assert.equal(terminal.decodeErrorCode, 120);
  assert.equal(terminal.error?.name, 'ImageCodecError');
  assert.equal(terminal.closeSucceeded, true);
});

test('same raw module has one owner across handles and rejected owners cannot close it', async () => {
  const { codec, raw, state } = fixture();
  const first = session(codec);
  const firstIterator = first[Symbol.asyncIterator]();
  assert.equal((await firstIterator.next()).value?.kind, 'header');
  const { terminal } = await drain(session(new ImageCodec(raw)));
  assert.equal(terminal.status, 'failed');
  assert.match(terminal.error?.message ?? '', /already has an owner/);
  assert.equal(terminal.liveBytes, null);
  assert.equal(state.closes, 0);
  await first.cancel();
  assert.equal((await first.completion).liveBytes, 0);
  assert.equal((await drain(session(codec))).terminal.status, 'complete');
});

test('closed leases cannot call C, including previously captured ABI functions', () => {
  const { codec } = fixture();
  const lease = codec.acquire();
  const allocate = lease.api.image_input;
  assert.equal(lease.close().succeeded, true);
  assert.throws(() => allocate(10), /closed/);
  assert.throws(() => lease.copy(1, 1), /closed/);
});

test('heap ranges and shared memory fail through cleanup rather than reading invalid output', async () => {
  const { raw } = fixture();
  for (const codec of [
    new ImageCodec({ ...raw, _image_input: () => raw.HEAPU8.length - 1 }),
    new ImageCodec({
      ...raw,
      HEAPU8: new Uint8Array(new SharedArrayBuffer(1024)),
    }),
  ]) {
    const { terminal } = await drain(session(codec));
    assert.equal(terminal.status, 'failed');
    assert.equal(terminal.deliveredBytes, 0);
  }
});

test('nonzero cleanup becomes failure and quarantines that module instance', async () => {
  const { codec } = fixture({ leak: true });
  const { terminal } = await drain(session(codec));
  assert.equal(terminal.status, 'failed');
  assert.equal(terminal.closeSucceeded, false);
  assert.equal(terminal.liveBytes, 1);
  assert.equal(terminal.error?.name, 'ImageCodecCleanupError');
  assert.throws(() => codec.acquire(), /failed cleanup/);
});

test('one session rejects a second consumer and concurrent next calls', async () => {
  const { codec } = fixture();
  const stream = session(codec);
  const iterator = stream[Symbol.asyncIterator]();
  assert.throws(() => stream[Symbol.asyncIterator](), /already has a consumer/);
  const first = iterator.next();
  await assert.rejects(iterator.next(), /Concurrent/);
  await first;
  await stream.cancel();
  assert.equal((await stream.completion).liveBytes, 0);
});
