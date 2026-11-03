// Byte-only development fixtures. No Source, image URL or user data is used.
self.onmessage = async ({ data }) => {
  try {
    let bytes;
    let mimeType = 'application/octet-stream';
    if (data.mode === 'png') {
      const canvas = new OffscreenCanvas(128, 256);
      const context = canvas.getContext('2d');
      const pixels = context.createImageData(128, 256);
      for (let i = 0; i < pixels.data.length; i += 4) {
        pixels.data[i] = (i / 4) % 256;
        pixels.data[i + 1] = (i / 512) % 256;
        pixels.data[i + 2] = 193;
        pixels.data[i + 3] = 255;
      }
      context.putImageData(pixels, 0, 0);
      bytes = new Uint8Array(
        await (await canvas.convertToBlob({ type: 'image/png' })).arrayBuffer(),
      );
      mimeType = 'image/png';
    } else {
      bytes = new Uint8Array(data.byteLength);
      for (let i = 0; i < bytes.length; i++)
        bytes[i] = (i * 31 + (i >>> 8)) & 255;
    }
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    const sha256 = Array.from(new Uint8Array(digest), (value) =>
      value.toString(16).padStart(2, '0'),
    ).join('');
    const buffer = bytes.buffer;
    self.postMessage({ type: 'bytes', id: data.id, buffer, sha256, mimeType }, [
      buffer,
    ]);
    self.postMessage({
      type: 'detached',
      id: data.id,
      detached: buffer.byteLength === 0,
    });
  } catch (error) {
    self.postMessage({ type: 'error', id: data.id, message: String(error) });
  }
};
