/* Browser raster backend for Android bitmap APIs. No website-specific image transforms. */
import {
  bool,
  integer,
  number,
  object,
  optionalText,
  text,
  workerScope,
} from './bridge-common.js';
import { imageDimensionsFromData } from 'image-dimensions';
import {
  layoutText,
  textDirection,
  TEXT_UNITS,
  TEXT_WORK_BYTES,
  type TextAlignment,
} from './text-layout.js';
type Rect = [number, number, number, number];
type Matrix = [number, number, number, number, number, number];
interface Paint {
  color: number;
  strokeWidth: number;
  join: CanvasLineJoin;
  cap: CanvasLineCap;
  align: CanvasTextAlign;
  flags: number;
  fontStyle: number;
  size: number;
  family: string;
  scaleX: number;
  style: 'FILL' | 'STROKE' | 'FILL_AND_STROKE';
  direction: 'ltr' | 'rtl' | 'auto';
}
const operations = [
  'create',
  'closeDecoder',
  'recycle',
  'measure',
  'layout',
  'pixels',
  'raw',
  'putPixels',
  'putRaw',
  'color',
  'erase',
  'drawBitmap',
  'roundRect',
  'text',
  'font',
  'encode',
  'openDecoder',
  'nextFrame',
  'decode',
] as const;
interface GraphicsRequest {
  op: (typeof operations)[number];
  id: number;
  width: number;
  height: number;
  f16: boolean;
  rect: Rect | undefined;
  matrix: Matrix | undefined;
  paint: Paint;
  text: string;
  bytes: string;
  color: number;
  source: number;
  src: Rect;
  dst: Rect;
  rx: number;
  ry: number;
  x: number;
  y: number;
  format: string;
  quality: number;
  bounds: boolean;
  sample: number;
  densityScale: number;
  alignment: TextAlignment;
  spacingMult: number;
  spacingAdd: number;
  includePad: boolean;
}
function rect(value: unknown): Rect {
  if (!Array.isArray(value) || value.length !== 4)
    throw Error('Expected four rectangle coordinates');
  return [
    number(value[0]),
    number(value[1]),
    number(value[2]),
    number(value[3]),
  ];
}
function matrix(value: unknown): Matrix {
  if (!Array.isArray(value) || value.length !== 6)
    throw Error('Expected six matrix coordinates');
  return [
    number(value[0]),
    number(value[1]),
    number(value[2]),
    number(value[3]),
    number(value[4]),
    number(value[5]),
  ];
}
function paintValue(value: unknown): Paint {
  const data = value === undefined ? {} : object(value);
  const join = optionalText(data.join) ?? 'MITER',
    cap = optionalText(data.cap) ?? 'BUTT',
    align = optionalText(data.align) ?? 'LEFT';
  if (join !== 'MITER' && join !== 'ROUND' && join !== 'BEVEL')
    throw Error('Unknown line join');
  if (cap !== 'BUTT' && cap !== 'ROUND' && cap !== 'SQUARE')
    throw Error('Unknown line cap');
  if (align !== 'LEFT' && align !== 'RIGHT' && align !== 'CENTER')
    throw Error('Unknown text alignment');
  const style = optionalText(data.style) ?? 'FILL';
  if (style !== 'FILL' && style !== 'STROKE' && style !== 'FILL_AND_STROKE')
    throw Error('Unknown paint style');
  const direction = optionalText(data.direction) ?? 'auto';
  if (direction !== 'ltr' && direction !== 'rtl' && direction !== 'auto')
    throw Error('Unknown text direction');
  return {
    direction,
    color: data.color === undefined ? -16777216 : number(data.color),
    strokeWidth: data.strokeWidth === undefined ? 1 : number(data.strokeWidth),
    join: { MITER: 'miter', ROUND: 'round', BEVEL: 'bevel' }[
      join
    ] as CanvasLineJoin,
    cap: { BUTT: 'butt', ROUND: 'round', SQUARE: 'square' }[
      cap
    ] as CanvasLineCap,
    align: { LEFT: 'left', RIGHT: 'right', CENTER: 'center' }[
      align
    ] as CanvasTextAlign,
    flags: data.flags === undefined ? 0 : integer(data.flags, 0, 2147483647),
    fontStyle: data.fontStyle === undefined ? 0 : integer(data.fontStyle, 0, 3),
    size: data.size === undefined ? 12 : number(data.size),
    family: optionalText(data.family) ?? 'sans-serif',
    scaleX: data.scaleX === undefined ? 1 : number(data.scaleX),
    style,
  };
}
export function parseGraphicsRequest(value: unknown): GraphicsRequest {
  const data = object(value),
    op = operations.find((operation) => operation === data.op);
  if (!op) throw Error('Unknown raster operation');
  const alignment = optionalText(data.alignment) ?? 'ALIGN_NORMAL';
  if (
    alignment !== 'ALIGN_NORMAL' &&
    alignment !== 'ALIGN_OPPOSITE' &&
    alignment !== 'ALIGN_CENTER'
  )
    throw Error('Unknown layout alignment');
  const numeric = (key: string, fallback = 0) =>
    data[key] === undefined ? fallback : number(data[key]);
  return {
    op,
    id: data.id === undefined ? 0 : integer(data.id, 1),
    width: numeric('width'),
    height: numeric('height'),
    f16: data.f16 === undefined ? false : bool(data.f16),
    rect: data.rect === undefined ? undefined : rect(data.rect),
    matrix: data.matrix === undefined ? undefined : matrix(data.matrix),
    paint: paintValue(data.paint),
    text: optionalText(data.text) ?? '',
    bytes: optionalText(data.bytes) ?? '',
    color: numeric('color'),
    source: numeric('source'),
    src: data.src === undefined ? [0, 0, 0, 0] : rect(data.src),
    dst: data.dst === undefined ? [0, 0, 0, 0] : rect(data.dst),
    rx: numeric('rx'),
    ry: numeric('ry'),
    x: numeric('x'),
    y: numeric('y'),
    format: optionalText(data.format) ?? '',
    quality: numeric('quality'),
    bounds: data.bounds === undefined ? false : bool(data.bounds),
    sample: numeric('sample', 1),
    densityScale: numeric('densityScale', 1),
    alignment,
    spacingMult: numeric('spacingMult', 1),
    spacingAdd: numeric('spacingAdd'),
    includePad: data.includePad === undefined ? true : bool(data.includePad),
  };
}
interface BitmapLease {
  readonly id: number;
}
interface Surface {
  creator: GraphicsContext;
  owner?: WeakRef<BitmapLease>;
  canvas: OffscreenCanvas;
  ctx: OffscreenCanvasRenderingContext2D;
  f16: boolean;
  release: () => void;
  pins: number;
  retired: boolean;
}
interface Decoder {
  decoder: ImageDecoder;
  index: number;
  hdr: boolean;
  width: number;
  height: number;
  release: () => void;
  busy: boolean;
  closed: boolean;
}
interface GraphicsContext {
  requestId: string;
  generation: string;
  failure?: Error;
  ended: boolean;
}
interface ByteHandle {
  context: GraphicsContext;
  maximum: number;
  length: number;
  offset: number;
  parts: Uint8Array<ArrayBuffer>[];
  releases: (() => void)[];
  data?: Uint8Array<ArrayBuffer>;
  persistent: boolean;
  detached: boolean;
  pins: number;
  closed: boolean;
  javaRelease?: () => void;
}
export interface GraphicsLimits {
  totalBytes: number;
  rasterBytes: number;
  maxPixels: number;
}
interface FloatCanvasContext extends OffscreenCanvasRenderingContext2D {
  getContextAttributes(): { colorType?: string };
}
function floatContext(
  context: OffscreenCanvasRenderingContext2D,
): context is FloatCanvasContext {
  return (
    'getContextAttributes' in context &&
    typeof context.getContextAttributes === 'function'
  );
}
// The Float16 ImageData overload is implemented by supporting browsers but is
// not yet present in TypeScript's WebWorker declarations. Keep this one API
// boundary explicit; its use still requires the runtime's Float16 feature check.
interface FloatImageDataConstructor {
  new (
    data: Float16Array<ArrayBuffer>,
    width: number,
    height: number,
    options: { pixelFormat: 'rgba-float16'; colorSpace: 'display-p3' },
  ): ImageData;
}
declare global {
  var teaGraphicsSync:
    ReturnType<typeof createGraphicsBridge>['teaGraphicsSync'] | undefined;
  var teaGraphicsAsync:
    ReturnType<typeof createGraphicsBridge>['teaGraphicsAsync'] | undefined;
  var teaGraphicsBegin:
    ReturnType<typeof createGraphicsBridge>['teaGraphicsBegin'] | undefined;
  var teaGraphicsCancel:
    ReturnType<typeof createGraphicsBridge>['teaGraphicsCancel'] | undefined;
  var teaGraphicsEnd:
    ReturnType<typeof createGraphicsBridge>['teaGraphicsEnd'] | undefined;
  var teaGraphicsBytesOpen:
    ReturnType<typeof createGraphicsBridge>['teaGraphicsBytesOpen'] | undefined;
  var teaGraphicsBytesWrite:
    | ReturnType<typeof createGraphicsBridge>['teaGraphicsBytesWrite']
    | undefined;
  var teaGraphicsBytesRead:
    ReturnType<typeof createGraphicsBridge>['teaGraphicsBytesRead'] | undefined;
  var teaGraphicsBytesClose:
    | ReturnType<typeof createGraphicsBridge>['teaGraphicsBytesClose']
    | undefined;
  var teaGraphicsBytesDetach:
    | ReturnType<typeof createGraphicsBridge>['teaGraphicsBytesDetach']
    | undefined;
  var teaGraphicsBitmapClaim:
    | ReturnType<typeof createGraphicsBridge>['teaGraphicsBitmapClaim']
    | undefined;
  var teaGraphicsBitmapId:
    ReturnType<typeof createGraphicsBridge>['teaGraphicsBitmapId'] | undefined;
  var teaGraphicsBitmapRecycle:
    | ReturnType<typeof createGraphicsBridge>['teaGraphicsBitmapRecycle']
    | undefined;
  var teaGraphicsSnapshot:
    ReturnType<typeof createGraphicsBridge>['teaGraphicsSnapshot'] | undefined;
}

