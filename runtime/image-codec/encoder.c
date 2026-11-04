#include "encoder.h"

#include <emscripten/emscripten.h>
#include <stdlib.h>
#include <string.h>

#include "spng.h"

typedef union AllocationHeader {
  size_t size;
  max_align_t alignment;
} AllocationHeader;

static size_t live_bytes, peak_bytes, allocations, input_length, output_length;
static spng_ctx* context;
static uint8_t *input, *output;
static int last_error;

static void* meter_malloc(size_t size) {
  if (size > ENCODER_MAX_ALLOCATION_BYTES - live_bytes ||
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
  if (size > ENCODER_MAX_ALLOCATION_BYTES - (live_bytes - old_size) ||
      size > SIZE_MAX - sizeof(AllocationHeader))
    return NULL;
  AllocationHeader* next = realloc(allocation, sizeof(*allocation) + size);
  if (!next) return NULL;
  next->size = size;
  live_bytes = live_bytes - old_size + size;
  if (live_bytes > peak_bytes) peak_bytes = live_bytes;
  return next + 1;
}

static void release(void) {
  /* get_png_buffer transfers ownership; the context will not free output. */
  spng_ctx_free(context);
  context = NULL;
  meter_free(output);
  output = NULL;
  meter_free(input);
  input = NULL;
  input_length = output_length = 0;
}

static int failure(int code) {
  last_error = code;
  release();
  return -100 - abs(code);
}

EMSCRIPTEN_KEEPALIVE uint8_t* encoder_input(size_t length) {
  if (input || output || context) return NULL;
  peak_bytes = live_bytes;
  last_error = 0;
  if (!length || length > ENCODER_MAX_INPUT_BYTES) {
    last_error = -1;
    return NULL;
  }
  input = meter_malloc(length);
  if (input)
    input_length = length;
  else
    last_error = -2;
  return input;
}

EMSCRIPTEN_KEEPALIVE int encoder_encode(uint32_t width, uint32_t height) {
  if (!input || output || context || !width || width > ENCODER_MAX_WIDTH ||
      !height || height > ENCODER_MAX_HEIGHT ||
      (size_t)width * height * 4 != input_length)
    return failure(-3);
  struct spng_alloc allocator = {meter_malloc, meter_realloc, meter_calloc,
                                 meter_free};
  context = spng_ctx_new2(&allocator, SPNG_CTX_ENCODER);
  if (!context) return failure(-4);
  struct spng_ihdr header = {0};
  header.width = width;
  header.height = height;
  header.bit_depth = 8;
  header.color_type = SPNG_COLOR_TYPE_TRUECOLOR_ALPHA;
  int error = spng_set_option(context, SPNG_ENCODE_TO_BUFFER, 1);
  if (!error) error = spng_set_option(context, SPNG_IMG_COMPRESSION_LEVEL, 6);
  if (!error) error = spng_set_ihdr(context, &header);
  if (!error)
    error = spng_encode_image(context, input, input_length, SPNG_FMT_PNG,
                              SPNG_ENCODE_FINALIZE);
  if (error) return failure(error);
  output = spng_get_png_buffer(context, &output_length, &error);
  if (error || !output) return failure(error ? error : -5);
  if (!output_length || output_length > ENCODER_MAX_OUTPUT_BYTES)
    return failure(-6);
  return 0;
}

EMSCRIPTEN_KEEPALIVE uint8_t* encoder_output(void) { return output; }
EMSCRIPTEN_KEEPALIVE uint32_t encoder_length(void) {
  return (uint32_t)output_length;
}
EMSCRIPTEN_KEEPALIVE int encoder_error_code(void) { return last_error; }
EMSCRIPTEN_KEEPALIVE size_t encoder_live_bytes(void) { return live_bytes; }
EMSCRIPTEN_KEEPALIVE size_t encoder_peak_bytes(void) { return peak_bytes; }
EMSCRIPTEN_KEEPALIVE size_t encoder_allocations(void) { return allocations; }

EMSCRIPTEN_KEEPALIVE void encoder_close(void) {
  release();
  last_error = 0;
}
