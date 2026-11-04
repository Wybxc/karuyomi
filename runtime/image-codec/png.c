#include <emscripten/emscripten.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "codec.h"
#include "spng.h"

typedef union AllocationHeader {
  size_t size;
  max_align_t alignment;
} AllocationHeader;

static size_t live_bytes, peak_bytes, allocations, input_length;
static const size_t allocation_limit = IMAGE_MAX_ALLOCATION_BYTES;
static spng_ctx* decoder;
static uint8_t *input, *strip;
static struct spng_ihdr image;
static uint32_t current_row, strip_rows, strip_start;
static int last_error, error_phase, finished;

static int decode_failure(int error, int phase) {
  last_error = error;
  error_phase = phase;
  return -100 - abs(error);
}

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

static void* meter_calloc(size_t count, size_t size) {
  if (size && count > SIZE_MAX / size) return NULL;
  size_t bytes = count * size;
  void* result = meter_malloc(bytes);
  if (result) memset(result, 0, bytes);
  return result;
}

static void* meter_realloc(void* pointer, size_t size) {
  if (!pointer) return meter_malloc(size);
  if (!size) {
    meter_free(pointer);
    return NULL;
  }
  AllocationHeader* allocation = (AllocationHeader*)pointer - 1;
  size_t old_size = allocation->size;
  if (size > allocation_limit - (live_bytes - old_size) ||
      size > SIZE_MAX - sizeof(AllocationHeader))
    return NULL;
  AllocationHeader* next = realloc(allocation, sizeof(*allocation) + size);
  if (!next) return NULL;
  next->size = size;
  live_bytes = live_bytes - old_size + size;
  if (live_bytes > peak_bytes) peak_bytes = live_bytes;
  return next + 1;
}

EMSCRIPTEN_KEEPALIVE uint8_t* image_input(size_t length) {
  if (decoder || input) return NULL;
  peak_bytes = live_bytes;
  last_error = error_phase = 0;
  if (!length || length > IMAGE_MAX_INPUT_BYTES) return NULL;
  input = meter_malloc(length);
  if (input) input_length = length;
  return input;
}

EMSCRIPTEN_KEEPALIVE int image_open(size_t length, uint32_t rows,
                                    uint32_t denominator) {
  if (!input || decoder || length != input_length || !rows ||
      rows > IMAGE_MAX_STRIP_ROWS || denominator != 1)
    return decode_failure(-1, IMAGE_PHASE_OPEN);
  error_phase = IMAGE_PHASE_OPEN;
  struct spng_alloc allocator = {meter_malloc, meter_realloc, meter_calloc,
                                 meter_free};
  decoder = spng_ctx_new2(&allocator, 0);
  if (!decoder) return decode_failure(-2, IMAGE_PHASE_OPEN);
  int error = spng_set_image_limits(decoder, 4096, 100000);
  if (!error) error = spng_set_chunk_limits(decoder, 1024 * 1024, 1024 * 1024);
  if (!error) error = spng_set_png_buffer(decoder, input, length);
  if (!error) error = spng_get_ihdr(decoder, &image);
  if (error) return decode_failure(error, IMAGE_PHASE_OPEN);
  /* The first verified path uses native alpha. Do not silently widen this to
   * palette/grayscale/tRNS or interlaced PNG without corresponding oracles. */
  if (image.interlace_method || image.bit_depth != 8 ||
      image.color_type != SPNG_COLOR_TYPE_TRUECOLOR_ALPHA)
    return decode_failure(-3, IMAGE_PHASE_OPEN);
  strip_rows = rows;
  strip = meter_malloc((size_t)image.width * 4 * strip_rows);
  if (!strip) return decode_failure(-4, IMAGE_PHASE_OPEN);
  error = spng_decode_image(decoder, NULL, 0, SPNG_FMT_RGBA8,
                            SPNG_DECODE_PROGRESSIVE);
  return error ? decode_failure(error, IMAGE_PHASE_OPEN) : 0;
}

EMSCRIPTEN_KEEPALIVE int image_next(void) {
  if (last_error) return -100 - abs(last_error);
  if (!decoder) return decode_failure(-1, IMAGE_PHASE_ROWS);
  if (finished) return 0;
  if (current_row == image.height) {
    error_phase = IMAGE_PHASE_FINISH;
    int error = spng_decode_chunks(decoder);
    if (error) return decode_failure(error, IMAGE_PHASE_FINISH);
    finished = 1;
    return 0;
  }
  error_phase = IMAGE_PHASE_ROWS;
  strip_start = current_row;
  size_t row_bytes = (size_t)image.width * 4;
  uint32_t count = 0;
  while (count < strip_rows && current_row < image.height) {
    int error = spng_decode_row(decoder, strip + row_bytes * count, row_bytes);
    if (error && error != SPNG_EOI)
      return decode_failure(error, IMAGE_PHASE_ROWS);
    count++;
    current_row++;
    if (error == SPNG_EOI && current_row != image.height)
      return decode_failure(-5, IMAGE_PHASE_ROWS);
  }
  return (int)count;
}

EMSCRIPTEN_KEEPALIVE uint8_t* image_strip(void) { return strip; }
EMSCRIPTEN_KEEPALIVE uint32_t image_width(void) { return image.width; }
EMSCRIPTEN_KEEPALIVE uint32_t image_height(void) { return image.height; }
EMSCRIPTEN_KEEPALIVE uint32_t image_source_width(void) { return image.width; }
EMSCRIPTEN_KEEPALIVE uint32_t image_source_height(void) { return image.height; }
EMSCRIPTEN_KEEPALIVE uint32_t image_strip_start(void) { return strip_start; }
EMSCRIPTEN_KEEPALIVE int image_error_code(void) { return last_error; }
EMSCRIPTEN_KEEPALIVE int image_error_phase(void) { return error_phase; }
EMSCRIPTEN_KEEPALIVE size_t image_live_bytes(void) { return live_bytes; }
EMSCRIPTEN_KEEPALIVE size_t image_peak_bytes(void) { return peak_bytes; }
EMSCRIPTEN_KEEPALIVE size_t image_allocations(void) { return allocations; }

EMSCRIPTEN_KEEPALIVE void image_close(void) {
  spng_ctx_free(decoder);
  decoder = NULL;
  meter_free(strip);
  strip = NULL;
  meter_free(input);
  input = NULL;
  input_length = current_row = strip_rows = strip_start = 0;
  memset(&image, 0, sizeof(image));
  finished = last_error = error_phase = 0;
}
