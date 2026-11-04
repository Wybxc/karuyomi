import { describe, expect, it, vi } from 'vitest';
import type { ImageTileOptions, ImageTileEvent } from '../client.ts';
import type { ImageHeader } from '../decoder.ts';
import type { ImageTileTerminal } from '../worker-protocol.ts';
import type { PreparedImageCodecAssets } from '../assets.ts';
import {
  IMAGE_TILE_STORE_LIMITS,
  ImageTileStore,
  type ImageTileDecodeSession,
  type ImageTileWindowSnapshot,
} from '../tile-store.ts';

function gate() {
  let release = () => {};
  const promise = new Promise<void>((resolve) => {
    release = resolve;
  });
  return { promise, release };
}
function terminal(
  status: 'complete' | 'failed' | 'cancelled',
  header: ImageHeader,
): ImageTileTerminal {
  return {
    status,
    invalidatesTiles: status !== 'complete',
    forced: false,
    error:
      status === 'failed'
        ? { name: 'Error', message: 'Invalid PNG IEND' }
        : null,
    decoder: {
      status,
      header,
      deliveredBytes: header.width * header.height * 4,
      decodedRows: header.height,
      decodeErrorCode: status === 'failed' ? 3 : 0,
      decodeErrorPhase: 0,
      error: null,
      closeSucceeded: true,
      liveBytes: 0,
      allocations: 0,
      peakBytes: 1024,
      heapBytes: 16 * 1024 * 1024,
    },
    encoder: {
      succeeded: true,
      liveBytes: 0,
      peakBytes: 1024,
      allocations: 0,
      heapBytes: 16 * 1024 * 1024,
      error: null,
    },
  };
}
interface Scenario {
  width?: number;
  height?: number;
  tileBytes?: number;
  failedTail?: boolean;
  tail?: ReturnType<typeof gate>;
  stopped?: ReturnType<typeof gate>;
  corruptSize?: boolean;
}
function fixture(scenarios: Scenario[] = [{}]) {
  const inputs: ImageTileOptions[] = [];
  const trace: string[] = [];
  let active = 0;
  let maximumActive = 0;
  let released = 0;
  let emittedTiles = 0;
  const prepare = async (): Promise<PreparedImageCodecAssets> => ({
    workerUrl: new URL('blob:https://reader.example/worker'),
    decoder: {
      moduleUrl: 'blob:https://reader.example/decoder',
      wasmBinary: new Uint8Array([1]),
    },
    encoder: {
      moduleUrl: 'blob:https://reader.example/encoder',
      wasmBinary: new Uint8Array([2]),
    },
    release() {
      trace.push('release');
      released++;
    },
  });
  const decode = (options: ImageTileOptions): ImageTileDecodeSession => {
    const scenario = scenarios[Math.min(inputs.length, scenarios.length - 1)]!;
    inputs.push(options);
    const sourceWidth = scenario.width ?? 16;
    const sourceHeight = scenario.height ?? 1024;
    const denominator = options.denominator ?? 1;
    const header: ImageHeader = {
      format: options.format,
      sourceWidth,
      sourceHeight,
      width: Math.ceil(sourceWidth / denominator),
      height: Math.ceil(sourceHeight / denominator),
      rowBytes: Math.ceil(sourceWidth / denominator) * 4,
      denominator,
    };
    let cancelled = false;
    let completed: ImageTileTerminal | undefined;
    let finish = (_value: ImageTileTerminal) => {};
    const completion = new Promise<ImageTileTerminal>((resolve) => {
      finish = resolve;
    });
    const cancellation = gate();
    const cancel = () => {
      cancelled = true;
      cancellation.release();
    };
    options.signal?.addEventListener('abort', cancel, { once: true });
    const iterator = (async function* (): AsyncGenerator<ImageTileEvent> {
      active++;
      maximumActive = Math.max(maximumActive, active);
      trace.push('start');
      try {
        yield { kind: 'header', ...header };
        for (
          let y = 0, index = 0;
          y < header.height && !cancelled;
          y += 256, index++
        ) {
          const height = Math.min(256, header.height - y);
          const size = scenario.tileBytes ?? 12;
          const png = new Blob([new Uint8Array(size)], { type: 'image/png' });
          emittedTiles++;
          yield {
            kind: 'tile',
            png,
            id: `${options.requestId}:${index}`,
            index,
            x: 0,
            y,
            width: header.width,
            height,
            sourceRect: {
              x: 0,
              y: y * denominator,
              width: sourceWidth,
              height: Math.min(
                height * denominator,
                sourceHeight - y * denominator,
              ),
            },
            mimeType: 'image/png',
            byteLength: size + (scenario.corruptSize ? 1 : 0),
            provisional: true,
          };
        }
        if (scenario.tail)
          await Promise.race([scenario.tail.promise, cancellation.promise]);
        completed = terminal(
          cancelled ? 'cancelled' : scenario.failedTail ? 'failed' : 'complete',
          header,
        );
        yield { kind: 'terminal', ...completed };
      } finally {
        if (scenario.stopped) await scenario.stopped.promise;
        active--;
        trace.push('stopped');
        options.signal?.removeEventListener('abort', cancel);
        finish(completed ?? terminal('cancelled', header));
      }
    })();
    return {
      completion,
      [Symbol.asyncIterator]: () => iterator,
      cancel: async () => {
        cancel();
        await completion;
      },
    };
  };
  const store = new ImageTileStore({ prepare, decode });
  const blob = new Blob([new Uint8Array([1, 2, 3])]);
  const add = (pageId = 'page', format: 'png' | 'jpeg' = 'png') => {
    const scenario = scenarios[Math.min(inputs.length, scenarios.length - 1)]!;
    store.addPage({
      pageId,
      generation: 'generation',
      blob,
      format,
      expectedSize: {
        width: scenario.width ?? 16,
        height: scenario.height ?? 1024,
      },
    });
  };
  const request = (
    sourceY = 0,
    sourceEndY = 256,
    pageId = 'page',
    denominator: 1 | 2 | 4 = 1,
  ) =>
    store.requestWindow({
      pageId,
      generation: 'generation',
      sourceY,
      sourceEndY,
      denominator,
    });
  return {
    store,
    inputs,
    trace,
    blob,
    add,
    request,
    get released() {
      return released;
    },
    get active() {
      return active;
    },
    get maximumActive() {
      return maximumActive;
    },
    get emittedTiles() {
      return emittedTiles;
    },
  };
}
async function settled(
  store: ImageTileStore,
  pageId = 'page',
): Promise<ImageTileWindowSnapshot> {
  for (;;) {
    const snapshot = store.snapshot(pageId, 'generation');
    if (snapshot.state !== 'pending') return snapshot;
    await store.waitForChange(
      pageId,
      'generation',
      snapshot.revision,
      AbortSignal.timeout(2000),
    );
  }
}

