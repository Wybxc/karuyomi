import type { Artifact } from '@karuyomi/contracts';
import { RuntimeFailure } from './errors.js';
import { nativeMaterials } from './materials.js';
import { VerifiedLoader } from './verified-loader.js';

export interface ImageCodecMaterial extends Artifact {
  logicalName: string;
  contentType: string;
}
export interface ImageCodecModuleBytes {
  moduleUrl: string;
  wasmBinary: Uint8Array<ArrayBuffer>;
}
export interface PreparedImageCodecAssets {
  workerUrl: URL;
  decoder: ImageCodecModuleBytes;
  encoder: ImageCodecModuleBytes;
  /** Pass to the client's releaseModules callback, after its Worker terminates. */
  release(): void;
}
export interface ImageCodecObjectUrls {
  createObjectURL(blob: Blob): string;
  revokeObjectURL(url: string): void;
}

/** One decode owns these verified modules until its dedicated Worker terminates. */
export async function prepareImageCodecAssets(
  materials: readonly ImageCodecMaterial[],
  format: 'png' | 'jpeg',
  loader: VerifiedLoader,
  signal: AbortSignal,
  objectUrls: ImageCodecObjectUrls = URL,
): Promise<PreparedImageCodecAssets> {
  signal.throwIfAborted();
  if (format !== 'png' && format !== 'jpeg')
    throw new RuntimeFailure('unsupported_capability', 'Unknown image codec');
  const byName = new Map<string, ImageCodecMaterial>();
  for (const material of materials) {
    if (byName.has(material.logicalName))
      throw new RuntimeFailure(
        'integrity_error',
        'Duplicate image codec material',
      );
    byName.set(material.logicalName, material);
  }
  const read = async (name: string, script: boolean) => {
    const artifact = byName.get(name);
    if (
      !artifact ||
      artifact.contentType !==
        (script ? 'application/javascript' : 'application/wasm')
    )
      throw new RuntimeFailure(
        'unsupported_capability',
        'Missing image codec material: ' + name,
      );
    return loader.sharedArtifact(artifact, signal, script);
  };
  // Do not create executable URLs until all five required transfers verify.
  const worker = await read('worker.js', true);
  const decoder = await read(format + '.mjs', true);
  const decoderWasm = await read(format + '.wasm', false);
  const encoder = await read('encoder.mjs', true);
  const encoderWasm = await read('encoder.wasm', false);
  signal.throwIfAborted();
  const created: string[] = [];
  const release = () => {
    for (const url of created.splice(0)) objectUrls.revokeObjectURL(url);
  };
  const scriptUrl = (bytes: Uint8Array<ArrayBuffer>) => {
    const url = objectUrls.createObjectURL(
      new Blob([bytes], { type: 'application/javascript' }),
    );
    created.push(url);
    return url;
  };
  try {
    return {
      workerUrl: new URL(scriptUrl(worker)),
      decoder: { moduleUrl: scriptUrl(decoder), wasmBinary: decoderWasm },
      encoder: { moduleUrl: scriptUrl(encoder), wasmBinary: encoderWasm },
      release,
    };
  } catch (error) {
    release();
    throw error;
  }
}

/** Native builds replace nativeMaterials with the bundled codec-only resolver. */
export function createImageCodecAssetProvider(
  origin: string,
  materials: readonly ImageCodecMaterial[],
  loader = new VerifiedLoader(origin, undefined, nativeMaterials),
) {
  return Object.freeze({
    prepare: (format: 'png' | 'jpeg', signal: AbortSignal) =>
      prepareImageCodecAssets(materials, format, loader, signal),
  });
}
