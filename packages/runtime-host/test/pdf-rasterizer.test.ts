import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  openPdfDocument,
  PDF_HEAP_BYTES,
} from '../../../runtime/teavm/bridge/pdf-rasterizer.js';
import { createGraphicsBridge } from '../../../runtime/teavm/bridge/graphics-bridge.js';

const require = createRequire(import.meta.url);
const wasm = () => readFile(require.resolve('@hyzyla/pdfium/pdfium.wasm'));

function sourcePdf() {
  const bodies = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 140] /Resources << >> /Contents 5 0 R >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 80 60] /Resources << >> /Contents 6 0 R >>',
    '1 0 0 rg 0 70 50 70 re f',
    '0 0 1 rg 0 0 80 60 re f',
  ];
  const offsets: number[] = [];
  let content = '%PDF-1.4\n';
  for (const [index, body] of bodies.entries()) {
    offsets.push(content.length);
    const value =
      index < 4
        ? body
        : '<< /Length ' +
          (body.length + 1) +
          ' >>\nstream\n' +
          body +
          '\nendstream';
    content += index + 1 + ' 0 obj\n' + value + '\nendobj\n';
  }
  const xref = content.length;
  content +=
    'xref\n0 7\n0000000000 65535 f \n' +
    offsets
      .map((offset) => String(offset).padStart(10, '0') + ' 00000 n \n')
      .join('') +
    'trailer\n<< /Size 7 /Root 1 0 R >>\nstartxref\n' +
    xref +
    '\n%%EOF\n';
  return new TextEncoder().encode(content);
}

describe('PDFium Source rendering', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });

  it('opens the original pages and returns transparent RGBA at the requested size', async () => {
    const module = await WebAssembly.compile(await wasm());
    await expect(
      openPdfDocument(module, new Uint8Array([1, 2, 3])),
    ).rejects.toMatchObject({ code: 'pdf_file_error' });
    const opened = await openPdfDocument(module, sourcePdf());
    try {
      expect(opened.document.getPageCount()).toBe(2);
      const page = opened.document.getPage(0);
      expect(page.getOriginalSize()).toEqual({
        originalWidth: 100,
        originalHeight: 140,
      });
      const { data, width, height } = await page.render({
        width: 180,
        height: 240,
        transparent: true,
      });
      expect([width, height, data.byteLength]).toEqual([
        180,
        240,
        180 * 240 * 4,
      ]);
      expect([...data.subarray(0, 4)]).toEqual([255, 0, 0, 255]);
      expect([...data.subarray(-4)]).toEqual([0, 0, 0, 0]);
      page.close();
      const second = opened.document.getPage(1);
      const blue = await second.render({ width: 80, height: 60 });
      expect([...blue.data.subarray(0, 4)]).toEqual([0, 0, 255, 255]);
      vi.spyOn(console, 'error').mockImplementation(() => {});
      await expect(
        second.render({ width: 6000, height: 6000 }),
      ).rejects.toThrow(/memory|alloc/i);
      second.close();
    } finally {
      opened.close();
    }
  });

  it('loads PDFium on demand and releases the document when the request ends', async () => {
    const load = vi.fn(wasm);
    vi.stubGlobal('karuyomiLoadPdfium', load);
    const bridge = createGraphicsBridge({
      totalBytes: PDF_HEAP_BYTES + 1024 * 1024,
    });
    bridge.teaGraphicsBegin({ requestId: 'first', generation: 'pdf' });
    const input = bridge.teaGraphicsBytesOpen(4096);
    bridge.teaGraphicsBytesWrite(input, sourcePdf());
    expect(load).not.toHaveBeenCalled();
    const result = await bridge.teaGraphicsAsync({
      op: 'openPdf',
      bytes: input,
    });
    expect(result.pageCount).toBe(2);
    bridge.teaGraphicsBytesClose(input);
    expect(load).toHaveBeenCalledTimes(1);
    expect(
      bridge.teaGraphicsSync({
        op: 'openPdfPage',
        id: result.id,
        pageIndex: 1,
      }),
    ).toEqual({ width: 80, height: 60 });
    expect(() =>
      bridge.teaGraphicsSync({ op: 'closePdf', id: result.id }),
    ).toThrow('A PDF page is still open');
    bridge.teaGraphicsSync({ op: 'closePdfPage', id: result.id });
    bridge.teaGraphicsSync({ op: 'closePdf', id: result.id });
    const next = bridge.teaGraphicsBytesOpen(4096);
    bridge.teaGraphicsBytesWrite(next, sourcePdf());
    const second = await bridge.teaGraphicsAsync({
      op: 'openPdf',
      bytes: next,
    });
    bridge.teaGraphicsEnd('first', 'pdf');
    expect(load).toHaveBeenCalledTimes(1);
    expect(bridge.teaGraphicsSnapshot()).toMatchObject({
      totalBytes: 0,
      handles: 0,
    });
    bridge.teaGraphicsBegin({ requestId: 'next', generation: 'pdf' });
    expect(() =>
      bridge.teaGraphicsSync({
        op: 'openPdfPage',
        id: second.id,
        pageIndex: 0,
      }),
    ).toThrow('Unknown or stale PDF');
    bridge.teaGraphicsEnd('next', 'pdf');
  });
});
