import {
  ENCODED_IMAGE_BODY_LIMIT,
  ENCODED_IMAGE_WIDTH_LIMIT,
  ENCODED_IMAGE_HEIGHT_LIMIT,
  ENCODED_JPEG_HEIGHT_LIMIT,
} from '@karuyomi/contracts';
import {
  decodeImageTiles,
  type ImageTileOptions,
  type ImageTileEvent,
} from '../../../runtime/image-codec/client.ts';
import type { ImageHeader } from '../../../runtime/image-codec/decoder.ts';
import {
  imageHeaderSchema,
  tileMetadataSchema,
  tileTerminalSchema,
  type ImageTileMetadata,
  type ImageTileTerminal,
} from '../../../runtime/image-codec/worker-protocol.ts';
import type { PreparedImageCodecAssets } from './image-codec-assets.js';
import { RuntimeFailure, runtimeFailure } from './errors.js';

export const IMAGE_TILE_STORE_LIMITS = Object.freeze({
  inputBytes: ENCODED_IMAGE_BODY_LIMIT,
  tileBytes: 8 * 1024 * 1024,
  cachedBytes: 16 * 1024 * 1024,
  leasedTiles: 64,
  leasedPixels: 32 * 1024 * 1024,
});
export interface ImageTileDecodeSession extends AsyncIterable<ImageTileEvent> {
  readonly completion: Promise<ImageTileTerminal>;
  cancel(): Promise<void>;
}
export interface ImageTileStoreDependencies {
  prepare(
    format: 'png' | 'jpeg',
    signal: AbortSignal,
  ): Promise<PreparedImageCodecAssets>;
  decode?(options: ImageTileOptions): ImageTileDecodeSession;
}
export interface ImageTilePage {
  pageId: string;
  generation: string;
  format: 'png' | 'jpeg';
  /** Already matched to the successful Source response; the caller owns its lease. */
  blob: Blob;
  /** Raw dimensions parsed from the owned encoded Source output, before orientation. */
  expectedSize: { width: number; height: number };
}
export interface ImageTileWindow {
  pageId: string;
  generation: string;
  /** Half-open coordinates in the original encoded image, before downsampling. */
  sourceY: number;
  sourceEndY: number;
  denominator: 1 | 2 | 4;
}
export interface ImageTileLease {
  readonly leaseId: string;
  readonly sessionId: string;
  readonly metadata: ImageTileMetadata;
  readonly png: Blob;
  readonly state: 'pending' | 'complete';
}
export interface ImageTileWindowSnapshot {
  readonly pageId: string;
  readonly generation: string;
  readonly revision: number;
  readonly state: 'pending' | 'complete' | 'failed';
  readonly header: ImageHeader | null;
  readonly tiles: readonly ImageTileLease[];
  /** Revoke these display resources, then acknowledge through releaseTile(). */
  readonly invalidatedLeaseIds: readonly string[];
  readonly error: RuntimeFailure | null;
}
interface WindowDemand extends ImageTileWindow {
  released: Set<string>;
}
interface PageOwner {
  pageId: string;
  generation: string;
  format: 'png' | 'jpeg';
  blob: Blob | undefined;
  expectedSize: { readonly width: number; readonly height: number };
  requirement: ImageTileMetadata[] | undefined;
  window: WindowDemand | undefined;
  headers: Map<number, ImageHeader>;
  revision: number;
  state: ImageTileWindowSnapshot['state'];
  error: RuntimeFailure | undefined;
  workRequested: boolean;
  closed: boolean;
  waiters: Set<(snapshot: ImageTileWindowSnapshot) => void>;
}
interface CachedTile {
  key: string;
  page: PageOwner;
  denominator: number;
  sessionId: string;
  metadata: ImageTileMetadata;
  png: Blob;
  committed: boolean;
  invalidated: boolean;
  leaseId: string | undefined;
  used: number;
}
interface ActiveDecode {
  page: PageOwner;
  sessionId: string;
  denominator: 1 | 2 | 4;
  controller: AbortController;
  done: Promise<void>;
  header: ImageHeader | undefined;
  nextIndex: number;
  nextRow: number;
  observed: Map<number, ImageTileMetadata>;
}

