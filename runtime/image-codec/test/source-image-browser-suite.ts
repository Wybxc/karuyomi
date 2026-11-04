/// <reference lib="dom" />
/** Synthetic Source-output ownership, real channel and codec Worker; no Source/Reader claim. */
import { z } from 'zod';
import { imageDimensionsFromData } from 'image-dimensions';
import {
  processedImageSchema,
  IMAGE_CHUNK_LIMIT,
} from '../../../packages/contracts/src/index.ts';
import { ImageSink } from '../../../packages/runtime-host/src/image-channel.ts';
import { ImageResourceStore } from '../../../packages/runtime-host/src/image-resources.ts';
import {
  ImageTileStore,
  IMAGE_TILE_STORE_LIMITS,
  type ImageTileWindowSnapshot,
} from '../tile-store.ts';
import { createImageCodecAssetProvider } from '../assets.ts';
import {
  VerifiedLoader,
  sha256,
} from '../../../packages/runtime-host/src/verified-loader.ts';
import { RuntimeFailure } from '../../../packages/runtime-host/src/errors.ts';
import { decodeImageTiles, type ImageTileSession } from '../client.ts';
import {
  imageHeaderSchema,
  type ImageTileTerminal,
} from '../worker-protocol.ts';

const tileReferenceSchema = z.object({
  index: z.int().nonnegative(),
  x: z.literal(0),
  y: z.int().nonnegative(),
  width: z.int().positive(),
  height: z.int().positive(),
  sourceRect: z.object({
    x: z.literal(0),
    y: z.int().nonnegative(),
    width: z.int().positive(),
    height: z.int().positive(),
  }),
  byteLength: z.int().positive(),
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
});
const fixtureSchema = z.object({
  name: z.enum(['png', 'jpeg']),
  format: z.enum(['png', 'jpeg']),
  path: z.string().regex(/^\/fixtures\/[a-z]+\.[a-z]+$/),
  encodedBytes: z.int().positive(),
  encodedSha256: z.string().regex(/^[a-f0-9]{64}$/),
  header: imageHeaderSchema,
  tiles: z.array(tileReferenceSchema).nonempty(),
});
const configSchema = z.object({
  schemaVersion: z.literal(1),
  runId: z.string().uuid(),
  materialVersion: z.string(),
  codecSource: z.json(),
  scope: z.record(z.string(), z.string()),
  imageCodecs: z.array(
    z.object({
      logicalName: z.string(),
      path: z.string(),
      sha256: z.string(),
      size: z.int().positive(),
      contentType: z.string(),
    }),
  ),
  cases: z.array(fixtureSchema).length(2),
});
type Fixture = z.infer<typeof fixtureSchema>;
type TraceEvent = { sequence: number; event: string; detail: unknown };
function check(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}
function element(id: string): HTMLElement {
  const value = document.getElementById(id);
  check(value, 'Missing page element: ' + id);
  return value;
}
const controls = {
  run: element('run'),
  close: element('close'),
  status: element('status'),
  log: element('log'),
  preview: element('preview'),
};
const log = (message: string) => {
  controls.log.textContent += message + '\n';
};
const config = configSchema.parse(await (await fetch('/config.json')).json());
const provider = createImageCodecAssetProvider(
  config.imageCodecs,
  new VerifiedLoader(location.origin),
);
const fixtures = new Map<string, Uint8Array<ArrayBuffer>>();
const cleanupTasks = new Set<() => Promise<void>>();
let running = false;
let closing = false;
let runController: AbortController | undefined;
let runCompletion: Promise<void> | undefined;

async function fixtureBytes(fixture: Fixture, signal: AbortSignal) {
  let bytes = fixtures.get(fixture.name);
  if (!bytes) {
    const response = await fetch(fixture.path, { signal });
    check(response.ok, 'Fixture transfer failed');
    bytes = new Uint8Array(await response.arrayBuffer());
    check(bytes.length === fixture.encodedBytes, 'Fixture transfer length');
    check(
      (await sha256(bytes)) === fixture.encodedSha256,
      'Fixture transfer SHA-256',
    );
    fixtures.set(fixture.name, bytes);
  }
  return bytes;
}

