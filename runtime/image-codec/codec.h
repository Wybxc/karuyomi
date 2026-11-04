#ifndef KARUYOMI_IMAGE_CODEC_H_
#define KARUYOMI_IMAGE_CODEC_H_

#include <stddef.h>
#include <stdint.h>

/* Each independently linked codec WASM owns one decoding session. The TS
 * lifecycle must serialize input/open/next/close and implement cancellation
 * between next() calls; C decoding is not synchronously preemptible. */
enum {
  IMAGE_MAX_INPUT_BYTES = 8 * 1024 * 1024,
  IMAGE_MAX_ALLOCATION_BYTES = 16 * 1024 * 1024,
  IMAGE_MAX_STRIP_ROWS = 256,
  IMAGE_PHASE_NONE = 0,
  IMAGE_PHASE_OPEN = 1,
  IMAGE_PHASE_ROWS = 2,
  IMAGE_PHASE_FINISH = 3
};

/* Allocate the encoded input, then fill exactly length bytes before open().
 * Starting a new idle session resets its peak counter; close() preserves the
 * previous peak and the actual remaining allocation counters for inspection. */
uint8_t* image_input(size_t length);

/* Both implementations emit straight RGBA8. PNG initially accepts only
 * noninterlaced RGBA8 and denominator 1. JPEG accepts the verified single-scan
 * 8-bit grayscale/RGB/YCbCr path and denominators 1, 2 or 4. These capabilities
 * do not change the product's image-admission policy. */
int image_open(size_t length, uint32_t rows, uint32_t denominator);

/* Return positive rows, zero only after validating the real stream ending, or
 * a negative failure sentinel. strip() remains valid until next()/close(); its
 * byte length is returned_rows * image_width() * 4. Copy before advancing. */
int image_next(void);
uint8_t* image_strip(void);
uint32_t image_width(void);
uint32_t image_height(void);
uint32_t image_source_width(void);
uint32_t image_source_height(void);
uint32_t image_strip_start(void);
int image_error_code(void);
int image_error_phase(void);

/* Metered allocation payload only: excludes AllocationHeader, allocator
 * overhead, realloc's transient storage, stack, JS/input copies and process
 * RSS. The WASM heap limit is a separate builder setting. */
size_t image_live_bytes(void);
size_t image_peak_bytes(void);
size_t image_allocations(void);

/* Idempotent cleanup; dimensions and decode errors reset, peak stays readable.
 */
void image_close(void);

#endif /* KARUYOMI_IMAGE_CODEC_H_ */
