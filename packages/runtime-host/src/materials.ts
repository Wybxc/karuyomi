import type { RuntimeMaterialResolver } from './verified-loader.js';

// Browser builds read hash-addressed static materials. The native build replaces
// this module with a generated resolver containing exactly those same bytes.
export const nativeMaterials: RuntimeMaterialResolver | undefined = undefined;