function createOwners(signal: AbortSignal) {
  const trace: TraceEvent[] = [];
  const record = (event: string, detail: unknown = null) =>
    trace.push({ sequence: trace.length + 1, event, detail });
  const counters = {
    sourceReceipts: 0,
    createdWorkers: 0,
    terminatedWorkers: 0,
    activeWorkers: 0,
    maximumWorkers: 0,
    activeModules: 0,
    preparedModules: 0,
    releasedModules: 0,
    displayUrls: 0,
  };
  const terminals: ImageTileTerminal[] = [];
  const sessions = new Set<ImageTileSession>();
  const source = new ImageResourceStore();
  const tiles = new ImageTileStore({
    prepare: async (format, abort) => {
      const assets = await provider.prepare(format, abort);
      counters.activeModules++;
      counters.preparedModules++;
      record('modules-prepared', { format });
      let released = false;
      return {
        ...assets,
        release: () => {
          if (released) return;
          released = true;
          assets.release();
          counters.activeModules--;
          counters.releasedModules++;
          record('modules-released');
        },
      };
    },
    decode: (options) => {
      const session = decodeImageTiles(options, {
        createWorker: (url) => {
          const worker = new Worker(url, { type: 'module' });
          counters.createdWorkers++;
          counters.activeWorkers++;
          counters.maximumWorkers = Math.max(
            counters.maximumWorkers,
            counters.activeWorkers,
          );
          record('worker-created', { requestId: options.requestId });
          let terminated = false;
          const terminate = worker.terminate.bind(worker);
          worker.terminate = () => {
            if (terminated) return;
            terminated = true;
            terminate();
            counters.activeWorkers--;
            counters.terminatedWorkers++;
            record('worker-terminated', { requestId: options.requestId });
          };
          return worker;
        },
      });
      sessions.add(session);
      void session.completion.then((terminal) => {
        terminals.push(terminal);
        record('codec-terminal', terminal);
        sessions.delete(session);
      });
      return session;
    },
  });
  const generation = crypto.randomUUID();
  const pageId = crypto.randomUUID();
  const leases = new Set<string>();
  const visible: { image: HTMLImageElement; url: string }[] = [];
  let input: Blob | undefined;
  let removed = false;
  let cleanupCompletion: Promise<void> | undefined;
  let sourceBytes = 0;
  const sourceIds = new Set<string>();
  function observe(snapshot: ImageTileWindowSnapshot) {
    for (const tile of snapshot.tiles) leases.add(tile.leaseId);
    for (const id of snapshot.invalidatedLeaseIds) leases.add(id);
    const usage = tiles.usage;
    check(
      usage.cachedBytes <= IMAGE_TILE_STORE_LIMITS.cachedBytes,
      'Encoded PNG tile cache budget',
    );
    check(
      usage.leasedPixels <= IMAGE_TILE_STORE_LIMITS.leasedPixels,
      'Display pixel lease budget',
    );
    check(
      usage.leasedTiles <= IMAGE_TILE_STORE_LIMITS.leasedTiles,
      'Display tile count budget',
    );
    check(counters.activeWorkers <= 1, 'Only one codec Worker per tile store');
    return snapshot;
  }
  async function waitFor(
    predicate: (snapshot: ImageTileWindowSnapshot) => boolean,
  ) {
    let snapshot = observe(tiles.snapshot(pageId, generation));
    while (!predicate(snapshot)) {
      signal.throwIfAborted();
      if (snapshot.state === 'failed')
        throw snapshot.error ?? new Error('Tile store failed');
      snapshot = observe(
        await tiles.waitForChange(
          pageId,
          generation,
          snapshot.revision,
          signal,
        ),
      );
    }
    return snapshot;
  }
  function stopDisplay() {
    for (const { image, url } of visible.splice(0)) {
      image.removeAttribute('src');
      image.remove();
      URL.revokeObjectURL(url);
      counters.displayUrls--;
    }
  }
  function releaseTiles() {
    stopDisplay();
    for (const id of leases) tiles.releaseTile(id, generation);
    leases.clear();
  }
  async function receive(fixture: Fixture, bytes: Uint8Array) {
    signal.throwIfAborted();
    counters.sourceReceipts++;
    sourceBytes = bytes.length;
    const collector = source.create(generation);
    sourceIds.add(collector.resourceId);
    const channel = new MessageChannel();
    collector.attach(channel.port1);
    let cancelled: RuntimeFailure | undefined;
    const sink = new ImageSink(channel.port2, collector.resourceId, (error) => {
      cancelled = error;
    });
    try {
      const handle = sink.open();
      for (let offset = 0; offset < bytes.length; offset += IMAGE_CHUNK_LIMIT) {
        signal.throwIfAborted();
        await sink.write(
          handle,
          bytes.subarray(offset, offset + IMAGE_CHUNK_LIMIT),
        );
      }
      const descriptor = processedImageSchema.parse(
        JSON.parse(await sink.close(handle)),
      );
      check(
        !cancelled,
        'Real image channel must acknowledge the complete body',
      );
      check(
        descriptor.byteLength === bytes.length,
        'Source byte receipt length',
      );
      check(
        Object.keys(descriptor).sort().join(',') ===
          'byteLength,generation,resourceId',
        'Source receipt is opaque',
      );
      // No real Java/Source invocation: only its opaque successful return is simulated.
      const resource = await collector.publish(descriptor);
      record('simulated-java-result-published', resource);
      input = await (await fetch(resource.url, { signal })).blob();
      const header = imageDimensionsFromData(
        new Uint8Array(await input.slice(0, 128 * 1024).arrayBuffer()),
      );
      check(
        header && header.type === fixture.format,
        'Client identifies the format',
      );
      check(
        header.width === fixture.header.sourceWidth &&
          header.height === fixture.header.sourceHeight,
        'Client identifies raw geometry',
      );
      tiles.addPage({
        pageId,
        generation,
        format: fixture.format,
        blob: input,
        expectedSize: { width: header.width, height: header.height },
      });
      check(
        source.snapshot.bytes === bytes.length &&
          source.snapshot.resources === 1,
        'Source encoded owner remains charged until client closes',
      );
      record('client-page-opened', source.snapshot);
    } finally {
      channel.port2.close();
    }
  }
  function request(sourceY: number, sourceEndY: number) {
    return observe(
      tiles.requestWindow({
        pageId,
        generation,
        sourceY,
        sourceEndY,
        denominator: 1,
      }),
    );
  }
  async function remove() {
    if (removed) return;
    record('remove-page-start', {
      usage: tiles.usage,
      source: source.snapshot,
    });
    const pending = tiles.removePage(pageId, generation);
    if (input)
      check(
        source.snapshot.bytes === sourceBytes,
        'Source owner stays charged while removePage waits for real terminal',
      );
    await pending;
    removed = true;
    check(
      counters.activeWorkers === 0 && counters.activeModules === 0,
      'removePage resolves after real Worker termination and material release',
    );
    record('remove-page-settled', {
      usage: tiles.usage,
      source: source.snapshot,
    });
  }
  function cleanup(): Promise<void> {
    cleanupCompletion ??= performCleanup();
    return cleanupCompletion;
  }
  async function performCleanup() {
    try {
      await remove();
    } finally {
      await Promise.all([...sessions].map((session) => session.cancel()));
      await tiles.clear();
      releaseTiles();
      source.release([...sourceIds][0] ?? '', generation);
      input = undefined;
      record('source-owner-released', source.snapshot);
      source.clear(
        new RuntimeFailure('cancelled', 'Browser ownership scenario ended'),
      );
      cleanupTasks.delete(cleanup);
    }
    check(
      source.snapshot.resources === 0 && source.snapshot.bytes === 0,
      'Every opaque Source resource released',
    );
    check(
      Object.values(tiles.usage).every((value) => value === 0),
      'Every tile cache, pin and active decoder released',
    );
    check(
      counters.activeWorkers === 0 &&
        counters.activeModules === 0 &&
        counters.displayUrls === 0,
      'Every real Worker, material owner and display URL closed',
    );
    check(
      counters.createdWorkers === counters.terminatedWorkers &&
        counters.preparedModules === counters.releasedModules,
      'Every logical Worker/module owner has a matching close',
    );
  }
  cleanupTasks.add(cleanup);
  return {
    source,
    tiles,
    counters,
    terminals,
    trace,
    pageId,
    generation,
    receive,
    request,
    waitFor,
    observe,
    remove,
    cleanup,
    releaseTiles,
    failure(error: unknown) {
      return new Error(error instanceof Error ? error.message : String(error), {
        cause: {
          counters,
          terminals,
          trace,
          source: source.snapshot,
          tiles: tiles.usage,
        },
      });
    },
    async verifyTiles(fixture: Fixture, snapshot: ImageTileWindowSnapshot) {
      const values = [];
      for (const tile of snapshot.tiles) {
        const reference = fixture.tiles.find(
          (item) => item.index === tile.metadata.index,
        );
        check(reference, 'Requested tile has a Node oracle');
        const {
          id: _id,
          mimeType: _mime,
          provisional: _provisional,
          ...geometry
        } = tile.metadata;
        const { sha256: expectedHash, ...expectedGeometry } = reference;
        check(
          JSON.stringify(geometry) === JSON.stringify(expectedGeometry),
          'Tile geometry matches independent Node module run',
        );
        const hash = await sha256(new Uint8Array(await tile.png.arrayBuffer()));
        check(
          hash === expectedHash,
          'Tile PNG bytes match independent Node module run',
        );
        const image = document.createElement('img');
        const url = URL.createObjectURL(tile.png);
        counters.displayUrls++;
        visible.push({ image, url });
        image.src = url;
        image.alt = fixture.name + ' tile ' + tile.metadata.index;
        controls.preview.append(image);
        await image.decode();
        check(
          image.naturalWidth === reference.width &&
            image.naturalHeight === reference.height,
          'Browser decodes only the bounded PNG strip',
        );
        values.push({
          index: tile.metadata.index,
          leaseId: tile.leaseId,
          sessionId: tile.sessionId,
          sha256: hash,
          byteLength: tile.png.size,
        });
      }
      check(values.length > 0, 'Window delivered bounded tiles');
      return values;
    },
  };
}

