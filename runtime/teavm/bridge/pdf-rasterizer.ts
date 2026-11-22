import { PDFiumDocument, PDFiumModule } from '@hyzyla/pdfium';

export const PDF_HEAP_BYTES = 128 * 1024 * 1024;
const WASM_PAGE_BYTES = 64 * 1024;

/** The pinned Emscripten allocator grows this instance's exported memory through grow(). */
async function boundedPdfium(module: WebAssembly.Module) {
  return PDFiumModule({
    instantiateWasm(imports, receive) {
      const instance = new WebAssembly.Instance(module, imports);
      const memory = instance.exports.memory;
      if (
        !(memory instanceof WebAssembly.Memory) ||
        memory.buffer.byteLength > PDF_HEAP_BYTES
      )
        throw Error('Invalid PDFium memory');
      const grow = memory.grow.bind(memory);
      memory.grow = (pages) => {
        if (memory.buffer.byteLength + pages * WASM_PAGE_BYTES > PDF_HEAP_BYTES)
          throw new RangeError('PDFium memory budget exceeded');
        return grow(pages);
      };
      receive(instance, module);
    },
  });
}

export async function openPdfDocument(
  module: WebAssembly.Module,
  bytes: Uint8Array<ArrayBuffer>,
) {
  if (!bytes.length)
    throw Object.assign(Error('PDF file is empty'), { code: 'pdf_file_error' });
  const engine = await boundedPdfium(module);
  engine._FPDF_InitLibraryWithConfig({
    version: 2,
    m_pIsolate: null,
    m_pUserFontPaths: null,
    m_v8EmbedderSlot: 0,
    m_pPlatform: null,
  });
  let pointer = 0;
  try {
    pointer = engine.wasmExports.malloc(bytes.length);
    if (!pointer)
      throw Object.assign(Error('PDF file exceeds the library memory budget'), {
        code: 'limit_exceeded',
      });
    engine.HEAPU8.set(bytes, pointer);
    const index = engine._FPDF_LoadMemDocument(pointer, bytes.length, 0);
    if (!index) {
      const reason = engine._FPDF_GetLastError();
      if (reason === 4 || reason === 5)
        throw Object.assign(Error('PDF requires a supported password scheme'), {
          code: 'pdf_protected',
        });
      throw Object.assign(Error('PDF document could not be opened'), {
        code: 'pdf_file_error',
      });
    }
    const document = new PDFiumDocument({
      module: engine,
      documentIdx: index,
      documentPtr: pointer,
    });
    return {
      document,
      close() {
        try {
          document.destroy();
        } finally {
          engine._FPDF_DestroyLibrary();
        }
      },
    };
  } catch (error) {
    if (pointer) engine.wasmExports.free(pointer);
    engine._FPDF_DestroyLibrary();
    throw error;
  }
}
