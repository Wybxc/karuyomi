import type { RuntimeMaterialResolver } from './verified-loader.js';
import { RuntimeFailure } from './errors.js';

export interface EncodedMaterial {
  base64: string;
  contentType: string;
}

/** Native bytes are compiled into the app; absent materials never use HTTP. */
export function createNativeMaterialResolver(
  materials: Readonly<Record<string, EncodedMaterial>>,
  legacyHashes: readonly string[],
): RuntimeMaterialResolver {
  const legacy = new Set(legacyHashes);
  return (sha256) => {
    if (legacy.has(sha256)) {
      throw new RuntimeFailure(
        'unsupported_capability',
        'This extension build uses legacy storage materials; update the extension build',
      );
    }
    const value = materials[sha256];
    if (!value) return undefined;
    const text = atob(value.base64);
    return {
      bytes: Uint8Array.from(text, (character) => character.charCodeAt(0)),
      contentType: value.contentType,
    };
  };
}
