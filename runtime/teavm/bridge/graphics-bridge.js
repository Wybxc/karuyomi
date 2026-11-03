/* Browser raster backend for Android bitmap APIs. No website-specific image transforms. */
(() => {
  const surfaces = new Map(),
    decoders = new Map();
  let next = 1,
    font = 0;
  const bytes = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  const b64 = (data) => {
    let s = '';
    for (let n = 0; n < data.length; n += 32768)
      s += String.fromCharCode(...data.subarray(n, n + 32768));
    return btoa(s);
  };
  const color = (c) =>
    `rgba(${(c >>> 16) & 255},${(c >>> 8) & 255},${c & 255},${(c >>> 24) / 255})`;
  function surface(id) {
    const s = surfaces.get(id);
    if (!s) throw Error('Unknown or recycled bitmap ' + id);
    return s;
  }
  function create(width, height, f16 = false) {
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
    if (f16 && ctx.getContextAttributes().colorType !== 'float16')
      throw Error('Float16 canvas unavailable');
    const id = next++;
    surfaces.set(id, { canvas, ctx, f16 });
    return { id, width, height };
  }
  function paint(ctx, p = {}) {
    ctx.globalAlpha = 1;
    ctx.fillStyle = ctx.strokeStyle = color(p.color ?? -16777216);
    ctx.lineWidth = p.strokeWidth || 1;
    ctx.lineJoin = (p.join || 'MITER').toLowerCase();
    ctx.lineCap = (p.cap || 'BUTT').toLowerCase();
    ctx.textAlign = (p.align || 'LEFT').toLowerCase();
    ctx.textBaseline = 'alphabetic';
    ctx.imageSmoothingEnabled = !!(p.flags & 2);
    ctx.font = `${p.fontStyle & 2 ? 'italic' : 'normal'} ${p.fontStyle & 1 ? 'bold' : 'normal'} ${p.size ?? 12}px ${['sans-serif', 'serif', 'monospace', 'cursive', 'fantasy', 'system-ui'].includes(p.family || 'sans-serif') ? p.family || 'sans-serif' : JSON.stringify(p.family)}`;
  }
  function shape(ctx, p, fill, stroke) {
    if (p.style !== 'STROKE') fill();
    if (p.style === 'STROKE' || p.style === 'FILL_AND_STROKE') stroke();
  }
  self.teaGraphicsSync = (a) => {
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
          const alpha = d[i + 3] / (a.f16 ? 1 : 255);
          for (let j = 0; j < 3; j++)
            d[i + j] = a.f16 ? d[i + j] * alpha : Math.round(d[i + j] * alpha);
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
        image = new ImageData(new Float16Array(data.buffer), r[2], r[3], {
          pixelFormat: 'rgba-float16',
          colorSpace: 'display-p3',
        });
      } else
        image = new ImageData(new Uint8ClampedArray(data.buffer), r[2], r[3]);
      if (a.op === 'putRaw') {
        const d = image.data;
        for (let i = 0; i < d.length; i += 4) {
          const alpha = d[i + 3] / (a.f16 ? 1 : 255);
          for (let j = 0; j < 3; j++)
            d[i + j] =
              alpha === 0
                ? 0
                : a.f16
                  ? d[i + j] / alpha
                  : Math.round(d[i + j] / alpha);
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
        const [l, t, r, b] = a.rect;
        c.beginPath();
        c.roundRect(l, t, r - l, b - t, [
          { x: Math.max(0, a.rx), y: Math.max(0, a.ry) },
        ]);
        shape(
          c,
          a.paint,
          () => c.fill(),
          () => c.stroke(),
        );
      } else if (a.op === 'text') {
        if (a.paint.size === 0) return {};
        c.translate(a.x, a.y);
        c.scale(a.paint.scaleX ?? 1, 1);
        shape(
          c,
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
  function mime(data) {
    if (data[0] === 137 && data[1] === 80) return 'image/png';
    if (data[0] === 255 && data[1] === 216) return 'image/jpeg';
    if (data[0] === 71 && data[1] === 73) return 'image/gif';
    if (String.fromCharCode(...data.subarray(8, 12)) === 'WEBP')
      return 'image/webp';
    if (String.fromCharCode(...data.subarray(4, 8)) === 'ftyp')
      return 'image/avif';
    return 'application/octet-stream';
  }
  self.teaGraphicsAsync = async (a) => {
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
            first.colorSpace.transfer,
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
      if (d.index >= d.decoder.tracks.selectedTrack.frameCount)
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
          body: self.teaGraphicsSync({ op: 'raw', id: tmp.id, f16: d.hdr })
            .body,
        };
      } finally {
        frame.close();
        if (tmp) self.teaGraphicsSync({ op: 'recycle', id: tmp.id });
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
})();