describe('host codec page ownership', () => {
  it('drains every strip and the terminal while retaining only the requested PNG window', async () => {
    const f = fixture();
    f.add();
    expect(f.request().state).toBe('pending');
    const snapshot = await settled(f.store);
    expect(snapshot.state).toBe('complete');
    expect(snapshot.tiles).toHaveLength(1);
    expect(snapshot.tiles[0]?.state).toBe('complete');
    expect(f.emittedTiles).toBe(4);
    expect(f.store.usage).toMatchObject({
      cachedBytes: 12,
      leasedTiles: 1,
      activeDecodes: 0,
    });
    expect(f.inputs[0]?.blob).toBe(f.blob);
    expect(f.trace).toEqual(['start', 'stopped', 'release']);
  });

  it('reuses lease identities and Blob bytes, and keeps JPEG scales as separate cached variants', async () => {
    const f = fixture();
    f.add('page', 'jpeg');
    f.request();
    const first = (await settled(f.store)).tiles[0]!;
    const cached = f.request().tiles[0]!;
    expect(cached.leaseId).toBe(first.leaseId);
    expect(cached.png).toBe(first.png);
    expect(f.inputs).toHaveLength(1);
    f.request(0, 256, 'page', 2);
    const scaled = (await settled(f.store)).tiles[0]!;
    expect(scaled.metadata.width).toBe(8);
    expect(scaled.leaseId).not.toBe(first.leaseId);
    expect(f.request().tiles[0]?.leaseId).toBe(first.leaseId);
    expect(f.inputs).toHaveLength(2);
  });

  it('evicts only unleased PNGs and regenerates missing strips from the original local Blob', async () => {
    const f = fixture([{ height: 768, tileBytes: 8 * 1024 * 1024 }]);
    f.add();
    f.request();
    const first = (await settled(f.store)).tiles[0]!;
    f.request(256, 512);
    const second = (await settled(f.store)).tiles[0]!;
    f.store.releaseTile(first.leaseId, 'generation');
    f.request(512, 768);
    await settled(f.store);
    f.store.releaseTile(second.leaseId, 'generation');
    f.request();
    const regenerated = (await settled(f.store)).tiles[0]!;
    expect(regenerated.leaseId).not.toBe(first.leaseId);
    expect(f.inputs).toHaveLength(4);
    expect(f.inputs.every((input) => input.blob === f.blob)).toBe(true);
    expect(f.store.usage.cachedBytes).toBe(16 * 1024 * 1024);
  });

  it('invalidates provisional output on a late tail failure and retains its quota until display release', async () => {
    const tail = gate();
    const f = fixture([{ tail, failedTail: true }]);
    f.add();
    f.request();
    await vi.waitFor(() =>
      expect(f.store.snapshot('page', 'generation').tiles).toHaveLength(1),
    );
    const lease = f.store.snapshot('page', 'generation').tiles[0]!;
    expect(lease.state).toBe('pending');
    tail.release();
    const failed = await settled(f.store);
    expect(failed.state).toBe('failed');
    expect(failed.tiles).toEqual([]);
    expect(failed.invalidatedLeaseIds).toEqual([lease.leaseId]);
    expect(f.store.usage).toMatchObject({ cachedBytes: 12, leasedTiles: 1 });
    f.store.releaseTile(lease.leaseId, 'old-generation');
    expect(f.store.usage.leasedTiles).toBe(1);
    f.store.releaseTile(lease.leaseId, 'generation');
    expect(f.store.usage).toMatchObject({
      cachedBytes: 0,
      leasedTiles: 0,
      leasedPixels: 0,
    });
  });

  it('waits for actual cancellation/Worker termination before removing the input and revoking modules', async () => {
    const tail = gate();
    const stopped = gate();
    const f = fixture([{ tail, stopped }]);
    f.add();
    f.request();
    await vi.waitFor(() =>
      expect(f.store.snapshot('page', 'generation').tiles).toHaveLength(1),
    );
    const lease = f.store.snapshot('page', 'generation').tiles[0]!;
    let removed = false;
    const removing = f.store.removePage('page', 'generation').then(() => {
      removed = true;
    });
    await Promise.resolve();
    await Promise.resolve();
    expect(removed).toBe(false);
    expect(f.released).toBe(0);
    expect(f.active).toBe(1);
    stopped.release();
    await removing;
    expect(f.trace.slice(-2)).toEqual(['stopped', 'release']);
    expect(f.store.usage).toMatchObject({
      pages: 0,
      leasedTiles: 1,
      cachedBytes: 12,
    });
    f.store.releaseTile(lease.leaseId, 'generation');
    expect(f.store.usage.cachedBytes).toBe(0);
  });

  it('serializes pages globally until the prior codec really stops', async () => {
    const tail = gate();
    const f = fixture([{ tail }, {}]);
    f.add();
    f.add('other');
    f.request();
    f.request(0, 256, 'other');
    await vi.waitFor(() => expect(f.emittedTiles).toBe(4));
    expect(f.inputs).toHaveLength(1);
    tail.release();
    await Promise.all([settled(f.store), settled(f.store, 'other')]);
    expect(f.maximumActive).toBe(1);
    expect(f.trace).toEqual([
      'start',
      'stopped',
      'release',
      'start',
      'stopped',
      'release',
    ]);
  });

  it('keeps a second page pending at 64 leases, then leases its cached tile after a pin is released', async () => {
    const f = fixture([
      { width: 1, height: 64 * 256 },
      { width: 1, height: 256 },
    ]);
    f.add();
    f.request(0, 64 * 256);
    const initial = await settled(f.store);
    expect(initial.tiles).toHaveLength(64);
    f.request();
    f.add('other');
    f.request(0, 256, 'other');
    await vi.waitFor(() => expect(f.released).toBe(2));
    expect(f.store.snapshot('other', 'generation')).toMatchObject({
      state: 'pending',
      tiles: [],
    });
    expect(f.store.usage.leasedTiles).toBe(64);
    f.store.releaseTile(initial.tiles[63]!.leaseId, 'generation');
    expect((await settled(f.store, 'other')).tiles).toHaveLength(1);
    expect(f.inputs).toHaveLength(2);
  });

  it('charges leased pixels independently from PNG bytes', async () => {
    const f = fixture([
      { width: 4096, height: 32 * 256, tileBytes: 1 },
      { width: 4096, height: 256, tileBytes: 1 },
    ]);
    f.add();
    f.request(0, 32 * 256);
    const first = await settled(f.store);
    expect(f.store.usage.leasedPixels).toBe(32 * 1024 * 1024);
    f.request();
    f.add('other');
    f.request(0, 256, 'other');
    await vi.waitFor(() => expect(f.released).toBe(2));
    expect(f.store.snapshot('other', 'generation').state).toBe('pending');
    f.store.releaseTile(first.tiles[31]!.leaseId, 'generation');
    expect((await settled(f.store, 'other')).state).toBe('complete');
    expect(f.store.usage.leasedPixels).toBe(32 * 1024 * 1024);
  });

  it.each([
    { width: 1, height: 65 * 256 },
    { width: 4096, height: 33 * 256 },
  ])(
    'rejects an impossible display window from header metadata before publishing tiles: %o',
    async (scenario) => {
      const f = fixture([scenario]);
      f.add();
      f.request(0, scenario.height);
      const snapshot = await settled(f.store);
      expect(snapshot.error?.code).toBe('limit_exceeded');
      expect(snapshot.tiles).toEqual([]);
      expect(f.emittedTiles).toBe(0);
      expect(f.store.usage.cachedBytes).toBe(0);
    },
  );

  it('rejects payload/metadata disagreement and releases prepared assets after stopping', async () => {
    const f = fixture([{ corruptSize: true }]);
    f.add();
    f.request();
    const snapshot = await settled(f.store);
    expect(snapshot.error?.code).toBe('protocol_error');
    expect(f.store.usage.cachedBytes).toBe(0);
    expect(f.trace).toEqual(['start', 'stopped', 'release']);
  });

  it('bounds requested PNG bytes and invalidates earlier provisional tiles when a window cannot fit', async () => {
    const f = fixture([{ height: 768, tileBytes: 8 * 1024 * 1024 }]);
    f.add();
    f.request(0, 768);
    const failed = await settled(f.store);
    expect(failed.error?.code).toBe('limit_exceeded');
    expect(failed.invalidatedLeaseIds).toHaveLength(2);
    expect(f.store.usage.cachedBytes).toBe(IMAGE_TILE_STORE_LIMITS.cachedBytes);
    for (const id of failed.invalidatedLeaseIds)
      f.store.releaseTile(id, 'generation');
    expect(f.store.usage.cachedBytes).toBe(0);
  });

  it('finishes the old sequential pass and locally replays discarded strips after the window moves', async () => {
    const tail = gate();
    const f = fixture([{ tail }, {}]);
    f.add();
    f.request();
    await vi.waitFor(() => expect(f.emittedTiles).toBe(4));
    f.request(768, 1024);
    expect(f.inputs).toHaveLength(1);
    tail.release();
    const moved = await settled(f.store);
    expect(moved.tiles[0]?.metadata.sourceRect.y).toBe(768);
    expect(f.inputs).toHaveLength(2);
    expect(f.maximumActive).toBe(1);
  });

  it('rejects oversized inputs and unsupported scales without preparing a codec', () => {
    const f = fixture();
    expect(() =>
      f.store.addPage({
        pageId: 'big',
        generation: 'generation',
        format: 'png',
        blob: new Blob([
          new Uint8Array(IMAGE_TILE_STORE_LIMITS.inputBytes + 1),
        ]),
        expectedSize: { width: 1, height: 1 },
      }),
    ).toThrow('8 MiB');
    f.add();
    expect(() => f.request(0, 256, 'page', 2)).toThrow('scale 1');
    expect(f.inputs).toHaveLength(0);
  });

  it('releases a late prepared material lease on cancellation without starting a Worker', async () => {
    const prepared = gate();
    let released = 0;
    let decoded = false;
    const store = new ImageTileStore({
      prepare: async () => {
        await prepared.promise;
        return {
          workerUrl: new URL('blob:https://reader.example/worker'),
          decoder: {
            moduleUrl: 'blob:https://reader.example/decoder',
            wasmBinary: new Uint8Array([1]),
          },
          encoder: {
            moduleUrl: 'blob:https://reader.example/encoder',
            wasmBinary: new Uint8Array([2]),
          },
          release: () => {
            released++;
          },
        };
      },
      decode: () => {
        decoded = true;
        throw new Error('must not start');
      },
    });
    store.addPage({
      pageId: 'page',
      generation: 'generation',
      format: 'png',
      blob: new Blob(['x']),
      expectedSize: { width: 1, height: 256 },
    });
    store.requestWindow({
      pageId: 'page',
      generation: 'generation',
      sourceY: 0,
      sourceEndY: 256,
      denominator: 1,
    });
    const removing = store.removePage('page', 'generation');
    expect(store.usage.activeDecodes).toBe(1);
    prepared.release();
    await removing;
    expect(decoded).toBe(false);
    expect(released).toBe(1);
  });

  it('does not rescan when the same pending window is requested repeatedly during one active pass', async () => {
    const tail = gate();
    const f = fixture([{ tail }]);
    f.add();
    f.request();
    await vi.waitFor(() => expect(f.emittedTiles).toBe(4));
    const lease = f.store.snapshot('page', 'generation').tiles[0]!;
    for (let index = 0; index < 10; index++)
      expect(f.request().tiles[0]?.leaseId).toBe(lease.leaseId);
    tail.release();
    await settled(f.store);
    expect(f.inputs).toHaveLength(1);
  });

  it('does not silently replace an explicitly released display lease for the same window', async () => {
    const f = fixture();
    f.add();
    f.request();
    const first = (await settled(f.store)).tiles[0]!;
    f.store.releaseTile(first.leaseId, 'generation');
    f.store.releaseTile(first.leaseId, 'generation');
    expect(f.store.snapshot('page', 'generation').tiles).toEqual([]);
    expect(f.store.usage).toMatchObject({
      leasedTiles: 0,
      leasedPixels: 0,
      cachedBytes: 12,
    });
    const requestedAgain = f.request();
    expect(requestedAgain.state).toBe('complete');
    expect(requestedAgain.tiles[0]?.png).toBe(first.png);
    expect(requestedAgain.tiles[0]?.leaseId).not.toBe(first.leaseId);
    expect(f.inputs).toHaveLength(1);
  });

  it('replays strips skipped for pinned-byte pressure when a display release occurs before the terminal', async () => {
    const tail = gate();
    const f = fixture([
      { height: 512, tileBytes: 8 * 1024 * 1024 },
      { height: 256, tileBytes: 8 * 1024 * 1024, tail },
      { height: 256, tileBytes: 8 * 1024 * 1024 },
    ]);
    f.add();
    f.request(0, 512);
    const first = await settled(f.store);
    f.request();
    f.add('other');
    f.request(0, 256, 'other');
    await vi.waitFor(() => expect(f.emittedTiles).toBe(3));
    expect(f.store.snapshot('other', 'generation').tiles).toEqual([]);
    f.store.releaseTile(first.tiles[1]!.leaseId, 'generation');
    tail.release();
    expect((await settled(f.store, 'other')).state).toBe('complete');
    expect(f.inputs).toHaveLength(3);
    expect(f.maximumActive).toBe(1);
  });

  it('keeps a blocked completed pass idle until enough pinned bytes, not merely one pin, are released', async () => {
    const f = fixture([{ height: 512, tileBytes: 8 * 1024 * 1024 }]);
    f.add();
    f.request(0, 512);
    const first = await settled(f.store);
    f.add('other');
    f.request(0, 512, 'other');
    await vi.waitFor(() => expect(f.released).toBe(2));
    expect(f.store.snapshot('other', 'generation').state).toBe('pending');
    f.store.releaseTile(first.tiles[0]!.leaseId, 'generation');
    await Promise.resolve();
    await Promise.resolve();
    expect(f.inputs).toHaveLength(2);
    f.store.releaseTile(first.tiles[1]!.leaseId, 'generation');
    expect((await settled(f.store, 'other')).state).toBe('complete');
    expect(f.inputs).toHaveLength(3);
  });

  it('matches codec header dimensions to the raw dimensions of the successful encoded Source result', async () => {
    const f = fixture();
    f.store.addPage({
      pageId: 'page',
      generation: 'generation',
      format: 'png',
      blob: f.blob,
      expectedSize: { width: 16, height: 1023 },
    });
    f.request();
    const failed = await settled(f.store);
    expect(failed.error?.code).toBe('protocol_error');
    expect(failed.tiles).toEqual([]);
    expect(f.emittedTiles).toBe(0);
  });

  it('does not alter a valid active window when a new request fails header-range validation', async () => {
    const f = fixture();
    f.add();
    f.request();
    const first = await settled(f.store);
    expect(() => f.request(2000, 2100)).toThrow('outside the image');
    const unchanged = f.store.snapshot('page', 'generation');
    expect(unchanged.state).toBe('complete');
    expect(unchanged.revision).toBe(first.revision);
    expect(unchanged.tiles[0]?.leaseId).toBe(first.tiles[0]?.leaseId);
  });

  it('enforces the negotiated format-specific dimensions before preparing materials', () => {
    const f = fixture();
    expect(() =>
      f.store.addPage({
        pageId: 'jpeg',
        generation: 'generation',
        format: 'jpeg',
        blob: f.blob,
        expectedSize: { width: 1, height: 65501 },
      }),
    ).toThrow('codec capability');
    expect(() =>
      f.store.addPage({
        pageId: 'png',
        generation: 'generation',
        format: 'png',
        blob: f.blob,
        expectedSize: { width: 4097, height: 1 },
      }),
    ).toThrow('codec capability');
    expect(f.store.usage.pages).toBe(0);
    expect(f.inputs).toHaveLength(0);
  });

  it('supports abortable revision waits and resolves pending waits during clear', async () => {
    const f = fixture();
    f.add();
    const controller = new AbortController();
    const waiting = f.store.waitForChange(
      'page',
      'generation',
      0,
      controller.signal,
    );
    controller.abort(new Error('reader left'));
    await expect(waiting).rejects.toThrow('reader left');
    const closing = f.store.waitForChange('page', 'generation', 0);
    await f.store.clear();
    expect((await closing).state).toBe('failed');
    expect(() => f.add('next')).toThrow('closed');
  });
});
