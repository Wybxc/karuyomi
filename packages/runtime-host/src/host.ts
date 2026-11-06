import { SourceRuntimeManager } from './manager.js';
import { VerifiedLoader } from './verified-loader.js';
import { ExtensionArtifactCache } from './extension-artifact-cache.js';
import { installRuntime } from './host-api.js';

const createManager = (imagesEnabled: boolean) =>
  new SourceRuntimeManager(
    new URL(/* @vite-ignore */ './worker.js', import.meta.url),
    (url) => new Worker(url),
    new VerifiedLoader(
      location.origin,
      undefined,
      undefined,
      new ExtensionArtifactCache(),
    ),
    60_000,
    { enabled: imagesEnabled },
  );

if (!window.karuyomiRuntime)
  installRuntime(createManager(true), () => createManager(false));
