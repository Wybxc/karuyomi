import {
  IMAGE_RESOURCE_LIMIT,
  openImagePageSchema,
  requestImageWindowSchema,
  waitImageWindowSchema,
  releaseImageTileSchema,
  closeImagePageSchema,
  runtimeErrorMessage,
  type OpenImagePage,
  type ImagePage,
  type RequestImageWindow,
  type WaitImageWindow,
  type ReleaseImageTile,
  type CloseImagePage,
  type ImageWindowSnapshot,
  type ImageResource,
} from '@karuyomi/contracts';
import { ImageWindowState } from '@karuyomi/protocol';
import type { EncodedImageLease } from './image-resources.js';
import {
  ImageTileStore,
  type ImageTileWindowSnapshot,
  type ImageTileLease,
} from './image-tile-store.js';
import { RuntimeFailure, runtimeFailure } from './errors.js';

interface PageOwner {
  readonly descriptor: ImagePage;
  readonly input: EncodedImageLease;
  window: RequestImageWindow | undefined;
  publicationFailed: boolean;
  readonly windowIds: Set<string>;
  closing: Promise<void> | undefined;
}
interface DisplayOwner {
  readonly page: PageOwner;
  readonly lease: ImageTileLease;
  readonly resource: ImageResource;
}

/** Composes Source input, sequential codec work and acknowledged display leases. */
export class ImagePageControl {
  private readonly pages = new Map<string, PageOwner>();
  private readonly inputs = new Map<string, PageOwner>();
  private readonly display = new Map<string, DisplayOwner>();
  private waiters = 0;
  private disposed = false;
  private disposing: Promise<void> | undefined;

  constructor(
    readonly store: ImageTileStore,
    private readonly borrow: (input: OpenImagePage) => EncodedImageLease,
    private readonly urls: Pick<
      typeof URL,
      'createObjectURL' | 'revokeObjectURL'
    > = URL,
  ) {}

  get usage() {
    return Object.freeze({
      ...this.store.usage,
      displayUrls: this.display.size,
      waits: this.waiters,
    });
  }

  open(input: OpenImagePage): ImagePage {
    const request = openImagePageSchema.parse(input);
    if (this.disposed)
      throw new RuntimeFailure('runtime_lost', 'Image page host is disposed');
    const key = JSON.stringify([request.generation, request.resourceId]);
    const existing = this.inputs.get(key);
    if (existing) {
      if (existing.closing)
        throw new RuntimeFailure('cancelled', 'Image page is closing');
      return existing.descriptor;
    }
    if (this.pages.size >= IMAGE_RESOURCE_LIMIT)
      throw new RuntimeFailure('limit_exceeded', 'Image page window is full');
    const lease = this.borrow(request);
    try {
      const descriptor: ImagePage = {
        pageId: crypto.randomUUID(),
        generation: request.generation,
        encoded: Object.freeze({ ...lease.descriptor }),
      };
      this.store.addPage({
        pageId: descriptor.pageId,
        generation: descriptor.generation,
        format: lease.descriptor.mimeType === 'image/png' ? 'png' : 'jpeg',
        blob: lease.blob,
        expectedSize: {
          width: lease.descriptor.rawWidth,
          height: lease.descriptor.rawHeight,
        },
      });
      const page: PageOwner = {
        descriptor,
        input: lease,
        window: undefined,
        publicationFailed: false,
        windowIds: new Set(),
        closing: undefined,
      };
      this.pages.set(descriptor.pageId, page);
      this.inputs.set(key, page);
      return Object.freeze(descriptor);
    } catch (error) {
      lease.release();
      throw error;
    }
  }

