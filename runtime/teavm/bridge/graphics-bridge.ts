/* Browser raster backend for Android bitmap APIs. No website-specific image transforms. */
import {
  bool,
  decodeBase64,
  encodeBase64,
  integer,
  number,
  object,
  optionalText,
  text,
  workerScope,
} from './bridge-common.js';
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
}
const operations = [
  'create',
  'closeDecoder',
  'recycle',
  'measure',
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
  body: string;
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
  return {
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
    body: optionalText(data.body) ?? '',
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
  };
}
interface Surface {
  canvas: OffscreenCanvas;
  ctx: OffscreenCanvasRenderingContext2D;
  f16: boolean;
}
interface Decoder {
  decoder: ImageDecoder;
  first: VideoFrame | null;
  index: number;
  hdr: boolean;
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
}

const scope = workerScope();
function createGraphicsBridge() {
  const surfaces = new Map<number, Surface>(),
    decoders = new Map<number, Decoder>();
  let next = 1,
    font = 0;
  const bytes = decodeBase64,
    b64 = encodeBase64;
  const color = (c: number) =>
    `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${(c >>> 24) / 255})`;
  function surface(id: number): Surface {
    const s = surfaces.get(id);
    if (!s) throw Error('Unknown or recycled bitmap ' + id);
    return s;
  }
  function create(width: number, height: number, f16 = false) {
    if (
      !Number.isInteger(width) ||
      !Number.isInteger(height) ||
      width < 1 ||
      height < 1 ||
      width * height > 64 * 1024 * 1024
    )
      throw Error('Bitmap dimensions exceed raster limit');
    const canvas = new OffscreenCanvas(width, height),
      ctx = canvas.getContext('2d', {
        willReadFrequently: true,
        ...(f16 ? { colorType: 'float16', colorSpace: 'display-p3' } : {}),
      });
    if (!ctx) throw Error('Canvas 2D unavailable');
    if (
      f16 &&
      (!floatContext(ctx) || ctx.getContextAttributes().colorType !== 'float16')
    )
      throw Error('Float16 canvas unavailable');
    const id = next++;
    surfaces.set(id, { canvas, ctx, f16 });
    return { id, width, height };
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
  const teaGraphicsSync = (input: unknown): Record<string, unknown> => {
    const a = parseGraphicsRequest(input);
    if (a.op === 'create') return create(a.width, a.height, a.f16);
    if (a.op === 'closeDecoder') {
      const d = decoders.get(a.id);
      if (d) {
        d.first?.close();
        d.decoder.close();
        decoders.delete(a.id);
      }
      return {};
    }
    if (a.op === 'recycle') {
      const s = surface(a.id);
      s.canvas.width = s.canvas.height = 0;
      surfaces.delete(a.id);
      return {};
    }
    if (a.op === 'measure') {
      const c = new OffscreenCanvas(1, 1).getContext('2d');
      if (!c) throw Error('Canvas 2D unavailable');
      paint(c, a.paint);
      return {
        width:
          a.paint.size === 0
            ? 0
            : c.measureText(a.text).width * (a.paint.scaleX ?? 1),
      };
    }
    const s = surface(a.id),
      c = s.ctx,
      w = s.canvas.width,
      h = s.canvas.height;
    if (a.op === 'pixels' || a.op === 'raw') {
      const r = a.rect || [0, 0, w, h],
        p = c.getImageData(
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
      return { body: b64(new Uint8Array(p.data.buffer)) };
    }
    if (a.op === 'putPixels' || a.op === 'putRaw') {
      const r = a.rect || [0, 0, w, h],
        data = bytes(a.body);
      let image;
      if (a.f16) {
        if (typeof Float16Array === 'undefined')
          throw Error('Float16Array unavailable');
        const FloatImageData = ImageData as typeof ImageData &
          FloatImageDataConstructor;
        image = new FloatImageData(new Float16Array(data.buffer), r[2], r[3], {
          pixelFormat: 'rgba-float16',
          colorSpace: 'display-p3',
        });
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
        if (a.paint.size === 0) return {};
        c.translate(a.x, a.y);
        c.scale(a.paint.scaleX ?? 1, 1);
        shape(
          a.paint,
          () => c.fillText(a.text, 0, 0),
          () => c.strokeText(a.text, 0, 0),
        );
      } else throw Error('Unknown raster operation ' + a.op);
    } finally {
      c.restore();
    }
    return {};
  };
  function mime(data: Uint8Array) {
    if (data[0] === 137 && data[1] === 80) return 'image/png';
    if (data[0] === 255 && data[1] === 216) return 'image/jpeg';
    if (data[0] === 71 && data[1] === 73) return 'image/gif';
    if (String.fromCharCode(...data.subarray(8, 12)) === 'WEBP')
      return 'image/webp';
    if (String.fromCharCode(...data.subarray(4, 8)) === 'ftyp')
      return 'image/avif';
    return 'application/octet-stream';
  }
  const teaGraphicsAsync = async (
    input: unknown,
  ): Promise<Record<string, unknown>> => {
    const a = parseGraphicsRequest(input);
    if (a.op === 'font') {
      const family = 'TeaFont' + ++font,
        face = new FontFace(family, bytes(a.body));
      await face.load();
      self.fonts.add(face);
      return { family };
    }
    if (a.op === 'encode') {
      if (a.format === 'WEBP_LOSSLESS') return { ok: false };
      const s = surface(a.id),
        type =
          a.format === 'JPEG'
            ? 'image/jpeg'
            : a.format === 'PNG'
              ? 'image/png'
              : 'image/webp',
        quality = a.quality / 100;
      const blob = await s.canvas.convertToBlob({ type, quality });
      return blob.type !== type
        ? { ok: false }
        : {
            ok: true,
            body: b64(new Uint8Array(await blob.arrayBuffer())),
            mime: blob.type,
          };
    }
    if (a.op === 'openDecoder') {
      const data = bytes(a.body);
      if (data.length > 64 * 1024 * 1024)
        throw Error('Encoded image too large');
      const decoder = new ImageDecoder({ data, type: mime(data) });
      try {
        await decoder.tracks.ready;
        const first = (await decoder.decode({ frameIndex: 0 })).image;
        if (first.displayWidth * first.displayHeight > 64 * 1024 * 1024) {
          first.close();
          throw Error('Decoded image too large');
        }
        const hdr = ['pq', 'hlg', 'smpte2084', 'arib-std-b67'].includes(
            first.colorSpace.transfer ?? '',
          ),
          id = next++;
        decoders.set(id, { decoder, first, index: 0, hdr });
        return {
          id,
          hdr,
          width: first.displayWidth,
          height: first.displayHeight,
        };
      } catch (e) {
        decoder.close();
        throw e;
      }
    }
    if (a.op === 'nextFrame') {
      const d = decoders.get(a.id);
      if (!d) throw Error('Decoder closed');
      if (d.index >= (d.decoder.tracks.selectedTrack?.frameCount ?? 0))
        return { end: true };
      const frame =
        d.first || (await d.decoder.decode({ frameIndex: d.index })).image;
      d.first = null;
      d.index++;
      let tmp;
      try {
        tmp = create(frame.displayWidth, frame.displayHeight, d.hdr);
        const s = surface(tmp.id);
        s.ctx.drawImage(frame, 0, 0);
        return {
          end: false,
          width: tmp.width,
          height: tmp.height,
          body: teaGraphicsSync({ op: 'raw', id: tmp.id, f16: d.hdr }).body,
        };
      } finally {
        frame.close();
        if (tmp) teaGraphicsSync({ op: 'recycle', id: tmp.id });
      }
    }
    if (a.op === 'decode') {
      const data = bytes(a.body);
      if (data.length > 64 * 1024 * 1024)
        throw Error('Encoded image too large');
      let image;
      try {
        image = await createImageBitmap(new Blob([data]));
      } catch (e) {
        return { ok: false, error: String(e) };
      }
      try {
        const originalWidth = image.width,
          originalHeight = image.height;
        if (a.bounds)
          return { ok: true, originalWidth, originalHeight, mime: mime(data) };
        const sample = Math.max(1, a.sample || 1),
          scale = a.densityScale ?? 1,
          result = create(
            Math.max(
              1,
              Math.round(
                Math.max(1, Math.floor(originalWidth / sample)) * scale,
              ),
            ),
            Math.max(
              1,
              Math.round(
                Math.max(1, Math.floor(originalHeight / sample)) * scale,
              ),
            ),
            a.f16,
          );
        const s = surface(result.id);
        s.ctx.drawImage(image, 0, 0, result.width, result.height);
        return {
          ...result,
          ok: true,
          originalWidth,
          originalHeight,
          mime: mime(data),
        };
      } finally {
        image.close();
      }
    }
    throw Error('Unknown asynchronous raster operation ' + a.op);
  };
  return { teaGraphicsSync, teaGraphicsAsync };
}
Object.assign(scope, createGraphicsBridge());
