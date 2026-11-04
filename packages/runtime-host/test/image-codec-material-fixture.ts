import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { digest, type ImageCodecMaterialInput } from '../materials.ts';

/** Small packaging fixtures; they are never presented as executable codec builds. */
export async function imageCodecMaterialFixture(
  directory: string,
): Promise<ImageCodecMaterialInput> {
  const artifacts: ImageCodecMaterialInput['manifest']['artifacts'] = {};
  for (const name of [
    'png.mjs',
    'png.wasm',
    'jpeg.mjs',
    'jpeg.wasm',
    'encoder.mjs',
    'encoder.wasm',
    'licenses/libspng-LICENSE.txt',
    'licenses/libjpeg-turbo-LICENSE.md',
    'licenses/libjpeg-turbo-README.ijg',
    'licenses/zlib-README',
  ]) {
    const bytes = Buffer.from('Packaging fixture: ' + name);
    await mkdir(path.dirname(path.join(directory, name)), { recursive: true });
    await writeFile(path.join(directory, name), bytes);
    artifacts[name] = { size: bytes.length, sha256: digest(bytes) };
  }
  return {
    directory,
    manifest: {
      identity: '1'.repeat(64),
      abi: 'karuyomi-image-strips-v1',
      encoderAbi: 'karuyomi-png-tiles-v1',
      artifacts,
    },
  };
}
