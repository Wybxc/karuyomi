import { gunzipSync } from 'fflate';
import type { RuntimeMaterialResolver } from './verified-loader.js';

export interface EncodedMaterial {
  base64: string;
  contentType: string;
  decodedSize?: number;
}

/** Native bytes are compiled into the app; absent materials never use HTTP. */
export function createNativeMaterialResolver(
  materials: Readonly<Record<string, EncodedMaterial>>,
): RuntimeMaterialResolver {
  return (sha256) => {
    const value = materials[sha256];
    if (!value) return undefined;
    const text = atob(value.base64);
    const bytes = Uint8Array.from(text, (character) => character.charCodeAt(0));
    return {
      bytes:
        value.decodedSize === undefined
          ? bytes
          : gunzipSync(bytes, { out: new Uint8Array(value.decodedSize) }),
      contentType: value.contentType,
    };
  };
}