  request(input: RequestImageWindow): ImageWindowSnapshot {
    const request = requestImageWindowSchema.parse(input);
    const page = this.page(request.pageId, request.generation);
    if (
      request.sourceY >= page.descriptor.encoded.rawHeight ||
      request.sourceEndY > page.descriptor.encoded.rawHeight
    )
      throw new RuntimeFailure(
        'protocol_error',
        'Image window is outside the encoded page',
      );
    if (page.window?.windowId === request.windowId) {
      if (
        page.window.sourceY !== request.sourceY ||
        page.window.sourceEndY !== request.sourceEndY ||
        page.window.denominator !== request.denominator
      )
        throw new RuntimeFailure(
          'protocol_error',
          'An image window identity cannot change its geometry',
        );
      if (!page.publicationFailed)
        return this.present(
          page,
          this.store.snapshot(request.pageId, request.generation),
        );
    } else {
      if (page.windowIds.has(request.windowId))
        throw new RuntimeFailure(
          'protocol_error',
          'An expired image window identity cannot be reused',
        );
      if (page.windowIds.size >= 10000)
        throw new RuntimeFailure(
          'limit_exceeded',
          'Image window identity budget is exhausted',
        );
    }
    const denominator = request.denominator;
    if (denominator !== 1 && denominator !== 2 && denominator !== 4)
      throw new RuntimeFailure('protocol_error', 'Invalid image scale');
    const snapshot = this.store.requestWindow({
      pageId: request.pageId,
      generation: request.generation,
      sourceY: request.sourceY,
      sourceEndY: request.sourceEndY,
      denominator,
    });
    page.window = { ...request };
    page.publicationFailed = false;
    page.windowIds.add(request.windowId);
    return this.present(page, snapshot);
  }

  async wait(input: WaitImageWindow): Promise<ImageWindowSnapshot> {
    const request = waitImageWindowSchema.parse(input);
    const page = this.page(request.pageId, request.generation);
    this.window(page, request.windowId);
    if (page.publicationFailed)
      throw new RuntimeFailure(
        'source_error',
        'Image display publication failed; request the window again',
        true,
      );
    const current = this.store.snapshot(request.pageId, request.generation);
    if (request.afterRevision > current.revision)
      throw new RuntimeFailure(
        'protocol_error',
        'Image revision is ahead of the host',
      );
    if (current.revision !== request.afterRevision)
      return this.present(page, current);
    if (this.waiters >= 32)
      throw new RuntimeFailure('limit_exceeded', 'Too many image window waits');
    const controller = new AbortController();
    const expired = new RuntimeFailure(
      'timeout',
      'Image window observation timed out',
    );
    const timer = setTimeout(
      () => controller.abort(expired),
      request.timeoutMs ?? 25000,
    );
    this.waiters++;
    try {
      try {
        await this.store.waitForChange(
          request.pageId,
          request.generation,
          request.afterRevision,
          controller.signal,
        );
      } catch (error) {
        if (error !== expired) throw error;
      }
      this.page(request.pageId, request.generation);
      this.window(page, request.windowId);
      if (page.publicationFailed)
        throw new RuntimeFailure(
          'source_error',
          'Image display publication failed; request the window again',
          true,
        );
      // A queued observation may resume after another request released or
      // invalidated its leases. Publish only the current owned snapshot.
      return this.present(
        page,
        this.store.snapshot(request.pageId, request.generation),
      );
    } finally {
      clearTimeout(timer);
      this.waiters--;
    }
  }

  release(input: ReleaseImageTile): { released: true } {
    const request = releaseImageTileSchema.parse(input);
    const entry = this.display.get(request.leaseId);
    if (entry?.resource.generation === request.generation) {
      // The caller has already removed Flutter/cache/native-file ownership.
      this.urls.revokeObjectURL(entry.resource.url);
      this.display.delete(request.leaseId);
      this.store.releaseTile(request.leaseId, request.generation);
    }
    return { released: true };
  }

  async close(input: CloseImagePage): Promise<{ closed: true }> {
    const request = closeImagePageSchema.parse(input);
    const page = this.pages.get(request.pageId);
    if (page?.descriptor.generation === request.generation)
      await this.closePage(page);
    return { closed: true };
  }

  async invalidate(): Promise<void> {
    await Promise.all(
      [...this.pages.values()].map((page) => this.closePage(page)),
    );
  }

  dispose(): Promise<void> {
    if (!this.disposing) {
      this.disposed = true;
      this.disposing = (async () => {
        await this.invalidate();
        // Disposing destroys the entire host; unlike page close this is the final
        // owner of any unacknowledged displays left by a disconnected client.
        for (const entry of [...this.display.values()])
          this.release({
            leaseId: entry.resource.resourceId,
            generation: entry.resource.generation,
          });
        await this.store.clear();
      })();
    }
    return this.disposing;
  }

