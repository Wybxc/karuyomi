import { SourceRuntimeManager } from './manager.js';
import { VerifiedLoader } from './verified-loader.js';
import { installRuntime } from './host-api.js';
import { createImageCodecAssetProvider } from './image-codec-assets.js';
import { imageCodecMaterials } from './image-codec-materials.js';

if (!window.karuyomiRuntime)
  installRuntime(
    new SourceRuntimeManager(
      new URL('./worker.js', import.meta.url),
      (url) => new Worker(url),
      new VerifiedLoader(location.origin),
      60_000,
      {
        tiles: createImageCodecAssetProvider(
          location.origin,
          imageCodecMaterials,
        ),
      },
    ),
  );