async function windows(fixture: Fixture, signal: AbortSignal) {
  const owners = createOwners(signal);
  const windows = [];
  try {
    check(
      fixture.header.sourceWidth * fixture.header.sourceHeight >
        16 * 1024 * 1024,
      'Fixture exceeds old full-image pixel limit',
    );
    await owners.receive(fixture, await fixtureBytes(fixture, signal));
    const height = fixture.header.sourceHeight;
    const middle = Math.floor(height / 2 / 256) * 256;
    for (const [slot, y] of [
      ['first', 0],
      ['last', height - 1],
      ['middle', middle],
      ['first-again', 0],
    ] as const) {
      const createdBefore = owners.counters.createdWorkers;
      owners.request(y, Math.min(y + 256, height));
      const provisional = await owners.waitFor(
        (value) => value.tiles.length > 0,
      );
      const activeWorkersBeforeRepeat = owners.counters.createdWorkers;
      const activeRepeat = owners.request(y, Math.min(y + 256, height));
      check(
        activeRepeat.tiles.length === provisional.tiles.length &&
          activeRepeat.tiles.every(
            (tile, index) =>
              tile.leaseId === provisional.tiles[index]?.leaseId &&
              tile.png === provisional.tiles[index]?.png,
          ),
        'Repeating a live window retains its existing tile leases',
      );
      check(
        owners.counters.createdWorkers === activeWorkersBeforeRepeat,
        'Repeating a live window never starts a duplicate codec pass',
      );
      const snapshot = await owners.waitFor(
        (value) => value.state === 'complete',
      );
      check(
        owners.counters.activeWorkers === 0,
        'Complete window follows real codec terminal',
      );
      const values = await owners.verifyTiles(fixture, snapshot);
      const stable = owners.request(y, Math.min(y + 256, height));
      check(
        stable.state === 'complete',
        'Repeated complete window is immediately available',
      );
      check(
        stable.tiles.length === snapshot.tiles.length &&
          stable.tiles.every(
            (tile, index) =>
              tile.leaseId === snapshot.tiles[index]?.leaseId &&
              tile.png === snapshot.tiles[index]?.png,
          ),
        'Same window retains the same leases and owned PNG Blobs',
      );
      check(
        owners.counters.createdWorkers ===
          createdBefore + (slot === 'first-again' ? 0 : 1),
        'Uncached window runs one real local pass; cached first window reuses tiles',
      );
      windows.push({
        slot,
        sourceY: y,
        tiles: values,
        decodePasses: owners.counters.createdWorkers - createdBefore,
        usage: owners.tiles.usage,
      });
      owners.releaseTiles();
    }
    check(
      owners.counters.sourceReceipts === 1 &&
        owners.counters.createdWorkers === 3,
      'Reverse last-to-middle rescan uses one retained Source Blob, without reacquisition',
    );
    check(
      owners.terminals.every(
        (terminal) =>
          terminal.status === 'complete' &&
          !terminal.forced &&
          !terminal.invalidatesTiles,
      ),
      'Each successful scan closes normally',
    );
    await owners.cleanup();
    return {
      name: fixture.name + '-owned-windows',
      passed: true,
      windows,
      counters: owners.counters,
      terminals: owners.terminals,
      trace: owners.trace,
      finalUsage: owners.tiles.usage,
      finalSource: owners.source.snapshot,
    };
  } catch (error) {
    throw owners.failure(error);
  } finally {
    await owners.cleanup();
  }
}