const scope = workerScope();
export function createGraphicsBridge(options: Partial<GraphicsLimits> = {}) {
  const surfaces = new Map<number, Surface>(),
    decoders = new Map<number, Decoder>(),
    handles = new Map<string, ByteHandle>(),
    fonts = new Map<string, { face: FontFace; release: () => void }>();
  // The bridge must never strongly retain an adopted Java Bitmap owner.
  const leases = new WeakMap<object, number>();
  const finalization =
    typeof WeakRef === 'function' && typeof FinalizationRegistry === 'function'
      ? new FinalizationRegistry<number>((id) => retire(id))
      : undefined;
  const limits = {
    totalBytes: 256 * 1024 * 1024,
    rasterBytes: 192 * 1024 * 1024,
    maxPixels: 16 * 1024 * 1024,
    ...options,
  };
  for (const value of Object.values(limits)) integer(value, 1);
  const CHUNK = 65536,
    BODY = 64 * 1024 * 1024,
    HEADER = 1024 * 1024;
  let current: GraphicsContext | undefined,
    totalBytes = 0,
    rasterBytes = 0;
  let next = 1,
    font = 0;
  let scratchRelease: (() => void) | undefined;
  let pending = 0;
  let loadingFonts = 0,
    openingDecoders = 0;
  function limit(message: string): Error {
    return Object.assign(Error(message), { code: 'limit_exceeded' });
  }
  function unsupported(message: string): Error {
    return Object.assign(Error(message), { code: 'unsupported_capability' });
  }
  function reserve(bytes: number, raster = 0): () => void {
    integer(bytes);
    integer(raster);
    if (
      totalBytes + bytes > limits.totalBytes ||
      rasterBytes + raster > limits.rasterBytes
    )
      reapSurfaces();
    if (
      totalBytes + bytes > limits.totalBytes ||
      rasterBytes + raster > limits.rasterBytes
    )
      throw Object.assign(Error('Graphics aggregate memory budget exceeded'), {
        code: 'limit_exceeded',
      });
    totalBytes += bytes;
    rasterBytes += raster;
    let live = true;
    return () => {
      if (live) {
        live = false;
        totalBytes -= bytes;
        rasterBytes -= raster;
      }
    };
  }
  function context(): GraphicsContext {
    if (!current || current.ended)
      throw Error('Graphics operation context is missing');
    check(current);
    return current;
  }
  function check(owner: GraphicsContext) {
    if (owner.failure) throw owner.failure;
    if (owner.ended)
      throw Object.assign(Error('Graphics operation ended'), {
        code: 'cancelled',
      });
  }
  function dimensions(width: number, height: number): void {
    integer(width, 1);
    integer(height, 1);
    if (width * height > limits.maxPixels)
      throw Object.assign(Error('Graphics pixel budget exceeded'), {
        code: 'limit_exceeded',
      });
  }
  const teaGraphicsBegin = (identity: {
    requestId: string;
    generation: string;
  }) => {
    if ((current && !current.ended) || pending)
      throw Error('Graphics operation overlap');
    const requestId = text(identity.requestId),
      generation = text(identity.generation);
    reapSurfaces();
    // One JSO block and its Java byte[] copy can coexist during a transfer.
    scratchRelease = reserve(2 * CHUNK);
    current = {
      requestId,
      generation,
      ended: false,
    };
  };
  const sameContext = (requestId: string, generation: string) =>
    current?.requestId === requestId && current.generation === generation;
  const teaGraphicsCancel = (requestId: string, generation: string) => {
    if (sameContext(requestId, generation) && current)
      current.failure ??= Object.assign(Error('Graphics operation cancelled'), {
        code: 'cancelled',
        name: 'AbortError',
      });
  };
  const teaGraphicsEnd = (requestId: string, generation: string) => {
    if (!sameContext(requestId, generation) || !current) return;
    current.ended = true;
    // Unadopted results were never returned as Java Bitmap objects. Live
    // adopted Bitmaps may outlive this operation and must remain usable.
    for (const [id, entry] of surfaces)
      if (entry.creator === current && !entry.owner) retire(id);
    for (const [id, entry] of handles)
      if (entry.context === current && (!entry.persistent || !entry.detached))
        closeBytes(id);
    if (!pending) {
      scratchRelease?.();
      scratchRelease = undefined;
    }
  };
  function byteHandle(id: string): ByteHandle {
    const entry = handles.get(id);
    if (!entry || entry.closed) throw Error('Unknown graphics byte handle');
    if (!entry.persistent && entry.context !== context())
      throw Error('Stale graphics byte handle');
    return entry;
  }
  const teaGraphicsBytesOpen = (maximum: number) => {
    const owner = context();
    integer(maximum, 1, BODY);
    if (handles.size >= 64) throw limit('Graphics byte handle limit exceeded');
    const id = 'graphics-bytes-' + next++;
    handles.set(id, {
      context: owner,
      maximum,
      length: 0,
      offset: 0,
      parts: [],
      releases: [],
      persistent: false,
      detached: false,
      pins: 0,
      closed: false,
    });
    return id;
  };
  const teaGraphicsBytesWrite = (id: string, bytes: Uint8Array) => {
    const entry = byteHandle(id);
    if (
      !(bytes instanceof Uint8Array) ||
      bytes.length < 1 ||
      bytes.length > CHUNK ||
      entry.data ||
      entry.detached ||
      entry.length + bytes.length > entry.maximum
    )
      throw Error('Invalid graphics upload block');
    const release = reserve(bytes.length);
    try {
      entry.parts.push(Uint8Array.from(bytes));
      entry.releases.push(release);
      entry.length += bytes.length;
    } catch (error) {
      release();
      throw error;
    }
  };
  function dataFor(entry: ByteHandle): Uint8Array<ArrayBuffer> {
    if (entry.detached) throw Error('Graphics bytes belong to a Java frame');
    if (entry.data) return entry.data;
    const release = reserve(entry.length);
    try {
      const data = new Uint8Array(entry.length);
      let offset = 0;
      for (const part of entry.parts) {
        data.set(part, offset);
        offset += part.length;
      }
      for (const previous of entry.releases) previous();
      entry.releases = [release];
      entry.parts = [];
      entry.data = data;
      return data;
    } catch (error) {
      release();
      throw error;
    }
  }
  const teaGraphicsBytesRead = (
    id: string,
    maximum: number,
  ): Uint8Array<ArrayBuffer> | null => {
    integer(maximum, 1, CHUNK);
    const entry = byteHandle(id),
      data = dataFor(entry);
    if (entry.offset === entry.length) return null;
    const end = Math.min(entry.length, entry.offset + maximum),
      copy = data.slice(entry.offset, end);
    entry.offset = end;
    return copy;
  };
  function releaseHandle(id: string, entry: ByteHandle) {
    if (!entry.closed || entry.pins) return;
    handles.delete(id);
    for (const release of entry.releases) release();
    entry.javaRelease?.();
    entry.parts = [];
    delete entry.data;
  }
  function closeBytes(id: string) {
    const entry = handles.get(id);
    if (!entry) return;
    entry.closed = true;
    releaseHandle(id, entry);
  }
  const teaGraphicsBytesClose = closeBytes;
  const teaGraphicsBytesDetach = (id: string) => {
    const entry = byteHandle(id);
    if (!entry.persistent || entry.offset !== entry.length)
      throw Error('Incomplete graphics frame transfer');
    entry.detached = true;
    delete entry.data;
    entry.parts = [];
    for (const release of entry.releases) release();
    entry.releases = [];
  };
  function outputBytes(
    data: Uint8Array<ArrayBuffer>,
    persistent = false,
  ): { bytes: string; length: number } {
    const id = teaGraphicsBytesOpen(Math.max(1, data.length)),
      entry = byteHandle(id);
    try {
      entry.releases.push(reserve(data.length));
      if (persistent) entry.javaRelease = reserve(data.length, data.length);
      entry.data = data;
      entry.length = data.length;
      entry.persistent = persistent;
      return { bytes: id, length: data.length };
    } catch (error) {
      closeBytes(id);
      throw error;
    }
  }
  function inputBytes(id: string) {
    const entry = byteHandle(id);
    return dataFor(entry);
  }
  function borrow(id: string) {
    const entry = byteHandle(id),
      data = dataFor(entry);
    entry.pins++;
    let live = true;
    return {
      data,
      release: () => {
        if (live) {
          live = false;
          entry.pins--;
          releaseHandle(id, entry);
        }
      },
    };
  }
  const teaGraphicsSnapshot = () => ({
    totalBytes,
    rasterBytes,
    surfaces: surfaces.size,
    decoders: decoders.size,
    fonts: fonts.size,
    handles: handles.size,
  });
  const color = (c: number) =>
    `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${(c >>> 24) / 255})`;
  function surface(id: number): Surface {
    const s = surfaces.get(id);
    if (!s) throw Error('Unknown or recycled bitmap ' + id);
    return s;
  }
  function create(width: number, height: number, f16 = false) {
    dimensions(width, height);
    if (surfaces.size >= 64) reapSurfaces();
    if (surfaces.size >= 64)
      throw limit('Bitmap count exceeds graphics budget');
    const size = width * height * (f16 ? 8 : 4),
      release = reserve(size, size);
    let canvas: OffscreenCanvas | undefined;
    try {
      if (typeof OffscreenCanvas === 'undefined')
        throw unsupported('Canvas 2D unavailable');
      canvas = new OffscreenCanvas(width, height);
      const ctx = canvas.getContext('2d', {
        willReadFrequently: true,
        ...(f16 ? { colorType: 'float16', colorSpace: 'display-p3' } : {}),
      });
      if (!ctx) throw unsupported('Canvas 2D unavailable');
      if (
        f16 &&
        (!floatContext(ctx) ||
          ctx.getContextAttributes().colorType !== 'float16')
      )
        throw unsupported('Float16 canvas unavailable');
      const id = next++;
      surfaces.set(id, {
        creator: context(),
        canvas,
        ctx,
        f16,
        release,
        pins: 0,
        retired: false,
      });
      return { id, width, height };
    } catch (error) {
      if (canvas) canvas.width = canvas.height = 0;
      release();
      throw error;
    }
  }
  function reapSurfaces() {
    for (const [id, entry] of surfaces)
      if (entry.owner && entry.owner.deref() === undefined) retire(id);
  }
  const teaGraphicsBitmapClaim = (id: number): BitmapLease => {
    const owner = context(),
      entry = surface(integer(id, 1, 2147483647));
    if (!finalization)
      throw unsupported(
        'Bitmap lifetime requires WeakRef and FinalizationRegistry',
      );
    if (entry.creator !== owner || entry.owner)
      throw Error('Bitmap ownership already claimed or stale');
    const lease = Object.freeze({ id });
    leases.set(lease, id);
    entry.owner = new WeakRef(lease);
    finalization.register(lease, id, lease);
    return lease;
  };
  const teaGraphicsBitmapId = (lease: unknown): number => {
    const token: object = object(lease);
    const id = leases.get(token);
    if (id === undefined || surfaces.get(id)?.owner?.deref() !== token)
      throw Error('Unknown or recycled bitmap owner');
    // deref keeps the actual owner alive through this JS job. An asynchronous
    // encode additionally pins its surface before yielding to browser work.
    return id;
  };
  const teaGraphicsBitmapRecycle = (lease: unknown): void => {
    const token: object = object(lease);
    const id = leases.get(token);
    if (id === undefined) return;
    leases.delete(token);
    finalization?.unregister(token);
    retire(id);
  };
  function retire(id: number) {
    const s = surfaces.get(id);
    if (!s) return;
    const owner = s.owner?.deref();
    if (owner) {
      leases.delete(owner);
      finalization?.unregister(owner);
    }
    surfaces.delete(id);
    s.retired = true;
    releaseSurface(s);
  }
  function releaseSurface(s: Surface) {
    if (s.retired && !s.pins) {
      s.canvas.width = s.canvas.height = 0;
      s.release();
    }
  }
  function closeDecoder(id: number) {
    const d = decoders.get(id);
    if (!d) return;
    decoders.delete(id);
    d.closed = true;
    d.decoder.close();
    if (!d.busy) d.release();
  }
  function paint(ctx: OffscreenCanvasRenderingContext2D, p: Paint) {
    ctx.globalAlpha = 1;
    ctx.fillStyle = ctx.strokeStyle = color(p.color ?? -16777216);
    ctx.lineWidth = p.strokeWidth || 1;
    ctx.lineJoin = p.join;
    ctx.lineCap = p.cap;
    ctx.textAlign = p.align;
    ctx.textBaseline = 'alphabetic';
    ctx.imageSmoothingEnabled = !!(p.flags & 2);
    ctx.font = `${p.fontStyle & 2 ? 'italic' : 'normal'} ${p.fontStyle & 1 ? 'bold' : 'normal'} ${p.size ?? 12}px ${['sans-serif', 'serif', 'monospace', 'cursive', 'fantasy', 'system-ui'].includes(p.family || 'sans-serif') ? p.family || 'sans-serif' : JSON.stringify(p.family)}`;
  }
  function shape(p: Paint, fill: () => void, stroke: () => void) {
    if (p.style !== 'STROKE') fill();
    if (p.style === 'STROKE' || p.style === 'FILL_AND_STROKE') stroke();
  }
  function tileSize(
    r: Rect,
    f16: boolean,
    width: number,
    height: number,
  ): number {
    integer(r[0]);
    integer(r[1]);
    integer(r[2], 1);
    integer(r[3], 1);
    const size = r[2] * r[3] * (f16 ? 8 : 4);
    if (r[0] + r[2] > width || r[1] + r[3] > height || size > CHUNK)
      throw Error('Graphics pixel block must fit a surface and 64KiB');
    return size;
  }
  const teaGraphicsSync = (input: unknown): Record<string, unknown> => {
    const a = parseGraphicsRequest(input);
    if (a.op === 'measure' || a.op === 'layout' || a.op === 'text') {
      if (a.text.length > TEXT_UNITS)
        throw limit('Text exceeds 8192 UTF-16 units');
      if (
        a.paint.size < 0 ||
        a.paint.size > 4096 ||
        a.paint.scaleX < 0 ||
        a.paint.scaleX > 64
      )
        throw limit('Text paint exceeds dimensions budget');
    }
    if (a.op === 'closeDecoder') {
      closeDecoder(a.id);
      return {};
    }
    if (a.op === 'recycle') {
      retire(a.id);
      return {};
    }
    context();
    if (a.op === 'create') return create(a.width, a.height, a.f16);
    if (a.op === 'measure' || a.op === 'layout') {
      const release = reserve(
        4 + (a.op === 'layout' ? TEXT_WORK_BYTES : 4096 + a.text.length * 8),
        4,
      );
      let canvas: OffscreenCanvas | undefined;
      try {
        if (typeof OffscreenCanvas === 'undefined')
          throw unsupported('Canvas 2D unavailable');
        canvas = new OffscreenCanvas(1, 1);
        const c = canvas.getContext('2d');
        if (!c) throw Error('Canvas 2D unavailable');
        paint(c, a.paint);
        const measure = (value: string) => {
          if (a.paint.size === 0)
            return {
              width: 0,
              top: 0,
              ascent: 0,
              descent: 0,
              bottom: 0,
              leading: 0,
            };
          c.direction =
            a.paint.direction === 'auto'
              ? textDirection(value) === -1
                ? 'rtl'
                : 'ltr'
              : a.paint.direction;
          const metrics = c.measureText(value || 'Hg');
          const ascent = Number.isFinite(metrics.emHeightAscent)
            ? metrics.emHeightAscent
            : metrics.fontBoundingBoxAscent;
          const descent = Number.isFinite(metrics.emHeightDescent)
            ? metrics.emHeightDescent
            : metrics.fontBoundingBoxDescent;
          const result = {
            width: value ? metrics.width * a.paint.scaleX : 0,
            top: -Math.max(
              ascent,
              metrics.fontBoundingBoxAscent,
              metrics.actualBoundingBoxAscent,
            ),
            ascent: -ascent,
            descent,
            bottom: Math.max(
              descent,
              metrics.fontBoundingBoxDescent,
              metrics.actualBoundingBoxDescent,
            ),
            leading: 0,
          };
          if (Object.values(result).some((value) => !Number.isFinite(value)))
            throw unsupported('Canvas font metrics unavailable');
          return result;
        };
        if (a.op === 'measure') return measure(a.text);
        const result = layoutText(
          {
            text: a.text,
            width: a.width,
            alignment: a.alignment,
            spacingMult: a.spacingMult,
            spacingAdd: a.spacingAdd,
            includePad: a.includePad,
          },
          measure,
        );
        dimensions(Math.max(1, a.width), Math.max(1, result.height));
        return { ...result };
      } finally {
        if (canvas) canvas.width = canvas.height = 0;
        release();
      }
    }
    const s = surface(a.id),
      c = s.ctx,
      w = s.canvas.width,
      h = s.canvas.height;
    if (a.op === 'pixels' || a.op === 'raw') {
      const r: Rect = a.rect || [0, 0, w, h];
      const size = tileSize(r, a.f16, w, h),
        release = reserve(size, size);
      try {
        const p = c.getImageData(
          ...r,
          a.f16
            ? { pixelFormat: 'rgba-float16', colorSpace: 'display-p3' }
            : {},
        );
        if (a.op === 'raw') {
          const d = p.data;
          if (a.f16 && !(d instanceof Float16Array))
            throw Error('Float16 pixel read unavailable');
          for (let i = 0; i < d.length; i += 4) {
            const alpha = d[i + 3]! / (a.f16 ? 1 : 255);
            for (let j = 0; j < 3; j++)
              d[i + j] = a.f16
                ? d[i + j]! * alpha
                : Math.round(d[i + j]! * alpha);
          }
        }
        return outputBytes(new Uint8Array(p.data.buffer));
      } finally {
        release();
      }
    }
    if (a.op === 'putPixels' || a.op === 'putRaw') {
      const r: Rect = a.rect || [0, 0, w, h],
        size = tileSize(r, a.f16, w, h),
        data = inputBytes(a.bytes);
      if (data.length !== size)
        throw Error('Graphics pixel block length mismatch');
      const release = reserve(size, size);
      try {
        let image;
        if (a.f16) {
          if (typeof Float16Array === 'undefined')
            throw Error('Float16Array unavailable');
          const FloatImageData = ImageData as typeof ImageData &
            FloatImageDataConstructor;
          image = new FloatImageData(
            new Float16Array(data.buffer),
            r[2],
            r[3],
            {
              pixelFormat: 'rgba-float16',
              colorSpace: 'display-p3',
            },
          );
        } else
          image = new ImageData(new Uint8ClampedArray(data.buffer), r[2], r[3]);
        if (a.op === 'putRaw') {
          const d = image.data;
          for (let i = 0; i < d.length; i += 4) {
            const alpha = d[i + 3]! / (a.f16 ? 1 : 255);
            for (let j = 0; j < 3; j++)
              d[i + j] =
                alpha === 0
                  ? 0
                  : a.f16
                    ? d[i + j]! / alpha
                    : Math.round(d[i + j]! / alpha);
          }
        }
        c.putImageData(image, r[0], r[1]);
        return {};
      } finally {
        release();
      }
    }
    c.save();
    try {
      c.setTransform(...(a.matrix || [1, 0, 0, 1, 0, 0]));
      paint(c, a.paint);
      if (a.op === 'color' || a.op === 'erase') {
        c.resetTransform();
        if (a.op === 'erase') c.clearRect(0, 0, w, h);
        c.fillStyle = color(a.color);
        c.fillRect(0, 0, w, h);
      } else if (a.op === 'drawBitmap') {
        const src = surface(a.source).canvas,
          [sx, sy, sr, sb] = a.src,
          [dx, dy, dr, db] = a.dst;
        c.globalAlpha = ((a.paint.color >>> 24) & 255) / 255;
        c.drawImage(src, sx, sy, sr - sx, sb - sy, dx, dy, dr - dx, db - dy);
      } else if (a.op === 'roundRect') {
        if (!a.rect) throw Error('Rectangle is required');
        const [l, t, r, b] = a.rect;
        c.beginPath();
        c.roundRect(l, t, r - l, b - t, [
          { x: Math.max(0, a.rx), y: Math.max(0, a.ry) },
        ]);
        shape(
          a.paint,
          () => c.fill(),
          () => c.stroke(),
        );
      } else if (a.op === 'text') {
        const releaseText = reserve(4096 + a.text.length * 8);
        try {
          c.direction =
            a.paint.direction === 'auto'
              ? textDirection(a.text) === -1
                ? 'rtl'
                : 'ltr'
              : a.paint.direction;
          if (a.paint.size === 0) return {};
          c.translate(a.x, a.y);
          c.scale(a.paint.scaleX ?? 1, 1);
          shape(
            a.paint,
            () => c.fillText(a.text, 0, 0),
            () => c.strokeText(a.text, 0, 0),
          );
        } finally {
          releaseText();
        }
      } else throw Error('Unknown raster operation ' + a.op);
    } finally {
      c.restore();
    }
    return {};
  };
  function mime(type: string) {
    return 'image/' + (type === 'heic' ? 'heic' : type);
  }
  function header(data: Uint8Array) {
    const prefix = data.subarray(0, HEADER),
      release = reserve(prefix.length);
    try {
      return imageDimensionsFromData(prefix);
    } finally {
      release();
    }
  }
  async function asynchronous(
    a: GraphicsRequest,
    owner: GraphicsContext,
  ): Promise<Record<string, unknown>> {
    if (a.op === 'font') {
      if (typeof FontFace === 'undefined')
        throw unsupported('FontFace unavailable');
      if (fonts.size + loadingFonts >= 32)
        throw limit('Font count exceeds graphics budget');
      const input = borrow(a.bytes);
      loadingFonts++;
      let release: (() => void) | undefined;
      let face: FontFace | undefined;
      let retained = false;
      try {
        if (input.data.length > 8 * 1024 * 1024)
          throw limit('Font exceeds byte budget');
        // Account the browser-owned encoded font as well as the retained input.
        release = reserve(input.data.length);
        const family = 'TeaFont' + ++font;
        face = new FontFace(family, input.data);
        await face.load();
        check(owner);
        self.fonts.add(face);
        const fontRelease = release;
        fonts.set(family, {
          face,
          release: () => {
            fontRelease();
            input.release();
          },
        });
        retained = true;
        return { family };
      } finally {
        loadingFonts--;
        if (!retained) {
          if (face) self.fonts.delete(face);
          release?.();
          input.release();
        }
      }
    }
    if (a.op === 'encode') {
      if (a.format === 'WEBP_LOSSLESS') return { ok: false };
      const s = surface(a.id),
        type =
          a.format === 'JPEG'
            ? 'image/jpeg'
            : a.format === 'PNG'
              ? 'image/png'
              : 'image/webp';
      // convertToBlob has no cancellation API. Hold its source and reservation
      // until it settles, even when the owning Source operation is cancelled.
      const release = reserve(BODY);
      s.pins++;
      try {
        const blob = await s.canvas.convertToBlob({
          type,
          quality: a.quality / 100,
        });
        check(owner);
        if (blob.type !== type) return { ok: false };
        if (blob.size > BODY) throw limit('Encoded bitmap exceeds byte budget');
        const copyRelease = reserve(blob.size);
        try {
          const data = new Uint8Array(await blob.arrayBuffer());
          check(owner);
          return { ok: true, mime: type, ...outputBytes(data) };
        } finally {
          copyRelease();
        }
      } finally {
        s.pins--;
        releaseSurface(s);
        release();
      }
    }
    if (a.op === 'openDecoder') {
      if (decoders.size + openingDecoders >= 8)
        throw limit('Decoder count exceeds graphics budget');
      if (typeof ImageDecoder === 'undefined')
        throw unsupported('Animated image decoder unavailable');
      const input = borrow(a.bytes);
      openingDecoders++;
      let decoder: ImageDecoder | undefined;
      let release: (() => void) | undefined;
      let retained = false;
      try {
        const info = header(input.data);
        if (!info) throw Error('Unsupported or incomplete image header');
        dimensions(info.width, info.height);
        // One encoded codec copy and one conservative RGBA_F16 working raster.
        const raster = info.width * info.height * 8;
        release = reserve(input.data.length + raster, raster);
        decoder = new ImageDecoder({ data: input.data, type: mime(info.type) });
        await decoder.tracks.ready;
        check(owner);
        const frameRelease = reserve(raster, raster);
        let frame: VideoFrame | undefined;
        let hdr = false;
        try {
          frame = (await decoder.decode({ frameIndex: 0 })).image;
          check(owner);
          dimensions(frame.displayWidth, frame.displayHeight);
          if (
            frame.displayWidth * frame.displayHeight >
            info.width * info.height
          )
            throw limit('Decoded frame exceeds declared dimensions');
          hdr = ['pq', 'hlg', 'smpte2084', 'arib-std-b67'].includes(
            frame.colorSpace.transfer ?? '',
          );
        } finally {
          frame?.close();
          frameRelease();
        }
        const id = next++,
          codecRelease = release;
        decoders.set(id, {
          decoder,
          index: 0,
          hdr,
          width: info.width,
          height: info.height,
          busy: false,
          closed: false,
          release: () => {
            codecRelease();
            input.release();
          },
        });
        retained = true;
        return { id, hdr, width: info.width, height: info.height };
      } finally {
        openingDecoders--;
        if (!retained) {
          decoder?.close();
          release?.();
          input.release();
        }
      }
    }
    if (a.op === 'nextFrame') {
      const d = decoders.get(a.id);
      if (!d || d.closed) throw Error('Decoder closed');
      if (d.busy) throw Error('Concurrent image decoder entry');
      if (d.index >= (d.decoder.tracks.selectedTrack?.frameCount ?? 0))
        return { end: true };
      const raster = d.width * d.height * 8,
        release = reserve(raster, raster);
      d.busy = true;
      let frame: VideoFrame | undefined;
      let tmp: { id: number; width: number; height: number } | undefined;
      let readRelease: (() => void) | undefined;
      try {
        frame = (await d.decoder.decode({ frameIndex: d.index })).image;
        check(owner);
        if (d.closed) throw Error('Decoder closed during frame decode');
        dimensions(frame.displayWidth, frame.displayHeight);
        if (frame.displayWidth * frame.displayHeight > d.width * d.height)
          throw limit('Decoded frame exceeds declared dimensions');
        tmp = create(frame.displayWidth, frame.displayHeight, d.hdr);
        const s = surface(tmp.id),
          length = tmp.width * tmp.height * (d.hdr ? 8 : 4);
        if (length > BODY) throw limit('Decoded frame exceeds byte budget');
        s.ctx.drawImage(frame, 0, 0);
        readRelease = reserve(length, length);
        const image = s.ctx.getImageData(
          0,
          0,
          tmp.width,
          tmp.height,
          d.hdr
            ? { pixelFormat: 'rgba-float16', colorSpace: 'display-p3' }
            : {},
        );
        if (d.hdr && !(image.data instanceof Float16Array))
          throw Error('Float16 pixel read unavailable');
        premultiply(image.data, d.hdr);
        const result = outputBytes(new Uint8Array(image.data.buffer), true);
        d.index++;
        return { end: false, width: tmp.width, height: tmp.height, ...result };
      } finally {
        readRelease?.();
        frame?.close();
        if (tmp) retire(tmp.id);
        d.busy = false;
        release();
        if (d.closed) d.release();
      }
    }
    if (a.op === 'decode') {
      const input = borrow(a.bytes);
      let release: (() => void) | undefined;
      let blobRelease: (() => void) | undefined;
      let image: ImageBitmap | undefined;
      let result: { id: number; width: number; height: number } | undefined;
      let published = false;
      try {
        const info = header(input.data);
        if (!info) return { ok: false };
        if (a.bounds)
          return {
            ok: true,
            originalWidth: info.width,
            originalHeight: info.height,
            mime: mime(info.type),
          };
        dimensions(info.width, info.height);
        if (typeof createImageBitmap === 'undefined')
          throw unsupported('Bitmap decoder unavailable');
        const raster = info.width * info.height * 8;
        release = reserve(raster, raster);
        blobRelease = reserve(input.data.length);
        try {
          image = await createImageBitmap(new Blob([input.data]));
        } catch (error) {
          check(owner);
          return { ok: false, error: String(error) };
        }
        check(owner);
        dimensions(image.width, image.height);
        if (image.width * image.height > info.width * info.height)
          throw limit('Decoded image exceeds declared dimensions');
        integer(a.sample, 1);
        if (a.densityScale <= 0) throw Error('Invalid bitmap density');
        result = create(
          Math.max(
            1,
            Math.round(
              Math.max(1, Math.floor(image.width / a.sample)) * a.densityScale,
            ),
          ),
          Math.max(
            1,
            Math.round(
              Math.max(1, Math.floor(image.height / a.sample)) * a.densityScale,
            ),
          ),
          a.f16,
        );
        surface(result.id).ctx.drawImage(
          image,
          0,
          0,
          result.width,
          result.height,
        );
        published = true;
        return {
          ...result,
          ok: true,
          originalWidth: image.width,
          originalHeight: image.height,
          mime: mime(info.type),
        };
      } finally {
        if (result && !published) retire(result.id);
        image?.close();
        blobRelease?.();
        release?.();
        input.release();
      }
    }
    throw Error('Unknown asynchronous raster operation ' + a.op);
  }
  function premultiply(
    data: Uint8ClampedArray<ArrayBuffer> | Float16Array<ArrayBuffer>,
    f16: boolean,
  ) {
    for (let i = 0; i < data.length; i += 4) {
      const alpha = data[i + 3]! / (f16 ? 1 : 255);
      for (let j = 0; j < 3; j++)
        data[i + j] = f16
          ? data[i + j]! * alpha
          : Math.round(data[i + j]! * alpha);
    }
  }
  const teaGraphicsAsync = async (
    input: unknown,
  ): Promise<Record<string, unknown>> => {
    const owner = context();
    if (pending >= 4)
      throw limit('Pending raster tasks exceed graphics budget');
    pending++;
    try {
      return await asynchronous(parseGraphicsRequest(input), owner);
    } finally {
      pending--;
      if (owner.ended && !pending) {
        scratchRelease?.();
        scratchRelease = undefined;
      }
    }
  };
  return {
    teaGraphicsSync,
    teaGraphicsAsync,
    teaGraphicsBegin,
    teaGraphicsCancel,
    teaGraphicsEnd,
    teaGraphicsBytesOpen,
    teaGraphicsBytesWrite,
    teaGraphicsBytesRead,
    teaGraphicsBytesClose,
    teaGraphicsBytesDetach,
    teaGraphicsBitmapClaim,
    teaGraphicsBitmapId,
    teaGraphicsBitmapRecycle,
    teaGraphicsSnapshot,
  };
}
Object.assign(scope, createGraphicsBridge());