  private page(pageId: string, generation: string): PageOwner {
    const page = this.pages.get(pageId);
    if (
      this.disposed ||
      !page ||
      page.closing ||
      page.descriptor.generation !== generation
    )
      throw new RuntimeFailure('runtime_lost', 'Image page has expired');
    return page;
  }
  private window(page: PageOwner, windowId: string): void {
    if (page.window?.windowId !== windowId)
      throw new RuntimeFailure('cancelled', 'Image window was replaced');
  }
  private closePage(page: PageOwner): Promise<void> {
    if (!page.closing) {
      page.closing = (async () => {
        const { pageId, generation, encoded } = page.descriptor;
        await this.store.removePage(pageId, generation);
        // Store may allocate a provisional lease between control observations.
        // No display ever received those IDs, so they have no client ACK owner.
        this.releaseUnpublished(page);
        page.input.release();
        this.pages.delete(pageId);
        this.inputs.delete(JSON.stringify([generation, encoded.resourceId]));
      })();
    }
    return page.closing;
  }
  private releaseUnpublished(
    page: PageOwner,
    visible: ReadonlySet<string> = new Set(),
  ): void {
    for (const id of this.store.leaseIds(
      page.descriptor.pageId,
      page.descriptor.generation,
    ))
      if (!this.display.has(id) && !visible.has(id))
        this.store.releaseTile(id, page.descriptor.generation);
  }
  private present(
    page: PageOwner,
    snapshot: ImageTileWindowSnapshot,
  ): ImageWindowSnapshot {
    const window = page.window;
    if (!window)
      throw new RuntimeFailure('protocol_error', 'Image window is missing');
    const visible = new Set(snapshot.tiles.map((tile) => tile.leaseId));
    this.releaseUnpublished(page, visible);
    const created: string[] = [];
    try {
      const tiles = snapshot.tiles.map((lease) => {
        let entry = this.display.get(lease.leaseId);
        if (!entry) {
          const metadata = lease.metadata;
          const resource: ImageResource = {
            resourceId: lease.leaseId,
            generation: snapshot.generation,
            mimeType: 'image/png',
            byteLength: metadata.byteLength,
            width: metadata.width,
            height: metadata.height,
            url: this.urls.createObjectURL(lease.png),
          };
          entry = { page, lease, resource };
          this.display.set(lease.leaseId, entry);
          created.push(lease.leaseId);
        }
        return {
          leaseId: lease.leaseId,
          sessionId: lease.sessionId,
          index: lease.metadata.index,
          sourceRect: lease.metadata.sourceRect,
          denominator: window.denominator,
          provisional: lease.state === 'pending',
          resource: entry.resource,
        };
      });
      const header = snapshot.header;
      return {
        pageId: snapshot.pageId,
        generation: snapshot.generation,
        windowId: window.windowId,
        revision: snapshot.revision,
        state:
          snapshot.state === 'pending'
            ? ImageWindowState.PENDING
            : snapshot.state === 'complete'
              ? ImageWindowState.COMPLETE
              : ImageWindowState.FAILED,
        ...(header
          ? {
              header: {
                width: header.width,
                height: header.height,
                sourceWidth: header.sourceWidth,
                sourceHeight: header.sourceHeight,
                denominator: header.denominator,
              },
            }
          : {}),
        tiles,
        invalidatedLeaseIds: snapshot.invalidatedLeaseIds.filter((id) =>
          this.display.has(id),
        ),
        ...(snapshot.error
          ? { error: runtimeErrorMessage(snapshot.error.toJSON()) }
          : {}),
      };
    } catch (error) {
      page.publicationFailed = true;
      for (const leaseId of created)
        this.release({ leaseId, generation: snapshot.generation });
      // No caller received this batch. Release every new pin, including those
      // whose URL was never constructed, while retaining earlier displays.
      this.releaseUnpublished(page);
      throw runtimeFailure(error);
    }
  }
}