/** The host owns encoded PNG caching and display leases, never URLs or native files. */
export class ImageTileStore {
  private readonly pages = new Map<string, PageOwner>();
  private readonly cache = new Map<string, CachedTile>();
  private readonly leases = new Map<string, CachedTile>();
  private active: ActiveDecode | undefined;
  private bytes = 0;
  private pixels = 0;
  private sequence = 0;
  private clock = 0;
  private closing: Promise<void> | undefined;

  constructor(private readonly dependencies: ImageTileStoreDependencies) {}

  get usage() {
    return Object.freeze({
      cachedBytes: this.bytes,
      leasedTiles: this.leases.size,
      leasedPixels: this.pixels,
      activeDecodes: this.active ? 1 : 0,
      pages: this.pages.size,
    });
  }

  addPage(input: ImageTilePage): void {
    if (this.closing)
      throw new RuntimeFailure('runtime_lost', 'Image tile store is closed');
    this.id(input.pageId);
    this.id(input.generation);
    if (
      !(input.blob instanceof Blob) ||
      input.blob.size < 1 ||
      input.blob.size > IMAGE_TILE_STORE_LIMITS.inputBytes
    )
      throw new RuntimeFailure('limit_exceeded', 'Codec input exceeds 8 MiB');
    if (input.format !== 'png' && input.format !== 'jpeg')
      throw new RuntimeFailure('unsupported_capability', 'Unknown image codec');
    const heightLimit =
      input.format === 'jpeg'
        ? ENCODED_JPEG_HEIGHT_LIMIT
        : ENCODED_IMAGE_HEIGHT_LIMIT;
    if (
      !input.expectedSize ||
      !Number.isSafeInteger(input.expectedSize.width) ||
      input.expectedSize.width < 1 ||
      input.expectedSize.width > ENCODED_IMAGE_WIDTH_LIMIT ||
      !Number.isSafeInteger(input.expectedSize.height) ||
      input.expectedSize.height < 1 ||
      input.expectedSize.height > heightLimit
    )
      throw new RuntimeFailure(
        'limit_exceeded',
        'Encoded image dimensions exceed the codec capability',
      );
    const key = this.pageKey(input.pageId, input.generation);
    if (this.pages.has(key))
      throw new RuntimeFailure('protocol_error', 'Image page already exists');
    this.pages.set(key, {
      pageId: input.pageId,
      generation: input.generation,
      format: input.format,
      blob: input.blob,
      expectedSize: Object.freeze({ ...input.expectedSize }),
      requirement: undefined,
      window: undefined,
      headers: new Map(),
      revision: 0,
      state: 'pending',
      error: undefined,
      workRequested: false,
      closed: false,
      waiters: new Set(),
    });
  }

  /** Replacing a window does not revoke tiles still pinned by a display owner. */
  requestWindow(input: ImageTileWindow): ImageTileWindowSnapshot {
    const page = this.page(input.pageId, input.generation);
    if (
      !Number.isSafeInteger(input.sourceY) ||
      !Number.isSafeInteger(input.sourceEndY) ||
      input.sourceY < 0 ||
      input.sourceEndY <= input.sourceY ||
      input.sourceEndY >
        (page.format === 'jpeg'
          ? ENCODED_JPEG_HEIGHT_LIMIT
          : ENCODED_IMAGE_HEIGHT_LIMIT) ||
      ![1, 2, 4].includes(input.denominator)
    )
      throw new RuntimeFailure('protocol_error', 'Invalid image tile window');
    if (page.format === 'png' && input.denominator !== 1)
      throw new RuntimeFailure(
        'unsupported_capability',
        'PNG requires scale 1',
      );
    const previous = page.window;
    const unchanged =
      previous?.denominator === input.denominator &&
      previous.sourceY === input.sourceY &&
      previous.sourceEndY === input.sourceEndY;
    const window: WindowDemand = { ...input, released: new Set() };
    const header = page.headers.get(input.denominator);
    if (header) this.checkWindow(window, header);
    if (!unchanged) page.requirement = undefined;
    page.window = window;
    page.error = undefined;
    page.state = 'pending';
    this.refresh(page);
    page.workRequested = this.needsDecode(page);
    this.notify(page);
    this.pump();
    return this.describe(page);
  }

