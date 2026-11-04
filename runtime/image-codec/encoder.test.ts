import assert from 'node:assert/strict';
import test from 'node:test';
import { z } from 'zod';
import { instantiateCodecModule } from './codec-api.ts';
import { PngEncoder, PNG_ENCODER_LIMITS } from './encoder.ts';

function fixture(leak = false) {
  const state = { input: 0, calls: 0, live: 0, peak: 0, closes: 0 };
  const raw = {
    HEAPU8: new Uint8Array(1024),
    _encoder_input: (length: number) => {
      state.input = length;
      state.live = state.peak = length;
      return 16;
    },
    _encoder_encode: (_width: number, _height: number) => {
      state.calls++;
      raw.HEAPU8 = new Uint8Array(2048);
      raw.HEAPU8.set([137, 80, 78, 71], 512);
      state.live += 4;
      state.peak = state.live;
      return 0;
    },
    _encoder_output: () => 512,
    _encoder_length: () => 4,
    _encoder_error_code: () => 0,
    _encoder_live_bytes: () => state.live,
    _encoder_peak_bytes: () => state.peak,
    _encoder_allocations: () => (state.live ? 1 : 0),
    _encoder_close: () => {
      state.closes++;
      state.live = leak ? 1 : 0;
    },
  };
  return { raw, state, encoder: new PngEncoder(raw) };
}
test('encoder validates its actual exports and copies from the current grown heap', () => {
  assert.throws(() => new PngEncoder({ HEAPU8: new Uint8Array(8) }));
  const { raw, encoder } = fixture();
  const lease = encoder.acquire();
  const png = lease.encode(new Uint8Array(16), 2, 2);
  assert.deepEqual([...png], [137, 80, 78, 71]);
  raw.HEAPU8.fill(0);
  assert.equal(png[0], 137);
  assert.throws(
    () => lease.encode(new Uint8Array(16), 2, 2),
    /already encoded/,
  );
  assert.equal(lease.close().liveBytes, 0);
  assert.throws(() => lease.metrics(), /closed/);
});
test('encoder rejects shape, length and shared input before C allocation', () => {
  for (const [bytes, width, height] of [
    [new Uint8Array(16), 3, 2],
    [new Uint8Array(4), 4097, 1],
    [new Uint8Array(4), 1, 257],
    [new Uint8Array(new SharedArrayBuffer(4)), 1, 1],
  ] satisfies [Uint8Array, number, number][]) {
    const { encoder, state } = fixture();
    const lease = encoder.acquire();
    assert.throws(() => lease.encode(bytes, width, height), /Invalid bounded/);
    assert.equal(state.input, 0);
    lease.close();
  }
});
test('encoder enforces output and ABI result types then closes real owned state', () => {
  for (const override of [
    { _encoder_length: () => PNG_ENCODER_LIMITS.pngBytes + 1 },
    { _encoder_output: () => 2047 },
    { _encoder_encode: () => 'wrong type' },
  ]) {
    const { raw, state } = fixture();
    const lease = new PngEncoder({ ...raw, ...override }).acquire();
    assert.throws(() => lease.encode(new Uint8Array(16), 2, 2));
    assert.equal(lease.close().succeeded, true);
    assert.equal(state.live, 0);
  }
});
test('encoder raw modules have exclusive owners and failed cleanup quarantines reuse', () => {
  const { raw, encoder } = fixture();
  const lease = encoder.acquire();
  assert.throws(() => new PngEncoder(raw).acquire(), /already has an owner/);
  const encode = lease.api.encoder_input;
  lease.close();
  assert.throws(() => encode(4), /closed/);
  encoder.acquire().close();
  const leaking = fixture(true).encoder;
  const leakingLease = leaking.acquire();
  leakingLease.encode(new Uint8Array(16), 2, 2);
  assert.equal(leakingLease.close().succeeded, false);
  assert.throws(() => leaking.acquire(), /failed cleanup/);
});
test('verified WASM bytes reach a real module factory argument without a relative fetch', async () => {
  const source =
    'export default async function(options) { return {wasm: [...options.wasmBinary], location: options.locateFile("encoder.wasm", "blob:https://example.invalid/encoder")}; }';
  const url = new URL('data:text/javascript,' + encodeURIComponent(source));
  const raw = await instantiateCodecModule(url, {
    wasmBinary: new Uint8Array([1, 2, 3]),
  });
  const parsed = z
    .object({ wasm: z.array(z.number()), location: z.string() })
    .parse(raw);
  assert.deepEqual(parsed.wasm, [1, 2, 3]);
  assert.equal(parsed.location, 'data:application/wasm;base64,');
  await assert.rejects(
    instantiateCodecModule(url, {
      wasmBinary: new Uint8Array(new SharedArrayBuffer(3)),
    }),
    /Invalid verified/,
  );
  await assert.rejects(
    instantiateCodecModule(url, { wasmBinary: new Uint8Array() }),
    /Invalid verified/,
  );
});
