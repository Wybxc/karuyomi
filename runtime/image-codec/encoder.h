#ifndef KARUYOMI_IMAGE_ENCODER_H_
#define KARUYOMI_IMAGE_ENCODER_H_

#include <stddef.h>
#include <stdint.h>

/* One synchronous RGBA8 strip per independently owned WASM session. The caller
 * copies the PNG before close; cancellation is handled outside the C call. */
enum {
  ENCODER_MAX_WIDTH = 4096,
  ENCODER_MAX_HEIGHT = 256,
  ENCODER_MAX_INPUT_BYTES = 4 * 1024 * 1024,
  ENCODER_MAX_OUTPUT_BYTES = 8 * 1024 * 1024,
  ENCODER_MAX_ALLOCATION_BYTES = 16 * 1024 * 1024
};

uint8_t* encoder_input(size_t length);
int encoder_encode(uint32_t width, uint32_t height);
uint8_t* encoder_output(void);
uint32_t encoder_length(void);
int encoder_error_code(void);
size_t encoder_live_bytes(void);
size_t encoder_peak_bytes(void);
size_t encoder_allocations(void);

/* Failed encode also releases owned storage, retaining its error and peak.
 * Close is idempotent, clears the error and preserves the real allocation
 * counters and peak. The next idle input starts a new peak measurement.
 * Payload excludes allocator/header overhead, realloc transients, stack,
 * JS copies and process RSS; the WASM heap is limited separately. */
void encoder_close(void);

#endif /* KARUYOMI_IMAGE_ENCODER_H_ */