async function tailFailure(fixture: Fixture, signal: AbortSignal) {
  const owners = createOwners(signal);
  try {
    const original = await fixtureBytes(fixture, signal);
    await owners.receive(
      fixture,
      original.slice(0, -(fixture.format === 'png' ? 12 : 2)),
    );
    owners.request(0, 256);
    const delivered = await owners.waitFor(
      (snapshot) => snapshot.tiles.length > 0,
    );
    check(
      delivered.tiles.some((tile) => tile.state === 'pending'),
      'Tail test delivered a provisional tile before stream completion',
    );
    const ids = delivered.tiles.map((tile) => tile.leaseId);
    const failed = await owners.waitFor(
      (snapshot) => snapshot.state === 'failed',
    );
    check(
      failed.tiles.length === 0 &&
        ids.every((id) => failed.invalidatedLeaseIds.includes(id)),
      'Bad tail invalidates every delivered provisional lease',
    );
    check(
      owners.tiles.usage.leasedTiles >= ids.length &&
        owners.tiles.usage.cachedBytes > 0,
      'Invalidated display owners remain charged until explicit release',
    );
    check(
      owners.terminals.at(-1)?.status === 'failed' &&
        owners.terminals.at(-1)?.forced === false,
      'Real codec detects tail failure and closes normally',
    );
    const invalidatedUsage = owners.tiles.usage;
    await owners.cleanup();
    return {
      name: fixture.name + '-tail-invalidates-leases',
      passed: true,
      invalidatedLeaseIds: ids,
      invalidatedUsage,
      counters: owners.counters,
      terminals: owners.terminals,
      trace: owners.trace,
      finalUsage: owners.tiles.usage,
      finalSource: owners.source.snapshot,
    };
  } catch (error) {
    throw owners.failure(error);
  } finally {
    await owners.cleanup();
  }
}

