import type { ImageCodecMaterial } from './image-codec-assets.js';

// Fixed build catalog, supplied by esbuild to both terminal host entry points.
// Only descriptors enter the Web host; bytes are delivered as Static Assets.
declare const __KARUYOMI_IMAGE_CODEC_MATERIALS__: readonly ImageCodecMaterial[];
export const imageCodecMaterials = __KARUYOMI_IMAGE_CODEC_MATERIALS__;
