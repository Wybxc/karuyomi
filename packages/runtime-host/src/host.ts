import { SourceRuntimeManager } from './manager.js';
import { VerifiedLoader } from './verified-loader.js';
import { ExtensionArtifactCache } from './extension-artifact-cache.js';
import { installRuntime } from './host-api.js';

if (!window.karuyomiRuntime)
  installRuntime(
    new SourceRuntimeManager(
      new URL(/* @vite-ignore */ './worker.js', import.meta.url),
      (url) => new Worker(url),
      new VerifiedLoader(
        location.origin,
        undefined,
        undefined,
        new ExtensionArtifactCache(),
      ),
    ),
  );