  snapshot(pageId: string, generation: string): ImageTileWindowSnapshot {
    return this.describe(this.page(pageId, generation));
  }

  waitForChange(
    pageId: string,
    generation: string,
    revision: number,
    signal?: AbortSignal,
  ): Promise<ImageTileWindowSnapshot> {
    const page = this.page(pageId, generation);
    signal?.throwIfAborted();
    if (!Number.isSafeInteger(revision) || revision < 0)
      throw new RuntimeFailure('protocol_error', 'Invalid image revision');
    if (page.revision !== revision) return Promise.resolve(this.describe(page));
    return new Promise((resolve, reject) => {
      const receive = (snapshot: ImageTileWindowSnapshot) => {
        signal?.removeEventListener('abort', abort);
        page.waiters.delete(receive);
        resolve(snapshot);
      };
      const abort = () => {
        page.waiters.delete(receive);
        reject(signal?.reason);
      };
      page.waiters.add(receive);
      signal?.addEventListener('abort', abort, { once: true });
    });
  }

  /** Includes pins outside the current window and pins awaiting invalidation ACK. */
  leaseIds(pageId: string, generation: string): readonly string[] {
    return [...this.leases].flatMap(([id, entry]) =>
      entry.page.pageId === pageId && entry.page.generation === generation
        ? [id]
        : [],
    );
  }

  /** Call only after the matching Blob URL/file and decoded display cache stop using it. */
  releaseTile(leaseId: string, generation: string): void {
    const entry = this.leases.get(leaseId);
    if (!entry || entry.page.generation !== generation) return;
    this.leases.delete(leaseId);
    if (entry.page.window && this.wanted(entry, entry.page.window))
      entry.page.window.released.add(entry.key);
    this.pixels -= entry.metadata.width * entry.metadata.height;
    entry.leaseId = undefined;
    if (entry.invalidated) this.bytes -= entry.png.size;
    for (const page of this.pages.values()) {
      if (page.closed) continue;
      if (page === entry.page && page.error) {
        // Failed pages remain observable until close. Removing an invalidated
        // display pin changes their snapshot just as a new tile would.
        this.notify(page);
        continue;
      }
      if (!page.window || page.error) continue;
      this.refresh(page);
      page.workRequested = this.needsDecode(page);
      this.notify(page);
    }
    this.pump();
  }

  /** The caller may release the encoded input owner only after this promise settles. */
  async removePage(pageId: string, generation: string): Promise<void> {
    const page = this.pages.get(this.pageKey(pageId, generation));
    if (!page) return;
    page.closed = true;
    page.workRequested = false;
    page.error = new RuntimeFailure('cancelled', 'Image page was released');
    const active = this.active?.page === page ? this.active : undefined;
    active?.controller.abort(page.error);
    await active?.done;
    this.invalidate((entry) => entry.page === page);
    page.blob = undefined;
    page.headers.clear();
    page.requirement = undefined;
    page.window = undefined;
    page.state = 'failed';
    this.notify(page);
    this.pages.delete(this.pageKey(pageId, generation));
  }

  clear(): Promise<void> {
    if (!this.closing) {
      this.closing = Promise.all(
        [...this.pages.values()].map((page) =>
          this.removePage(page.pageId, page.generation),
        ),
      ).then(() => {});
    }
    return this.closing;
  }