async function cancelDuringDecode(fixture: Fixture, signal: AbortSignal) {
  const owners = createOwners(signal);
  try {
    await owners.receive(fixture, await fixtureBytes(fixture, signal));
    owners.request(0, 256);
    const provisional = await owners.waitFor(
      (snapshot) => snapshot.tiles.length > 0,
    );
    check(
      owners.counters.activeWorkers === 1 && provisional.state === 'pending',
      'Cancellation starts while real codec Worker is active',
    );
    await owners.remove();
    const terminal = owners.terminals.at(-1);
    check(
      terminal?.status === 'cancelled' && terminal.forced === false,
      'removePage awaits cooperative real Worker cancellation',
    );
    check(
      owners.source.snapshot.bytes === fixture.encodedBytes,
      'Encoded Source owner stays charged after codec terminal until its owner releases it',
    );
    await owners.cleanup();
    const terminalIndex = owners.trace.findIndex(
      (event) => event.event === 'codec-terminal',
    );
    const removedIndex = owners.trace.findIndex(
      (event) => event.event === 'remove-page-settled',
    );
    const borrowIndex = owners.trace.findIndex(
      (event) => event.event === 'source-owner-released',
    );
    check(
      terminalIndex >= 0 &&
        terminalIndex < removedIndex &&
        removedIndex < borrowIndex,
      'Real terminal precedes removePage resolution, then opaque Source resource release',
    );
    return {
      name: fixture.name + '-remove-page-terminal-order',
      passed: true,
      counters: owners.counters,
      terminals: owners.terminals,
      trace: owners.trace,
      finalUsage: owners.tiles.usage,
      finalSource: owners.source.snapshot,
    };
  } catch (error) {
    throw owners.failure(error);
  } finally {
    await owners.cleanup();
  }
}

