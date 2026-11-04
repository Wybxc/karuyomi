#include <emscripten/emscripten.h>
#include <setjmp.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "codec.h"
#include "jpeglib.h"

// These backend headers require the public libjpeg declarations first.
#include "jerror.h"
#include "jmemsys.h"

typedef union AllocationHeader {
  size_t size;
  max_align_t alignment;
} AllocationHeader;

typedef struct ImageError {
  struct jpeg_error_mgr pub;
  jmp_buf jump;
} ImageError;

static const size_t allocation_limit = IMAGE_MAX_ALLOCATION_BYTES;
static size_t live_bytes, peak_bytes, allocations, input_length;
static struct jpeg_decompress_struct image;
static ImageError error;
static uint8_t *input, *strip;
static uint32_t strip_rows, strip_start, output_width, output_height;
static int opened, finished, last_error, error_phase;

static void* meter_malloc(size_t size) {
  if (size > allocation_limit - live_bytes ||
      size > SIZE_MAX - sizeof(AllocationHeader))
    return NULL;
  AllocationHeader* allocation = malloc(sizeof(*allocation) + size);
  if (!allocation) return NULL;
  allocation->size = size;
  live_bytes += size;
  if (live_bytes > peak_bytes) peak_bytes = live_bytes;
  allocations++;
  return allocation + 1;
}

static void meter_free(void* pointer) {
  if (!pointer) return;
  AllocationHeader* allocation = (AllocationHeader*)pointer - 1;
  live_bytes -= allocation->size;
  allocations--;
  free(allocation);
}

/* Official jmemsys backend interface.  These definitions satisfy all symbols
 * before libjpeg.a is linked, so its unmodified jmemnobs.o is not extracted.
 * Requests include libjpeg pool padding/headers but not our AllocationHeader,
 * libc metadata, stack, static data, JS buffers, or process RSS. */
void* jpeg_get_small(j_common_ptr cinfo, size_t size) {
  (void)cinfo;
  return meter_malloc(size);
}
void* jpeg_get_large(j_common_ptr cinfo, size_t size) {
  (void)cinfo;
  return meter_malloc(size);
}
void jpeg_free_small(j_common_ptr cinfo, void* pointer, size_t size) {
  (void)cinfo;
  (void)size;
  meter_free(pointer);
}
void jpeg_free_large(j_common_ptr cinfo, void* pointer, size_t size) {
  (void)cinfo;
  (void)size;
  meter_free(pointer);
}
size_t jpeg_mem_available(j_common_ptr cinfo, size_t minimum, size_t maximum,
                          size_t allocated) {
  (void)cinfo;
  (void)minimum;
  (void)allocated;
  size_t available = allocation_limit - live_bytes;
  return maximum < available ? maximum : available;
}
void jpeg_open_backing_store(j_common_ptr cinfo, backing_store_ptr store,
                             long size) {
  (void)store;
  (void)size;
  ERREXIT(cinfo, JERR_NO_BACKING_STORE);
}
long jpeg_mem_init(j_common_ptr cinfo) {
  (void)cinfo;
  return 0;
}
void jpeg_mem_term(j_common_ptr cinfo) { (void)cinfo; }

static void fail(j_common_ptr cinfo) {
  last_error = cinfo->err->msg_code;
  longjmp(error.jump, 1);
}
static void emit(j_common_ptr cinfo, int level) {
  if (level < 0)
    fail(cinfo); /* Do not accept synthetic EOI or corrupt recovery. */
}
static int failure(int code) {
  last_error = code;
  return -100 - abs(code);
}

EMSCRIPTEN_KEEPALIVE uint8_t* image_input(size_t length) {
  if (input || image.mem) return NULL;
  peak_bytes = live_bytes;
  last_error = error_phase = 0;
  if (!length || length > IMAGE_MAX_INPUT_BYTES) return NULL;
  input = meter_malloc(length);
  if (input) input_length = length;
  return input;
}

