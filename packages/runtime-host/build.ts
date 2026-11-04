import { build, type BuildOptions } from 'esbuild';
import { cp, mkdir, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { digest, nativeMaterialGroups, prepareMaterials } from './materials.ts';

const directory = fileURLToPath(new URL('./', import.meta.url));
const output = path.join(directory, 'dist');
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
const { catalog, data } = await prepareMaterials(output);
const nativeGroups = nativeMaterialGroups(catalog);
const common = {
  absWorkingDir: directory,
  bundle: true,
  platform: 'browser',
  target: 'es2022',
  minify: true,
  write: false,
  define: {
    __KARUYOMI_IMAGE_CODEC_MATERIALS__: JSON.stringify(catalog.imageCodecs),
  },
} satisfies BuildOptions;
const web = await Promise.all([
  build({ ...common, entryPoints: ['src/host.ts'], format: 'esm' }),
  build({ ...common, entryPoints: ['src/worker.ts'], format: 'iife' }),
]);
await writeFile(path.join(output, 'host.js'), web[0]!.outputFiles[0]!.contents);
await writeFile(
  path.join(output, 'worker.js'),
  web[1]!.outputFiles[0]!.contents,
);
await cp(
  path.join(directory, 'public/host.html'),
  path.join(output, 'host.html'),
);

// Each embedded value is decoded into fresh bytes. VerifiedLoader independently
// checks MIME, size and SHA on every use, and never falls back to a network read.
const embedded = Object.fromEntries(
  nativeGroups.sourceWorker.map(({ sha256 }) => {
    const value = data.get(sha256);
    if (!value) throw new Error('Missing Native Source material: ' + sha256);
    return [
      sha256,
      {
        base64: value.bytes.toString('base64'),
        contentType: value.contentType,
      },
    ];
  }),
);
const nativeMaterialModule = `import {createNativeMaterialResolver} from ${JSON.stringify(path.join(directory, 'src/native-materials.ts'))};
const values=${JSON.stringify(embedded)};
export const nativeMaterials=createNativeMaterialResolver(values);`;
const nativeWorker = await build({
  ...common,
  entryPoints: ['src/worker.ts'],
  format: 'iife',
  plugins: [
    {
      name: 'embedded-native-materials',
      setup(builder) {
        builder.onResolve({ filter: /^\.\/materials\.js$/ }, () => ({
          path: 'materials',
          namespace: 'native-materials',
        }));
        builder.onLoad({ filter: /.*/, namespace: 'native-materials' }, () => ({
          contents: nativeMaterialModule,
          loader: 'js',
          resolveDir: directory,
        }));
      },
    },
  ],
});
// Codec bytes belong to the terminal host only, never every Source Worker.
const codecEmbedded = Object.fromEntries(
  nativeGroups.imageCodecs.map(({ sha256 }) => {
    const value = data.get(sha256);
    if (!value)
      throw new Error('Missing Native image codec material: ' + sha256);
    return [
      sha256,
      {
        base64: value.bytes.toString('base64'),
        contentType: value.contentType,
      },
    ];
  }),
);
const nativeHost = await build({
  ...common,
  stdin: {
    contents: `import './src/host.native.ts';
import {createImageCodecAssetProvider} from './src/image-codec-assets.ts';
import {decodeImageTiles} from '../../runtime/image-codec/client.ts';
const provider=createImageCodecAssetProvider(location.origin,${JSON.stringify(nativeGroups.imageCodecs)});
Object.defineProperty(window,'karuyomiImageCodecs',{value:Object.freeze({...provider,decodeImageTiles})});`,
    resolveDir: directory,
    sourcefile: 'native-image-codec-host.ts',
    loader: 'ts',
  },
  format: 'iife',
  define: {
    __KARUYOMI_MATERIAL_VERSION__: JSON.stringify(catalog.materialVersion),
    __KARUYOMI_IMAGE_CODEC_MATERIALS__: JSON.stringify(
      nativeGroups.imageCodecs,
    ),
  },
  plugins: [
    {
      name: 'embedded-native-image-codecs',
      setup(builder) {
        builder.onResolve({ filter: /^\.\/materials\.js$/ }, () => ({
          path: 'image-codecs',
          namespace: 'native-image-codecs',
        }));
        builder.onLoad(
          { filter: /.*/, namespace: 'native-image-codecs' },
          () => ({
            contents: `import {createNativeMaterialResolver} from ${JSON.stringify(path.join(directory, 'src/native-materials.ts'))};
export const nativeMaterials=createNativeMaterialResolver(${JSON.stringify(codecEmbedded)});`,
            loader: 'js',
            resolveDir: directory,
          }),
        );
      },
    },
  ],
});
const nativeOutput = path.join(output, 'native');
await mkdir(nativeOutput, { recursive: true });
const nativeFiles = {
  host: { name: 'host.js', bytes: nativeHost.outputFiles[0]!.contents },
  worker: { name: 'worker.js', bytes: nativeWorker.outputFiles[0]!.contents },
};
const files: Record<string, { path: string; sha256: string; size: number }> =
  {};
for (const [key, { name, bytes }] of Object.entries(nativeFiles)) {
  await writeFile(path.join(nativeOutput, name), bytes);
  files[key] = { path: name, sha256: digest(bytes), size: bytes.length };
}
const nativeManifest = {
  schemaVersion: 1,
  protocolVersion: catalog.protocolVersion,
  hostAbi: catalog.hostAbi,
  runtimeBaseline: catalog.runtimeBaseline,
  materialVersion: catalog.materialVersion,
  files,
  materials: nativeGroups.sourceWorker,
  imageCodecs: nativeGroups.imageCodecs,
  sources: catalog.sources,
};
await writeFile(
  path.join(nativeOutput, 'manifest.json'),
  JSON.stringify(nativeManifest, null, 2) + '\n',
);

console.log(
  JSON.stringify({
    materialVersion: catalog.materialVersion,
    materials: data.size,
    nativeFiles: files,
  }),
);
