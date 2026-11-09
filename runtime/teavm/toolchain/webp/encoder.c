#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "src/webp/encode.h"

#define MAX_PIXELS (16u * 1024u * 1024u)
#define MAX_RGBA_BYTES (4u * MAX_PIXELS)
#define MAX_ENCODED_BYTES (64u * 1024u * 1024u)

typedef struct {
  uint8_t* bytes;
  size_t capacity;
  size_t used;
} Output;

static int WriteOutput(const uint8_t* data, size_t size,
                       const WebPPicture* picture) {
  Output* const output = (Output*)picture->custom_ptr;
  if (size > output->capacity - output->used) return 0;
  memcpy(output->bytes + output->used, data, size);
  output->used += size;
  return 1;
}

void* webp_alloc(size_t bytes) {
  if (bytes == 0 || bytes > MAX_RGBA_BYTES) return NULL;
  return malloc(bytes);
}

void webp_free(void* pointer) { free(pointer); }

// Both buffers are caller-owned and allocated in the same Wasm memory. A
// failed encode can leave partial bytes in output, which must be discarded.
size_t webp_encode(const uint8_t* rgba, unsigned width, unsigned height,
                   uint8_t* output, size_t capacity, float quality) {
  if (rgba == NULL || output == NULL || width == 0 || height == 0 ||
      width > WEBP_MAX_DIMENSION || height > WEBP_MAX_DIMENSION ||
      width * height > MAX_PIXELS || capacity == 0 ||
      capacity > MAX_ENCODED_BYTES || !(quality >= 0.0f && quality <= 100.0f)) {
    return 0;
  }

  WebPConfig config;
  WebPPicture picture;
  if (!WebPConfigInit(&config) || !WebPPictureInit(&picture)) return 0;
  config.lossless = 0;
  config.quality = quality;
  config.method = 4;
  // High-detail pages can exhaust the Wasm heap with libwebp's token buffer.
  config.low_memory = 1;
  config.thread_level = 0;
  if (!WebPValidateConfig(&config)) return 0;

  Output target = {output, capacity, 0};
  picture.width = (int)width;
  picture.height = (int)height;
  picture.writer = WriteOutput;
  picture.custom_ptr = &target;
  const int ok = WebPPictureImportRGBA(&picture, rgba, (int)(width * 4u)) &&
                 WebPEncode(&config, &picture);
  WebPPictureFree(&picture);
  return ok ? target.used : 0;
}