  private id(value: string): void {
    if (typeof value !== 'string' || !value.length || value.length > 200)
      throw new RuntimeFailure('protocol_error', 'Invalid image page identity');
  }
  private pageKey(pageId: string, generation: string): string {
    return JSON.stringify([generation, pageId]);
  }
  private page(pageId: string, generation: string): PageOwner {
    const page = this.pages.get(this.pageKey(pageId, generation));
    if (!page || page.closed)
      throw new RuntimeFailure('runtime_lost', 'Image page has expired');
    return page;
  }
  private tileKey(page: PageOwner, denominator: number, index: number): string {
    return JSON.stringify([page.generation, page.pageId, denominator, index]);
  }
  private wanted(entry: CachedTile, window: WindowDemand): boolean {
    return (
      entry.denominator === window.denominator &&
      entry.metadata.sourceRect.y < window.sourceEndY &&
      entry.metadata.sourceRect.y + entry.metadata.sourceRect.height >
        window.sourceY
    );
  }
  private entries(page: PageOwner): CachedTile[] {
    const window = page.window;
    return window
      ? [...this.cache.values()]
          .filter((entry) => entry.page === page && this.wanted(entry, window))
          .sort((a, b) => a.metadata.index - b.metadata.index)
      : [];
  }
  private covers(page: PageOwner, entries: CachedTile[]): boolean {
    const window = page.window;
    const header = window && page.headers.get(window.denominator);
    if (!window || !header) return false;
    let y = window.sourceY;
    const end = Math.min(window.sourceEndY, header.sourceHeight);
    for (const entry of entries) {
      if (entry.metadata.sourceRect.y > y) return false;
      y = Math.max(
        y,
        entry.metadata.sourceRect.y + entry.metadata.sourceRect.height,
      );
      if (y >= end) return true;
    }
    return false;
  }
  private cachedCoverage(page: PageOwner): boolean {
    return this.covers(page, this.entries(page));
  }
  private canRetain(page: PageOwner): boolean {
    const window = page.window;
    if (!window || !page.requirement) return true;
    const required = page.requirement.filter(
      (metadata) =>
        !window.released.has(
          this.tileKey(page, window.denominator, metadata.index),
        ),
    );
    const otherPins = [...this.leases.values()].filter(
      (entry) =>
        entry.invalidated || entry.page !== page || !this.wanted(entry, window),
    );
    return (
      otherPins.length + required.length <=
        IMAGE_TILE_STORE_LIMITS.leasedTiles &&
      otherPins.reduce((sum, entry) => sum + entry.png.size, 0) +
        required.reduce((sum, metadata) => sum + metadata.byteLength, 0) <=
        IMAGE_TILE_STORE_LIMITS.cachedBytes &&
      otherPins.reduce(
        (sum, entry) => sum + entry.metadata.width * entry.metadata.height,
        0,
      ) +
        required.reduce(
          (sum, metadata) => sum + metadata.width * metadata.height,
          0,
        ) <=
        IMAGE_TILE_STORE_LIMITS.leasedPixels
    );
  }
  private needsDecode(page: PageOwner): boolean {
    return (
      !this.cachedCoverage(page) &&
      this.canRetain(page) &&
      !(
        this.active?.page === page &&
        this.active.denominator === page.window?.denominator
      )
    );
  }
  private refresh(page: PageOwner): void {
    if (page.closed || page.error) return;
    const entries = this.entries(page);
    for (const entry of entries) {
      entry.used = ++this.clock;
      if (
        !entry.leaseId &&
        !page.window?.released.has(entry.key) &&
        this.leases.size < IMAGE_TILE_STORE_LIMITS.leasedTiles &&
        this.pixels + entry.metadata.width * entry.metadata.height <=
          IMAGE_TILE_STORE_LIMITS.leasedPixels
      ) {
        entry.leaseId = `image-tile-lease-${++this.sequence}`;
        this.leases.set(entry.leaseId, entry);
        this.pixels += entry.metadata.width * entry.metadata.height;
      }
    }
    const leased = entries.filter((entry) => entry.leaseId);
    page.state =
      this.covers(page, leased) && leased.every((entry) => entry.committed)
        ? 'complete'
        : 'pending';
  }
  private describe(page: PageOwner): ImageTileWindowSnapshot {
    return {
      pageId: page.pageId,
      generation: page.generation,
      revision: page.revision,
      state: page.state,
      header: page.window
        ? (page.headers.get(page.window.denominator) ?? null)
        : null,
      tiles: this.entries(page).flatMap((entry): ImageTileLease[] =>
        entry.leaseId
          ? [
              {
                leaseId: entry.leaseId,
                sessionId: entry.sessionId,
                metadata: entry.metadata,
                png: entry.png,
                state: entry.committed ? 'complete' : 'pending',
              },
            ]
          : [],
      ),
      invalidatedLeaseIds: [...this.leases].flatMap(([leaseId, entry]) =>
        entry.page === page && entry.invalidated ? [leaseId] : [],
      ),
      error: page.error ?? null,
    };
  }
  private notify(page: PageOwner): void {
    page.revision++;
    const snapshot = this.describe(page);
    for (const waiter of [...page.waiters]) waiter(snapshot);
  }
  private checkWindow(window: WindowDemand, header: ImageHeader): void {
    if (window.sourceY >= header.sourceHeight)
      throw new RuntimeFailure('protocol_error', 'Window is outside the image');
    const rows = 256 * header.denominator;
    const count =
      Math.floor(
        (Math.min(window.sourceEndY, header.sourceHeight) - 1) / rows,
      ) -
      Math.floor(window.sourceY / rows) +
      1;
    const firstRow = Math.floor(window.sourceY / rows) * 256;
    const lastRow = Math.min(
      header.height,
      (Math.floor(
        (Math.min(window.sourceEndY, header.sourceHeight) - 1) / rows,
      ) +
        1) *
        256,
    );
    if (
      count > IMAGE_TILE_STORE_LIMITS.leasedTiles ||
      (lastRow - firstRow) * header.width > IMAGE_TILE_STORE_LIMITS.leasedPixels
    )
      throw new RuntimeFailure(
        'limit_exceeded',
        'Requested tile window exceeds its display budget',
      );
  }
  private pump(): void {
    if (this.active || this.closing) return;
    const page = [...this.pages.values()].find(
      (candidate) =>
        !candidate.closed && !candidate.error && candidate.workRequested,
    );
    if (!page?.window || !page.blob) return;
    page.workRequested = false;
    const run: ActiveDecode = {
      page,
      sessionId: `image-codec-session-${++this.sequence}`,
      denominator: page.window.denominator,
      controller: new AbortController(),
      done: Promise.resolve(),
      header: undefined,
      nextIndex: 0,
      nextRow: 0,
      observed: new Map(),
    };
    this.active = run;
    run.done = this.run(run);
  }
  private cacheTile(
    run: ActiveDecode,
    event: Extract<ImageTileEvent, { kind: 'tile' }>,
  ): void {
    const { kind: _kind, png: _png, ...value } = event;
    const metadata = tileMetadataSchema.parse(value);
    const header = run.header;
    if (
      !header ||
      metadata.id !== `${run.sessionId}:${metadata.index}` ||
      metadata.index !== run.nextIndex ||
      metadata.y !== run.nextRow ||
      metadata.width !== header.width ||
      metadata.height !== Math.min(256, header.height - run.nextRow) ||
      metadata.sourceRect.y !== metadata.y * header.denominator ||
      metadata.sourceRect.width !== header.sourceWidth ||
      metadata.sourceRect.height !==
        Math.min(
          metadata.height * header.denominator,
          header.sourceHeight - metadata.sourceRect.y,
        ) ||
      !(event.png instanceof Blob) ||
      event.png.type !== 'image/png' ||
      event.png.size !== metadata.byteLength ||
      event.png.size > IMAGE_TILE_STORE_LIMITS.tileBytes
    )
      throw new RuntimeFailure(
        'protocol_error',
        'Invalid image tile payload or geometry',
      );
    run.nextIndex++;
    run.nextRow += metadata.height;
    run.observed.set(metadata.index, metadata);
    const page = run.page;
    const window = page.window;
    const key = this.tileKey(page, run.denominator, metadata.index);
    const candidate: CachedTile = {
      key,
      page,
      denominator: run.denominator,
      sessionId: run.sessionId,
      metadata: Object.freeze({
        ...metadata,
        sourceRect: Object.freeze(metadata.sourceRect),
      }),
      png: event.png,
      committed: false,
      invalidated: false,
      leaseId: undefined,
      used: ++this.clock,
    };
    if (!window || !this.wanted(candidate, window)) return;
    // Account the requested window even if old display pins prevent its retention.
    const known = new Map(
      this.entries(page).map((entry) => [entry.metadata.index, entry.metadata]),
    );
    for (const [index, item] of run.observed)
      if (
        item.sourceRect.y < window.sourceEndY &&
        item.sourceRect.y + item.sourceRect.height > window.sourceY
      )
        known.set(index, item);
    const sizes = [...known.values()];
    if (
      sizes.reduce((sum, item) => sum + item.byteLength, 0) >
        IMAGE_TILE_STORE_LIMITS.cachedBytes ||
      sizes.reduce((sum, item) => sum + item.width * item.height, 0) >
        IMAGE_TILE_STORE_LIMITS.leasedPixels ||
      sizes.length > IMAGE_TILE_STORE_LIMITS.leasedTiles
    )
      throw new RuntimeFailure(
        'limit_exceeded',
        'Requested tile window exceeds its cache budget',
      );
    if (this.cache.has(key)) return;
    while (this.bytes + event.png.size > IMAGE_TILE_STORE_LIMITS.cachedBytes) {
      const evict = [...this.cache.values()]
        .filter((entry) => !entry.leaseId)
        .sort((a, b) => a.used - b.used)[0];
      if (!evict) return;
      this.cache.delete(evict.key);
      this.bytes -= evict.png.size;
    }
    this.cache.set(key, candidate);
    this.bytes += event.png.size;
    this.refresh(page);
    this.notify(page);
  }
  private invalidate(predicate: (entry: CachedTile) => boolean): void {
    for (const entry of this.cache.values()) {
      if (!predicate(entry)) continue;
      this.cache.delete(entry.key);
      entry.invalidated = true;
      if (!entry.leaseId) this.bytes -= entry.png.size;
    }
  }
  private async run(run: ActiveDecode): Promise<void> {
    let assets: PreparedImageCodecAssets | undefined;
    let session: ImageTileDecodeSession | undefined;
    let failure: RuntimeFailure | undefined;
    const page = run.page;
    try {
      assets = await this.dependencies.prepare(
        page.format,
        run.controller.signal,
      );
      run.controller.signal.throwIfAborted();
      const blob = page.blob;
      if (!blob)
        throw new RuntimeFailure('cancelled', 'Image page was released');
      session = (this.dependencies.decode ?? decodeImageTiles)({
        workerUrl: assets.workerUrl,
        decoder: assets.decoder,
        encoder: assets.encoder,
        blob,
        format: page.format,
        denominator: run.denominator,
        requestId: run.sessionId,
        generation: page.generation,
        signal: run.controller.signal,
      });
      let terminal: ImageTileTerminal | undefined;
      for await (const event of session) {
        if (terminal)
          throw new RuntimeFailure(
            'protocol_error',
            'Image data follows its terminal',
          );
        if (event.kind === 'terminal') {
          const { kind: _kind, ...value } = event;
          terminal = tileTerminalSchema.parse(value);
        } else if (!page.closed && !run.controller.signal.aborted) {
          if (event.kind === 'header') {
            const { kind: _kind, ...value } = event;
            const header = imageHeaderSchema.parse(value);
            const previous = page.headers.values().next().value;
            if (
              run.header ||
              header.format !== page.format ||
              header.denominator !== run.denominator ||
              header.width !==
                Math.ceil(header.sourceWidth / run.denominator) ||
              header.height !==
                Math.ceil(header.sourceHeight / run.denominator) ||
              header.rowBytes !== header.width * 4 ||
              page.expectedSize.width !== header.sourceWidth ||
              page.expectedSize.height !== header.sourceHeight ||
              (previous &&
                (previous.sourceWidth !== header.sourceWidth ||
                  previous.sourceHeight !== header.sourceHeight))
            )
              throw new RuntimeFailure(
                'protocol_error',
                'Inconsistent image header',
              );
            run.header = Object.freeze(header);
            page.headers.set(run.denominator, run.header);
            if (page.window?.denominator === run.denominator)
              this.checkWindow(page.window, header);
            this.notify(page);
          } else this.cacheTile(run, event);
        }
      }
      const completed = await session.completion;
      if (
        !terminal ||
        completed.status !== terminal.status ||
        completed.invalidatesTiles !== terminal.invalidatesTiles
      )
        throw new RuntimeFailure(
          'protocol_error',
          'Image codec terminal is missing or inconsistent',
        );
      if (run.controller.signal.aborted) throw run.controller.signal.reason;
      if (terminal.invalidatesTiles)
        throw new RuntimeFailure(
          terminal.status === 'cancelled' ? 'cancelled' : 'source_error',
          terminal.error?.message ?? 'Image codec did not complete',
        );
      if (!run.header || run.nextRow !== run.header.height)
        throw new RuntimeFailure(
          'protocol_error',
          'Image codec did not deliver all rows',
        );
    } catch (error) {
      failure = runtimeFailure(error);
      if (session) {
        try {
          await session.cancel();
        } catch (cleanup) {
          failure = new RuntimeFailure(
            'runtime_lost',
            `Image codec cancellation failed: ${runtimeFailure(cleanup).message}`,
          );
        }
      }
    } finally {
      // completion resolves only after the actual Worker has terminated. Never
      // revoke executable materials while a cancelled Worker can still use them.
      if (session) {
        try {
          await session.completion;
        } catch (error) {
          failure = runtimeFailure(error);
        }
      }
      try {
        assets?.release();
      } catch (error) {
        failure = runtimeFailure(error);
      }
      if (
        !failure &&
        !page.closed &&
        page.window?.denominator === run.denominator
      ) {
        const window = page.window;
        page.requirement = [...run.observed.values()].filter(
          (metadata) =>
            metadata.sourceRect.y < window.sourceEndY &&
            metadata.sourceRect.y + metadata.sourceRect.height > window.sourceY,
        );
        if (
          page.requirement.reduce((sum, item) => sum + item.byteLength, 0) >
          IMAGE_TILE_STORE_LIMITS.cachedBytes
        )
          failure = new RuntimeFailure(
            'limit_exceeded',
            'Requested tile window exceeds its cache budget',
          );
      }
      if (failure || page.closed) {
        this.invalidate((entry) => entry.sessionId === run.sessionId);
        page.error = failure ?? page.error;
        page.state = 'failed';
        page.workRequested = false;
      } else {
        for (const entry of this.cache.values())
          if (entry.sessionId === run.sessionId) entry.committed = true;
        this.refresh(page);
      }
      this.active = undefined;
      // Recompute after the true terminal: a release during the pass may have
      // made previously discarded strips affordable. Otherwise wait for pins.
      if (!page.error && !page.closed)
        page.workRequested = this.needsDecode(page);
      this.notify(page);
      this.pump();
    }
  }
}
