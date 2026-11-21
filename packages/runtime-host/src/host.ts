import { SourceRuntimeManager } from './manager.js';
import { VerifiedLoader } from './verified-loader.js';
import { ExtensionArtifactCache } from './extension-artifact-cache.js';
import { installRuntime } from './host-api.js';

const createManager = () =>
  new SourceRuntimeManager(
    new URL(/* @vite-ignore */ './worker.js', import.meta.url),
    (url) => new Worker(url),
    new VerifiedLoader(
      location.origin,
      undefined,
      undefined,
      new ExtensionArtifactCache(),
    ),
  );

if (!window.karuyomiRuntime) installRuntime(createManager(), createManager);