controls.run.addEventListener('click', () => {
  runCompletion = run();
  void runCompletion.catch((error: unknown) => {
    controls.status.textContent = '验收入口失败';
    log(
      error instanceof Error ? (error.stack ?? error.message) : String(error),
    );
  });
});
async function run() {
  if (running || closing) return;
  running = true;
  controls.run.setAttribute('disabled', '');
  controls.status.textContent = '验收中';
  const controller = new AbortController();
  runController = controller;
  const deadline = setTimeout(
    () => controller.abort(new Error('Ownership suite exceeded five minutes')),
    5 * 60 * 1000,
  );
  const cases: unknown[] = [];
  let passed = true;
  try {
    for (const fixture of config.cases) {
      for (const scenario of [windows, tailFailure, cancelDuringDecode]) {
        controller.signal.throwIfAborted();
        const name = fixture.name + '/' + scenario.name;
        log('开始 ' + name);
        try {
          const result = await scenario(fixture, controller.signal);
          cases.push(result);
          log('通过 ' + name);
        } catch (error) {
          passed = false;
          const failure = {
            name,
            passed: false,
            error:
              error instanceof Error
                ? {
                    name: error.name,
                    message: error.message,
                    stack: error.stack,
                    cause: error.cause,
                  }
                : String(error),
          };
          cases.push(failure);
          log(JSON.stringify(failure));
        }
      }
    }
  } catch (error) {
    passed = false;
    cases.push({
      name: 'suite-interrupted',
      passed: false,
      error: String(error),
    });
  } finally {
    clearTimeout(deadline);
    await Promise.all([...cleanupTasks].map((cleanup) => cleanup()));
    const report = {
      schemaVersion: 1,
      runId: config.runId,
      passed,
      materialVersion: config.materialVersion,
      codecSource: config.codecSource,
      scope: config.scope,
      environment: {
        userAgent: navigator.userAgent,
        origin: location.origin,
        crossOriginIsolated,
      },
      cases,
    };
    const response = await fetch('/report', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(report),
    });
    check(response.ok, 'Ownership report saved');
    controls.status.textContent = passed
      ? '全部通过，报告已保存'
      : '存在失败，报告已保存';
    log(JSON.stringify({ passed, cases: cases.length }));
    running = false;
    runController = undefined;
    if (!closing) controls.run.removeAttribute('disabled');
  }
}
controls.close.addEventListener('click', () => {
  void (async () => {
    if (closing) return;
    closing = true;
    runController?.abort(
      new Error('Browser operator closed ownership verification'),
    );
    await runCompletion?.catch(() => {});
    await Promise.all([...cleanupTasks].map((cleanup) => cleanup()));
    const response = await fetch('/shutdown', { method: 'POST' });
    check(response.ok, 'Verification server shutdown');
    controls.status.textContent = '服务已关闭';
  })();
});
log(
  '准备就绪；点击运行。此页只验证合成 Source 处理后正文与真实 codec Worker 的所有权链。',
);