EMSCRIPTEN_KEEPALIVE int image_open(size_t length, uint32_t rows,
                                    uint32_t denominator) {
  error_phase = IMAGE_PHASE_OPEN;
  if (!input || image.mem || length != input_length || !rows ||
      rows > IMAGE_MAX_STRIP_ROWS ||
      (denominator != 1 && denominator != 2 && denominator != 4))
    return failure(-1);
  if (setjmp(error.jump)) return -100 - abs(last_error);
  image.err = jpeg_std_error(&error.pub);
  error.pub.error_exit = fail;
  error.pub.emit_message = emit;
  jpeg_create_decompress(&image);
  jpeg_mem_src(&image, input, length);
  if (jpeg_read_header(&image, TRUE) != JPEG_HEADER_OK) return failure(-2);
  if (jpeg_has_multiple_scans(&image)) return failure(-4);
  if (image.data_precision != 8 || image.arith_code || image.Ss != 0 ||
      image.Se != 63 || image.Ah != 0 || image.Al != 0 ||
      (image.jpeg_color_space != JCS_GRAYSCALE &&
       image.jpeg_color_space != JCS_RGB &&
       image.jpeg_color_space != JCS_YCbCr))
    return failure(-3);
  if (!image.image_width || image.image_width > 4096 || !image.image_height ||
      image.image_height > 65500)
    return failure(-5);
  image.out_color_space = JCS_EXT_RGBA;
  image.scale_num = 1;
  image.scale_denom = denominator;
  image.dct_method = JDCT_ISLOW;
  image.do_fancy_upsampling = TRUE;
  image.quantize_colors = FALSE;
  image.buffered_image = FALSE;
  jpeg_calc_output_dimensions(&image);
  output_width = image.output_width;
  output_height = image.output_height;
  strip_rows = rows;
  strip = meter_malloc((size_t)output_width * 4 * strip_rows);
  if (!strip) return failure(-6);
  if (!jpeg_start_decompress(&image)) return failure(-7);
  if (image.output_components != 4 || image.output_width != output_width ||
      image.output_height != output_height)
    return failure(-8);
  opened = 1;
  return 0;
}

EMSCRIPTEN_KEEPALIVE int image_next(void) {
  if (last_error) return -100 - abs(last_error);
  if (!opened) {
    error_phase = IMAGE_PHASE_ROWS;
    return failure(-9);
  }
  if (finished) return 0;
  if (image.output_scanline == image.output_height) {
    error_phase = IMAGE_PHASE_FINISH;
    if (setjmp(error.jump)) return -100 - abs(last_error);
    if (!jpeg_finish_decompress(&image)) return failure(-10);
    finished = 1;
    return 0;
  }
  error_phase = IMAGE_PHASE_ROWS;
  if (setjmp(error.jump)) return -100 - abs(last_error);
  strip_start = image.output_scanline;
  JSAMPROW row_pointers[IMAGE_MAX_STRIP_ROWS];
  uint32_t count = 0;
  while (count < strip_rows && image.output_scanline < image.output_height) {
    uint32_t available = strip_rows - count;
    for (uint32_t index = 0; index < available; index++)
      row_pointers[index] = strip + (size_t)(count + index) * output_width * 4;
    JDIMENSION read = jpeg_read_scanlines(&image, row_pointers, available);
    if (!read) return failure(-11);
    count += read;
  }
  return (int)count;
}

EMSCRIPTEN_KEEPALIVE uint8_t* image_strip(void) { return strip; }
EMSCRIPTEN_KEEPALIVE uint32_t image_width(void) { return output_width; }
EMSCRIPTEN_KEEPALIVE uint32_t image_height(void) { return output_height; }
EMSCRIPTEN_KEEPALIVE uint32_t image_source_width(void) {
  return image.image_width;
}
EMSCRIPTEN_KEEPALIVE uint32_t image_source_height(void) {
  return image.image_height;
}
EMSCRIPTEN_KEEPALIVE uint32_t image_strip_start(void) { return strip_start; }
EMSCRIPTEN_KEEPALIVE int image_error_code(void) { return last_error; }
EMSCRIPTEN_KEEPALIVE int image_error_phase(void) { return error_phase; }
EMSCRIPTEN_KEEPALIVE size_t image_live_bytes(void) { return live_bytes; }
EMSCRIPTEN_KEEPALIVE size_t image_peak_bytes(void) { return peak_bytes; }
EMSCRIPTEN_KEEPALIVE size_t image_allocations(void) { return allocations; }

EMSCRIPTEN_KEEPALIVE void image_close(void) {
  /* destroy does not normally report errors, but no exported call may retain
   * a jump target that belonged to an already-returned C frame. */
  if (!setjmp(error.jump) && image.mem) jpeg_destroy_decompress(&image);
  meter_free(strip);
  meter_free(input);
  strip = input = NULL;
  memset(&image, 0, sizeof(image));
  input_length = strip_rows = strip_start = output_width = output_height = 0;
  opened = finished = last_error = error_phase = 0;
}
