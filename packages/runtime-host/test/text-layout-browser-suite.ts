/** Real Canvas2D text layout gate, independent of the Java/Android oracle. */
import {
  number,
  workerScope,
} from '../../../runtime/teavm/bridge/bridge-common.js';
import type {} from '../../../runtime/teavm/bridge/graphics-bridge.js';
function assert(value: unknown, message: string): asserts value {
  if (!value) throw Error(message);
}
const scope = workerScope();
self.onmessage = async () => {
  const checks: string[] = [],
    identity = { requestId: 'text-layout', generation: 'text-layout' };
  const begin = scope.teaGraphicsBegin,
    end = scope.teaGraphicsEnd,
    sync = scope.teaGraphicsSync,
    snapshot = scope.teaGraphicsSnapshot;
  if (!begin || !end || !sync || !snapshot)
    throw Error('Product graphics bridge missing');
  let imageId: number | undefined;
  begin(identity);
  try {
    const paint = {
      size: 36,
      fontStyle: 1,
      family: 'sans-serif',
      color: -16777216,
    };
    const metrics = sync({ op: 'measure', text: 'Hg', paint });
    assert(
      typeof metrics.ascent === 'number' &&
        metrics.ascent < 0 &&
        typeof metrics.descent === 'number' &&
        metrics.descent > 0,
      'Actual Canvas font metrics',
    );
    const layout = sync({
      op: 'layout',
      text: 'A heading with enough words to wrap into several lines',
      width: 220,
      paint,
      spacingMult: 1.1,
      spacingAdd: 2,
      includePad: true,
    });
    assert(
      Array.isArray(layout.lines) && layout.lines.length > 1,
      'Real measured text wraps',
    );
    assert(
      typeof layout.height === 'number' && layout.height > 36,
      'Real layout height',
    );
    checks.push('real-font-metrics-and-multiline-layout');
    const image = sync({
      op: 'create',
      width: 300,
      height: layout.height + 50,
    });
    imageId = number(image.id);
    sync({ op: 'color', id: image.id, color: -1 });
    for (const raw of layout.lines) {
      assert(
        Array.isArray(raw) && raw.every((value) => typeof value === 'number'),
        'Typed bounded line coordinates',
      );
      sync({
        op: 'text',
        id: image.id,
        text: 'A heading with enough words to wrap into several lines'.slice(
          number(raw[0]),
          number(raw[2]),
        ),
        x: number(raw[6]) + 25,
        y: number(raw[4]) + 25,
        paint,
      });
    }
    const read = scope.teaGraphicsBytesRead,
      close = scope.teaGraphicsBytesClose;
    assert(read && close, 'Bounded pixel bridge');
    let nonWhite = 0;
    for (let row = 0; row < layout.height + 50; row++) {
      const output = sync({
        op: 'pixels',
        id: image.id,
        rect: [0, row, 300, 1],
      });
      assert(typeof output.bytes === 'string', 'Bounded pixel read');
      try {
        let bytes;
        while ((bytes = read(output.bytes, 65536)) !== null)
          for (let i = 0; i < bytes.length; i += 4)
            if (
              bytes[i] !== 255 ||
              bytes[i + 1] !== 255 ||
              bytes[i + 2] !== 255
            )
              nonWhite++;
      } finally {
        close(output.bytes);
      }
    }
    assert(nonWhite > 100, 'Layout drawing contains actual visible glyphs');
    sync({ op: 'recycle', id: image.id });
    imageId = undefined;
    checks.push('real-multiline-glyph-raster-and-recycle');
    const budgetImage = sync({ op: 'create', width: 1, height: 1 });
    imageId = number(budgetImage.id);
    for (const dimensions of [
      { size: -1 },
      { size: 1e20 },
      { scaleX: -1 },
      { scaleX: 65 },
    ]) {
      let failed = false;
      try {
        sync({
          op: 'text',
          id: imageId,
          text: 'A',
          x: 0,
          y: 0,
          paint: { ...paint, ...dimensions },
        });
      } catch (error) {
        failed = error instanceof Error;
      }
      assert(failed, 'Independent drawText dimensions budget rejects');
    }
    sync({ op: 'recycle', id: imageId });
    imageId = undefined;
    checks.push('draw-text-dimensions-budget-rejection');
    const rtl = sync({
      op: 'layout',
      text: 'مرحبا بالعالم',
      width: 300,
      paint,
    });
    assert(
      Array.isArray(rtl.lines) &&
        Array.isArray(rtl.lines[0]) &&
        rtl.lines[0][8] === -1,
      'Library-resolved RTL paragraph',
    );
    checks.push('paragraph-direction');
    for (const request of [
      { op: 'layout', text: 'a'.repeat(8193), width: 100, paint },
      { op: 'layout', text: '\n'.repeat(512), width: 100, paint },
      { op: 'layout', text: 'x', width: 16385, paint },
    ]) {
      let failed = false;
      try {
        sync(request);
      } catch (error) {
        failed = error instanceof Error;
      }
      assert(failed, 'Layout budget rejects');
    }
    checks.push('text-line-and-dimension-budget-rejection');
    end(identity.requestId, identity.generation);
    assert(snapshot().totalBytes === 0, 'Layout scratch and surfaces released');
    self.postMessage({
      passed: true,
      checks,
      metrics,
      layoutHeight: layout.height,
      nonWhite,
      resources: snapshot(),
    });
  } catch (error) {
    if (imageId !== undefined) sync({ op: 'recycle', id: imageId });
    end(identity.requestId, identity.generation);
    self.postMessage({
      passed: false,
      error: String(error),
      stack: error instanceof Error ? error.stack : undefined,
      resources: snapshot(),
    });
  }
};
